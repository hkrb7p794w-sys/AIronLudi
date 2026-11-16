import { describe, expect, it } from "vitest";
import { generate } from "../src/ai";
import { compatBase } from "../src/openai-compat";
import { listPriceUsd, parsePreference, providerInfo, providerOrder } from "../src/providers";
import type { Env, GenerateRequest, WorkersAiBinding } from "../src/types";
import { env, fakeDeps, geminiText, groqText, jsonResponse } from "./helpers";

const request: GenerateRequest = { prompt: "Hallo", json: true, images: [] };

function workersAi(
  result: unknown | Error,
): WorkersAiBinding & { calls: { model: string; input: unknown }[] } {
  const calls: { model: string; input: unknown }[] = [];
  return {
    calls,
    run: async (model, input) => {
      calls.push({ model, input });
      if (result instanceof Error) throw result;
      return result;
    },
  };
}

const ids = (list: { id: string }[]) => list.map((provider) => provider.id);

describe("providerOrder", () => {
  it("standard, eigene Reihenfolge, Vorliebe", () => {
    expect(ids(providerOrder(env, "auto"))).toEqual([
      "gemini",
      "cerebras",
      "groq",
      "github",
      "workers_ai",
      "mistral",
      "openai_compat",
    ]);
    expect(ids(providerOrder({ ...env, AI_PROVIDER_ORDER: "groq, workers_ai" }, "auto"))).toEqual([
      "groq",
      "workers_ai",
      "gemini",
      "cerebras",
      "github",
      "mistral",
      "openai_compat",
    ]);
    expect(ids(providerOrder(env, "gemini"))[0]).toBe("gemini");
  });

  it("privat schickt nichts an Anbieter, die mit Eingaben trainieren", () => {
    expect(ids(providerOrder(env, "privat"))).toEqual([
      "openai_compat",
      "cerebras",
      "groq",
      "github",
      "workers_ai",
    ]);
    expect(ids(providerOrder(env, "workers_ai"))).toEqual([
      "workers_ai",
      "cerebras",
      "groq",
      "github",
      "openai_compat",
    ]);
    // Auch mit Aufgaben-Reihenfolge nie Gemini oder das kostenlose Mistral.
    expect(ids(providerOrder(env, "privat", true, "meal_analyze"))).toEqual(["github", "groq", "workers_ai"]);
  });

  it("Bilder nur an Anbieter mit Bild-Eingabe", () => {
    expect(ids(providerOrder(env, "privat", true))).not.toContain("openai_compat");
  });

  it("Reihenfolge je Aufgabe: Fotos zu Gemini/GitHub/Mistral, Pläne zu Cerebras, kurze Hinweise zu Groq", () => {
    expect(ids(providerOrder(env, "auto", true, "meal_analyze"))).toEqual([
      "gemini",
      "github",
      "mistral",
      "groq",
      "workers_ai",
    ]);
    expect(ids(providerOrder(env, "auto", false, "weekly_recipes")).slice(0, 3)).toEqual([
      "cerebras",
      "gemini",
      "github",
    ]);
    expect(ids(providerOrder(env, "auto", false, "coach_chat")).slice(0, 2)).toEqual(["gemini", "cerebras"]);
    expect(ids(providerOrder(env, "auto", false, "gym_hints"))[0]).toBe("groq");
    // Unbekannte Aufgabe: Standard.
    expect(ids(providerOrder(env, "auto", false, "ping"))[0]).toBe("gemini");
    // Ausdrückliche Wahl in der App gewinnt.
    expect(ids(providerOrder(env, "mistral", false, "weekly_recipes"))[0]).toBe("mistral");
  });

  it("AI_TASK_ORDER ersetzt die Standardzuordnung, ungültiges JSON wird ignoriert", () => {
    const custom = { ...env, AI_TASK_ORDER: '{"weekly_recipes": "gemini, workers_ai"}' };
    expect(ids(providerOrder(custom, "auto", false, "weekly_recipes")).slice(0, 3)).toEqual([
      "gemini",
      "workers_ai",
      "cerebras",
    ]);
    expect(ids(providerOrder(custom, "auto", false, "gym_hints"))[0]).toBe("groq");
    const broken = { ...env, AI_TASK_ORDER: "{kaputt" };
    expect(ids(providerOrder(broken, "auto", false, "weekly_recipes"))[0]).toBe("cerebras");
  });

  it("unbekannte Vorliebe = auto", () => {
    expect(parsePreference("quatsch")).toBe("auto");
    expect(parsePreference("workers_ai")).toBe("workers_ai");
  });
});

