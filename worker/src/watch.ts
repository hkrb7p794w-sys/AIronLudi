/**
 * Karte auf der Garmin-Uhr (Connect-IQ-Datenfeld `garmin/`): Kopplung von Uhr und Konto, Ablage der Uhr-Pakete
 * (Route, Varianten, Wegenetz; Format `garmin/FORMAT.md`) und Abruf in Teilen durch die Uhr.
 *
 * Uhr (ohne App-Anmeldung – die Uhr hat kein Token; ihr Geräteschlüssel ist das Geheimnis):
 *   POST /v1/watch/hello  { "device": "<Geräteschlüssel>" } → { "paired": false, "code": "K7Q2PX" } bzw. { "paired": true }
 *   GET  /v1/watch/index?device=…                       → { "routes": [{ id, name, distanceMeters, bytes, chunks, updatedAt }] }
 *   GET  /v1/watch/chunk?device=…&route=…&n=0           → { "route", "n", "count", "data": "<Base64>" }
 * App (mit Anmeldung):
 *   POST   /v1/watch/pair          { "code": "K7Q2PX" }  → { "paired": true }
 *   PUT    /v1/watch/routes/<id>   { name, distanceMeters, bytes, chunks: [Base64 …] }
 *   GET    /v1/watch/routes        → wie /v1/watch/index (was auf der Uhr landet)
 *   DELETE /v1/watch/routes/<id>
 *
 * Ablage in KV (`LEAGUE`, Präfix `watch:`): Geräteschlüssel nur als SHA-256, Kopplungscodes 15 Minuten, Routen
 * 60 Tage, höchstens fünf je Person (die älteste fällt weg).
 */

export interface WatchStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
}

export const CODE_TTL_SECONDS = 15 * 60;
export const DEVICE_TTL_SECONDS = 365 * 24 * 60 * 60;
export const ROUTE_TTL_SECONDS = 60 * 24 * 60 * 60;
export const MAX_ROUTES = 5;
export const MAX_CHUNKS = 40;
/** Base64 eines Teils (6000 Bytes ergeben 8000 Zeichen). */
export const MAX_CHUNK_CHARS = 8200;
export const MAX_PACKAGE_BYTES = 200_000;
/** Ohne verwechselbare Zeichen (0/O, 1/I/L). */
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export interface WatchContext {
  store?: WatchStore;
  /** Angemeldete Person (`principalKey`), `null` ohne Anmeldung. */
  principal: string | null;
  now: number;
  /** Zufall für Kopplungscodes (Tests ersetzen ihn). */
  random?: () => number;
}

