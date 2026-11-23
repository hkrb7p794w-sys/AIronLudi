import { describe, expect, it } from "vitest";
import { guestToken } from "../src/auth";
import { handle } from "../src/index";
import { type CounterStore, type MapsCache, parseRoundTrip, simplifyOrs } from "../src/maps";
import { env, fakeDeps, jsonResponse, textResponse } from "./helpers";

const mapsEnv = { ...env, ORS_API_KEY: "ors-key", MAPTILER_API_KEY: "tiles-key" };

const roundTrip = (body: unknown, token = "app-token-123") =>
  new Request("https://x/v1/maps/roundtrip", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });

const tile = (path: string, token = "app-token-123") =>
  new Request(`https://x/v1/maps/tiles/${path}`, { headers: { authorization: `Bearer ${token}` } });

const orsAnswer = () =>
  jsonResponse(200, {
    type: "FeatureCollection",
    features: [
      {
        geometry: {
          coordinates: [
            [13.405, 52.52, 34.21],
            [13.41, 52.53, 40],
            [13.405, 52.52, 34],
          ],
        },
        properties: { summary: { distance: 2345.6 } },
      },
    ],
  });

/** Cache im Speicher wie `caches.default` (nur, was mit `public` kommt). */
function memoryCache(): MapsCache & { entries: Map<string, Response> } {
  const entries = new Map<string, Response>();
  return {
    entries,
    match: async (request) => entries.get(request.url)?.clone(),
    put: async (request, response) => {
      expect(response.headers.get("cache-control")).toContain("public");
      entries.set(request.url, response);
    },
  };
}

function memoryCounters(): CounterStore & { values: Map<string, string> } {
  const values = new Map<string, string>();
  return {
    values,
    get: async (key) => values.get(key) ?? null,
    put: async (key, value) => {
      values.set(key, value);
    },
  };
}

