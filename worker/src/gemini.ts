/**
 * Robuster Gemini-Aufruf – übernommen aus dem Altbestand (garmin_ai_coach/ai_coach.py):
 * - 404 „nicht mehr verfügbar“: das in der Meldung genannte Nachfolgemodell nehmen.
 * - 429/5xx: mit Pause wiederholen, danach auf ein anderes Flash-Modell aus der Modellliste
 *   der API ausweichen („lite“ zuerst) und das Hauptmodell 30 Minuten meiden.
 * Pausen kürzer als im Add-on, weil die App auf die Antwort wartet.
 */
import {
  attemptSignal,
  type Deps,
  type Env,
  type GenerateRequest,
  type GenerateResult,
  ProviderError,
  type Usage,
} from "./types";

const BASE = "https://generativelanguage.googleapis.com/v1beta";
export const DEFAULT_MODEL = "gemini-3.6-flash";
export const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);
export const RETRY_DELAYS_MS = [0, 1500, 4000];
export const PRIMARY_COOLDOWN_MS = 30 * 60 * 1000;
const MAX_SUCCESSOR_HOPS = 2;

/** Zustand je Worker-Instanz (überlebt mehrere Anfragen, aber keinen Neustart). */
const state: { fallbackModel?: string; primaryDownUntil: number } = { primaryDownUntil: 0 };

export function resetGeminiState(): void {
  state.fallbackModel = undefined;
  state.primaryDownUntil = 0;
}

/** Nachfolgemodell aus einer 404-Meldung, z. B. „… please use models/gemini-3.6-flash …“. */
export function modelFrom404(message: string, tried: string): string | undefined {
  for (const match of message.matchAll(/models\/([A-Za-z0-9.-]+)/g)) {
    // Satzzeichen am Ende gehören nicht zum Namen („… use models/gemini-3.6-flash.“).
    const name = match[1]?.replace(/[.-]+$/, "");
    if (name && name !== tried) return name;
  }
  return undefined;
}

/** Ausweichkandidaten: „lite“ zuerst, Vorschauversionen zuletzt. */
export function rankFallbacks(names: string[], current: string): string[] {
  return names
    .filter((name) => name !== current)
    .sort((a, b) => {
      const key = (n: string) => [n.includes("lite") ? 0 : 1, n.includes("preview") ? 1 : 0] as const;
      const [la, pa] = key(a);
      const [lb, pb] = key(b);
      return la - lb || pa - pb || a.localeCompare(b);
    });
}

async function listFlashModels(env: Env, deps: Deps): Promise<string[]> {
  try {
    const response = await deps.fetch(`${BASE}/models?pageSize=200`, {
      headers: { "x-goog-api-key": env.GEMINI_API_KEY ?? "" },
    });
    if (!response.ok) return [];
    const body = (await response.json()) as {
      models?: { name?: string; supportedGenerationMethods?: string[] }[];
    };
    return (body.models ?? [])
      .filter((m) => m.supportedGenerationMethods?.includes("generateContent"))
      .map((m) => (m.name ?? "").replace("models/", ""))
      .filter((name) => name.includes("flash"))
      .filter((name) => !/(image|tts|audio|live|embedding|exp)/.test(name));
  } catch (error) {
    deps.log(`[gemini] Modellliste nicht abrufbar: ${String(error)}`);
    return [];
  }
}

async function pickFallback(current: string, env: Env, deps: Deps): Promise<string | undefined> {
  const configured = env.GEMINI_FALLBACK_MODEL?.trim();
  if (configured && configured !== current) return configured;
  if (state.fallbackModel && state.fallbackModel !== current) return state.fallbackModel;
  state.fallbackModel = rankFallbacks(await listFlashModels(env, deps), current)[0];
  return state.fallbackModel;
}

function requestBody(request: GenerateRequest, model: string): unknown {
  const parts: unknown[] = [{ text: request.prompt }];
  for (const image of request.images) {
    parts.push({ inlineData: { mimeType: image.mimeType, data: image.data } });
  }
  return {
    contents: [{ role: "user", parts }],
    ...(request.system ? { systemInstruction: { parts: [{ text: request.system }] } } : {}),
    // Thinking-Modelle zählen Denk-Tokens mit; ein knappes Budget liefert sonst leere Antworten.
    generationConfig: {
      maxOutputTokens: request.maxOutputTokens ?? 4096,
      ...(request.temperature === undefined ? {} : { temperature: request.temperature }),
      ...(request.json ? { responseMimeType: "application/json" } : {}),
      // Nur Gemini 3 kennt die Stufe; ältere Ausweichmodelle würden die Anfrage ablehnen.
      ...(request.lowThinking && model.startsWith("gemini-3")
        ? { thinkingConfig: { thinkingLevel: "low" } }
        : {}),
    },
  };
}

/** Tokens aus `usageMetadata` (Denk-Tokens zählen zur Ausgabe). */
export function geminiUsage(body: unknown): Usage | undefined {
  const meta = (body as { usageMetadata?: Record<string, number> }).usageMetadata;
  if (!meta) return undefined;
  return {
    inputTokens: meta.promptTokenCount ?? 0,
    outputTokens: (meta.candidatesTokenCount ?? 0) + (meta.thoughtsTokenCount ?? 0),
  };
}

