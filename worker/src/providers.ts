/**
 * Anbieter-Register: Jeder KI-Anbieter ist ein Eintrag mit gleicher Schnittstelle. Neue Anbieter oder Modelle
 * kommen hier dazu, ohne Aufgaben, Prompts oder die App zu ändern. Die App wählt nur eine Vorliebe
 * (`auto`, `privat` oder einen Anbieter); welche Anbieter eingerichtet sind, entscheidet der Worker.
 */
import { generateWithGemini } from "./gemini";
import { generateWithGroq } from "./groq";
import {
  compatBase,
  DEFAULT_CEREBRAS_MODEL,
  DEFAULT_GITHUB_MODEL,
  DEFAULT_MISTRAL_MODEL,
  generateWithCerebras,
  generateWithGitHubModels,
  generateWithMistral,
  generateWithOpenAiCompat,
} from "./openai-compat";
import type { Deps, Env, GenerateRequest, GenerateResult, ProviderId, Usage } from "./types";
import { DEFAULT_WORKERS_AI_MODEL, generateWithWorkersAi } from "./workers-ai";

export interface ProviderDefinition {
  id: ProviderId;
  label: string;
  enabled(env: Env): boolean;
  /** Modell, das ohne Ausweichen genutzt wird (für die Anzeige). */
  model(env: Env): string;
  /** Kostenlose Kontingente dürfen Eingaben zur Produktverbesserung nutzen (Gemini, „Unpaid Services“). */
  usesInputsForTraining: boolean;
  /** Bilder (Mahlzeit, Etikett) möglich. */
  vision: boolean;
  /** Listenpreis in US-Dollar je Million Tokens (Eingabe, Ausgabe) – Schätzung, falls bezahlt würde. */
  pricePerMillion(model: string): [number, number];
  run(request: GenerateRequest, env: Env, deps: Deps): Promise<GenerateResult>;
}

/** Listenpreise Workers AI (developers.cloudflare.com/workers-ai/platform/pricing, Stand 20.10.2026). */
const WORKERS_AI_PRICES: Record<string, [number, number]> = {
  "@cf/google/gemma-4-26b-a4b-it": [0.1, 0.3],
  "@cf/qwen/qwen3-30b-a3b-fp8": [0.051, 0.335],
  "@cf/qwen/qwen3.8-27b": [0.45, 3.2],
  "@cf/openai/gpt-oss-120b": [0.35, 0.75],
  "@cf/openai/gpt-oss-20b": [0.2, 0.3],
  "@cf/meta/llama-4-scout-17b-16e-instruct": [0.27, 0.85],
  "@cf/deepseek-ai/deepseek-v4.1-flash-1017": [0.3, 1.2],
};

