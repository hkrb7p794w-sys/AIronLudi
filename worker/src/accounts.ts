/**
 * Konten für Freunde und Familie: Benutzername + Passwort, Sitzungen je Gerät, Einladungen.
 *
 * Sicherheit (siehe docs/decisions.md, „Konten“):
 * - Passwörter nur als PBKDF2-SHA-256 mit 16 Byte Salz und 100.000 Runden (Höchstwert der Web Crypto in Workers).
 *   Die Rundenzahl steht im Hash, damit sie sich später ändern lässt.
 * - Sitzungs-Token `s1.<32 Zufallsbytes>` liegen nur als SHA-256 in der Datenbank; wer die Datenbank liest, kann
 *   sich damit nicht anmelden. Sitzungen verfallen 180 Tage nach der letzten Nutzung, höchstens 10 je Konto.
 * - Nach 5 Fehlversuchen ist das Konto 15 Minuten gesperrt (auch für die Wiederherstellung).
 * - Registrieren nur mit Einladung: Einladungscode (einmalig, 14 Tage gültig) oder bestehendes Gast- bzw. Haupt-Token.
 *   Je Gast-Token höchstens ein Konto.
 * - Kein E-Mail-Versand: Wer das Passwort vergisst, nutzt den Wiederherstellungscode von der Registrierung. Fehlt der,
 *   stellt der Betreiber (Haupt-Token) einen neuen Wiederherstellungscode aus. Daten sieht er dabei nicht.
 * - Gespeichert werden nur Benutzername, Anzeigename und die Hashes – keine Gesundheitsdaten.
 *
 * POST   /v1/account/register   {username, displayName, password, invite?, device?} → 201 {token, account, recoveryCode}
 * POST   /v1/account/login      {username, password, device?}                        → {token, account}
 * POST   /v1/account/recover    {username, recoveryCode, newPassword, device?}       → {token, account, recoveryCode}
 * GET    /v1/account/me         (Sitzung)                                            → {account, sessions}
 * POST   /v1/account/logout     (Sitzung) {all?}
 * POST   /v1/account/password   (Sitzung) {oldPassword, newPassword}                 → andere Sitzungen beendet
 * PATCH  /v1/account/profile    (Sitzung) {displayName} – auch als POST
 * POST   /v1/account/delete     (Sitzung) {password}
 * GET    /v1/account/invites    (Sitzung oder Haupt-Token)                           → offene Einladungen
 * POST   /v1/account/invites    (Sitzung oder Haupt-Token)                           → {code, expiresAt}
 * DELETE /v1/account/invites/<code>
 * POST   /v1/account/admin/reset (nur Haupt-Token) {username}                        → {recoveryCode}
 */
import type { Principal } from "./auth";
import { ensureSchema, type SqlDatabase } from "./db";
import { GAME_CLEANUP } from "./game";
import { SOCIAL_CLEANUP } from "./social";
import { readLimited } from "./tasks-util";

export const PBKDF2_ITERATIONS = 100_000;
export const SESSION_PREFIX = "s1.";
export const SESSION_TTL_MS = 180 * 24 * 3600 * 1000;
export const MAX_SESSIONS = 10;
export const MAX_FAILED_LOGINS = 5;
export const LOCK_MS = 15 * 60 * 1000;
export const INVITE_TTL_MS = 14 * 24 * 3600 * 1000;
export const MAX_OPEN_INVITES = 5;
/** Letzte Nutzung höchstens einmal am Tag schreiben (spart Schreibzugriffe). */
const TOUCH_INTERVAL_MS = 24 * 3600 * 1000;
const MAX_BODY = 8_192;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const USERNAME = /^[a-z0-9][a-z0-9_.]{2,19}$/;
const RESERVED = new Set([
  "admin",
  "administrator",
  "coach",
  "ironludi",
  "support",
  "system",
  "root",
  "owner",
]);

export interface Account {
  id: string;
  username: string;
  displayName: string;
  isAdmin: boolean;
}

interface AccountRow {
  id: string;
  username: string;
  display_name: string;
  pw_hash: string;
  recovery_hash: string;
  is_admin: number;
  failed_logins: number;
  locked_until: number;
}

