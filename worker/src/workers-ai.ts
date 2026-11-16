/**
 * Workers AI: offene Modelle (Gemma, Qwen, Llama, Mistral, DeepSeek …) direkt bei Cloudflare über das
 * Binding `AI` – kein zusätzlicher API-Key. Kostenlos sind 10.000 Neurons pro Tag; Eingaben und Ausgaben werden
 * nicht gespeichert und nicht zum Training genutzt (developers.cloudflare.com/workers-ai/platform/data-usage).
 */
import { type ChatCompletion, chatUsage, messages } from "./groq";
import {
  attemptMilliseconds,
  type Deps,
  type Env,
  type GenerateRequest,
  type GenerateResult,
  ProviderError,
} from "./types";

/** Gemma 4 26B A4B: Apache 2.0, Bild-Eingabe, 256k Kontext, günstig (9.091/27.273 Neurons je Mio. Tokens). */
export const DEFAULT_WORKERS_AI_MODEL = "@cf/google/gemma-4-26b-a4b-it";
const RETRY_DELAYS_MS = [0, 1500];
const MAX_TOKENS = 9_000;

/** Antwort ist entweder im Chat-Completions-Format oder (ältere Modelle) `{response, usage}`. */
type WorkersAiOutput = ChatCompletion & { response?: unknown };

function extract(output: WorkersAiOutput): string {
  const chat = output.choices?.[0]?.message?.content;
  if (typeof chat === "string") return chat.trim();
  if (typeof output.response === "string") return output.response.trim();
  // JSON-Modus liefert bei manchen Modellen bereits ein Objekt.
  if (output.response && typeof output.response === "object") return JSON.stringify(output.response);
  return "";
}

/** Kapazität knapp (3040), Tageskontingent aufgebraucht oder 429/5xx: ein anderer Anbieter kann helfen. */
function retryable(message: string): boolean {
  return /3040|capacity|429|5\d\d|timeout|busy|neurons|daily/i.test(message);
}

function withTimeout<T>(work: Promise<T>, milliseconds: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | null = null;
  const limit = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timeout")), milliseconds);
  });
  return Promise.race([work, limit]).finally(() => clearTimeout(timer));
}

export async function generateWithWorkersAi(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<GenerateResult> {
  if (!env.AI) throw new ProviderError("Workers-AI-Binding fehlt", false);
  const model = env.WORKERS_AI_MODEL?.trim() || DEFAULT_WORKERS_AI_MODEL;
  const input = {
    messages: messages(request),
    // Bei rund 140 Tokens je Sekunde: Eine ausufernde Antwort endet so vor dem Zeitlimit und löst einen Fehler aus.
    max_tokens: Math.min(request.maxOutputTokens ?? 4096, MAX_TOKENS),
    temperature: request.temperature ?? 0.4,
    ...(request.json ? { response_format: { type: "json_object" } } : {}),
    // Denkmodus aus: kürzere Antworten, weniger Neurons, das JSON kommt direkt.
    chat_template_kwargs: { enable_thinking: false },
  };
  let lastError: ProviderError | undefined;
  for (const delay of RETRY_DELAYS_MS) {
    if (delay) await deps.sleep(delay);
    if (request.deadline !== undefined && deps.now() >= request.deadline) {
      throw lastError ?? new ProviderError(`Workers AI (${model}): Zeitlimit erreicht`, true);
    }
    let output: WorkersAiOutput;
    try {
      output = (await withTimeout(
        env.AI.run(model, input, { rejectIfBusy: true }),
        attemptMilliseconds(request, deps),
      )) as WorkersAiOutput;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      lastError = new ProviderError(`Workers AI (${model}): ${message}`, retryable(message));
      if (!lastError.retryable) throw lastError;
      continue;
    }
    const text = extract(output);
    if (!text) throw new ProviderError(`Workers AI (${model}) hat leeren Text geliefert`, true);
    if (request.json && output.choices?.[0]?.finish_reason === "length") {
      throw new ProviderError(`Workers AI (${model}): Antwort abgeschnitten`, false);
    }
    return { text, model, provider: "workers_ai", usage: chatUsage(output) };
  }
  throw lastError ?? new ProviderError("Workers AI ohne Ergebnis", true);
}
