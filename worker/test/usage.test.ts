import { describe, expect, it } from "vitest";
import { guestToken } from "../src/auth";
import { handle } from "../src/index";
import type { Env } from "../src/types";
import {
  checkQuota,
  DEFAULT_GUEST_DAILY_LIMIT,
  dailyLimit,
  nextReset,
  recordUsage,
  type UsageStore,
  usageDay,
} from "../src/usage";
import { env, fakeDeps, geminiText } from "./helpers";

/** Mittwoch, 11.11.2026, 12:00 UTC. */
const NOW = Date.UTC(2026, 10, 11, 12);

function memoryStore(): UsageStore & { data: Map<string, { value: string; metadata?: unknown }> } {
  const data = new Map<string, { value: string; metadata?: unknown }>();
  return {
    data,
    get: async (key) => data.get(key)?.value ?? null,
    put: async (key, value, options) => {
      data.set(key, { value, metadata: options?.metadata });
    },
    list: async ({ prefix, limit }) => ({
      keys: [...data.entries()]
        .filter(([key]) => key.startsWith(prefix))
        .slice(0, limit)
        .map(([name, entry]) => ({ name, metadata: entry.metadata })),
      list_complete: true,
    }),
  };
}

const withStore = (store: UsageStore, extra: Partial<Env> = {}): Env =>
  ({ ...env, LEAGUE: store as unknown as KVNamespace, ...extra }) as Env;

async function guest(id = "abcdefghjkmn"): Promise<string> {
  return guestToken("app-token-123", id);
}

const generate = (token: string, task = "ping") =>
  new Request("https://coach-ai.example.workers.dev/v1/ai/generate", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ task }),
  });

const get = (path: string, token: string) =>
  new Request(`https://coach-ai.example.workers.dev${path}`, {
    headers: { authorization: `Bearer ${token}` },
  });

const ok = () => geminiText('{"punkte": ["Heute locker bleiben."]}');
const bodyOf = async (response: Response) => (await response.json()) as any;

describe("Grenzen", () => {
  it("Standard: Gäste 60 am Tag, Betreiber unbegrenzt, eigene Werte aus den Variablen", () => {
    expect(dailyLimit(env, { kind: "guest", id: "x" })).toBe(DEFAULT_GUEST_DAILY_LIMIT);
    expect(dailyLimit(env, { kind: "owner" })).toBe(0);
    expect(dailyLimit({ ...env, AI_GUEST_DAILY_LIMIT: "12" }, { kind: "guest", id: "x" })).toBe(12);
    expect(dailyLimit({ ...env, AI_GUEST_DAILY_LIMIT: "0" }, { kind: "guest", id: "x" })).toBe(0);
    expect(dailyLimit({ ...env, AI_GUEST_DAILY_LIMIT: "viel" }, { kind: "guest", id: "x" })).toBe(60);
    expect(dailyLimit({ ...env, AI_OWNER_DAILY_LIMIT: "100" }, { kind: "owner" })).toBe(100);
  });

  it("Tageswechsel um Mitternacht UTC", () => {
    expect(usageDay(NOW)).toBe("2026-11-11");
    expect(nextReset(NOW)).toBe("2026-11-12T00:00:00.000Z");
  });
});

