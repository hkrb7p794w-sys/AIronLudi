/**
 * Rangliste zwischen Nutzer:innen derselben App-Installation (gleiches COACH_APP_TOKEN), z. B. Paar oder Freunde.
 * Gespeichert werden nur Anzeigename, Begleiter-Symbol und Punkte aus der Planerfüllung – keine
 * Gesundheitsdaten. Einträge verfallen nach 90 Tagen ohne Aktualisierung.
 *
 * GET    /v1/league/<code>              – alle Einträge, sortiert nach Wochenpunkten
 * PUT    /v1/league/<code>/members/<id> – eigenen Eintrag setzen
 * DELETE /v1/league/<code>/members/<id> – Rangliste verlassen
 *
 * Alle Aufrufe mit Haupt- oder Gast-Token (Prüfung in index.ts). Ein Eintrag gehört dem Token, das ihn zuerst
 * gesetzt hat: Andere dürfen ihn weder überschreiben noch löschen. Einträge von vor dieser Regel (ohne Besitzer)
 * übernimmt der nächste Schreibzugriff.
 */
import { readLimited } from "./tasks-util";

export interface LeagueEntry {
  id: string;
  name: string;
  /** Symbol des Begleiters bzw. „person“. */
  avatar: string;
  /** Montag der Woche (yyyy-MM-dd), auf die sich weekPoints beziehen. */
  week: string;
  weekPoints: number;
  totalPoints: number;
  streak: number;
  done: number;
  planned: number;
  updatedAt: string;
}

/** Gespeicherte Metadaten: Eintrag plus Besitzer (wird nie ausgeliefert). */
type StoredEntry = LeagueEntry & { owner?: string };

function publicEntry(stored: StoredEntry): LeagueEntry {
  const { owner: _owner, ...entry } = stored;
  return entry;
}

export interface LeagueStore {
  put(key: string, value: string, options?: { metadata?: unknown; expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
  list(options: {
    prefix: string;
    limit?: number;
  }): Promise<{ keys: { name: string; metadata?: unknown }[] }>;
}

export const LEAGUE_TTL_SECONDS = 90 * 24 * 3600;
export const MAX_MEMBERS = 20;
const MAX_ENTRY_BYTES = 4_096;
const CODE = /^[a-z0-9-]{6,40}$/;
const MEMBER = /^[A-Za-z0-9-]{8,64}$/;
const WEEK = /^\d{4}-\d{2}-\d{2}$/;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function count(value: unknown, max: number): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value <= max ? value : null;
}

/** Prüft und begrenzt einen Eintrag aus der App. */
export function parseEntry(id: string, body: unknown, now: Date): LeagueEntry | string {
  const value = (body ?? {}) as Record<string, unknown>;
  const name = typeof value.name === "string" ? value.name.trim().slice(0, 30) : "";
  if (!name) return "name fehlt";
  const avatar =
    typeof value.avatar === "string" && /^[a-z.]{1,40}$/.test(value.avatar) ? value.avatar : "person";
  if (typeof value.week !== "string" || !WEEK.test(value.week)) return "week ungültig";
  const weekPoints = count(value.weekPoints, 1_000);
  const totalPoints = count(value.totalPoints, 1_000_000);
  const streak = count(value.streak, 1_000);
  const done = count(value.done, 50);
  const planned = count(value.planned, 50);
  if (weekPoints === null || totalPoints === null || streak === null || done === null || planned === null) {
    return "Zahlen ungültig";
  }
  return {
    id,
    name,
    avatar,
    week: value.week,
    weekPoints,
    totalPoints,
    streak,
    done,
    planned,
    updatedAt: now.toISOString(),
  };
}

/** Wochenpunkte zählen nur für die aktuelle Woche; ältere Einträge stehen mit 0 Wochenpunkten da. */
export function ranked(entries: LeagueEntry[], week: string): LeagueEntry[] {
  return entries
    .map((entry) => (entry.week === week ? entry : { ...entry, weekPoints: 0, done: 0, planned: 0 }))
    .sort(
      (a, b) => b.weekPoints - a.weekPoints || b.totalPoints - a.totalPoints || a.name.localeCompare(b.name),
    );
}

/** Montag der Woche (UTC) als yyyy-MM-dd. */
export function mondayOf(now: Date): string {
  const day = (now.getUTCDay() + 6) % 7;
  const monday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - day));
  return monday.toISOString().slice(0, 10);
}

/** Bearbeitet /v1/league/…; `null`, wenn der Pfad nicht passt. Die Anmeldung prüft der Aufrufer. */
export async function handleLeague(
  request: Request,
  store: LeagueStore | undefined,
  now: Date,
  caller = "owner",
): Promise<Response | null> {
  const { pathname, searchParams } = new URL(request.url);
  const match = /^\/v1\/league\/([^/]+)(?:\/members\/([^/]+))?$/.exec(pathname);
  if (!match) return null;
  const [, code = "", member] = match;
  if (!CODE.test(code)) return json(400, { error: "Ungültiger Ranglisten-Code" });
  if (!store) return json(503, { error: "Rangliste nicht eingerichtet (KV LEAGUE fehlt)" });
  const prefix = `league:${code}:`;

  if (member === undefined) {
    if (request.method !== "GET") return json(405, { error: "Nur GET" });
    const { keys } = await store.list({ prefix, limit: MAX_MEMBERS });
    const entries = keys
      .map((key) => key.metadata as StoredEntry | undefined)
      .filter((e) => e !== undefined)
      .map(publicEntry);
    // Die App schickt ihren Montag mit (lokale Zeitzone); sonst zählt der UTC-Montag.
    const week = searchParams.get("week") ?? "";
    return json(200, { members: ranked(entries, WEEK.test(week) ? week : mondayOf(now)) });
  }

  if (!MEMBER.test(member)) return json(400, { error: "Ungültige Mitglieds-ID" });
  const key = prefix + member;
  if (request.method !== "PUT" && request.method !== "DELETE")
    return json(405, { error: "Nur PUT oder DELETE" });
  const { keys } = await store.list({ prefix, limit: MAX_MEMBERS + 1 });
  const existing = keys.find((k) => k.name === key)?.metadata as StoredEntry | undefined;
  if (existing?.owner !== undefined && existing.owner !== caller) {
    return json(403, { error: "Eintrag gehört jemand anderem" });
  }
  if (request.method === "DELETE") {
    await store.delete(key);
    return json(200, { ok: true });
  }
  const raw = await readLimited(request, MAX_ENTRY_BYTES);
  if (raw === null) return json(413, { error: "Eintrag zu groß" });
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json(400, { error: "Ungültiges JSON" });
  }
  const entry = parseEntry(member, body, now);
  if (typeof entry === "string") return json(400, { error: entry });
  if (keys.length >= MAX_MEMBERS && !keys.some((k) => k.name === key)) {
    return json(409, { error: "Rangliste ist voll" });
  }
  // Alles in den Metadaten (≤ 1024 Bytes): Eine list()-Abfrage liefert die ganze Rangliste.
  const stored: StoredEntry = { ...entry, owner: caller };
  await store.put(key, "", { metadata: stored, expirationTtl: LEAGUE_TTL_SECONDS });
  return json(200, { member: entry });
}
