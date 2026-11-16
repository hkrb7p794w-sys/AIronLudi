/**
 * KI-Nutzung je Person: zählt erfolgreiche KI-Anfragen und deren geschätzten Listenpreis pro Tag (UTC), begrenzt
 * Gäste auf ein Tageslimit und gibt dem Betreiber eine Kostenübersicht.
 *
 * - Personen sind das Haupt-Token (`owner`) und die Gast-Tokens (`guest:<id>`, siehe auth.ts); es gibt keine Namen.
 * - Gespeichert wird im KV `LEAGUE` unter `usage:<Tag>:<Person>` (nur Zahlen, 45 Tage). Die Zahlen stehen zusätzlich
 *   als KV-Metadaten, damit die Übersicht mit einem Listenaufruf auskommt.
 * - **Weiche Grenze:** Lesen und Schreiben sind nicht atomar; bei gleichzeitigen Anfragen kann ein Gast das Limit
 *   um einzelne Anfragen überschreiten. Fällt der Speicher aus (z. B. KV-Schreibgrenze des Gratis-Plans), läuft die
 *   KI ohne Zählung weiter – die Grenze schaltet nie die KI ab, weil der Zähler klemmt.
 * - Der Preis ist der **Listenpreis**, den die Anfrage bei bezahlter Nutzung kosten würde (siehe providers.ts), nicht
 *   die tatsächliche Rechnung: In kostenlosen Kontingenten zahlst du nichts.
 */
import { type Principal, principalKey } from "./auth";
import type { Env } from "./types";

export interface UsageRecord {
  /** Erfolgreiche Anfragen. */
  n: number;
  /** Geschätzter Listenpreis in US-Dollar. */
  usd: number;
  tasks: Record<string, number>;
  providers: Record<string, number>;
}

export interface UsageStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { metadata?: unknown; expirationTtl?: number }): Promise<void>;
  list(options: { prefix: string; limit?: number; cursor?: string }): Promise<{
    keys: { name: string; metadata?: unknown }[];
    list_complete?: boolean;
    cursor?: string;
  }>;
}

export const USAGE_TTL_SECONDS = 45 * 24 * 3600;
/** Standard-Tageslimit je Gast; `0` = unbegrenzt. */
export const DEFAULT_GUEST_DAILY_LIMIT = 60;
const MAX_LIST_PAGES = 10;

export const emptyUsage = (): UsageRecord => ({ n: 0, usd: 0, tasks: {}, providers: {} });

/** UTC-Tag `YYYY-MM-DD`. */
export function usageDay(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

export function usageKey(day: string, principal: Principal): string {
  return `usage:${day}:${principalKey(principal)}`;
}

/** Nächster Tageswechsel (00:00 UTC) als ISO-Zeit. */
export function nextReset(now: number): string {
  const day = new Date(now);
  return new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate() + 1)).toISOString();
}

