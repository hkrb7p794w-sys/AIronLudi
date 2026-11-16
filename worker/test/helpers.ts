import type { Deps, Env } from "../src/types";

export interface Call {
  url: string;
  init?: RequestInit;
  body?: unknown;
}

type Responder = (call: Call) => Response | Promise<Response>;

/** Simuliertes fetch: arbeitet eine Liste von Antworten der Reihe nach ab und protokolliert Aufrufe. */
export function fakeDeps(
  responders: Responder[],
  start = 1_000_000,
): Deps & { calls: Call[]; logs: string[] } {
  const calls: Call[] = [];
  const logs: string[] = [];
  let clock = start;
  return {
    calls,
    logs,
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
      const call: Call = { url, init, body: init?.body ? JSON.parse(String(init.body)) : undefined };
      calls.push(call);
      const responder = responders.shift();
      if (!responder) throw new Error(`Unerwarteter Aufruf: ${url}`);
      return responder(call);
    }) as typeof fetch,
    sleep: async (ms) => {
      clock += ms;
    },
    now: () => clock,
    log: (message) => logs.push(message),
  };
}

export const jsonResponse = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

export const textResponse = (status: number, body: string) => new Response(body, { status });

export const geminiText = (text: string) =>
  jsonResponse(200, { candidates: [{ content: { parts: [{ text }] }, finishReason: "STOP" }] });

export const groqText = (text: string) => jsonResponse(200, { choices: [{ message: { content: text } }] });

export const env: Env = {
  GEMINI_API_KEY: "gemini-key",
  GROQ_API_KEY: "groq-key",
  COACH_APP_TOKEN: "app-token-123",
  GEMINI_MODEL: "gemini-3.6-flash",
};