describe("Kartendienste", () => {
  it("melden in /v1/health, ob sie eingerichtet sind – ohne Schlüssel preiszugeben", async () => {
    const response = await handle(new Request("https://x/v1/health"), mapsEnv, fakeDeps([]));
    const body = await response.json();
    expect(body).toMatchObject({ maps: { roundTrip: true, tiles: true } });
    expect(JSON.stringify(body)).not.toContain("ors-key");
    const without = await (await handle(new Request("https://x/v1/health"), env, fakeDeps([]))).json();
    expect(without).toMatchObject({ maps: { roundTrip: false, tiles: false } });
  });

  it("brauchen eine Anmeldung und den Schlüssel", async () => {
    const start = { lat: 52.52, lon: 13.405, lengthMeters: 5000, discipline: "run" };
    expect((await handle(roundTrip(start, "falsch"), mapsEnv, fakeDeps([]))).status).toBe(401);
    const missing = await handle(roundTrip(start), env, fakeDeps([]));
    expect(missing.status).toBe(503);
    expect(await missing.json()).toMatchObject({ code: "not_configured" });
    expect((await handle(tile("dark/3/4/2.png"), env, fakeDeps([]))).status).toBe(503);
  });

  it("prüft die Anfrage", () => {
    expect(parseRoundTrip({ lat: 52.52, lon: 13.405, lengthMeters: 100, discipline: "run" })).toContain(
      "Länge",
    );
    expect(parseRoundTrip({ lat: 152, lon: 13.405, lengthMeters: 5000, discipline: "run" })).toContain(
      "Start",
    );
    expect(parseRoundTrip({ lat: 52.52, lon: 13.405, lengthMeters: 5000, discipline: "ski" })).toContain(
      "Disziplin",
    );
    expect(
      parseRoundTrip({ lat: 52.520049, lon: 13.40501, lengthMeters: 5004, discipline: "gravel", seed: 4 }),
    ).toEqual({ lat: 52.52, lon: 13.405, lengthMeters: 5000, profile: "cycling-regular", seed: 4 });
  });

  it("holen einen Rundweg von openrouteservice, vereinfacht und zwischengespeichert", async () => {
    const cache = memoryCache();
    const deps = fakeDeps([orsAnswer]);
    const body = { lat: 52.52, lon: 13.405, lengthMeters: 2300, discipline: "roadBike", seed: 2 };
    const response = await handle(roundTrip(body), mapsEnv, deps, cache);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toContain("private");
    expect(await response.json()).toEqual({
      points: [
        [52.52, 13.405, 34.2],
        [52.53, 13.41, 40],
        [52.52, 13.405, 34],
      ],
      distanceMeters: 2346,
      engine: "openrouteservice",
    });
    expect(deps.calls[0]?.url).toBe("https://api.openrouteservice.org/v2/directions/cycling-road/geojson");
    expect(new Headers(deps.calls[0]?.init?.headers).get("authorization")).toBe("ors-key");
    expect(deps.calls[0]?.body).toMatchObject({
      coordinates: [[13.405, 52.52]],
      options: { round_trip: { length: 2300, seed: 2 } },
    });
    // Zweite gleiche Anfrage: aus dem Cache, ohne openrouteservice.
    const again = await handle(roundTrip(body), mapsEnv, fakeDeps([]), cache);
    expect(again.status).toBe(200);
    expect(deps.calls.length).toBe(1);
  });

  it("melden „kein Weg“, Auslastung und Tageslimit verständlich", async () => {
    const body = { lat: 52.52, lon: 13.405, lengthMeters: 5000, discipline: "walk" };
    const none = await handle(
      roundTrip(body),
      mapsEnv,
      fakeDeps([() => jsonResponse(404, { error: { code: 2009 } })]),
    );
    expect(none.status).toBe(404);
    expect(await none.json()).toMatchObject({ code: "no_route" });
    const busy = await handle(roundTrip(body), mapsEnv, fakeDeps([() => textResponse(429, "slow down")]));
    expect(busy.status).toBe(429);

    const counters = memoryCounters();
    const guest = await guestToken("app-token-123", "abcdefghjkmn");
    const limited = { ...mapsEnv, LEAGUE: counters as unknown as KVNamespace, MAPS_DAILY_LIMIT: "1" };
    expect((await handle(roundTrip(body, guest), limited, fakeDeps([orsAnswer]))).status).toBe(200);
    const over = await handle(roundTrip(body, guest), limited, fakeDeps([]));
    expect(over.status).toBe(429);
    expect(await over.json()).toMatchObject({ code: "maps_quota" });
    expect([...counters.values.keys()][0]).toContain("guest:abcdefghjkmn");
  });

  it("reichen Kacheln je Stil durch und speichern sie zwischen", async () => {
    const cache = memoryCache();
    const deps = fakeDeps([
      () => new Response(new Uint8Array([137, 80, 78, 71]), { headers: { "content-type": "image/png" } }),
    ]);
    const response = await handle(tile("dark/3/4/2.png"), mapsEnv, deps, cache);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("image/png");
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(new Uint8Array([137, 80, 78, 71]));
    expect(deps.calls[0]?.url).toBe(
      "https://api.maptiler.com/maps/streets-v2-dark/256/3/4/2.png?key=tiles-key",
    );
    expect((await handle(tile("dark/3/4/2.png"), mapsEnv, fakeDeps([]), cache)).status).toBe(200);
    expect((await handle(tile("neon/3/4/2.png"), mapsEnv, fakeDeps([]))).status).toBe(404);
    expect((await handle(tile("light/3/9/2.png"), mapsEnv, fakeDeps([]))).status).toBe(404);
  });

  it("vereinfachen nur gültige Antworten", () => {
    expect(simplifyOrs({ features: [] })).toBeNull();
    expect(simplifyOrs({ features: [{ geometry: { coordinates: [[1, 2]] } }] })).toBeNull();
  });
});
