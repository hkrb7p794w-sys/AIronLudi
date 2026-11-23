/**
 * Kartendienste mit Schlüssel für den Routenplaner. Die Schlüssel liegen nur hier (Worker-Secrets), nie in der App.
 *
 * POST /v1/maps/roundtrip                 – Rundweg von openrouteservice (ORS_API_KEY), vereinfacht zurückgegeben
 *      { "lat": 52.5, "lon": 13.4, "lengthMeters": 8000, "discipline": "run", "seed": 3 }
 *      → { "points": [[lat, lon, ele], …], "distanceMeters": 8123, "engine": "openrouteservice" }
 * GET  /v1/maps/tiles/<stil>/<z>/<x>/<y>.png – Kacheln von MapTiler (MAPTILER_API_KEY); Stile light, dark, outdoor
 *
 * Beides nur mit Anmeldung (wie die KI). Antworten liegen im Cloudflare-Cache (Rundwege 1 Tag, Kacheln 7 Tage), damit
 * die freien Kontingente reichen. Rundwege zusätzlich mit Tageslimit je Person (MAPS_DAILY_LIMIT, Standard 200).
 */

import type { Deps, Env } from "./types";

export const ROUNDTRIP_TTL_SECONDS = 24 * 60 * 60;
export const TILE_TTL_SECONDS = 7 * 24 * 60 * 60;
export const DEFAULT_DAILY_LIMIT = 200;
const ORS_URL = "https://api.openrouteservice.org/v2/directions";
const MAX_LENGTH_METERS = 100_000;
const MAX_POINTS = 4_000;

/** Profil von openrouteservice je Disziplin der App. */
export const ORS_PROFILES: Record<string, string> = {
  run: "foot-walking",
  walk: "foot-walking",
  roadBike: "cycling-road",
  gravel: "cycling-regular",
};

/** Stil der App → Karte bei MapTiler (Raster, 256 px). */
export const TILE_STYLES: Record<string, string> = {
  light: "streets-v2",
  dark: "streets-v2-dark",
  outdoor: "outdoor-v2",
};

/** Ausschnitt der Cache-API (`caches.default`), den der Worker nutzt; Tests ersetzen ihn. */
export interface MapsCache {
  match(request: Request): Promise<Response | undefined>;
  put(request: Request, response: Response): Promise<void>;
}

/** Ausschnitt von Workers KV für das Tageslimit. */
export interface CounterStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

export interface MapsContext {
  env: Env;
  deps: Deps;
  /** Wer anfragt (für das Tageslimit), z. B. `guest:<id>`. */
  principal: string;
  cache?: MapsCache;
  counters?: CounterStore;
}

function json(status: number, body: unknown, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra },
  });
}

/** Welche Kartendienste eingerichtet sind (für /v1/health und die App). */
export function mapsInfo(env: Env): { roundTrip: boolean; tiles: boolean } {
  return { roundTrip: Boolean(env.ORS_API_KEY), tiles: Boolean(env.MAPTILER_API_KEY) };
}

export async function handleMaps(request: Request, context: MapsContext): Promise<Response | null> {
  const { pathname } = new URL(request.url);
  if (pathname === "/v1/maps/roundtrip") {
    if (request.method !== "POST") return json(405, { error: "Nur POST" });
    return roundTrip(request, context);
  }
  const tile = /^\/v1\/maps\/tiles\/([a-z]+)\/(\d{1,2})\/(\d{1,7})\/(\d{1,7})\.png$/.exec(pathname);
  if (tile) {
    if (request.method !== "GET") return json(405, { error: "Nur GET" });
    const [, style, z, x, y] = tile;
    return tiles(style ?? "", Number(z), Number(x), Number(y), context);
  }
  return null;
}

export interface RoundTripInput {
  lat: number;
  lon: number;
  lengthMeters: number;
  profile: string;
  seed: number;
}

