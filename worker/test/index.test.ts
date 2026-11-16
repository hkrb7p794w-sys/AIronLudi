import { beforeEach, describe, expect, it } from "vitest";
import { parseJsonOutput } from "../src/ai";
import { resetGeminiState } from "../src/gemini";
import { resetGroqState } from "../src/groq";
import { handle, tokensMatch } from "../src/index";
import { env, fakeDeps, geminiText, groqText, textResponse } from "./helpers";

const post = (body: unknown, token = "app-token-123") =>
  new Request("https://coach-ai.example.workers.dev/v1/ai/generate", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

describe("worker", () => {
  beforeEach(() => {
    resetGeminiState();
    resetGroqState();
  });

  it("meldet Gesundheit ohne Anmeldung und ohne Keys preiszugeben", async () => {
    const response = await handle(new Request("https://x/v1/health"), env, fakeDeps([]));
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body).toMatchObject({ status: "ok", providers: { gemini: true, groq: true }, configured: true });
    expect(JSON.stringify(body)).not.toContain("gemini-key");
  });

  it("lehnt falsche oder fehlende Tokens ab", async () => {
    expect((await handle(post({ task: "ping" }, "falsch"), env, fakeDeps([]))).status).toBe(401);
    const noAuth = new Request("https://x/v1/ai/generate", { method: "POST", body: "{}" });
    expect((await handle(noAuth, env, fakeDeps([]))).status).toBe(401);
  });

  it("ist ohne App-Token gesperrt", async () => {
    const response = await handle(
      post({ task: "ping" }),
      { ...env, COACH_APP_TOKEN: undefined },
      fakeDeps([]),
    );
    expect(response.status).toBe(503);
  });

  it("prüft Aufgabe, Eingabe und Bilder", async () => {
    const deps = fakeDeps([]);
    expect((await handle(post("kein json"), env, deps)).status).toBe(400);
    expect((await handle(post({ task: "toString" }), env, deps)).status).toBe(400);
    expect((await handle(post({ task: "ping", input: [] }), env, deps)).status).toBe(400);
    const withImage = { task: "ping", images: [{ mimeType: "image/jpeg", data: "QUJD" }] };
    expect((await handle(post(withImage), env, deps)).status).toBe(400);
    expect(deps.calls).toHaveLength(0);
  });

  it("beantwortet ping über Gemini und parst JSON", async () => {
    const deps = fakeDeps([() => geminiText('```json\n{"ok": true, "gruss": "Hallo"}\n```')]);
    const response = await handle(post({ task: "ping" }), env, deps);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      output: { ok: true, gruss: "Hallo" },
      model: "gemini-3.6-flash",
      provider: "gemini",
    });
  });

  it("weicht auf Groq aus, wenn Gemini scheitert", async () => {
    const deps = fakeDeps([
      () => textResponse(400, "invalid"),
      () => groqText('{"ok": true, "gruss": "Hi"}'),
    ]);
    const response = await handle(post({ task: "ping" }), env, deps);
    expect(await response.json()).toMatchObject({ provider: "groq", output: { ok: true } });
  });

  it("meldet 502, wenn alle Anbieter scheitern", async () => {
    const deps = fakeDeps([() => textResponse(400, "a"), () => textResponse(401, "b")]);
    const response = await handle(post({ task: "ping" }), env, deps);
    expect(response.status).toBe(502);
    expect(((await response.json()) as { code: string }).code).toBe("ai_unavailable");
  });

  it("vergleicht Tokens vollständig", () => {
    expect(tokensMatch("abc", "abc")).toBe(true);
    expect(tokensMatch("abc", "abd")).toBe(false);
    expect(tokensMatch("abc", "abcd")).toBe(false);
    expect(tokensMatch("", "abc")).toBe(false);
  });

  it("liest JSON auch aus Codeblöcken", () => {
    expect(parseJsonOutput('{"a":1}')).toEqual({ a: 1 });
    expect(parseJsonOutput('Hier:\n```json\n{"a":2}\n```')).toEqual({ a: 2 });
    expect(() => parseJsonOutput("kein json")).toThrow();
    expect(parseJsonOutput('{"a":"}{"}\n{"b":[1,2]}')).toEqual([{ a: "}{" }, { b: [1, 2] }]);
    expect(() => parseJsonOutput('{"a": [1, 2')).toThrow();
  });
});