describe("Workers AI", () => {
  it("antwortet im Chat-Format mit Verbrauch und ohne Denkmodus", async () => {
    const ai = workersAi({
      choices: [{ message: { content: '{"ok": true}' } }],
      usage: { prompt_tokens: 1000, completion_tokens: 200 },
    });
    const result = await generate(request, { ...env, AI: ai }, fakeDeps([]), "workers_ai");
    expect(result).toMatchObject({ provider: "workers_ai", text: '{"ok": true}' });
    expect(result.usage).toEqual({ inputTokens: 1000, outputTokens: 200 });
    expect(ai.calls[0]?.model).toBe("@cf/google/gemma-4-26b-a4b-it");
    expect(ai.calls[0]?.input).toMatchObject({
      response_format: { type: "json_object" },
      chat_template_kwargs: { enable_thinking: false },
    });
  });

  it("ältere Antwortform und Objekt im JSON-Modus", async () => {
    const ai = workersAi({ response: { ok: true } });
    const result = await generate(request, { ...env, AI: ai }, fakeDeps([]), "workers_ai");
    expect(result.text).toBe('{"ok":true}');
  });

  it("Kapazitätsfehler: weiter zum nächsten Anbieter", async () => {
    const ai = workersAi(new Error("3040: Capacity temporarily exceeded"));
    const deps = fakeDeps([() => groqText('{"ok": true}')]);
    const result = await generate(request, { ...env, AI: ai }, deps, "workers_ai");
    expect(result.provider).toBe("groq");
    expect(ai.calls.length).toBe(2);
  });

  it("ohne Binding wird übersprungen", async () => {
    const deps = fakeDeps([() => geminiText('{"ok": true}')]);
    const result = await generate(request, env, deps, "auto");
    expect(result.provider).toBe("gemini");
  });
});

describe("Cerebras und Mistral", () => {
  const keys: Env = { ...env, CEREBRAS_API_KEY: "c", MISTRAL_API_KEY: "m" };
  const ok = () =>
    jsonResponse(200, { choices: [{ message: { content: "{}" } }], usage: { prompt_tokens: 7 } });

  it("Cerebras: gpt-oss mit wenig Denken bei großen JSON-Antworten", async () => {
    const deps = fakeDeps([ok]);
    const result = await generate(
      { ...request, lowThinking: true, maxOutputTokens: 9000, task: "weekly_recipes" },
      keys,
      deps,
    );
    expect(result.provider).toBe("cerebras");
    expect(deps.calls[0]?.url).toBe("https://api.cerebras.ai/v1/chat/completions");
    expect(deps.calls[0]?.body).toMatchObject({
      model: "gpt-oss-120b",
      max_completion_tokens: 9000,
      reasoning_effort: "low",
      response_format: { type: "json_object" },
    });
    expect(new Headers(deps.calls[0]?.init?.headers).get("authorization")).toBe("Bearer c");
  });

  it("Mistral: Bild als Zeichenkette, eigenes Bildmodell möglich", async () => {
    const deps = fakeDeps([ok]);
    const result = await generate(
      { ...request, images: [{ mimeType: "image/jpeg", data: "QUJD" }], task: "meal_analyze" },
      { ...keys, GEMINI_API_KEY: undefined, MISTRAL_VISION_MODEL: "pixtral-large-latest" },
      deps,
    );
    expect(result.provider).toBe("mistral");
    expect(deps.calls[0]?.url).toBe("https://api.mistral.ai/v1/chat/completions");
    const body = deps.calls[0]?.body as { model: string; messages: { content: unknown }[] };
    expect(body.model).toBe("pixtral-large-latest");
    expect(body.messages.at(-1)?.content).toEqual([
      { type: "text", text: "Hallo" },
      { type: "image_url", image_url: "data:image/jpeg;base64,QUJD" },
    ]);
  });

  it("Kontingent erschöpft (429): weiter zum nächsten Anbieter", async () => {
    const deps = fakeDeps([() => jsonResponse(429, { error: "rate" }), () => groqText("{}")]);
    const result = await generate(
      { ...request, task: "weekly_recipes" },
      { ...keys, GEMINI_API_KEY: undefined },
      deps,
    );
    expect(result.provider).toBe("groq");
    expect(deps.calls.map((call) => new URL(call.url).host)).toEqual(["api.cerebras.ai", "api.groq.com"]);
  });

  it("GitHub Models: Token, gpt-4.1, Antwortlänge auf 4.000 begrenzt, Fotos als Objekt", async () => {
    const deps = fakeDeps([ok]);
    const result = await generate(
      {
        ...request,
        maxOutputTokens: 9000,
        images: [{ mimeType: "image/jpeg", data: "QUJD" }],
        task: "meal_analyze",
      },
      { ...env, GEMINI_API_KEY: undefined, GH_MODELS_TOKEN: "ghp" },
      deps,
    );
    expect(result.provider).toBe("github");
    expect(deps.calls[0]?.url).toBe("https://models.github.ai/inference/chat/completions");
    const body = deps.calls[0]?.body as {
      model: string;
      max_tokens: number;
      messages: { content: unknown }[];
    };
    expect(body).toMatchObject({ model: "openai/gpt-4.1", max_tokens: 4000 });
    expect(body.messages.at(-1)?.content).toEqual([
      { type: "text", text: "Hallo" },
      { type: "image_url", image_url: { url: "data:image/jpeg;base64,QUJD" } },
    ]);
    expect(new Headers(deps.calls[0]?.init?.headers).get("authorization")).toBe("Bearer ghp");
  });

  it("ohne Key übersprungen und als nicht eingerichtet gemeldet", () => {
    const info = providerInfo(env) as { id: string; enabled: boolean; vision: boolean }[];
    expect(info.find((p) => p.id === "cerebras")).toMatchObject({ enabled: false, vision: false });
    expect(info.find((p) => p.id === "mistral")).toMatchObject({ enabled: false, vision: true });
  });
});

