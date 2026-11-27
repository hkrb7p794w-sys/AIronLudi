import { describe, expect, it } from "vitest";
import { guestToken } from "../src/auth";
import { handle } from "../src/index";
import { MAX_ROUTES, type WatchStore } from "../src/watch";
import { env, fakeDeps } from "./helpers";

const DEVICE = "abcdef0123456789abcdef0123456789";

function memoryStore(): WatchStore & { values: Map<string, string>; ttl: Map<string, number | undefined> } {
  const values = new Map<string, string>();
  const ttl = new Map<string, number | undefined>();
  return {
    values,
    ttl,
    get: async (key) => values.get(key) ?? null,
    put: async (key, value, options) => {
      values.set(key, value);
      ttl.set(key, options?.expirationTtl);
    },
    delete: async (key) => {
      values.delete(key);
    },
  };
}

function setup() {
  const store = memoryStore();
  const testEnv = { ...env, LEAGUE: store as unknown as KVNamespace };
  const call = (method: string, path: string, body?: unknown, token?: string) =>
    handle(
      new Request(`https://x${path}`, {
        method,
        headers: {
          "content-type": "application/json",
          ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      }),
      testEnv,
      fakeDeps([]),
    );
  return { store, call };
}

const routeBody = (name = "Runde am Kanal") => ({
  name,
  distanceMeters: 10123,
  bytes: 9000,
  chunks: ["QUlXMQ==", "AAAA"],
});

describe("Karte auf der Uhr", () => {
  it("koppelt die Uhr über einen Code; der Geräteschlüssel liegt nur als Hash", async () => {
    const { store, call } = setup();
    const hello = await (await call("POST", "/v1/watch/hello", { device: DEVICE })).json();
    expect(hello).toMatchObject({ paired: false });
    const code = (hello as { code: string }).code;
    expect(code).toMatch(/^[A-HJKMNP-Z2-9]{6}$/);
    // Gleiche Uhr fragt erneut: gleicher Code.
    expect(await (await call("POST", "/v1/watch/hello", { device: DEVICE })).json()).toMatchObject({ code });
    expect([...store.values.keys()].join(" ")).not.toContain(DEVICE);
    expect(store.ttl.get(`watch:code:${code}`)).toBe(15 * 60);

    // Ohne Anmeldung kein Koppeln; mit Anmeldung (auch Kleinschreibung) gekoppelt.
    expect((await call("POST", "/v1/watch/pair", { code })).status).toBe(401);
    expect((await call("POST", "/v1/watch/pair", { code: "ZZZZZZ" }, "app-token-123")).status).toBe(404);
    const paired = await call("POST", "/v1/watch/pair", { code: code.toLowerCase() }, "app-token-123");
    expect(await paired.json()).toEqual({ paired: true });
    expect(await (await call("POST", "/v1/watch/hello", { device: DEVICE })).json()).toEqual({
      paired: true,
    });
    // Der Code ist verbraucht.
    expect((await call("POST", "/v1/watch/pair", { code }, "app-token-123")).status).toBe(404);
  });

  it("Routen hochladen, auf der Uhr auflisten und in Teilen abrufen; je Person getrennt", async () => {
    const { call } = setup();
    const { code } = (await (await call("POST", "/v1/watch/hello", { device: DEVICE })).json()) as {
      code: string;
    };
    expect((await call("GET", `/v1/watch/index?device=${DEVICE}`)).status).toBe(403);
    await call("POST", "/v1/watch/pair", { code }, "app-token-123");

    const put = await call("PUT", "/v1/watch/routes/r-1", routeBody(), "app-token-123");
    expect(put.status).toBe(200);
    const index = (await (await call("GET", `/v1/watch/index?device=${DEVICE}`)).json()) as {
      routes: { id: string; chunks: number; name: string }[];
    };
    expect(index.routes).toHaveLength(1);
    expect(index.routes[0]).toMatchObject({
      id: "r-1",
      name: "Runde am Kanal",
      chunks: 2,
      distanceMeters: 10123,
    });
    const chunk = await (await call("GET", `/v1/watch/chunk?device=${DEVICE}&route=r-1&n=1`)).json();
    expect(chunk).toEqual({ route: "r-1", n: 1, count: 2, data: "AAAA" });
    expect((await call("GET", `/v1/watch/chunk?device=${DEVICE}&route=r-1&n=2`)).status).toBe(404);

    // Andere Person (Gast) sieht nichts davon.
    const guest = await guestToken("app-token-123", "abcdefghjkmn");
    expect(await (await call("GET", "/v1/watch/routes", undefined, guest)).json()).toEqual({ routes: [] });

    // Löschen.
    const deleted = await call("DELETE", "/v1/watch/routes/r-1", undefined, "app-token-123");
    expect(await deleted.json()).toEqual({ routes: [] });
  });

  it("höchstens fünf Routen; die älteste fällt weg; Grenzen werden geprüft", async () => {
    const { store, call } = setup();
    for (let i = 0; i < MAX_ROUTES + 1; i++) {
      await call("PUT", `/v1/watch/routes/r-${i}`, routeBody(`Route ${i}`), "app-token-123");
    }
    const list = (await (await call("GET", "/v1/watch/routes", undefined, "app-token-123")).json()) as {
      routes: { id: string }[];
    };
    expect(list.routes.map((route) => route.id)).toEqual(["r-5", "r-4", "r-3", "r-2", "r-1"]);
    expect(store.values.has("watch:route:owner:r-0")).toBe(false);

    expect(
      (await call("PUT", "/v1/watch/routes/r-x", { ...routeBody(), chunks: [] }, "app-token-123")).status,
    ).toBe(400);
    expect(
      (await call("PUT", "/v1/watch/routes/r-x", { ...routeBody(), bytes: 500_000 }, "app-token-123")).status,
    ).toBe(413);
    expect((await call("PUT", "/v1/watch/routes/bad id", routeBody(), "app-token-123")).status).toBe(404);
    expect((await call("POST", "/v1/watch/hello", { device: "kurz" })).status).toBe(400);
  });
});