export interface AccountContext {
  db: SqlDatabase | undefined;
  now: number;
  /** Wer mit welchem Token anfragt (Haupt-, Gast- oder Sitzungs-Token); `null` = ohne Anmeldung. */
  principal: Principal | null;
  /** Rohes Sitzungs-Token, falls mit einer Sitzung angemeldet (für „dieses Gerät abmelden“). */
  sessionToken?: string;
}

// MARK: - Regeln (gleiche Regeln in der App: CoachCore `AccountRules`, Android `AccountRules`)

export function normalizeUsername(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

export function usernameProblem(username: string): string | null {
  if (!USERNAME.test(username)) {
    return "Benutzername: 3–20 Zeichen, nur a–z, 0–9, Punkt und Unterstrich, am Anfang ein Buchstabe oder eine Ziffer.";
  }
  if (RESERVED.has(username)) return "Dieser Benutzername ist reserviert.";
  return null;
}

export function passwordProblem(password: unknown, username: string): string | null {
  if (typeof password !== "string" || password.length < 10)
    return "Das Passwort braucht mindestens 10 Zeichen.";
  if (password.length > 128) return "Das Passwort darf höchstens 128 Zeichen haben.";
  if (username && password.toLowerCase().includes(username))
    return "Das Passwort darf den Benutzernamen nicht enthalten.";
  if (new Set(password).size < 4) return "Das Passwort ist zu einfach.";
  return null;
}

function displayNameOf(value: unknown, fallback: string): string | null {
  if (value === undefined || value === null || value === "") return fallback;
  if (typeof value !== "string") return null;
  const trimmed = value.trim().replace(/\s+/g, " ");
  return trimmed.length >= 1 && trimmed.length <= 40 ? trimmed : null;
}

function deviceOf(value: unknown): string {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, 60) : "Gerät";
}

// MARK: - Krypto

const encoder = new TextEncoder();