/** Prüft die Anfrage; Text = Fehlermeldung. */
export function parseRoundTrip(body: unknown): RoundTripInput | string {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return "Ungültiges JSON";
  const { lat, lon, lengthMeters, discipline, seed } = body as Record<string, unknown>;
  if (typeof lat !== "number" || typeof lon !== "number" || Math.abs(lat) > 90 || Math.abs(lon) > 180)
    return "Start fehlt oder ist ungültig";
  if (typeof lengthMeters !== "number" || lengthMeters < 500 || lengthMeters > MAX_LENGTH_METERS)
    return "Länge muss zwischen 500 m und 100 km liegen";
  const profile = typeof discipline === "string" ? ORS_PROFILES[discipline] : undefined;
  if (!profile) return "Unbekannte Disziplin";
  const seedValue = typeof seed === "number" && Number.isFinite(seed) ? Math.abs(Math.trunc(seed)) % 1000 : 0;
  // Gerundet: gleiche Anfragen treffen den Cache, ohne dass der Start genauer als ~10 m sein muss.
  return {
    lat: Math.round(lat * 10_000) / 10_000,
    lon: Math.round(lon * 10_000) / 10_000,
    lengthMeters: Math.round(lengthMeters / 10) * 10,
    profile,
    seed: seedValue,
  };
}

/** GeoJSON von openrouteservice → Punkte [lat, lon, ele] und Länge; `null`, wenn keine Strecke darin ist. */
export function simplifyOrs(body: unknown): { points: number[][]; distanceMeters: number } | null {
  const feature = (body as { features?: unknown[] } | null)?.features?.[0] as
    | { geometry?: { coordinates?: unknown }; properties?: { summary?: { distance?: unknown } } }
    | undefined;
  const coordinates = feature?.geometry?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null;
  const points: number[][] = [];
  for (const coordinate of coordinates) {
    if (!Array.isArray(coordinate) || typeof coordinate[0] !== "number" || typeof coordinate[1] !== "number")
      return null;
    const [lon, lat, ele] = coordinate as [number, number, number?];
    points.push(typeof ele === "number" ? [lat, lon, Math.round(ele * 10) / 10] : [lat, lon]);
  }
  const distance = feature?.properties?.summary?.distance;
  if (typeof distance !== "number") return null;
  return { points: thin(points, MAX_POINTS), distanceMeters: Math.round(distance) };
}

function thin(points: number[][], max: number): number[][] {
  if (points.length <= max) return points;
  const step = (points.length - 1) / (max - 1);
  return Array.from({ length: max }, (_, index) => points[Math.round(index * step)] ?? []);
}

/** Im Cache mit `public` ablegen (die Cache-API speichert `private` nicht); die App bekommt `private`. */
async function remember(
  cache: MapsCache | undefined,
  key: Request,
  response: Response,
  ttl: number,
): Promise<void> {
  if (!cache) return;
  const copy = new Response(response.clone().body, response);
  copy.headers.set("cache-control", `public, max-age=${ttl}`);
  await cache.put(key, copy);
}

