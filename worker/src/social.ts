/**
 * Freunde und Feed zwischen Konten (nur mit Sitzung eines Kontos, siehe accounts.ts).
 *
 * - Freunde finden sich über den Benutzernamen (Suche ab 2 Zeichen, nur Anfang des Namens). Eine Anfrage wird erst
 *   mit Zustimmung zur Freundschaft; Ablehnen, Entfernen und Sperren gehen jederzeit, ohne dass die andere Person
 *   benachrichtigt wird.
 * - Beiträge sieht nur, wer mit der Person befreundet ist (und sie selbst). Geteilt wird nur, was die Person in der App
 *   ausdrücklich teilt: Training (Sportart, Dauer, Strecke, Übungen, Bestleistungen), Mahlzeit (Positionen mit
 *   Nährwerten zum Übernehmen) oder ein Meilenstein. Keine Körperwerte (Gewicht, Puls, HRV, Schlaf).
 * - Beiträge verfallen nach 90 Tagen; Reaktionen und Kommentare gehen mit.
 *
 * GET    /v1/social/search?q=…                – bis 10 Konten, deren Benutzername so beginnt
 * GET    /v1/social/friends                   – Freunde, eingehende und ausgehende Anfragen
 * POST   /v1/social/friends/<username>        – anfragen bzw. eingehende Anfrage annehmen
 * DELETE /v1/social/friends/<username>        – entfernen, ablehnen oder Anfrage zurückziehen
 * POST   /v1/social/blocks/<username>         – sperren (beendet Freundschaft, keine Anfragen mehr)
 * DELETE /v1/social/blocks/<username>         – Sperre aufheben
 * GET    /v1/social/people/<username>         – Profil; Beiträge nur für Freunde
 * GET    /v1/social/feed?before=<ms>          – Beiträge von dir und deinen Freunden, neueste zuerst
 * POST   /v1/social/posts {kind, …}           – Beitrag teilen (höchstens 30 am Tag)
 * DELETE /v1/social/posts/<id>                – eigenen Beitrag löschen
 * PUT    /v1/social/posts/<id>/reaction {emoji} / DELETE – eigene Reaktion
 * GET    /v1/social/posts/<id>/comments / POST {text}   – Kommentare
 * DELETE /v1/social/comments/<id>             – eigenen Kommentar oder Kommentar unter eigenem Beitrag löschen
 */
import { ensureSchema, type SqlDatabase, type SqlStatement } from "./db";
import { sanitizeMeal } from "./share";
import { readLimited } from "./tasks-util";

export const POST_TTL_MS = 90 * 24 * 3600 * 1000;
export const MAX_POSTS_PER_DAY = 30;
export const MAX_PENDING_REQUESTS = 30;
export const MAX_COMMENTS_PER_POST = 100;
export const FEED_PAGE = 30;
export const REACTIONS = ["👏", "🔥", "💪", "😋", "❤️"] as const;
const MAX_BODY = 32_000;
const DAY_MS = 24 * 3600 * 1000;
const SPORTS = new Set(["run", "bike", "swim", "strength", "walk", "hike", "yoga", "mobility", "other"]);
const KINDS = new Set(["workout", "meal", "milestone"]);

export interface Me {
  id: string;
  username: string;
}

export type Relation = "self" | "friends" | "incoming" | "outgoing" | "none" | "blocked";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function fail(status: number, error: string, code: string): Response {
  return json(status, { error, code });
}

function pair(x: string, y: string): [string, string] {
  return x < y ? [x, y] : [y, x];
}

function randomId(): string {
  return [...crypto.getRandomValues(new Uint8Array(12))].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, max) : "";
}

function number(value: unknown, max: number): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= max
    ? Math.round(value * 100) / 100
    : undefined;
}

function strings(value: unknown, count: number, max: number): string[] {
  return (Array.isArray(value) ? value : [])
    .map((item) => text(item, max))
    .filter(Boolean)
    .slice(0, count);
}