function base64url(bytes: Uint8Array): string {
  let text = "";
  for (const byte of bytes) text += String.fromCharCode(byte);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64url(text: string): Uint8Array {
  const binary = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function randomBytes(count: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(count));
}

function randomCode(length: number): string {
  return [...randomBytes(length)].map((byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

/** Vergleich in konstanter Zeit. */
function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}

async function pbkdf2(password: string, salt: Uint8Array, iterations: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations },
    key,
    256,
  );
  return new Uint8Array(bits);
}

export async function hashPassword(password: string, iterations = PBKDF2_ITERATIONS): Promise<string> {
  const salt = randomBytes(16);
  return `pbkdf2$sha256$${iterations}$${base64url(salt)}$${base64url(await pbkdf2(password, salt, iterations))}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, hash, rounds, salt, expected] = stored.split("$");
  const iterations = Number(rounds);
  if (scheme !== "pbkdf2" || hash !== "sha256" || !salt || !expected || !Number.isInteger(iterations))
    return false;
  if (iterations < 1 || iterations > PBKDF2_ITERATIONS) return false;
  return equalBytes(await pbkdf2(password, fromBase64url(salt), iterations), fromBase64url(expected));
}

/** Wiederherstellungscode `ABCD-EFGH-JKLM-NPQR` (16 Zeichen, 80 Bit). */
export function newRecoveryCode(): string {
  return randomCode(16).match(/.{4}/g)?.join("-") ?? "";
}

function normalizeRecovery(code: unknown): string {
  return typeof code === "string" ? code.toUpperCase().replace(/[^A-Z0-9]/g, "") : "";
}

async function recoveryHash(code: string): Promise<string> {
  return sha256Hex(`recovery:${normalizeRecovery(code)}`);
}

// MARK: - Sitzungen

export function isSessionToken(token: string): boolean {
  return token.startsWith(SESSION_PREFIX) && token.length > SESSION_PREFIX.length + 20;
}

async function createSession(
  db: SqlDatabase,
  accountId: string,
  device: string,
  now: number,
): Promise<string> {
  const token = `${SESSION_PREFIX}${base64url(randomBytes(32))}`;
  await db
    .prepare(
      "INSERT INTO sessions (token_hash, account_id, device, created_at, last_used) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(await sha256Hex(token), accountId, device, now, now)
    .run();
  // Älteste Sitzungen über dem Höchstwert und abgelaufene entfernen.
  await db
    .prepare(
      `DELETE FROM sessions WHERE account_id = ? AND (last_used < ? OR token_hash NOT IN (
         SELECT token_hash FROM sessions WHERE account_id = ? ORDER BY last_used DESC LIMIT ?))`,
    )
    .bind(accountId, now - SESSION_TTL_MS, accountId, MAX_SESSIONS)
    .run();
  return token;
}

/** Konto zu einem Sitzungs-Token; `null`, wenn unbekannt oder abgelaufen. */
export async function accountForSession(
  db: SqlDatabase,
  token: string,
  now: number,
): Promise<Account | null> {
  await ensureSchema(db);
  const tokenHash = await sha256Hex(token);
  const row = await db
    .prepare(
      `SELECT a.id, a.username, a.display_name, a.is_admin, s.last_used FROM sessions s
       JOIN accounts a ON a.id = s.account_id WHERE s.token_hash = ?`,
    )
    .bind(tokenHash)
    .first<{ id: string; username: string; display_name: string; is_admin: number; last_used: number }>();
  if (!row) return null;
  if (row.last_used < now - SESSION_TTL_MS) {
    await db.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(tokenHash).run();
    return null;
  }
  if (now - row.last_used > TOUCH_INTERVAL_MS) {
    await db.prepare("UPDATE sessions SET last_used = ? WHERE token_hash = ?").bind(now, tokenHash).run();
  }
  return { id: row.id, username: row.username, displayName: row.display_name, isAdmin: row.is_admin === 1 };
}

// MARK: - HTTP

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function fail(status: number, error: string, code: string, extra: Record<string, unknown> = {}): Response {
  return json(status, { error, code, ...extra });
}

async function readBody(request: Request): Promise<Record<string, unknown> | Response> {
  const raw = await readLimited(request, MAX_BODY);
  if (raw === null) return fail(413, "Anfrage zu groß", "too_large");
  if (!raw.trim()) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
      throw new Error("kein Objekt");
    return parsed as Record<string, unknown>;
  } catch {
    return fail(400, "Ungültiges JSON", "invalid_json");
  }
}

function publicAccount(row: { id: string; username: string; display_name: string; is_admin: number }) {
  return { id: row.id, username: row.username, displayName: row.display_name, isAdmin: row.is_admin === 1 };
}

const WRONG_LOGIN = "Benutzername oder Passwort falsch.";

function lockedResponse(until: number, now: number): Response {
  const minutes = Math.max(1, Math.ceil((until - now) / 60_000));
  return fail(429, `Zu viele Fehlversuche. Bitte in ${minutes} Minuten erneut versuchen.`, "locked", {
    retryAfterSeconds: Math.ceil((until - now) / 1000),
  });
}

async function findAccount(db: SqlDatabase, username: string): Promise<AccountRow | null> {
  return db
    .prepare(
      `SELECT id, username, display_name, pw_hash, recovery_hash, is_admin, failed_logins, locked_until
       FROM accounts WHERE username = ?`,
    )
    .bind(username)
    .first<AccountRow>();
}

async function registerFailure(db: SqlDatabase, row: AccountRow, now: number): Promise<void> {
  const failures = row.failed_logins + 1;
  const lock = failures >= MAX_FAILED_LOGINS ? now + LOCK_MS : row.locked_until;
  await db
    .prepare("UPDATE accounts SET failed_logins = ?, locked_until = ? WHERE id = ?")
    .bind(failures >= MAX_FAILED_LOGINS ? 0 : failures, lock, row.id)
    .run();
}

async function clearFailures(db: SqlDatabase, row: AccountRow): Promise<void> {
  if (row.failed_logins > 0 || row.locked_until > 0) {
    await db
      .prepare("UPDATE accounts SET failed_logins = 0, locked_until = 0 WHERE id = ?")
      .bind(row.id)
      .run();
  }
}

async function register(
  db: SqlDatabase,
  body: Record<string, unknown>,
  ctx: AccountContext,
): Promise<Response> {
  const username = normalizeUsername(body.username);
  const usernameError = usernameProblem(username);
  if (usernameError) return fail(400, usernameError, "invalid_username");
  const passwordError = passwordProblem(body.password, username);
  if (passwordError) return fail(400, passwordError, "weak_password");
  const displayName = displayNameOf(body.displayName, username);
  if (!displayName) return fail(400, "Anzeigename: 1–40 Zeichen.", "invalid_display_name");

  // Wer darf? Haupt-Token, ein Gast-Token (einmal) oder ein gültiger Einladungscode.
  let invitedBy: string;
  let guestId: string | null = null;
  let inviteCode: string | null = null;
  const principal = ctx.principal;
  if (principal?.kind === "owner") {
    invitedBy = "owner";
  } else if (principal?.kind === "guest") {
    invitedBy = "owner";
    guestId = principal.id;
    const existing = await db.prepare("SELECT 1 AS x FROM accounts WHERE guest_id = ?").bind(guestId).first();
    if (existing)
      return fail(409, "Mit diesem Zugang wurde schon ein Konto angelegt. Bitte anmelden.", "guest_used");
  } else {
    inviteCode = normalizeRecovery(body.invite);
    if (!inviteCode) return fail(403, "Zum Registrieren brauchst du eine Einladung.", "invite_required");
    const invite = await db
      .prepare("SELECT created_by, expires_at, used_by FROM invites WHERE code = ?")
      .bind(inviteCode)
      .first<{ created_by: string; expires_at: number; used_by: string | null }>();
    if (!invite || invite.used_by || invite.expires_at < ctx.now) {
      return fail(403, "Die Einladung ist ungültig, abgelaufen oder schon benutzt.", "invite_invalid");
    }
    invitedBy = invite.created_by;
  }

  if (await db.prepare("SELECT 1 AS x FROM accounts WHERE username = ?").bind(username).first()) {
    return fail(409, "Dieser Benutzername ist schon vergeben.", "username_taken");
  }

  const id = base64url(randomBytes(12));
  const recoveryCode = newRecoveryCode();
  const isAdmin = principal?.kind === "owner" ? 1 : 0;
  try {
    await db
      .prepare(
        `INSERT INTO accounts (id, username, display_name, pw_hash, recovery_hash, is_admin, invited_by, guest_id, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        id,
        username,
        displayName,
        await hashPassword(String(body.password)),
        await recoveryHash(recoveryCode),
        isAdmin,
        invitedBy,
        guestId,
        ctx.now,
      )
      .run();
  } catch {
    // Gleichzeitige Registrierung mit demselben Namen oder Gast-Token (UNIQUE).
    return fail(409, "Dieser Benutzername ist schon vergeben.", "username_taken");
  }
  if (inviteCode) {
    const used = await db
      .prepare("UPDATE invites SET used_by = ? WHERE code = ? AND used_by IS NULL")
      .bind(id, inviteCode)
      .run();
    if ((used.meta?.changes ?? 1) === 0) {
      // Jemand war schneller: Konto wieder entfernen.
      await db.prepare("DELETE FROM accounts WHERE id = ?").bind(id).run();
      return fail(403, "Die Einladung ist ungültig, abgelaufen oder schon benutzt.", "invite_invalid");
    }
  }
  const token = await createSession(db, id, deviceOf(body.device), ctx.now);
  return json(201, {
    token,
    account: { id, username, displayName, isAdmin: isAdmin === 1 },
    recoveryCode,
  });
}