function dayKey(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

async function roundTrip(request: Request, context: MapsContext): Promise<Response> {
  const { env, deps } = context;
  const key = env.ORS_API_KEY;
  if (!key)
    return json(503, {
      error: "Rundwege sind im Worker nicht eingerichtet (ORS_API_KEY fehlt)",
      code: "not_configured",
    });
  let body: unknown;
  try {
    body = JSON.parse(await request.text());
  } catch {
    return json(400, { error: "Ungültiges JSON" });
  }
  const input = parseRoundTrip(body);
  if (typeof input === "string") return json(400, { error: input });

  const cacheKey = new Request(
    `https://maps.cache/roundtrip/${input.profile}/${input.lat}/${input.lon}/${input.lengthMeters}/${input.seed}`,
  );
  const cached = await context.cache?.match(cacheKey);
  if (cached) return cached;

  // Tageslimit je Person (zählt nur Anfragen, die wirklich zu openrouteservice gehen).
  const limit = Number(env.MAPS_DAILY_LIMIT ?? DEFAULT_DAILY_LIMIT);
  const counterKey = `maps:${dayKey(deps.now())}:${context.principal}`;
  if (context.counters && limit > 0) {
    const used = Number((await context.counters.get(counterKey)) ?? 0);
    if (used >= limit)
      return json(429, {
        error: "Tageslimit für Rundwege erreicht – morgen geht es weiter.",
        code: "maps_quota",
      });
    await context.counters.put(counterKey, String(used + 1), { expirationTtl: 2 * 24 * 60 * 60 });
  }

  let response: Response;
  try {
    response = await deps.fetch(`${ORS_URL}/${input.profile}/geojson`, {
      method: "POST",
      headers: { authorization: key, "content-type": "application/json", accept: "application/geo+json" },
      body: JSON.stringify({
        coordinates: [[input.lon, input.lat]],
        elevation: true,
        instructions: false,
        options: { round_trip: { length: input.lengthMeters, points: 5, seed: input.seed } },
      }),
      signal: AbortSignal.timeout(25_000),
    });
  } catch (error) {
    deps.log(`ORS nicht erreichbar: ${String(error)}`);
    return json(502, { error: "openrouteservice ist gerade nicht erreichbar", code: "unavailable" });
  }
  if (response.status === 404 || response.status === 400) {
    // 2009 u. a.: kein Weg in der Nähe (z. B. Start im Wasser).
    return json(404, { error: "Kein Rundweg gefunden", code: "no_route" });
  }
  if (response.status === 429)
    return json(429, { error: "openrouteservice ist ausgelastet", code: "rate_limited" });
  if (!response.ok) {
    deps.log(`ORS antwortet ${response.status}`);
    return json(502, { error: `openrouteservice antwortet ${response.status}`, code: "unavailable" });
  }
  let simplified: ReturnType<typeof simplifyOrs>;
  try {
    simplified = simplifyOrs(await response.json());
  } catch {
    simplified = null;
  }
  if (!simplified)
    return json(502, { error: "Unerwartete Antwort von openrouteservice", code: "unavailable" });
  const result = json(
    200,
    { ...simplified, engine: "openrouteservice" },
    { "cache-control": `private, max-age=${ROUNDTRIP_TTL_SECONDS}` },
  );
  await remember(context.cache, cacheKey, result, ROUNDTRIP_TTL_SECONDS);
  return result;
}

async function tiles(
  style: string,
  z: number,
  x: number,
  y: number,
  context: MapsContext,
): Promise<Response> {
  const { env, deps } = context;
  const key = env.MAPTILER_API_KEY;
  if (!key)
    return json(503, { error: "Kartenkacheln sind im Worker nicht eingerichtet", code: "not_configured" });
  const map = TILE_STYLES[style];
  if (!map) return json(404, { error: "Unbekannter Kartenstil" });
  const size = 2 ** z;
  if (z > 20 || x >= size || y >= size) return json(404, { error: "Kachel außerhalb der Karte" });
  const cacheKey = new Request(`https://maps.cache/tiles/${map}/${z}/${x}/${y}.png`);
  const cached = await context.cache?.match(cacheKey);
  if (cached) return cached;
  let upstream: Response;
  try {
    upstream = await deps.fetch(
      `https://api.maptiler.com/maps/${map}/256/${z}/${x}/${y}.png?key=${encodeURIComponent(key)}`,
      {
        signal: AbortSignal.timeout(15_000),
      },
    );
  } catch {
    return json(502, { error: "Kartendienst nicht erreichbar" });
  }
  if (!upstream.ok)
    return json(upstream.status === 404 ? 404 : 502, { error: `Kartendienst antwortet ${upstream.status}` });
  const result = new Response(upstream.body, {
    status: 200,
    headers: {
      "content-type": upstream.headers.get("content-type") ?? "image/png",
      "cache-control": `private, max-age=${TILE_TTL_SECONDS}`,
    },
  });
  await remember(context.cache, cacheKey, result, TILE_TTL_SECONDS);
  return result;
}