/** Nur bekannte Felder je Art; alles andere (z. B. Puls, Gewicht) fällt weg. */
export function sanitizePost(
  body: Record<string, unknown>,
): { kind: string; payload: Record<string, unknown> } | string {
  const kind = typeof body.kind === "string" ? body.kind : "";
  if (!KINDS.has(kind)) return "Unbekannte Art von Beitrag";
  const note = text(body.note, 280);
  if (kind === "workout") {
    const sport = typeof body.sport === "string" && SPORTS.has(body.sport) ? body.sport : "other";
    const title = text(body.title, 80);
    if (!title) return "Titel fehlt";
    const payload: Record<string, unknown> = { sport, title };
    const fields: [string, number][] = [
      ["durationMin", 1_440],
      ["distanceKm", 1_000],
      ["elevationM", 10_000],
      ["sets", 500],
      ["volumeKg", 200_000],
    ];
    for (const [key, max] of fields) {
      const value = number(body[key], max);
      if (value !== undefined) payload[key] = value;
    }
    const exercises = strings(body.exercises, 12, 60);
    if (exercises.length) payload.exercises = exercises;
    const records = strings(body.records, 10, 80);
    if (records.length) payload.records = records;
    if (note) payload.note = note;
    return { kind, payload };
  }
  if (kind === "meal") {
    const meal = sanitizeMeal(body.meal);
    if (typeof meal === "string") return meal;
    return { kind, payload: note ? { meal, note } : { meal } };
  }
  const title = text(body.title, 80);
  if (!title) return "Titel fehlt";
  const payload: Record<string, unknown> = { title };
  const detail = text(body.text, 200);
  if (detail) payload.text = detail;
  const badge = typeof body.badge === "string" && /^[a-z0-9_.]{2,40}$/.test(body.badge) ? body.badge : "";
  if (badge) payload.badge = badge;
  return { kind, payload };
}

// MARK: - Beziehungen

async function accountByUsername(db: SqlDatabase, username: string) {
  return db
    .prepare("SELECT id, username, display_name FROM accounts WHERE username = ?")
    .bind(username.trim().toLowerCase())
    .first<{ id: string; username: string; display_name: string }>();
}

async function isBlocked(db: SqlDatabase, x: string, y: string): Promise<boolean> {
  const row = await db
    .prepare(
      "SELECT 1 AS x FROM blocks WHERE (blocker = ?1 AND blocked = ?2) OR (blocker = ?2 AND blocked = ?1) LIMIT 1",
    )
    .bind(x, y)
    .first();
  return Boolean(row);
}

export async function relation(db: SqlDatabase, me: string, other: string): Promise<Relation> {
  if (me === other) return "self";
  const blocked = await db
    .prepare("SELECT 1 AS x FROM blocks WHERE blocker = ? AND blocked = ?")
    .bind(me, other)
    .first();
  if (blocked) return "blocked";
  const [a, b] = pair(me, other);
  const row = await db
    .prepare("SELECT status, requested_by FROM friendships WHERE a = ? AND b = ?")
    .bind(a, b)
    .first<{ status: string; requested_by: string }>();
  if (!row) return "none";
  if (row.status === "accepted") return "friends";
  return row.requested_by === me ? "outgoing" : "incoming";
}

/** Freundes-IDs einer Person (für Feed und Ranglisten). */
export function friendIdsSql(param: string): string {
  return `SELECT CASE WHEN f.a = ${param} THEN f.b ELSE f.a END FROM friendships f
          WHERE (f.a = ${param} OR f.b = ${param}) AND f.status = 'accepted'`;
}

async function areFriendsOrSelf(db: SqlDatabase, me: string, other: string): Promise<boolean> {
  if (me === other) return true;
  return (await relation(db, me, other)) === "friends";
}

// MARK: - Beiträge

interface PostRow {
  id: string;
  author: string;
  kind: string;
  created_at: number;
  payload: string;
  username: string;
  display_name: string;
  reactions: number;
  mine: string | null;
  comments: number;
  top: string | null;
}

const POST_SELECT = `SELECT p.id, p.author, p.kind, p.created_at, p.payload, a.username, a.display_name,
    (SELECT COUNT(*) FROM reactions r WHERE r.post_id = p.id) AS reactions,
    (SELECT emoji FROM reactions r WHERE r.post_id = p.id AND r.account_id = ?1) AS mine,
    (SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id) AS comments,
    (SELECT GROUP_CONCAT(emoji, '') FROM (SELECT emoji FROM reactions r WHERE r.post_id = p.id
       GROUP BY emoji ORDER BY COUNT(*) DESC LIMIT 3)) AS top
  FROM posts p JOIN accounts a ON a.id = p.author`;

function publicPost(row: PostRow, me: string) {
  let payload: unknown = {};
  try {
    payload = JSON.parse(row.payload);
  } catch {
    payload = {};
  }
  return {
    id: row.id,
    kind: row.kind,
    createdAt: new Date(row.created_at).toISOString(),
    author: { username: row.username, displayName: row.display_name },
    mine: row.author === me,
    payload,
    reactions: row.reactions,
    myReaction: row.mine,
    topReactions: row.top ?? "",
    comments: row.comments,
  };
}