describe("Zählen und Begrenzen", () => {
  it("zählt Anfragen, Listenpreis, Aufgabe und Anbieter je Person und Tag", async () => {
    const store = memoryStore();
    const person = { kind: "guest" as const, id: "abcdefghjkmn" };
    await recordUsage(store, person, NOW, "meal_analyze", "gemini", 0.004);
    const record = await recordUsage(store, person, NOW, "coach_chat", "workers_ai", 0.0007);
    expect(record).toEqual({
      n: 2,
      usd: 0.0047,
      tasks: { meal_analyze: 1, coach_chat: 1 },
      providers: { gemini: 1, workers_ai: 1 },
    });
    // Anderer Tag und andere Person zählen getrennt.
    await recordUsage(store, person, NOW + 86_400_000, "coach_chat", "gemini", 0.001);
    await recordUsage(store, { kind: "owner" }, NOW, "coach_chat", "gemini", 0.001);
    expect(store.data.size).toBe(3);
  });

  it("sperrt einen Gast beim Limit mit klarer Meldung, der Betreiber bleibt frei", async () => {
    const store = memoryStore();
    const limited = withStore(store, { AI_GUEST_DAILY_LIMIT: "2" });
    const token = await guest();
    const deps = fakeDeps([ok, ok], NOW);
    for (let i = 0; i < 2; i++) {
      const response = await handle(generate(token, "daily_note"), limited, deps);
      expect(response.status).toBe(200);
    }
    const blocked = await handle(generate(token, "daily_note"), limited, deps);
    expect(blocked.status).toBe(429);
    expect(await bodyOf(blocked)).toMatchObject({
      code: "quota_exceeded",
      used: 2,
      limit: 2,
      resetsAt: "2026-11-12T00:00:00.000Z",
      error: expect.stringContaining("Tageslimit (2 Anfragen)"),
    });
    // Kein dritter Anbieteraufruf.
    expect(deps.calls).toHaveLength(2);

    const ownerDeps = fakeDeps([ok], NOW);
    expect((await handle(generate("app-token-123", "daily_note"), limited, ownerDeps)).status).toBe(200);
  });

  it("meldet die Restmenge in der Antwort", async () => {
    const store = memoryStore();
    const limited = withStore(store, { AI_GUEST_DAILY_LIMIT: "5" });
    const response = await handle(generate(await guest(), "daily_note"), limited, fakeDeps([ok], NOW));
    expect((await bodyOf(response)).quota).toEqual({ used: 1, limit: 5 });
  });

  it("der Verbindungstest ping zählt nicht und wird nie begrenzt", async () => {
    const store = memoryStore();
    const limited = withStore(store, { AI_GUEST_DAILY_LIMIT: "1" });
    const deps = fakeDeps([ok, ok, ok], NOW);
    for (let i = 0; i < 3; i++) {
      expect((await handle(generate(await guest(), "ping"), limited, deps)).status).toBe(200);
    }
    expect(store.data.size).toBe(0);
  });

  it("fehlgeschlagene Anfragen zählen nicht", async () => {
    const store = memoryStore();
    const limited = withStore(store, { AI_GUEST_DAILY_LIMIT: "5", AI_PROVIDER_ORDER: "gemini" });
    const only = { ...limited, GROQ_API_KEY: undefined };
    const deps = fakeDeps(
      [
        () => new Response("{}", { status: 500 }),
        () => new Response("{}", { status: 500 }),
        () => new Response("{}", { status: 500 }),
        () => new Response("{}", { status: 500 }),
        () => new Response("{}", { status: 500 }),
        () => new Response("{}", { status: 500 }),
      ],
      NOW,
    );
    const response = await handle(generate(await guest(), "daily_note"), only, deps);
    expect(response.status).toBe(502);
    expect(store.data.size).toBe(0);
  });

  it("Tagesbudget in Dollar sperrt, sobald der Listenpreis erreicht ist", async () => {
    const store = memoryStore();
    const person = { kind: "guest" as const, id: "abcdefghjkmn" };
    const budgeted = withStore(store, { AI_GUEST_DAILY_LIMIT: "0", AI_GUEST_DAILY_BUDGET_USD: "0.01" });
    await recordUsage(store, person, NOW, "meal_analyze", "gemini", 0.011);
    const quota = await checkQuota(budgeted, store, person, NOW);
    expect(quota).toMatchObject({ allowed: false, reason: "budget" });
    expect(await checkQuota(budgeted, store, person, NOW + 86_400_000)).toMatchObject({ allowed: true });
  });

  it("fällt der Speicher aus, läuft die KI weiter (nie wegen des Zählers abschalten)", async () => {
    const broken: UsageStore = {
      get: async () => {
        throw new Error("KV down");
      },
      put: async () => {
        throw new Error("KV Schreibgrenze");
      },
      list: async () => ({ keys: [] }),
    };
    const deps = fakeDeps([ok], NOW);
    const response = await handle(generate(await guest(), "daily_note"), withStore(broken), deps);
    expect(response.status).toBe(200);
    expect(deps.logs.some((line) => line.includes("[usage]"))).toBe(true);
  });

  it("ohne Speicher gibt es keine Grenze", async () => {
    const response = await handle(generate(await guest(), "daily_note"), env, fakeDeps([ok], NOW));
    expect(response.status).toBe(200);
    expect((await bodyOf(response)).quota).toBeUndefined();
  });
});

