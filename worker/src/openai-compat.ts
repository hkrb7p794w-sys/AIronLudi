/**
 * Anbieter mit OpenAI-kompatibler Chat-Completions-API: gehostet (Cerebras, Mistral) oder eigener Server (Ollama,
 * LM Studio, llama.cpp, vLLM – von außen erreichbar z. B. über Cloudflare Tunnel). Adresse, Key und Modell kommen aus
 * den Worker-Variablen; ohne Key bzw. Adresse ist der Anbieter aus.
 */
import { type ChatCompletion, chatUsage, messages } from "./groq";
import {
  attemptSignal,
  type Deps,
  type Env,
  type GenerateRequest,
  type GenerateResult,
  ProviderError,
  type ProviderId,
} from "./types";

export function compatBase(url: string | undefined): string | undefined {
  const trimmed = url?.trim().replace(/\/+$/, "");
  if (!trimmed || !/^https:\/\//.test(trimmed)) return undefined;
  return trimmed.endsWith("/chat/completions") ? trimmed.slice(0, -"/chat/completions".length) : trimmed;
}

export interface ChatEndpoint {
  provider: ProviderId;
  label: string;
  base: string;
  model: string;
  key?: string;
  /** Name des Feldes für die Antwortlänge (Cerebras: `max_completion_tokens`, sonst `max_tokens`). */
  maxTokensField?: "max_tokens" | "max_completion_tokens";
  /** Mistral erwartet `image_url` als Zeichenkette statt als Objekt. */
  imageUrlAsString?: boolean;
  /** Zusätzliche Felder, z. B. `reasoning_effort` für gpt-oss. */
  extra?: Record<string, unknown>;
}

function chatMessages(request: GenerateRequest, imageUrlAsString: boolean): unknown[] {
  const list = messages(request);
  if (!imageUrlAsString) return list;
  return list.map((message) => {
    const content = (message as { content?: unknown }).content;
    if (!Array.isArray(content)) return message;
    return {
      ...(message as object),
      content: content.map((part: { type?: string; image_url?: { url?: string } }) =>
        part.type === "image_url" ? { type: "image_url", image_url: part.image_url?.url } : part,
      ),
    };
  });
}

/** Ein Aufruf; 429 und 5xx gelten als vorübergehend, der Worker weicht dann auf den nächsten Anbieter aus. */
export async function generateWithChatEndpoint(
  endpoint: ChatEndpoint,
  request: GenerateRequest,
  deps: Deps,
): Promise<GenerateResult> {
  const { label, model } = endpoint;
  let response: Response;
  try {
    response = await deps.fetch(`${endpoint.base}/chat/completions`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(endpoint.key ? { authorization: `Bearer ${endpoint.key}` } : {}),
      },
      body: JSON.stringify({
        model,
        messages: chatMessages(request, endpoint.imageUrlAsString === true),
        [endpoint.maxTokensField ?? "max_tokens"]: request.maxOutputTokens ?? 4096,
        temperature: request.temperature ?? 0.4,
        ...(request.json ? { response_format: { type: "json_object" } } : {}),
        ...endpoint.extra,
      }),
      signal: attemptSignal(request, deps),
    });
  } catch (error) {
    throw new ProviderError(`${label} nicht erreichbar: ${String(error)}`, true);
  }
  const raw = await response.text();
  if (response.status === 429 || response.status >= 500) {
    throw new ProviderError(`${label} HTTP ${response.status} (${model})`, true, response.status);
  }
  if (!response.ok) {
    throw new ProviderError(`${label} HTTP ${response.status} (${model})`, false, response.status);
  }
  let body: ChatCompletion;
  try {
    body = JSON.parse(raw) as ChatCompletion;
  } catch {
    throw new ProviderError(`${label} (${model}): Antwort ist kein JSON`, true);
  }
  const text = body.choices?.[0]?.message?.content?.trim();
  if (!text) throw new ProviderError(`${label} (${model}) hat leeren Text geliefert`, true);
  if (request.json && body.choices?.[0]?.finish_reason === "length") {
    throw new ProviderError(`${label} (${model}): Antwort abgeschnitten`, false);
  }
  return { text, model, provider: endpoint.provider, usage: chatUsage(body) };
}

