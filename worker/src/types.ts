export interface Env {
  /** Secrets (per Deploy-Workflow aus GitHub-Secrets gesetzt). */
  GEMINI_API_KEY?: string;
  GROQ_API_KEY?: string;
  CEREBRAS_API_KEY?: string;
  MISTRAL_API_KEY?: string;
  /** Fine-grained Token mit „Models: Read-only“ für GitHub Models. */
  GH_MODELS_TOKEN?: string;
  COACH_APP_TOKEN?: string;
  /** Gesperrte Gast-IDs (siehe auth.ts), durch Komma getrennt. */
  REVOKED_GUESTS?: string;
  /** Workers KV „coach-releases“: IPA und Versionsangaben für die private SideStore-Quelle. */
  RELEASES?: KVNamespace;
  /** Workers KV „coach-league“: Ranglisten (nur Namen und Punkte). */
  LEAGUE?: KVNamespace;
  /** D1 „coach-social“: Konten, Sitzungen, Einladungen (siehe db.ts, accounts.ts). */
  DB?: D1Database;
  /** Variablen aus wrangler.jsonc. */
  GEMINI_MODEL?: string;
  GEMINI_FALLBACK_MODEL?: string;
  GROQ_MODEL?: string;
  GROQ_VISION_MODEL?: string;
  CEREBRAS_MODEL?: string;
  MISTRAL_MODEL?: string;
  MISTRAL_VISION_MODEL?: string;
  GITHUB_MODEL?: string;
  /** Workers AI (Binding „AI“ in wrangler.jsonc): offene Modelle bei Cloudflare, kein eigener Key nötig. */
  AI?: WorkersAiBinding;
  WORKERS_AI_MODEL?: string;
  /** Eigener OpenAI-kompatibler Server (z. B. Ollama/LM Studio per Tunnel, OpenRouter, Mistral). */
  OPENAI_COMPAT_URL?: string;
  OPENAI_COMPAT_KEY?: string;
  OPENAI_COMPAT_MODEL?: string;
  /** Reihenfolge der Anbieter bei „Automatisch“, z. B. "gemini,workers_ai,groq". */
  AI_PROVIDER_ORDER?: string;
  /**
   * Reihenfolge je Aufgabe als JSON, z. B. {"weekly_recipes": "gemini,cerebras"}. Ergänzt bzw. ersetzt die
   * Standardzuordnung in providers.ts (TASK_ROUTES); nicht genannte Anbieter folgen danach.
   */
  AI_TASK_ORDER?: string;
  /** KI-Tageslimit je Gast (Anfragen, Standard 60, 0 = unbegrenzt) und für den Betreiber (Standard 0). */
  AI_GUEST_DAILY_LIMIT?: string;
  AI_OWNER_DAILY_LIMIT?: string;
  /** Optionales Tagesbudget je Gast in US-Dollar (Listenpreis, 0 = aus). */
  AI_GUEST_DAILY_BUDGET_USD?: string;
  /** WHOOP-App aus dem Developer-Dashboard (siehe whoop.ts); das Secret bleibt im Worker. */
  WHOOP_CLIENT_ID?: string;
  WHOOP_CLIENT_SECRET?: string;
}

/** Ausschnitt des Workers-AI-Bindings, den der Worker nutzt (Tests ersetzen ihn). */
export interface WorkersAiBinding {
  run(model: string, input: unknown, options?: unknown): Promise<unknown>;
}

export interface ImageInput {
  mimeType: string;
  /** Base64 ohne `data:`-Präfix. */
  data: string;
}

export interface GenerateRequest {
  system?: string;
  prompt: string;
  json: boolean;
  images: ImageInput[];
  temperature?: number;
  /** Längere Antworten (z. B. Wochenrezepte); Standard 4096. */
  maxOutputTokens?: number;
  /** Wenig Denk-Tokens: Sie zählen zum Antwortlimit und sind bei großen JSON-Antworten sonst das Problem. */
  lowThinking?: boolean;
  /** Zeitpunkt (ms), bis zu dem die Antwort da sein muss; die App wartet nicht länger. */
  deadline?: number;
  /** Aufgabe (z. B. `meal_analyze`): bestimmt die Reihenfolge der Anbieter. */
  task?: string;
}

export type ProviderId =
  | "gemini"
  | "cerebras"
  | "groq"
  | "mistral"
  | "github"
  | "workers_ai"
  | "openai_compat";

/** Verbrauch einer Anfrage, so wie der Anbieter ihn meldet (fehlt, wenn er nichts meldet). */
export interface Usage {
  inputTokens: number;
  outputTokens: number;
}

export interface GenerateResult {
  text: string;
  model: string;
  provider: ProviderId;
  usage?: Usage;
}

/** Abhängigkeiten, die Tests ersetzen. */
export interface Deps {
  fetch: typeof fetch;
  sleep: (ms: number) => Promise<void>;
  now: () => number;
  log: (message: string) => void;
}

export const defaultDeps: Deps = {
  fetch: (input, init) => fetch(input, init),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now: () => Date.now(),
  log: (message) => console.log(message),
};

export class ProviderError extends Error {
  constructor(
    message: string,
    /** true: ein anderes Modell oder ein späterer Versuch kann helfen. */
    readonly retryable: boolean,
    readonly status?: number,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}

const ATTEMPT_MS = 75_000;

/** Zeit für einen einzelnen Versuch: begrenzt, und nie länger als die App noch wartet. */
export function attemptMilliseconds(request: GenerateRequest, deps: Deps): number {
  if (request.deadline === undefined) return ATTEMPT_MS;
  return Math.min(ATTEMPT_MS, Math.max(request.deadline - deps.now(), 1_000));
}

export function attemptSignal(request: GenerateRequest, deps: Deps): AbortSignal {
  return AbortSignal.timeout(attemptMilliseconds(request, deps));
}
