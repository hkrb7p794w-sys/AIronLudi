import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import { handleShare, newCode, type ShareStore, sanitizeMeal, sharePage } from "../src/share";
import { env, fakeDeps } from "./helpers";

function memoryStore(): ShareStore & { data: Map<string, string>; ttl: number[] } {
  const data = new Map<string, string>();
  const ttl: number[] = [];
  return {
    data,
    ttl,
    get: async (key) => data.get(key) ?? null,
    put: async (key, value, options) => {
      data.set(key, value);
      ttl.push(options?.expirationTtl ?? 0);
    },
    delete: async (key) => {
      data.delete(key);
    },
  };
}

const meal = {
  title: "Reis mit Hähnchen",
  items: [
    {
      name: "Reis gekocht",
      grams: 200,
      per100g: { kcal: 130, protein_g: 2.7 },
      source: "BLS 4.0",
      extra: "weg",
    },
    { name: "Hähnchenbrust", grams: 150, per100g: { kcal: 110, "böse key": 1 } },
    { name: "", grams: 10 },
  ],
  owner: "Alex",
};

const request = (method: string, path: string, body?: unknown) =>
  new Request(`https://w.example${path}`, {
    method,
    headers: { authorization: `Bearer ${env.COACH_APP_TOKEN}` },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

describe("Mahlzeiten teilen", () => {
  it("legt ab, holt und zieht zurück – nur bekannte Felder, 7 Tage", async () => {
    const store = memoryStore();
    const now = new Date("2026-11-02T10:00:00Z");
    const created = await handleShare(
      request("POST", "/v1/share/meal", meal),
      store,
      now,
      "owner",
      () => "abcdefgh23",
    );
    expect(created?.status).toBe(200);
    expect(await created?.json()).toMatchObject({
      code: "abcdefgh23",
      expiresAt: "2026-11-09T10:00:00.000Z",
    });
    expect(store.ttl).toEqual([7 * 24 * 3600]);

    const fetched = await handleShare(request("GET", "/v1/share/meal/abcdefgh23"), store, now);
    const body = (await fetched?.json()) as {
      title: string;
      owner?: string;
      items: Record<string, unknown>[];
    };
    expect(body.title).toBe("Reis mit Hähnchen");
    expect(body.owner).toBeUndefined();
    expect(body.items).toHaveLength(2);
    expect(body.items[0]?.extra).toBeUndefined();
    expect(body.items[1]?.per100g).toEqual({ kcal: 110 });

    await handleShare(request("DELETE", "/v1/share/meal/abcdefgh23"), store, now);
    expect((await handleShare(request("GET", "/v1/share/meal/abcdefgh23"), store, now))?.status).toBe(404);
  });

  it("nur wer geteilt hat, darf zurückziehen", async () => {
    const store = memoryStore();
    const now = new Date("2026-11-02T10:00:00Z");
    await handleShare(
      request("POST", "/v1/share/meal", meal),
      store,
      now,
      "guest:aaaaaaaaaaaa",
      () => "abcdefgh23",
    );
    const foreign = await handleShare(request("DELETE", "/v1/share/meal/abcdefgh23"), store, now, "owner");
    expect(foreign?.status).toBe(403);
    // Lesen dürfen alle mit Zugang (dafür ist der Code da).
    expect(
      (await handleShare(request("GET", "/v1/share/meal/abcdefgh23"), store, now, "owner"))?.status,
    ).toBe(200);
    const own = await handleShare(
      request("DELETE", "/v1/share/meal/abcdefgh23"),
      store,
      now,
      "guest:aaaaaaaaaaaa",
    );
    expect(own?.status).toBe(200);
    expect((await handleShare(request("GET", "/v1/share/meal/abcdefgh23"), store, now))?.status).toBe(404);
  });

  it("lehnt Leeres, Ungültiges und zu Großes ab", async () => {
    const store = memoryStore();
    const now = new Date();
    expect(sanitizeMeal({ items: [] })).toBe("Mahlzeit ohne Positionen");
    expect((await handleShare(request("GET", "/v1/share/meal/NICHT-OK"), store, now))?.status).toBe(400);
    const big = { title: "x", items: [{ name: "y".repeat(30_000), grams: 1 }] };
    expect((await handleShare(request("POST", "/v1/share/meal", big), store, now))?.status).toBe(413);
    expect(await handleShare(request("GET", "/v1/other"), store, now)).toBeNull();
  });

  it("Code ohne Verwechsler, Seite ohne Inhalt, Zugriff nur mit Token", async () => {
    expect(newCode()).toMatch(/^[a-z2-9]{10}$/);
    expect(newCode()).not.toMatch(/[01lo]/);
    const page = sharePage("/m/abcdefgh23");
    expect(page?.headers.get("content-type")).toContain("text/html");
    expect(await page?.text()).toContain("coach://meal/abcdefgh23");
    expect(sharePage("/m/../../x")).toBeNull();
    const unauthorized = await handle(
      new Request("https://w.example/v1/share/meal/abcdefgh23"),
      { ...env, LEAGUE: memoryStore() as unknown as KVNamespace },
      fakeDeps([]),
    );
    expect(unauthorized.status).toBe(401);
  });
});