async function feed(db: SqlDatabase, me: string, before: number, now: number) {
  const { results } = await db
    .prepare(
      `${POST_SELECT} WHERE p.created_at < ?2 AND p.created_at > ?3 AND (p.author = ?1 OR p.author IN (${friendIdsSql("?1")}))
       ORDER BY p.created_at DESC LIMIT ${FEED_PAGE}`,
    )
    .bind(me, before, now - POST_TTL_MS)
    .all<PostRow>();
  return results.map((row) => publicPost(row, me));
}

async function postVisible(db: SqlDatabase, me: string, postId: string): Promise<{ author: string } | null> {
  const post = await db
    .prepare("SELECT author FROM posts WHERE id = ?")
    .bind(postId)
    .first<{ author: string }>();
  if (!post) return null;
  return (await areFriendsOrSelf(db, me, post.author)) ? post : null;
}

/** Was beim Löschen eines Kontos mitgeht (wird in accounts.ts an ACCOUNT_CLEANUP angehängt). */
export const SOCIAL_CLEANUP: ((db: SqlDatabase, id: string) => SqlStatement)[] = [
  (db, id) => db.prepare("DELETE FROM friendships WHERE a = ?1 OR b = ?1").bind(id),
  (db, id) => db.prepare("DELETE FROM blocks WHERE blocker = ?1 OR blocked = ?1").bind(id),
  (db, id) =>
    db
      .prepare(
        "DELETE FROM reactions WHERE account_id = ?1 OR post_id IN (SELECT id FROM posts WHERE author = ?1)",
      )
      .bind(id),
  (db, id) =>
    db
      .prepare(
        "DELETE FROM comments WHERE author = ?1 OR post_id IN (SELECT id FROM posts WHERE author = ?1)",
      )
      .bind(id),
  (db, id) => db.prepare("DELETE FROM posts WHERE author = ?").bind(id),
];

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

// MARK: - HTTP