async function login(db: SqlDatabase, body: Record<string, unknown>, ctx: AccountContext): Promise<Response> {
  const username = normalizeUsername(body.username);
  const password = typeof body.password === "string" ? body.password : "";
  if (!username || !password) return fail(400, "Benutzername und Passwort angeben.", "missing_fields");
  const row = await findAccount(db, username);
  // Unbekannte Namen ohne Hash-Rechnung abweisen: Benutzernamen sind über die Freundessuche ohnehin auffindbar.
  if (!row) return fail(401, WRONG_LOGIN, "wrong_login");
  if (row.locked_until > ctx.now) return lockedResponse(row.locked_until, ctx.now);
  if (!(await verifyPassword(password, row.pw_hash))) {
    await registerFailure(db, row, ctx.now);
    return fail(401, WRONG_LOGIN, "wrong_login");
  }
  await clearFailures(db, row);
  const token = await createSession(db, row.id, deviceOf(body.device), ctx.now);
  return json(200, { token, account: publicAccount(row) });
}

async function recover(
  db: SqlDatabase,
  body: Record<string, unknown>,
  ctx: AccountContext,
): Promise<Response> {
  const username = normalizeUsername(body.username);
  const row = username ? await findAccount(db, username) : null;
  const wrong = "Benutzername oder Wiederherstellungscode falsch.";
  if (!row) return fail(401, wrong, "wrong_recovery");
  if (row.locked_until > ctx.now) return lockedResponse(row.locked_until, ctx.now);
  const given = new TextEncoder().encode(await recoveryHash(String(body.recoveryCode ?? "")));
  if (!equalBytes(given, new TextEncoder().encode(row.recovery_hash))) {
    await registerFailure(db, row, ctx.now);
    return fail(401, wrong, "wrong_recovery");
  }
  const passwordError = passwordProblem(body.newPassword, row.username);
  if (passwordError) return fail(400, passwordError, "weak_password");
  const recoveryCode = newRecoveryCode();
  await db.batch([
    db
      .prepare(
        "UPDATE accounts SET pw_hash = ?, recovery_hash = ?, failed_logins = 0, locked_until = 0 WHERE id = ?",
      )
      .bind(await hashPassword(String(body.newPassword)), await recoveryHash(recoveryCode), row.id),
    db.prepare("DELETE FROM sessions WHERE account_id = ?").bind(row.id),
  ]);
  const token = await createSession(db, row.id, deviceOf(body.device), ctx.now);
  return json(200, { token, account: publicAccount(row), recoveryCode });
}