export const PROVIDERS: ProviderDefinition[] = [
  {
    id: "gemini",
    label: "Google Gemini",
    enabled: (env) => Boolean(env.GEMINI_API_KEY),
    model: (env) => env.GEMINI_MODEL?.trim() || "gemini-3.6-flash",
    usesInputsForTraining: true,
    vision: true,
    // Im kostenlosen Kontingent 0 €; Listenpreis grob wie Gemini Flash.
    pricePerMillion: () => [0.3, 2.5],
    run: generateWithGemini,
  },
  {
    id: "cerebras",
    label: "Cerebras",
    enabled: (env) => Boolean(env.CEREBRAS_API_KEY),
    model: (env) => env.CEREBRAS_MODEL?.trim() || DEFAULT_CEREBRAS_MODEL,
    // Laut Cerebras keine Nutzung von API-Eingaben zum Training.
    usesInputsForTraining: false,
    vision: false,
    pricePerMillion: () => [0.35, 0.75],
    run: generateWithCerebras,
  },
  {
    id: "groq",
    label: "Groq",
    enabled: (env) => Boolean(env.GROQ_API_KEY),
    model: (env) => env.GROQ_MODEL?.trim() || "llama-3.3-70b-versatile",
    usesInputsForTraining: false,
    vision: true,
    pricePerMillion: () => [0.59, 0.79],
    run: generateWithGroq,
  },
  {
    id: "github",
    label: "GitHub Models",
    enabled: (env) => Boolean(env.GH_MODELS_TOKEN),
    model: (env) => env.GITHUB_MODEL?.trim() || DEFAULT_GITHUB_MODEL,
    // Laut GitHub werden Eingaben nicht zum Training genutzt.
    usesInputsForTraining: false,
    vision: true,
    pricePerMillion: () => [2, 8],
    run: generateWithGitHubModels,
  },
  {
    id: "workers_ai",
    label: "Cloudflare Workers AI",
    enabled: (env) => Boolean(env.AI),
    model: (env) => env.WORKERS_AI_MODEL?.trim() || DEFAULT_WORKERS_AI_MODEL,
    usesInputsForTraining: false,
    vision: true,
    pricePerMillion: (model) => WORKERS_AI_PRICES[model] ?? [0.3, 1],
    run: generateWithWorkersAi,
  },
  {
    id: "mistral",
    label: "Mistral",
    enabled: (env) => Boolean(env.MISTRAL_API_KEY),
    model: (env) => env.MISTRAL_MODEL?.trim() || DEFAULT_MISTRAL_MODEL,
    // Kostenlose Stufe „Experiment“: Mistral darf Eingaben zum Training nutzen (wie das kostenlose Gemini).
    usesInputsForTraining: true,
    vision: true,
    pricePerMillion: () => [0.4, 2],
    run: generateWithMistral,
  },
  {
    id: "openai_compat",
    label: "Eigener Server",
    enabled: (env) => Boolean(compatBase(env.OPENAI_COMPAT_URL) && env.OPENAI_COMPAT_MODEL?.trim()),
    model: (env) => env.OPENAI_COMPAT_MODEL?.trim() || "",
    usesInputsForTraining: false,
    vision: false,
    // Lokal: keine Gebühr je Token (Strom und Hardware zählen extra).
    pricePerMillion: () => [0, 0],
    run: generateWithOpenAiCompat,
  },
];

export type Preference = "auto" | "privat" | ProviderId;

/**
 * Standardreihenfolge je Aufgabe (danach alle übrigen Anbieter wie bei `auto`). Ziel: Jede Aufgabe beim Anbieter, der
 * sie am besten kann, und das knappe Gemini-Kontingent für Fotos und Gespräche aufheben.
 * - Fotos und Mahlzeiten: Gemini erkennt Bilder am besten, GitHub Models (GPT-4.1) und Mistral als weitere Bildmodelle.
 * - Pläne und Rezepte (lange JSON-Antworten): Cerebras (gpt-oss-120b) mit großem Kontingent zuerst.
 * - Gespräche und Auswertungen: Gemini, dann Cerebras.
 * - Kurze Hinweise: Groq (schnell), damit Gemini frei bleibt.
 * Ändern ohne Code: Worker-Variable AI_TASK_ORDER.
 */
export const TASK_ROUTES: Record<string, ProviderId[]> = {
  meal_analyze: ["gemini", "github", "mistral", "groq", "workers_ai", "cerebras"],
  meal_amend: ["gemini", "github", "mistral", "groq", "workers_ai", "cerebras"],
  nutrition_label: ["gemini", "github", "mistral", "groq", "workers_ai"],
  weekly_recipes: ["cerebras", "gemini", "github", "groq", "workers_ai", "mistral"],
  cook_plan: ["cerebras", "gemini", "github", "groq", "workers_ai", "mistral"],
  gym_plan: ["cerebras", "gemini", "github", "groq", "workers_ai", "mistral"],
  meal_now: ["cerebras", "gemini", "github", "groq", "workers_ai", "mistral"],
  // Foto von Kühlschrank oder Vorrat: zuerst die Bildmodelle.
  pantry_recipes: ["gemini", "github", "mistral", "groq", "workers_ai"],
  coach_chat: ["gemini", "cerebras", "github", "mistral", "groq", "workers_ai"],
  ai_insights: ["gemini", "cerebras", "github", "mistral", "groq", "workers_ai"],
  daily_note: ["gemini", "cerebras", "github", "mistral", "groq", "workers_ai"],
  personal_note: ["gemini", "cerebras", "github", "mistral", "groq", "workers_ai"],
  nutrition_review: ["gemini", "cerebras", "github", "mistral", "groq", "workers_ai"],
  gym_hints: ["groq", "cerebras", "gemini", "github", "workers_ai", "mistral"],
};