/** `json`: Eine abgeschnittene JSON-Antwort (Budget aufgebraucht, Denk-Tokens zählen mit) ist unbrauchbar. */
export function extractText(body: unknown, model: string, json = false): string {
  const typed = body as {
    candidates?: { content?: { parts?: { text?: string }[] }; finishReason?: string }[];
    promptFeedback?: { blockReason?: string };
  };
  const candidate = typed.candidates?.[0];
  if (!candidate) {
    const reason = typed.promptFeedback?.blockReason ?? "unbekannt";
    throw new ProviderError(
      `Gemini (${model}) hat keinen Kandidaten geliefert (blockReason: ${reason})`,
      false,
    );
  }
  const text = (candidate.content?.parts ?? [])
    .map((part) => part.text ?? "")
    .join("")
    .trim();
  if (!text) {
    throw new ProviderError(
      `Gemini (${model}) hat leeren Text geliefert (finishReason: ${candidate.finishReason})`,
      true,
    );
  }
  if (json && candidate.finishReason === "MAX_TOKENS") {
    throw new ProviderError(`Gemini (${model}): Antwort abgeschnitten (zu lang)`, false);
  }
  return text;
}

async function tryModel(
  model: string,
  request: GenerateRequest,
  env: Env,
  deps: Deps,
  hops = 0,
): Promise<GenerateResult> {
  let lastError: ProviderError | undefined;
  for (const [attempt, delay] of RETRY_DELAYS_MS.entries()) {
    if (delay) await deps.sleep(delay);
    if (request.deadline !== undefined && deps.now() >= request.deadline) {
      throw lastError ?? new ProviderError(`Gemini (${model}): Zeitlimit erreicht`, true);
    }
    let response: Response;
    try {
      response = await deps.fetch(`${BASE}/models/${model}:generateContent`, {
        method: "POST",
        headers: { "x-goog-api-key": env.GEMINI_API_KEY ?? "", "content-type": "application/json" },
        body: JSON.stringify(requestBody(request, model)),
        signal: attemptSignal(request, deps),
      });
    } catch (error) {
      lastError = new ProviderError(`Netzwerkfehler (${model}): ${String(error)}`, true);
      continue;
    }
    if (response.status === 404 && hops < MAX_SUCCESSOR_HOPS) {
      const successor = modelFrom404(await response.text(), model);
      if (successor) {
        deps.log(`[gemini] Modell ${model} nicht verfügbar, wechsle auf ${successor}`);
        return tryModel(successor, request, env, deps, hops + 1);
      }
      throw new ProviderError(`Gemini-Modell ${model} nicht gefunden`, true, 404);
    }
    if (RETRYABLE_STATUS.has(response.status)) {
      lastError = new ProviderError(`Gemini HTTP ${response.status} (${model})`, true, response.status);
      deps.log(
        `[gemini] Versuch ${attempt + 1}/${RETRY_DELAYS_MS.length} mit ${model}: HTTP ${response.status}`,
      );
      continue;
    }
    if (!response.ok) {
      // Kein Antworttext: Er kann Eingaben enthalten und landet sonst im Protokoll.
      throw new ProviderError(`Gemini HTTP ${response.status} (${model})`, false, response.status);
    }
    try {
      const body = await response.json();
      return {
        text: extractText(body, model, request.json),
        model,
        provider: "gemini",
        usage: geminiUsage(body),
      };
    } catch (error) {
      if (error instanceof ProviderError && error.retryable) {
        lastError = error;
        continue;
      }
      throw error;
    }
  }
  throw lastError ?? new ProviderError(`Gemini (${model}) ohne Ergebnis`, true);
}

export async function generateWithGemini(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<GenerateResult> {
  if (!env.GEMINI_API_KEY) throw new ProviderError("GEMINI_API_KEY ist nicht gesetzt", false);
  const primary = env.GEMINI_MODEL?.trim() || DEFAULT_MODEL;

  if (deps.now() < state.primaryDownUntil) {
    const fallback = await pickFallback(primary, env, deps);
    if (fallback) {
      try {
        return await tryModel(fallback, request, env, deps);
      } catch (error) {
        deps.log(
          `[gemini] Ausweichmodell ${fallback} fehlgeschlagen (${String(error)}), versuche Hauptmodell`,
        );
      }
    }
  }

  try {
    const result = await tryModel(primary, request, env, deps);
    state.primaryDownUntil = 0;
    return result;
  } catch (error) {
    if (!(error instanceof ProviderError) || !error.retryable) throw error;
    const fallback = await pickFallback(primary, env, deps);
    if (!fallback) throw error;
    deps.log(`[gemini] ${primary} dauerhaft gestört, versuche ${fallback}`);
    state.primaryDownUntil = deps.now() + PRIMARY_COOLDOWN_MS;
    return tryModel(fallback, request, env, deps);
  }
}