describe("Übersicht", () => {
  async function filled() {
    const store = memoryStore();
    const a = { kind: "guest" as const, id: "aaaaaaaaaaaa" };
    const b = { kind: "guest" as const, id: "bbbbbbbbbbbb" };
    await recordUsage(store, a, NOW, "meal_analyze", "gemini", 0.01);
    await recordUsage(store, a, NOW, "coach_chat", "gemini", 0.02);
    await recordUsage(store, a, NOW - 86_400_000, "coach_chat", "gemini", 0.02);
    await recordUsage(store, b, NOW, "daily_note", "workers_ai", 0.001);
    await recordUsage(store, { kind: "owner" }, NOW - 40 * 86_400_000, "coach_chat", "gemini", 5);
    return withStore(store);
  }

  it("eigene Nutzung: heute mit Limit und letzte Tage", async () => {
    const withData = await filled();
    const token = await guest("aaaaaaaaaaaa");
    const response = await handle(get("/v1/usage", token), withData, fakeDeps([], NOW));
    const body = await bodyOf(response);
    expect(response.status).toBe(200);
    expect(body).toMatchObject({ day: "2026-11-11", limit: 60, used: 2 });
    expect(body.days).toHaveLength(7);
    expect(body.days[1]).toMatchObject({ day: "2026-11-10", n: 1 });
  });

  it("Betreiber sieht alle Personen, Summen und den Durchschnitt je aktiver Person", async () => {
    const withData = await filled();
    const response = await handle(get("/v1/usage/all", "app-token-123"), withData, fakeDeps([], NOW));
    expect(response.status).toBe(200);
    const body = await bodyOf(response);
    // Der Eintrag von vor 40 Tagen liegt außerhalb der 31 Tage.
    expect(body.total).toEqual({ n: 4, usd: 0.051, people: 2 });
    expect(body.averageUsdPerActivePerson).toBe(0.0255);
    expect(body.people[0]).toMatchObject({ person: "guest:aaaaaaaaaaaa", n: 3, usd: 0.05, activeDays: 2 });
    expect(body.people[0].tasks).toEqual({ meal_analyze: 1, coach_chat: 2 });
    expect(body.perDay[0]).toMatchObject({ day: "2026-11-11", n: 3, people: 2 });
    expect(body.note).toContain("Listenpreis");
  });

  it("Gäste dürfen die Gesamtübersicht nicht sehen", async () => {
    const withData = await filled();
    const response = await handle(get("/v1/usage/all", await guest()), withData, fakeDeps([], NOW));
    expect(response.status).toBe(403);
  });

  it("verlangt Anmeldung und nur GET", async () => {
    const unauthorized = await handle(get("/v1/usage", "falsch"), env, fakeDeps([], NOW));
    expect(unauthorized.status).toBe(401);
    const post = new Request("https://x/v1/usage", {
      method: "POST",
      headers: { authorization: "Bearer app-token-123" },
    });
    expect((await handle(post, env, fakeDeps([], NOW))).status).toBe(405);
  });
});
