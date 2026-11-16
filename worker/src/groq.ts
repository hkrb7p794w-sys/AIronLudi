/**
 * Groq als zweite Stufe, wenn Gemini ausfällt. OpenAI-kompatible Chat-Completions-API.
 * Ist das eingestellte Modell abgekündigt oder unbekannt, wählt der Worker eines aus der
 * Modellliste (gleiches Selbstheilungsprinzip wie bei Gemini).
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

const BASE = "https://api.groq.com/openai/v1";
export const DEFAULT_TEXT_MODEL = "llama-3.3-70b-versatile";
export const DEFAULT_VISION_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct";
const RETRY_DELAYS_MS = [0, 1500];
const TEXT_PREFERENCE = [/gpt-oss-120b/, /llama-3\.3-70b/, /llama-4-maverick/, /llama-4-scout/, /llama/];
const VISION_PREFERENCE = [/llama-4-scout/, /llama-4-maverick/, /vision/];

const state: { replacement: Record<string, string> } = { replacement: {} };

export function resetGroqState(): void {
  state.replacement = {};
}

export function pickModel(available: string[], preference: RegExp[], current: string): string | undefined {
  for (const pattern of preference) {
    const match = available.find((id) => id !== current && pattern.test(id));
    if (match) return match;
  }
  return undefined;
}

/** Antwort einer OpenAI-kompatiblen Chat-Completions-API (Groq, Workers AI, eigener Server). */
export interface ChatCompletion {
  choices?: { message?: { content?: string | null }; finish_reason?: string | null }[];
  usage?: { prompt_tokens?: number; completion_tokens?: number };
}

export function chatUsage(body: ChatCompletion): Usage | undefined {
  if (!body.usage) return undefined;
  return { inputTokens: body.usage.prompt_tokens ?? 0, outputTokens: body.usage.completion_tokens ?? 0 };
}

export function messages(request: GenerateRequest): unknown[] {
  const result: unknown[] = [];
  if (request.system) result.push({ role: "system", content: request.system });
  if (request.images.length === 0) {
    result.push({ role: "user", content: request.prompt });
  } else {
    result.push({
      role: "user",
      content: [
        { type: "text", text: request.prompt },
        ...request.images.map((image) => ({
          type: "image_url",
          image_url: { url: `data:${image.mimeType};base64,${image.data}` },
        })),
      ],
    });
  }
  return result;
}

function isModelGone(status: number, body: string): boolean {
  return status === 404 || /model_(decommissioned|not_found)|does not exist/.test(body);
}

async function listModels(env: Env, deps: Deps): Promise<string[]> {
  try {
    const response = await deps.fetch(`${BASE}/models`, {
      headers: { authorization: `Bearer ${env.GROQ_API_KEY ?? ""}` },
    });
    if (!response.ok) return [];
    const body = (await response.json()) as { data?: { id?: string; active?: boolean }[] };
    return (body.data ?? []).filter((m) => m.active !== false && m.id).map((m) => m.id as string);
  } catch {
    return [];
  }
}

async function call(
  model: string,
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<{ status: number; body: string }> {
  const response = await deps.fetch(`${BASE}/chat/completions`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.GROQ_API_KEY ?? ""}`, "content-type": "application/json" },
    body: JSON.stringify({
      model,
      messages: messages(request),
      max_completion_tokens: request.maxOutputTokens ?? 4096,
      temperature: request.temperature ?? 0.4,
      ...(request.json ? { response_format: { type: "json_object" } } : {}),
    }),
    signal: attemptSignal(request, deps),
  });
  return { status: response.status, body: await response.text() };
}

export async function generateWithGroq(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<GenerateResult> {
  if (!env.GROQ_API_KEY) throw new ProviderError("GROQ_API_KEY ist nicht gesetzt", false);
  const vision = request.images.length > 0;
  const configured = vision
    ? env.GROQ_VISION_MODEL?.trim() || DEFAULT_VISION_MODEL
    : env.GROQ_MODEL?.trim() || DEFAULT_TEXT_MODEL;
  let model = state.replacement[configured] ?? configured;
  let switched = false;

  let lastError: ProviderError | undefined;
  for (const delay of RETRY_DELAYS_MS) {
    if (delay) await deps.sleep(delay);
    if (request.deadline !== undefined && deps.now() >= request.deadline) {
      throw lastError ?? new ProviderError(`Groq (${model}): Zeitlimit erreicht`, true);
    }
    let result: { status: number; body: string };
    try {
      result = await call(model, request, env, deps);
    } catch (error) {
      lastError = new ProviderError(`Groq Netzwerkfehler: ${String(error)}`, true);
      continue;
    }
    if (result.status >= 400 && !switched && isModelGone(result.status, result.body)) {
      const replacement = pickModel(
        await listModels(env, deps),
        vision ? VISION_PREFERENCE : TEXT_PREFERENCE,
        model,
      );
      if (replacement) {
        deps.log(`[groq] Modell ${model} nicht verfügbar, wechsle auf ${replacement}`);
        state.replacement[configured] = replacement;
        model = replacement;
        switched = true;
        result = await call(model, request, env, deps);
      }
    }
    if (result.status === 429 || result.status >= 500) {
      lastError = new ProviderError(`Groq HTTP ${result.status} (${model})`, true, result.status);
      continue;
    }
    if (result.status >= 400) {
      // Kein Antworttext: `failed_generation` kann die Modellausgabe enthalten.
      throw new ProviderError(`Groq HTTP ${result.status} (${model})`, false);
    }
    const body = JSON.parse(result.body) as ChatCompletion;
    const text = body.choices?.[0]?.message?.content?.trim();
    if (!text) throw new ProviderError(`Groq (${model}) hat leeren Text geliefert`, true);
    if (request.json && body.choices?.[0]?.finish_reason === "length") {
      throw new ProviderError(`Groq (${model}): Antwort abgeschnitten`, false);
    }
    return { text, model, provider: "groq", usage: chatUsage(body) };
  }
  throw lastError ?? new ProviderError("Groq ohne Ergebnis", true);
}