describe("eigener Server", () => {
  const own: Env = {
    ...env,
    OPENAI_COMPAT_URL: "https://llm.example.org/v1/",
    OPENAI_COMPAT_MODEL: "qwen3:14b",
  };

  it("ruft die OpenAI-kompatible API auf", async () => {
    const deps = fakeDeps([
      () => jsonResponse(200, { choices: [{ message: { content: "{}" } }], usage: { prompt_tokens: 5 } }),
    ]);
    const result = await generate(request, { ...own, OPENAI_COMPAT_KEY: "k" }, deps, "privat");
    expect(result.provider).toBe("openai_compat");
    expect(deps.calls[0]?.url).toBe("https://llm.example.org/v1/chat/completions");
    expect(deps.calls[0]?.body).toMatchObject({ model: "qwen3:14b" });
    expect(result.usage).toEqual({ inputTokens: 5, outputTokens: 0 });
    expect(listPriceUsd("openai_compat", "qwen3:14b", result.usage)).toBe(0);
  });

  it("nur https", () => {
    expect(compatBase("http://192.168.0.2:11434/v1")).toBeUndefined();
    expect(compatBase("https://x.org/v1/chat/completions")).toBe("https://x.org/v1");
  });

  it("privat ohne passende Anbieter: klare Fehlermeldung, nichts an Gemini", async () => {
    const onlyGemini: Env = { GEMINI_API_KEY: "g", COACH_APP_TOKEN: "t" };
    const deps = fakeDeps([]);
    await expect(generate(request, onlyGemini, deps, "privat")).rejects.toThrow(/nicht eingerichtet/);
    expect(deps.calls.length).toBe(0);
  });
});

describe("Kosten und Übersicht", () => {
  it("Listenpreis aus Tokens", () => {
    expect(
      listPriceUsd("workers_ai", "@cf/google/gemma-4-26b-a4b-it", {
        inputTokens: 1_000_000,
        outputTokens: 0,
      }),
    ).toBe(0.1);
    expect(listPriceUsd("gemini", "x", undefined)).toBeUndefined();
  });

  it("Übersicht zeigt eingerichtete Anbieter", () => {
    const info = providerInfo({ ...env, AI: workersAi({}) }) as { id: string; enabled: boolean }[];
    expect(info.find((entry) => entry.id === "workers_ai")?.enabled).toBe(true);
    expect(info.find((entry) => entry.id === "openai_compat")?.enabled).toBe(false);
  });
});

describe("Antwort der App-Schnittstelle", () => {
  it("liefert Verbrauch und Listenpreis, Vorliebe aus der Anfrage", async () => {
    const { handle } = await import("../src/index");
    const deps = fakeDeps([
      () =>
        jsonResponse(200, {
          candidates: [
            { content: { parts: [{ text: '{"ok": true, "gruss": "Hallo"}' }] }, finishReason: "STOP" },
          ],
          usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 20, thoughtsTokenCount: 5 },
        }),
    ]);
    const response = await handle(
      new Request("https://w.example/v1/ai/generate", {
        method: "POST",
        headers: { authorization: `Bearer ${env.COACH_APP_TOKEN}` },
        body: JSON.stringify({ task: "ping", provider: "gemini" }),
      }),
      env,
      deps,
    );
    const body = (await response.json()) as { usage?: { inputTokens: number; outputTokens: number } };
    expect(response.status).toBe(200);
    expect(body.usage).toMatchObject({ inputTokens: 100, outputTokens: 25 });
  });
});