function idList(value: unknown): string[] {
  return typeof value === "string"
    ? value
        .split(",")
        .map((id) => id.trim())
        .filter(Boolean)
    : [];
}

/** Reihenfolge für eine Aufgabe: AI_TASK_ORDER (JSON) vor TASK_ROUTES; ungültiges JSON wird ignoriert. */
export function taskRoute(env: Env, task: string | undefined): string[] {
  if (!task) return [];
  if (env.AI_TASK_ORDER?.trim()) {
    try {
      const custom = JSON.parse(env.AI_TASK_ORDER) as Record<string, unknown>;
      const route = idList(custom?.[task]);
      if (route.length) return route;
    } catch {
      // Ungültige Variable: Standard verwenden statt die Anfrage scheitern zu lassen.
    }
  }
  return TASK_ROUTES[task] ?? [];
}

export function parsePreference(value: unknown): Preference {
  if (value === "privat" || value === "auto") return value;
  return PROVIDERS.some((provider) => provider.id === value) ? (value as ProviderId) : "auto";
}

/**
 * Reihenfolge der Versuche:
 * - `auto`: Reihenfolge der Aufgabe (TASK_ROUTES/AI_TASK_ORDER), danach AI_PROVIDER_ORDER bzw. Standard
 *   (Gemini, Cerebras, Groq, GitHub Models, Workers AI, Mistral, eigener Server).
 * - `privat`: nur Anbieter, die Eingaben nicht zum Training nutzen (eigener Server zuerst).
 * - ein Anbieter: dieser zuerst, danach die übrigen wie bei `auto` (bzw. `privat`, wenn er privat ist).
 * Bilder nur an Anbieter mit Bild-Eingabe.
 */
export function providerOrder(
  env: Env,
  preference: Preference,
  hasImages = false,
  task?: string,
): ProviderDefinition[] {
  const configured = [...taskRoute(env, task), ...idList(env.AI_PROVIDER_ORDER)];
  const byId = new Map(PROVIDERS.map((provider) => [provider.id, provider]));
  const base = [...configured.flatMap((id) => byId.get(id as ProviderId) ?? []), ...PROVIDERS];
  let ordered = [...new Set(base)];
  const privateOnly =
    preference === "privat" ||
    (preference !== "auto" && byId.get(preference)?.usesInputsForTraining === false);
  if (preference === "privat") {
    ordered = [
      ...ordered.filter((provider) => provider.id === "openai_compat"),
      ...ordered.filter((provider) => provider.id !== "openai_compat"),
    ];
  } else if (preference !== "auto") {
    const first = byId.get(preference);
    if (first) ordered = [first, ...ordered.filter((provider) => provider !== first)];
  }
  if (privateOnly) ordered = ordered.filter((provider) => !provider.usesInputsForTraining);
  if (hasImages) ordered = ordered.filter((provider) => provider.vision);
  return ordered;
}

/** Geschätzter Listenpreis einer Anfrage in US-Dollar (0 bei lokalem Server). */
export function listPriceUsd(
  provider: ProviderId,
  model: string,
  usage: Usage | undefined,
): number | undefined {
  if (!usage) return undefined;
  const definition = PROVIDERS.find((entry) => entry.id === provider);
  if (!definition) return undefined;
  const [input, output] = definition.pricePerMillion(model);
  return Math.round(((usage.inputTokens * input + usage.outputTokens * output) / 1_000_000) * 1e6) / 1e6;
}

/** Übersicht für die App (Einstellungen): eingerichtete Anbieter mit Modell und Datenschutz-Eigenschaften. */
export function providerInfo(env: Env): unknown[] {
  return PROVIDERS.map((provider) => ({
    id: provider.id,
    label: provider.label,
    enabled: provider.enabled(env),
    model: provider.enabled(env) ? provider.model(env) : null,
    usesInputsForTraining: provider.usesInputsForTraining,
    vision: provider.vision,
  }));
}