async function me(db: SqlDatabase, account: Account, ctx: AccountContext): Promise<Response> {
  const current = ctx.sessionToken ? await sha256Hex(ctx.sessionToken) : "";
  const { results } = await db
    .prepare(
      "SELECT token_hash, device, created_at, last_used FROM sessions WHERE account_id = ? ORDER BY last_used DESC",
    )
    .bind(account.id)
    .all<{ token_hash: string; device: string; created_at: number; last_used: number }>();
  return json(200, {
    account,
    sessions: results.map((session) => ({
      device: session.device,
      createdAt: new Date(session.created_at).toISOString(),
      lastUsed: new Date(session.last_used).toISOString(),
      current: session.token_hash === current,
    })),
  });
}

async function passwordRow(db: SqlDatabase, account: Account): Promise<AccountRow> {
  const row = await findAccount(db, account.username);
  if (!row) throw new Error("Konto verschwunden");
  return row;
}

async function changePassword(
  db: SqlDatabase,
  account: Account,
  body: Record<string, unknown>,
  ctx: AccountContext,
): Promise<Response> {
  const row = await passwordRow(db, account);
  if (row.locked_until > ctx.now) return lockedResponse(row.locked_until, ctx.now);
  if (!(await verifyPassword(String(body.oldPassword ?? ""), row.pw_hash))) {
    await registerFailure(db, row, ctx.now);
    return fail(401, "Das bisherige Passwort stimmt nicht.", "wrong_password");
  }
  const passwordError = passwordProblem(body.newPassword, row.username);
  if (passwordError) return fail(400, passwordError, "weak_password");
  const current = ctx.sessionToken ? await sha256Hex(ctx.sessionToken) : "";
  await db.batch([
    db
      .prepare("UPDATE accounts SET pw_hash = ?, failed_logins = 0, locked_until = 0 WHERE id = ?")
      .bind(await hashPassword(String(body.newPassword)), row.id),
    db.prepare("DELETE FROM sessions WHERE account_id = ? AND token_hash != ?").bind(row.id, current),
  ]);
  return json(200, { ok: true });
}

