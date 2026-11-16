import { beforeEach, describe, expect, it } from "vitest";
import { DEFAULT_VISION_MODEL, generateWithGroq, pickModel, resetGroqState } from "../src/groq";
import { env, fakeDeps, groqText, jsonResponse, textResponse } from "./helpers";

describe("groq", () => {
  beforeEach(() => resetGroqState());

  it("sendet OpenAI-kompatible Nachrichten mit JSON-Modus", async () => {
    const deps = fakeDeps([() => groqText('{"ok":true}')]);
    const result = await generateWithGroq({ prompt: "p", system: "s", json: true, images: [] }, env, deps);
    expect(result).toEqual({ text: '{"ok":true}', model: "llama-3.3-70b-versatile", provider: "groq" });
    expect(deps.calls[0]?.url).toBe("https://api.groq.com/openai/v1/chat/completions");
    expect(deps.calls[0]?.body).toMatchObject({
      messages: [
        { role: "system", content: "s" },
        { role: "user", content: "p" },
      ],
      response_format: { type: "json_object" },
    });
  });

  it("nutzt für Bilder das Vision-Modell und Data-URLs", async () => {
    const deps = fakeDeps([() => groqText("Bild")]);
    await generateWithGroq(
      { prompt: "p", json: false, images: [{ mimeType: "image/png", data: "QUJD" }] },
      env,
      deps,
    );
    const body = deps.calls[0]?.body as { model: string; messages: { content: unknown }[] };
    expect(body.model).toBe(DEFAULT_VISION_MODEL);
    expect(body.messages[0]?.content).toEqual([
      { type: "text", text: "p" },
      { type: "image_url", image_url: { url: "data:image/png;base64,QUJD" } },
    ]);
  });

  it("ersetzt ein abgekündigtes Modell aus der Modellliste", async () => {
    const deps = fakeDeps([
      () => textResponse(400, '{"error":{"code":"model_decommissioned"}}'),
      () =>
        jsonResponse(200, {
          data: [{ id: "whisper-large-v3" }, { id: "openai/gpt-oss-120b", active: true }],
        }),
      () => groqText("neu"),
    ]);
    const result = await generateWithGroq({ prompt: "p", json: false, images: [] }, env, deps);
    expect(result.model).toBe("openai/gpt-oss-120b");
  });

  it("wiederholt bei 429 einmal", async () => {
    const deps = fakeDeps([() => textResponse(429, "slow down"), () => groqText("ok")]);
    const result = await generateWithGroq({ prompt: "p", json: false, images: [] }, env, deps);
    expect(result.text).toBe("ok");
  });

  it("wählt Modelle nach Vorliebe", () => {
    expect(pickModel(["a", "llama-4-scout-x", "llama-3.3-70b-y"], [/llama-3\.3/, /llama/], "a")).toBe(
      "llama-3.3-70b-y",
    );
    expect(pickModel(["a"], [/b/], "a")).toBeUndefined();
  });
});
