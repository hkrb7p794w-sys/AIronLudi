import { beforeEach, describe, expect, it } from "vitest";
import { generateWithGemini, modelFrom404, rankFallbacks, resetGeminiState } from "../src/gemini";
import type { GenerateRequest } from "../src/types";
import { env, fakeDeps, geminiText, jsonResponse, textResponse } from "./helpers";

const request: GenerateRequest = { prompt: "Hallo", json: false, images: [] };
const models = jsonResponse(200, {
  models: [
    { name: "models/gemini-3.6-flash", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-3.6-flash-lite", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-3.6-flash-image", supportedGenerationMethods: ["generateContent"] },
    { name: "models/gemini-3.6-pro", supportedGenerationMethods: ["generateContent"] },
  ],
});

describe("gemini", () => {
  beforeEach(() => resetGeminiState());

  it("liest das Nachfolgemodell aus der 404-Meldung", () => {
    const message =
      "This model models/gemini-2.5-flash is no longer available. Please use models/gemini-3.6-flash.";
    expect(modelFrom404(message, "gemini-2.5-flash")).toBe("gemini-3.6-flash");
    expect(modelFrom404("nichts", "x")).toBeUndefined();
  });

  it("sortiert lite zuerst und Vorschauen zuletzt", () => {
    expect(rankFallbacks(["b-flash-preview", "a-flash", "c-flash-lite", "main"], "main")).toEqual([
      "c-flash-lite",
      "a-flash",
      "b-flash-preview",
    ]);
  });

  it("liefert Text und sendet Key im Header, JSON-Modus und Bilder", async () => {
    const deps = fakeDeps([() => geminiText('{"ok": true}')]);
    const result = await generateWithGemini(
      { prompt: "p", json: true, images: [{ mimeType: "image/jpeg", data: "QUJD" }], system: "s" },
      env,
      deps,
    );
    expect(result).toEqual({ text: '{"ok": true}', model: "gemini-3.6-flash", provider: "gemini" });
    expect(deps.calls[0]).toMatchObject({
      url: expect.stringContaining("/models/gemini-3.6-flash:generateContent"),
      init: { headers: { "x-goog-api-key": "gemini-key" } },
    });
    expect(deps.calls[0]?.body ?? {}).toMatchObject({
      contents: [{ parts: [{ text: "p" }, { inlineData: { mimeType: "image/jpeg", data: "QUJD" } }] }],
      systemInstruction: { parts: [{ text: "s" }] },
      generationConfig: { responseMimeType: "application/json" },
    });
  });

  it("folgt dem Nachfolgemodell bei 404", async () => {
    const deps = fakeDeps([
      () => textResponse(404, "models/gemini-3.6-flash is gone, use models/gemini-3.7-flash"),
      () => geminiText("ok"),
    ]);
    const result = await generateWithGemini(request, env, deps);
    expect(result.model).toBe("gemini-3.7-flash");
  });

  it("wiederholt bei 503 und weicht danach auf ein lite-Modell aus", async () => {
    const deps = fakeDeps([
      () => textResponse(503, "overloaded"),
      () => textResponse(503, "overloaded"),
      () => textResponse(429, "quota"),
      () => models,
      () => geminiText("vom Ausweichmodell"),
    ]);
    const result = await generateWithGemini(request, env, deps);
    expect(result).toMatchObject({ text: "vom Ausweichmodell", model: "gemini-3.6-flash-lite" });
    expect(deps.calls[3]?.url).toContain("/models?pageSize=200");

    // Innerhalb der Abkühlzeit geht der nächste Aufruf direkt an das Ausweichmodell.
    const next = fakeDeps([() => geminiText("direkt")], deps.now());
    const second = await generateWithGemini(request, env, next);
    expect(second.model).toBe("gemini-3.6-flash-lite");
    expect(next.calls).toHaveLength(1);
  });

  it("bricht bei 400 ohne Ausweichen ab", async () => {
    const deps = fakeDeps([() => textResponse(400, "bad request")]);
    await expect(generateWithGemini(request, env, deps)).rejects.toMatchObject({
      retryable: false,
      status: 400,
    });
    expect(deps.calls).toHaveLength(1);
  });

  it("behandelt leeren Text (Denk-Budget aufgebraucht) als wiederholbar", async () => {
    const empty = () =>
      jsonResponse(200, { candidates: [{ content: { parts: [] }, finishReason: "MAX_TOKENS" }] });
    const deps = fakeDeps([empty, () => geminiText("zweiter Versuch")]);
    const result = await generateWithGemini(request, env, deps);
    expect(result.text).toBe("zweiter Versuch");
  });

  it("meldet abgeschnittenes JSON statt es weiterzugeben", async () => {
    const cut = () =>
      jsonResponse(200, {
        candidates: [
          { content: { parts: [{ text: '{"items": [{"name": "Ei"' }] }, finishReason: "MAX_TOKENS" },
        ],
      });
    await expect(generateWithGemini({ ...request, json: true }, env, fakeDeps([cut]))).rejects.toMatchObject({
      retryable: false,
      message: expect.stringContaining("abgeschnitten"),
    });
    const text = await generateWithGemini({ ...request, json: false }, env, fakeDeps([cut]));
    expect(text.text).toContain("Ei");
  });

  it("verlangt einen Key", async () => {
    await expect(
      generateWithGemini(request, { ...env, GEMINI_API_KEY: undefined }, fakeDeps([])),
    ).rejects.toThrow("GEMINI_API_KEY");
  });
});