/** Tabellen, deren Zeilen beim Löschen eines Kontos mitgehen (Freunde, Feed … kommen hier dazu). */
export const ACCOUNT_CLEANUP: ((db: SqlDatabase, accountId: string) => ReturnType<SqlDatabase["prepare"]>)[] =
  [
    (db, id) => db.prepare("DELETE FROM sessions WHERE account_id = ?").bind(id),
    (db, id) => db.prepare("DELETE FROM invites WHERE created_by = ? AND used_by IS NULL").bind(id),
    ...SOCIAL_CLEANUP,
    ...GAME_CLEANUP,
    (db, id) => db.prepare("DELETE FROM accounts WHERE id = ?").bind(id),
  ];

async function deleteAccount(
  db: SqlDatabase,
  account: Account,
  body: Record<string, unknown>,
  ctx: AccountContext,
): Promise<Response> {
  const row = await passwordRow(db, account);
  if (row.locked_until > ctx.now) return lockedResponse(row.locked_until, ctx.now);
  if (!(await verifyPassword(String(body.password ?? ""), row.pw_hash))) {
    await registerFailure(db, row, ctx.now);
    return fail(401, "Das Passwort stimmt nicht.", "wrong_password");
  }
  await db.batch(ACCOUNT_CLEANUP.map((statement) => statement(db, row.id)));
  return json(200, { ok: true });
}

function inviteOwner(ctx: AccountContext, account: Account | null): string | null {
  if (account) return account.id;
  return ctx.principal?.kind === "owner" ? "owner" : null;
}

async function invites(db: SqlDatabase, request: Request, owner: string, ctx: AccountContext, code?: string) {
  if (request.method === "DELETE" && code) {
    await db
      .prepare("DELETE FROM invites WHERE code = ? AND created_by = ? AND used_by IS NULL")
      .bind(normalizeRecovery(code), owner)
      .run();
    return json(200, { ok: true });
  }
  const open = await db
    .prepare(
      "SELECT code, expires_at FROM invites WHERE created_by = ? AND used_by IS NULL AND expires_at > ? ORDER BY created_at",
    )
    .bind(owner, ctx.now)
    .all<{ code: string; expires_at: number }>();
  if (request.method === "GET") {
    return json(200, {
      invites: open.results.map((invite) => ({
        code: invite.code,
        expiresAt: new Date(invite.expires_at).toISOString(),
      })),
    });
  }
  if (request.method !== "POST") return fail(405, "Methode nicht erlaubt", "method");
  if (owner !== "owner" && open.results.length >= MAX_OPEN_INVITES) {
    return fail(
      429,
      `Du hast schon ${MAX_OPEN_INVITES} offene Einladungen. Lösche eine oder warte, bis sie benutzt ist.`,
      "too_many_invites",
    );
  }
  // Abgelaufene eigene Einladungen aufräumen.
  await db
    .prepare("DELETE FROM invites WHERE created_by = ? AND used_by IS NULL AND expires_at <= ?")
    .bind(owner, ctx.now)
    .run();
  const inviteCode = randomCode(10);
  const expiresAt = ctx.now + INVITE_TTL_MS;
  await db
    .prepare("INSERT INTO invites (code, created_by, created_at, expires_at) VALUES (?, ?, ?, ?)")
    .bind(inviteCode, owner, ctx.now, expiresAt)
    .run();
  return json(200, { code: inviteCode, expiresAt: new Date(expiresAt).toISOString() });
}

async function adminReset(db: SqlDatabase, body: Record<string, unknown>): Promise<Response> {
  const row = await findAccount(db, normalizeUsername(body.username));
  if (!row) return fail(404, "Konto nicht gefunden.", "not_found");
  const recoveryCode = newRecoveryCode();
  await db
    .prepare("UPDATE accounts SET recovery_hash = ?, failed_logins = 0, locked_until = 0 WHERE id = ?")
    .bind(await recoveryHash(recoveryCode), row.id)
    .run();
  return json(200, { username: row.username, recoveryCode });
}