function parseNumber(value: string | undefined, fallback: number): number {
  if (value === undefined || value.trim() === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

/** Betreiber: Haupt-Token oder ein damit angelegtes Konto. Alle anderen (Gäste, Konten) haben das Gast-Limit. */
function isOperator(principal: Principal): boolean {
  return principal.kind === "owner" || (principal.kind === "account" && principal.admin);
}

/**
 * Tageslimit in Anfragen; `0` = unbegrenzt. Gäste und Konten: `AI_GUEST_DAILY_LIMIT` (Standard 60), Betreiber:
 * `AI_OWNER_DAILY_LIMIT`.
 */
export function dailyLimit(env: Env, principal: Principal): number {
  return Math.floor(
    !isOperator(principal)
      ? parseNumber(env.AI_GUEST_DAILY_LIMIT, DEFAULT_GUEST_DAILY_LIMIT)
      : parseNumber(env.AI_OWNER_DAILY_LIMIT, 0),
  );
}

/** Optionales Tagesbudget für Gäste in Dollar (Listenpreis); `0` = aus. */
export function dailyBudgetUsd(env: Env, principal: Principal): number {
  return !isOperator(principal) ? parseNumber(env.AI_GUEST_DAILY_BUDGET_USD, 0) : 0;
}

function parseRecord(text: string | null | undefined): UsageRecord {
  if (!text) return emptyUsage();
  try {
    const value = JSON.parse(text) as Partial<UsageRecord>;
    return {
      n: Number.isFinite(value.n) ? Number(value.n) : 0,
      usd: Number.isFinite(value.usd) ? Number(value.usd) : 0,
      tasks: value.tasks && typeof value.tasks === "object" ? value.tasks : {},
      providers: value.providers && typeof value.providers === "object" ? value.providers : {},
    };
  } catch {
    return emptyUsage();
  }
}

export async function readUsage(store: UsageStore, day: string, principal: Principal): Promise<UsageRecord> {
  return parseRecord(await store.get(usageKey(day, principal)));
}

export interface Quota {
  allowed: boolean;
  used: number;
  /** 0 = unbegrenzt. */
  limit: number;
  usd: number;
  budget: number;
  reason?: "requests" | "budget";
}

/** Darf diese Person heute noch eine KI-Anfrage stellen? Ohne Speicher oder bei Lesefehlern: ja. */
export async function checkQuota(
  env: Env,
  store: UsageStore | undefined,
  principal: Principal,
  now: number,
): Promise<Quota> {
  const limit = dailyLimit(env, principal);
  const budget = dailyBudgetUsd(env, principal);
  const open: Quota = { allowed: true, used: 0, limit, usd: 0, budget };
  if (!store || (limit === 0 && budget === 0)) return open;
  let record: UsageRecord;
  try {
    record = await readUsage(store, usageDay(now), principal);
  } catch {
    return open;
  }
  const quota: Quota = { ...open, used: record.n, usd: record.usd };
  if (limit > 0 && record.n >= limit) return { ...quota, allowed: false, reason: "requests" };
  if (budget > 0 && record.usd >= budget) return { ...quota, allowed: false, reason: "budget" };
  return quota;
}

export function quotaMessage(quota: Quota): string {
  return quota.reason === "budget"
    ? "Dein KI-Tagesbudget ist aufgebraucht. Morgen geht es weiter."
    : `Dein KI-Tageslimit (${quota.limit} Anfragen) ist erreicht. Morgen geht es weiter.`;
}

/** Zählt eine erfolgreiche Anfrage. Wirft bei Speicherfehlern; der Aufrufer fängt das ab. */
export async function recordUsage(
  store: UsageStore,
  principal: Principal,
  now: number,
  task: string,
  provider: string,
  usd: number,
): Promise<UsageRecord> {
  const day = usageDay(now);
  const record = await readUsage(store, day, principal);
  record.n += 1;
  record.usd = Math.round((record.usd + usd) * 1e6) / 1e6;
  record.tasks[task] = (record.tasks[task] ?? 0) + 1;
  record.providers[provider] = (record.providers[provider] ?? 0) + 1;
  await store.put(usageKey(day, principal), JSON.stringify(record), {
    metadata: record,
    expirationTtl: USAGE_TTL_SECONDS,
  });
  return record;
}

/** Eigene Nutzung: heute mit Limit und die letzten Tage (`GET /v1/usage`). */
export async function ownSummary(
  env: Env,
  store: UsageStore | undefined,
  principal: Principal,
  now: number,
  days = 7,
): Promise<unknown> {
  const limit = dailyLimit(env, principal);
  const list = Array.from({ length: days }, (_, index) => usageDay(now - index * 86_400_000));
  const records = store
    ? await Promise.all(list.map((day) => readUsage(store, day, principal).catch(() => emptyUsage())))
    : list.map(() => emptyUsage());
  return {
    day: list[0],
    limit,
    used: records[0]?.n ?? 0,
    resetsAt: nextReset(now),
    days: list.map((day, index) => ({ day, n: records[index]?.n ?? 0, usd: records[index]?.usd ?? 0 })),
  };
}

interface PersonTotals {
  person: string;
  n: number;
  usd: number;
  activeDays: number;
  tasks: Record<string, number>;
}

/**
 * Übersicht für den Betreiber (`GET /v1/usage/all`): je Person und Tag der letzten `days` Tage, mit Summen und dem
 * Durchschnitt je aktiver Person. Ein Listenaufruf je 1.000 Einträge (Gratis-Plan: 1.000 Listenaufrufe am Tag).
 */
export async function ownerOverview(store: UsageStore | undefined, now: number, days = 31): Promise<unknown> {
  const cutoff = usageDay(now - (days - 1) * 86_400_000);
  const persons = new Map<string, PersonTotals>();
  const perDay = new Map<string, { n: number; usd: number; people: number }>();
  let pages = 0;
  let truncated = false;
  if (store) {
    let cursor: string | undefined;
    do {
      const page = await store.list({ prefix: "usage:", limit: 1000, cursor });
      for (const key of page.keys) {
        const match = /^usage:(\d{4}-\d{2}-\d{2}):(.+)$/.exec(key.name);
        if (!match || (match[1] as string) < cutoff) continue;
        const day = match[1] as string;
        const person = match[2] as string;
        const record = parseRecord(JSON.stringify(key.metadata ?? {}));
        const totals = persons.get(person) ?? { person, n: 0, usd: 0, activeDays: 0, tasks: {} };
        totals.n += record.n;
        totals.usd += record.usd;
        totals.activeDays += record.n > 0 ? 1 : 0;
        for (const [task, count] of Object.entries(record.tasks)) {
          totals.tasks[task] = (totals.tasks[task] ?? 0) + count;
        }
        persons.set(person, totals);
        const entry = perDay.get(day) ?? { n: 0, usd: 0, people: 0 };
        entry.n += record.n;
        entry.usd += record.usd;
        entry.people += record.n > 0 ? 1 : 0;
        perDay.set(day, entry);
      }
      cursor = page.list_complete === false ? page.cursor : undefined;
      pages += 1;
      if (cursor && pages >= MAX_LIST_PAGES) {
        truncated = true;
        break;
      }
    } while (cursor);
  }
  const people = [...persons.values()].sort((a, b) => b.usd - a.usd || b.n - a.n);
  const round = (value: number) => Math.round(value * 10_000) / 10_000;
  const totalUsd = people.reduce((sum, person) => sum + person.usd, 0);
  const totalN = people.reduce((sum, person) => sum + person.n, 0);
  const active = people.filter((person) => person.n > 0);
  return {
    since: cutoff,
    days,
    truncated,
    note: "usd = Listenpreis-Schätzung bei bezahlter Nutzung, nicht die tatsächliche Rechnung (Gratis-Kontingente kosten nichts).",
    total: { n: totalN, usd: round(totalUsd), people: active.length },
    averageUsdPerActivePerson: active.length ? round(totalUsd / active.length) : 0,
    averageRequestsPerActivePersonPerDay: active.length
      ? Math.round(
          (totalN /
            Math.max(
              1,
              active.reduce((sum, p) => sum + p.activeDays, 0),
            )) *
            10,
        ) / 10
      : 0,
    people: people.map((person) => ({ ...person, usd: round(person.usd) })),
    perDay: [...perDay.entries()]
      .sort(([a], [b]) => (a < b ? 1 : -1))
      .map(([day, entry]) => ({ day, ...entry, usd: round(entry.usd) })),
  };
}
