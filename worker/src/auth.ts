/**
 * Anmeldung am Worker. Zwei Arten von Tokens:
 *
 * - **Haupt-Token** (`COACH_APP_TOKEN`): die Person, die den Worker betreibt. Darf alles, auch Gast-Tokens ausstellen.
 * - **Gast-Token** `g1.<id>.<signatur>`: für eingeladene Personen (Rangliste, geteilte Mahlzeiten, KI). Die Signatur ist
 *   HMAC-SHA-256 über die ID mit dem Haupt-Token als Schlüssel; der Worker speichert nichts dafür. Einzelne Gäste
 *   sperrt die Worker-Variable `REVOKED_GUESTS` (IDs, durch Komma getrennt). Ein Gast-Token verrät das Haupt-Token
 *   nicht und öffnet nicht die private SideStore-Quelle.
 *
 * POST /v1/invite – nur mit Haupt-Token: neues Gast-Token, Antwort {token, id}
 */
import { accountForSession, isSessionToken } from "./accounts";
import type { SqlDatabase } from "./db";
import type { Env } from "./types";

/** Haupt-Token, Gast-Token oder Sitzung eines Kontos (`s1.…`, siehe accounts.ts). */
export type Principal =
  | { kind: "owner" }
  | { kind: "guest"; id: string }
  | { kind: "account"; id: string; username: string; displayName: string; admin: boolean };

const GUEST_PREFIX = "g1.";
const GUEST_ID = /^[a-z0-9]{12}$/;
const ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789";

/** Vergleich in konstanter Zeit (bezogen auf den Inhalt), damit das Token nicht erraten werden kann. */
export function tokensMatch(given: string, expected: string): boolean {
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

async function signature(master: string, id: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(master),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`guest:${id}`));
  return [...new Uint8Array(mac)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function guestToken(master: string, id: string): Promise<string> {
  return `${GUEST_PREFIX}${id}.${await signature(master, id)}`;
}

export function newGuestID(
  random: (bytes: Uint8Array) => Uint8Array = (b) => crypto.getRandomValues(b),
): string {
  return [...random(new Uint8Array(12))].map((byte) => ALPHABET[byte % ALPHABET.length]).join("");
}

function revoked(env: Env): Set<string> {
  return new Set(
    (env.REVOKED_GUESTS ?? "")
      .split(",")
      .map((id) => id.trim())
      .filter(Boolean),
  );
}

export function bearerToken(header: string): string {
  return header.startsWith("Bearer ") ? header.slice(7).trim() : "";
}

/** Wer fragt an? `null` bei fehlendem, falschem, gesperrtem oder abgelaufenem Token. */
export async function authenticate(header: string, env: Env, now = Date.now()): Promise<Principal | null> {
  const master = env.COACH_APP_TOKEN;
  if (!master) return null;
  const token = bearerToken(header);
  if (!token) return null;
  if (isSessionToken(token)) {
    const db = env.DB as unknown as SqlDatabase | undefined;
    if (!db) return null;
    const account = await accountForSession(db, token, now);
    return account
      ? {
          kind: "account",
          id: account.id,
          username: account.username,
          displayName: account.displayName,
          admin: account.isAdmin,
        }
      : null;
  }
  if (token.startsWith(GUEST_PREFIX)) {
    const parts = token.slice(GUEST_PREFIX.length).split(".");
    const [id = "", sig = ""] = parts;
    if (parts.length !== 2 || !GUEST_ID.test(id) || revoked(env).has(id)) return null;
    return tokensMatch(sig, await signature(master, id)) ? { kind: "guest", id } : null;
  }
  return tokensMatch(token, master) ? { kind: "owner" } : null;
}

/** Kennung für die Zuordnung gespeicherter Einträge (Rangliste, geteilte Mahlzeiten). */
export function principalKey(principal: Principal): string {
  if (principal.kind === "owner") return "owner";
  return principal.kind === "guest" ? `guest:${principal.id}` : `acct:${principal.id}`;
}