/** Alle `/v1/account/…`-Pfade; `null` für andere Pfade. */
export async function handleAccount(request: Request, ctx: AccountContext): Promise<Response | null> {
  const { pathname } = new URL(request.url);
  if (!pathname.startsWith("/v1/account/")) return null;
  const db = ctx.db;
  if (!db)
    return fail(503, "Konten sind auf diesem Server nicht eingerichtet (D1 fehlt).", "accounts_unavailable");
  await ensureSchema(db);
  const action = pathname.slice("/v1/account/".length);
  const method = request.method;
  const principal = ctx.principal;
  const account: Account | null =
    principal?.kind === "account"
      ? {
          id: principal.id,
          username: principal.username,
          displayName: principal.displayName,
          isAdmin: principal.admin,
        }
      : null;

  const needsBody = method === "POST" || method === "PATCH";
  const body = needsBody ? await readBody(request) : {};
  if (body instanceof Response) return body;

  if (method === "POST" && action === "register") {
    if (account) return fail(409, "Du bist schon angemeldet.", "already_signed_in");
    return register(db, body, ctx);
  }
  if (method === "POST" && action === "login") return login(db, body, ctx);
  if (method === "POST" && action === "recover") return recover(db, body, ctx);

  if (action === "invites" || action.startsWith("invites/")) {
    const owner = inviteOwner(ctx, account);
    if (!owner) return fail(401, "Bitte anmelden.", "unauthorized");
    return invites(db, request, owner, ctx, action.split("/")[1]);
  }
  if (method === "POST" && action === "admin/reset") {
    if (principal?.kind !== "owner") return fail(403, "Nur mit dem Haupt-Token.", "forbidden");
    return adminReset(db, body);
  }

  if (!account) return fail(401, "Bitte anmelden.", "unauthorized");
  if (method === "GET" && action === "me") return me(db, account, ctx);
  if (method === "POST" && action === "logout") {
    if (body.all === true) {
      await db.prepare("DELETE FROM sessions WHERE account_id = ?").bind(account.id).run();
    } else if (ctx.sessionToken) {
      await db
        .prepare("DELETE FROM sessions WHERE token_hash = ?")
        .bind(await sha256Hex(ctx.sessionToken))
        .run();
    }
    return json(200, { ok: true });
  }
  if (method === "POST" && action === "password") return changePassword(db, account, body, ctx);
  // POST zusätzlich zu PATCH: HttpURLConnection auf Android kennt kein PATCH.
  if ((method === "PATCH" || method === "POST") && action === "profile") {
    const displayName = displayNameOf(body.displayName, "");
    if (!displayName) return fail(400, "Anzeigename: 1–40 Zeichen.", "invalid_display_name");
    await db.prepare("UPDATE accounts SET display_name = ? WHERE id = ?").bind(displayName, account.id).run();
    return json(200, { account: { ...account, displayName } });
  }
  if (method === "POST" && action === "delete") return deleteAccount(db, account, body, ctx);
  return fail(404, "Nicht gefunden", "not_found");
}

/**
 * Einladungsseite `/i/<code>`: öffnet die App auf iPhone (`coach://account?…`) bzw. Android (`ironludi://account?…`)
 * mit Server und Code. Der Code allein öffnet nichts außer der Registrierung.
 */
export function invitePage(pathname: string, origin: string): Response | null {
  const match = /^\/i\/([A-Z2-9]{10})$/.exec(pathname);
  if (!match) return null;
  const code = match[1] as string;
  const query = `worker=${encodeURIComponent(origin)}&invite=${code}`;
  const ios = `coach://account?${query}`;
  const android = `ironludi://account?${query}`;
  const html = `<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Einladung zu IronLudi</title></head>
<body style="font-family:-apple-system,system-ui,sans-serif;padding:24px;line-height:1.5;max-width:560px">
<h1 style="font-size:22px">Du bist zu IronLudi eingeladen</h1>
<p>Lege mit dieser Einladung dein eigenes Konto an. Nur du kennst dein Passwort.</p>
<p><a href="${ios}" style="font-size:18px">Auf dem iPhone öffnen</a></p>
<p><a href="${android}" style="font-size:18px">Auf Android öffnen</a></p>
<p>Falls nichts passiert: App öffnen › Einstellungen › Konto › „Konto erstellen“, als Server
<strong>${origin}</strong> und als Einladungscode <strong>${code}</strong> eingeben. Die Einladung gilt 14 Tage und
einmal.</p></body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "x-robots-tag": "noindex",
    },
  });
}