export interface WatchRouteInfo {
  id: string;
  name: string;
  distanceMeters: number;
  bytes: number;
  chunks: number;
  updatedAt: string;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function validDevice(value: unknown): value is string {
  return typeof value === "string" && value.length >= 16 && value.length <= 128 && /^[\w-]+$/.test(value);
}

function validRouteID(value: string): boolean {
  return /^[A-Za-z0-9-]{1,64}$/.test(value);
}

async function readJson(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const parsed: unknown = JSON.parse(await request.text());
    return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

async function readIndex(store: WatchStore, principal: string): Promise<WatchRouteInfo[]> {
  const raw = await store.get(`watch:index:${principal}`);
  if (!raw) return [];
  try {
    const list: unknown = JSON.parse(raw);
    return Array.isArray(list) ? (list as WatchRouteInfo[]) : [];
  } catch {
    return [];
  }
}

/** Person zu einem Geräteschlüssel (`null`: nicht gekoppelt). */
async function ownerOf(store: WatchStore, device: string): Promise<string | null> {
  return store.get(`watch:device:${await sha256(device)}`);
}

function newCode(random: () => number): string {
  let code = "";
  for (let i = 0; i < 6; i++) code += CODE_ALPHABET[Math.floor(random() * CODE_ALPHABET.length)];
  return code;
}

/** Wird von der Uhr ohne Anmeldung aufgerufen? (`index.ts` prüft sonst das App-Token.) */
export function isWatchDeviceRoute(pathname: string): boolean {
  return pathname === "/v1/watch/hello" || pathname === "/v1/watch/index" || pathname === "/v1/watch/chunk";
}

export async function handleWatch(request: Request, context: WatchContext): Promise<Response | null> {
  const url = new URL(request.url);
  const { pathname } = url;
  if (!pathname.startsWith("/v1/watch/")) return null;
  const store = context.store;
  if (!store) return json(503, { error: "Ablage nicht eingerichtet (KV LEAGUE fehlt)" });
  const random = context.random ?? Math.random;

  // Uhr
  if (pathname === "/v1/watch/hello") {
    if (request.method !== "POST") return json(405, { error: "Nur POST" });
    const body = await readJson(request);
    const device = body?.device;
    if (!validDevice(device)) return json(400, { error: "Geräteschlüssel fehlt" });
    if (await ownerOf(store, device)) return json(200, { paired: true });
    const hash = await sha256(device);
    let code = await store.get(`watch:pending:${hash}`);
    if (!code) {
      code = newCode(random);
      await store.put(`watch:code:${code}`, hash, { expirationTtl: CODE_TTL_SECONDS });
      await store.put(`watch:pending:${hash}`, code, { expirationTtl: CODE_TTL_SECONDS });
    }
    return json(200, { paired: false, code });
  }
  if (pathname === "/v1/watch/index" || pathname === "/v1/watch/chunk") {
    if (request.method !== "GET") return json(405, { error: "Nur GET" });
    const device = url.searchParams.get("device");
    if (!validDevice(device)) return json(400, { error: "Geräteschlüssel fehlt" });
    const owner = await ownerOf(store, device);
    if (!owner) return json(403, { error: "Uhr nicht gekoppelt", code: "not_paired" });
    if (pathname === "/v1/watch/index") return json(200, { routes: await readIndex(store, owner) });
    const route = url.searchParams.get("route") ?? "";
    const n = Number(url.searchParams.get("n"));
    if (!validRouteID(route) || !Number.isInteger(n) || n < 0)
      return json(400, { error: "Route oder Teil fehlt" });
    const raw = await store.get(`watch:route:${owner}:${route}`);
    if (!raw) return json(404, { error: "Route nicht gefunden" });
    const chunks = (JSON.parse(raw) as { chunks: string[] }).chunks;
    if (n >= chunks.length) return json(404, { error: "Teil nicht gefunden" });
    return json(200, { route, n, count: chunks.length, data: chunks[n] });
  }

  // App
  const principal = context.principal;
  if (!principal) return json(401, { error: "Nicht autorisiert", code: "unauthorized" });
  if (pathname === "/v1/watch/pair") {
    if (request.method !== "POST") return json(405, { error: "Nur POST" });
    const body = await readJson(request);
    const code = typeof body?.code === "string" ? body.code.trim().toUpperCase() : "";
    if (!/^[A-Z0-9]{6}$/.test(code)) return json(400, { error: "Code mit sechs Zeichen eingeben" });
    const hash = await store.get(`watch:code:${code}`);
    if (!hash) return json(404, { error: "Code unbekannt oder abgelaufen", code: "unknown_code" });
    await store.put(`watch:device:${hash}`, principal, { expirationTtl: DEVICE_TTL_SECONDS });
    await store.delete(`watch:code:${code}`);
    await store.delete(`watch:pending:${hash}`);
    return json(200, { paired: true });
  }
  if (pathname === "/v1/watch/routes") {
    if (request.method !== "GET") return json(405, { error: "Nur GET" });
    return json(200, { routes: await readIndex(store, principal) });
  }
  const match = /^\/v1\/watch\/routes\/([^/]+)$/.exec(pathname);
  if (!match?.[1] || !validRouteID(match[1])) return json(404, { error: "Nicht gefunden" });
  const id = match[1];
  const key = `watch:route:${principal}:${id}`;
  if (request.method === "DELETE") {
    await store.delete(key);
    const index = (await readIndex(store, principal)).filter((item) => item.id !== id);
    await store.put(`watch:index:${principal}`, JSON.stringify(index), { expirationTtl: ROUTE_TTL_SECONDS });
    return json(200, { routes: index });
  }
  if (request.method !== "PUT") return json(405, { error: "Nur PUT oder DELETE" });
  const body = await readJson(request);
  const chunks = body?.chunks;
  const name = typeof body?.name === "string" ? body.name.slice(0, 60) : "";
  const distance = typeof body?.distanceMeters === "number" ? Math.round(body.distanceMeters) : 0;
  const bytes = typeof body?.bytes === "number" ? Math.round(body.bytes) : 0;
  if (
    !Array.isArray(chunks) ||
    chunks.length === 0 ||
    chunks.length > MAX_CHUNKS ||
    !chunks.every((chunk) => typeof chunk === "string" && chunk.length > 0 && chunk.length <= MAX_CHUNK_CHARS)
  ) {
    return json(400, { error: "Teile fehlen oder sind zu groß" });
  }
  if (bytes <= 0 || bytes > MAX_PACKAGE_BYTES) return json(413, { error: "Paket zu groß für die Uhr" });
  const updatedAt = new Date(context.now).toISOString();
  await store.put(key, JSON.stringify({ chunks }), { expirationTtl: ROUTE_TTL_SECONDS });
  const info: WatchRouteInfo = {
    id,
    name,
    distanceMeters: distance,
    bytes,
    chunks: chunks.length,
    updatedAt,
  };
  const previous = (await readIndex(store, principal)).filter((item) => item.id !== id);
  const index = [info, ...previous];
  for (const dropped of index.splice(MAX_ROUTES))
    await store.delete(`watch:route:${principal}:${dropped.id}`);
  await store.put(`watch:index:${principal}`, JSON.stringify(index), { expirationTtl: ROUTE_TTL_SECONDS });
  return json(200, { routes: index });
}