export async function generateWithOpenAiCompat(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<GenerateResult> {
  const base = compatBase(env.OPENAI_COMPAT_URL);
  const model = env.OPENAI_COMPAT_MODEL?.trim();
  if (!base || !model) throw new ProviderError("Eigener Server ist nicht eingerichtet", false);
  return generateWithChatEndpoint(
    { provider: "openai_compat", label: "Eigener Server", base, model, key: env.OPENAI_COMPAT_KEY },
    request,
    deps,
  );
}

export const CEREBRAS_BASE = "https://api.cerebras.ai/v1";
export const DEFAULT_CEREBRAS_MODEL = "gpt-oss-120b";

/** Cerebras: sehr schnell, großes kostenloses Tageskontingent, keine Bilder. */
export async function generateWithCerebras(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<GenerateResult> {
  if (!env.CEREBRAS_API_KEY) throw new ProviderError("CEREBRAS_API_KEY ist nicht gesetzt", false);
  const model = env.CEREBRAS_MODEL?.trim() || DEFAULT_CEREBRAS_MODEL;
  return generateWithChatEndpoint(
    {
      provider: "cerebras",
      label: "Cerebras",
      base: CEREBRAS_BASE,
      model,
      key: env.CEREBRAS_API_KEY,
      maxTokensField: "max_completion_tokens",
      // Denk-Tokens zählen zum Antwortlimit; bei großen JSON-Antworten wenig denken (wie bei Gemini).
      ...(/gpt-oss/.test(model)
        ? { extra: { reasoning_effort: request.lowThinking ? "low" : "medium" } }
        : {}),
    },
    request,
    deps,
  );
}

export const MISTRAL_BASE = "https://api.mistral.ai/v1";
export const DEFAULT_MISTRAL_MODEL = "mistral-medium-latest";

/** Mistral: europäischer Anbieter, gutes Deutsch, Bilder mit demselben Modell. */
export async function generateWithMistral(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<GenerateResult> {
  if (!env.MISTRAL_API_KEY) throw new ProviderError("MISTRAL_API_KEY ist nicht gesetzt", false);
  const model =
    (request.images.length > 0 ? env.MISTRAL_VISION_MODEL?.trim() : undefined) ||
    env.MISTRAL_MODEL?.trim() ||
    DEFAULT_MISTRAL_MODEL;
  return generateWithChatEndpoint(
    {
      provider: "mistral",
      label: "Mistral",
      base: MISTRAL_BASE,
      model,
      key: env.MISTRAL_API_KEY,
      imageUrlAsString: true,
    },
    request,
    deps,
  );
}

export const GITHUB_MODELS_BASE = "https://models.github.ai/inference";
export const DEFAULT_GITHUB_MODEL = "openai/gpt-4.1";
/** Kostenlose Stufe: höchstens 4.000 Ausgabe-Tokens je Anfrage (größere Anfragen lehnt GitHub ab). */
const GITHUB_MAX_OUTPUT = 4000;

/** GitHub Models: mit dem GitHub-Konto kostenlos (knappe Tageslimits), Bilder je nach Modell. */
export async function generateWithGitHubModels(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<GenerateResult> {
  if (!env.GH_MODELS_TOKEN) throw new ProviderError("GH_MODELS_TOKEN ist nicht gesetzt", false);
  const model = env.GITHUB_MODEL?.trim() || DEFAULT_GITHUB_MODEL;
  return generateWithChatEndpoint(
    {
      provider: "github",
      label: "GitHub Models",
      base: GITHUB_MODELS_BASE,
      model,
      key: env.GH_MODELS_TOKEN,
    },
    { ...request, maxOutputTokens: Math.min(request.maxOutputTokens ?? 4096, GITHUB_MAX_OUTPUT) },
    deps,
  );
}