export async function handleSocial(
  request: Request,
  db: SqlDatabase | undefined,
  me: Me | null,
  now: number,
): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/v1/social/")) return null;
  if (!db)
    return fail(503, "Freunde sind auf diesem Server nicht eingerichtet (D1 fehlt).", "social_unavailable");
  if (!me) return fail(401, "Für Freunde brauchst du ein Konto. Bitte anmelden.", "account_required");
  await ensureSchema(db);
  const parts = url.pathname.slice("/v1/social/".length).split("/").filter(Boolean);
  const method = request.method;
  const [section, target, sub] = parts;

  if (section === "search" && method === "GET") {
    const query = (url.searchParams.get("q") ?? "").trim().toLowerCase().replace(/^@/, "");
    if (query.length < 2 || !/^[a-z0-9_.]+$/.test(query)) return json(200, { people: [] });
    const { results } = await db
      .prepare(
        `SELECT id, username, display_name FROM accounts
         WHERE username >= ?1 AND username < ?2 AND id != ?3
           AND id NOT IN (SELECT blocker FROM blocks WHERE blocked = ?3)
         ORDER BY username LIMIT 10`,
      )
      .bind(query, `${query}￿`, me.id)
      .all<{ id: string; username: string; display_name: string }>();
    const people = [];
    for (const row of results) {
      people.push({
        username: row.username,
        displayName: row.display_name,
        relation: await relation(db, me.id, row.id),
      });
    }
    return json(200, { people });
  }

  if (section === "friends" && !target && method === "GET") {
    const { results } = await db
      .prepare(
        `SELECT f.status, f.requested_by, f.created_at, a.id, a.username, a.display_name FROM friendships f
         JOIN accounts a ON a.id = CASE WHEN f.a = ?1 THEN f.b ELSE f.a END
         WHERE f.a = ?1 OR f.b = ?1 ORDER BY a.display_name COLLATE NOCASE`,
      )
      .bind(me.id)
      .all<{
        status: string;
        requested_by: string;
        created_at: number;
        id: string;
        username: string;
        display_name: string;
      }>();
    const person = (row: (typeof results)[number]) => ({
      username: row.username,
      displayName: row.display_name,
      since: new Date(row.created_at).toISOString(),
    });
    return json(200, {
      friends: results.filter((row) => row.status === "accepted").map(person),
      incoming: results.filter((row) => row.status === "pending" && row.requested_by !== me.id).map(person),
      outgoing: results.filter((row) => row.status === "pending" && row.requested_by === me.id).map(person),
    });
  }

  if ((section === "friends" || section === "blocks" || section === "people") && target) {
    const other = await accountByUsername(db, target);
    if (!other || other.id === me.id) return fail(404, "Konto nicht gefunden.", "not_found");
    const [a, b] = pair(me.id, other.id);

    if (section === "people" && method === "GET") {
      const rel = await relation(db, me.id, other.id);
      if (rel !== "blocked" && (await isBlocked(db, me.id, other.id)))
        return fail(404, "Konto nicht gefunden.", "not_found");
      let posts: ReturnType<typeof publicPost>[] = [];
      if (rel === "friends") {
        const { results } = await db
          .prepare(
            `${POST_SELECT} WHERE p.author = ?2 AND p.created_at > ?3 ORDER BY p.created_at DESC LIMIT 20`,
          )
          .bind(me.id, other.id, now - POST_TTL_MS)
          .all<PostRow>();
        posts = results.map((row) => publicPost(row, me.id));
      }
      return json(200, { username: other.username, displayName: other.display_name, relation: rel, posts });
    }

    if (section === "friends" && method === "POST") {
      if (await isBlocked(db, me.id, other.id)) return fail(403, "Anfrage nicht möglich.", "blocked");
      const rel = await relation(db, me.id, other.id);
      if (rel === "friends") return json(200, { relation: "friends" });
      if (rel === "outgoing") return json(200, { relation: "outgoing" });
      if (rel === "incoming") {
        await db
          .prepare("UPDATE friendships SET status = 'accepted', created_at = ? WHERE a = ? AND b = ?")
          .bind(now, a, b)
          .run();
        return json(200, { relation: "friends" });
      }
      const pending = await db
        .prepare("SELECT COUNT(*) AS n FROM friendships WHERE requested_by = ? AND status = 'pending'")
        .bind(me.id)
        .first<{ n: number }>();
      if ((pending?.n ?? 0) >= MAX_PENDING_REQUESTS) {
        return fail(429, `Du hast schon ${MAX_PENDING_REQUESTS} offene Anfragen.`, "too_many_requests");
      }
      await db
        .prepare(
          "INSERT OR IGNORE INTO friendships (a, b, status, requested_by, created_at) VALUES (?, ?, 'pending', ?, ?)",
        )
        .bind(a, b, me.id, now)
        .run();
      return json(200, { relation: "outgoing" });
    }
    if (section === "friends" && method === "DELETE") {
      await db.prepare("DELETE FROM friendships WHERE a = ? AND b = ?").bind(a, b).run();
      return json(200, { relation: "none" });
    }
    if (section === "blocks" && method === "POST") {
      await db.batch([
        db.prepare("DELETE FROM friendships WHERE a = ? AND b = ?").bind(a, b),
        db
          .prepare("INSERT OR IGNORE INTO blocks (blocker, blocked, created_at) VALUES (?, ?, ?)")
          .bind(me.id, other.id, now),
      ]);
      return json(200, { relation: "blocked" });
    }
    if (section === "blocks" && method === "DELETE") {
      await db.prepare("DELETE FROM blocks WHERE blocker = ? AND blocked = ?").bind(me.id, other.id).run();
      return json(200, { relation: "none" });
    }
  }

  if (section === "feed" && method === "GET") {
    const before = Number(url.searchParams.get("before") ?? now + 1);
    return json(200, { posts: await feed(db, me.id, Number.isFinite(before) ? before : now + 1, now) });
  }

  if (section === "posts" && !target && method === "POST") {
    const body = await readBody(request);
    if (body instanceof Response) return body;
    const post = sanitizePost(body);
    if (typeof post === "string") return fail(400, post, "invalid_post");
    const today = await db
      .prepare("SELECT COUNT(*) AS n FROM posts WHERE author = ? AND created_at > ?")
      .bind(me.id, now - DAY_MS)
      .first<{ n: number }>();
    if ((today?.n ?? 0) >= MAX_POSTS_PER_DAY) {
      return fail(429, `Höchstens ${MAX_POSTS_PER_DAY} Beiträge am Tag.`, "too_many_posts");
    }
    const id = randomId();
    const old = now - POST_TTL_MS;
    await db.batch([
      db
        .prepare("INSERT INTO posts (id, author, kind, created_at, payload) VALUES (?, ?, ?, ?, ?)")
        .bind(id, me.id, post.kind, now, JSON.stringify(post.payload)),
      // Eigene alte Beiträge mit Reaktionen und Kommentaren aufräumen.
      db
        .prepare(
          "DELETE FROM reactions WHERE post_id IN (SELECT id FROM posts WHERE author = ? AND created_at < ?)",
        )
        .bind(me.id, old),
      db
        .prepare(
          "DELETE FROM comments WHERE post_id IN (SELECT id FROM posts WHERE author = ? AND created_at < ?)",
        )
        .bind(me.id, old),
      db.prepare("DELETE FROM posts WHERE author = ? AND created_at < ?").bind(me.id, old),
    ]);
    const row = await db.prepare(`${POST_SELECT} WHERE p.id = ?2`).bind(me.id, id).first<PostRow>();
    return json(201, { post: row ? publicPost(row, me.id) : { id } });
  }

  if (section === "posts" && target) {
    const visible = await postVisible(db, me.id, target);
    if (!visible) return fail(404, "Beitrag nicht gefunden.", "not_found");
    if (!sub && method === "DELETE") {
      if (visible.author !== me.id) return fail(403, "Nur eigene Beiträge löschen.", "forbidden");
      await db.batch([
        db.prepare("DELETE FROM reactions WHERE post_id = ?").bind(target),
        db.prepare("DELETE FROM comments WHERE post_id = ?").bind(target),
        db.prepare("DELETE FROM posts WHERE id = ?").bind(target),
      ]);
      return json(200, { ok: true });
    }
    if (sub === "reaction" && method === "PUT") {
      const body = await readBody(request);
      if (body instanceof Response) return body;
      const emoji = typeof body.emoji === "string" ? body.emoji : "";
      if (!(REACTIONS as readonly string[]).includes(emoji))
        return fail(400, "Unbekannte Reaktion.", "invalid_reaction");
      await db
        .prepare(
          `INSERT INTO reactions (post_id, account_id, emoji, created_at) VALUES (?, ?, ?, ?)
           ON CONFLICT (post_id, account_id) DO UPDATE SET emoji = excluded.emoji, created_at = excluded.created_at`,
        )
        .bind(target, me.id, emoji, now)
        .run();
      return json(200, { ok: true });
    }
    if (sub === "reaction" && method === "DELETE") {
      await db
        .prepare("DELETE FROM reactions WHERE post_id = ? AND account_id = ?")
        .bind(target, me.id)
        .run();
      return json(200, { ok: true });
    }
    if (sub === "reactions" && method === "GET") {
      const { results } = await db
        .prepare(
          `SELECT r.emoji, a.username, a.display_name FROM reactions r JOIN accounts a ON a.id = r.account_id
           WHERE r.post_id = ? ORDER BY r.created_at`,
        )
        .bind(target)
        .all<{ emoji: string; username: string; display_name: string }>();
      return json(200, {
        reactions: results.map((row) => ({
          emoji: row.emoji,
          username: row.username,
          displayName: row.display_name,
        })),
      });
    }
    if (sub === "comments" && method === "GET") {
      const { results } = await db
        .prepare(
          `SELECT c.id, c.text, c.created_at, c.author, a.username, a.display_name FROM comments c
           JOIN accounts a ON a.id = c.author WHERE c.post_id = ? ORDER BY c.created_at LIMIT ${MAX_COMMENTS_PER_POST}`,
        )
        .bind(target)
        .all<{
          id: string;
          text: string;
          created_at: number;
          author: string;
          username: string;
          display_name: string;
        }>();
      return json(200, {
        comments: results.map((row) => ({
          id: row.id,
          text: row.text,
          createdAt: new Date(row.created_at).toISOString(),
          author: { username: row.username, displayName: row.display_name },
          canDelete: row.author === me.id || visible.author === me.id,
        })),
      });
    }
    if (sub === "comments" && method === "POST") {
      const body = await readBody(request);
      if (body instanceof Response) return body;
      const comment = text(body.text, 280);
      if (!comment) return fail(400, "Kommentar ist leer.", "empty_comment");
      const count = await db
        .prepare("SELECT COUNT(*) AS n FROM comments WHERE post_id = ?")
        .bind(target)
        .first<{ n: number }>();
      if ((count?.n ?? 0) >= MAX_COMMENTS_PER_POST)
        return fail(429, "Zu viele Kommentare.", "too_many_comments");
      const id = randomId();
      await db
        .prepare("INSERT INTO comments (id, post_id, author, text, created_at) VALUES (?, ?, ?, ?, ?)")
        .bind(id, target, me.id, comment, now)
        .run();
      return json(201, { id });
    }
  }

  if (section === "comments" && target && method === "DELETE") {
    const row = await db
      .prepare(
        "SELECT c.author, p.author AS post_author FROM comments c JOIN posts p ON p.id = c.post_id WHERE c.id = ?",
      )
      .bind(target)
      .first<{ author: string; post_author: string }>();
    if (!row || (row.author !== me.id && row.post_author !== me.id)) {
      return fail(404, "Kommentar nicht gefunden.", "not_found");
    }
    await db.prepare("DELETE FROM comments WHERE id = ?").bind(target).run();
    return json(200, { ok: true });
  }

  return fail(404, "Nicht gefunden", "not_found");
}
