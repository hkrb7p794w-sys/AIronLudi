/**
 * Spielelemente zwischen Freunden: Wochen-Rangliste und Challenges (nur mit Konto, siehe social.ts).
 *
 * Grundsatz „Regeln entscheiden“: Die App rechnet die Werte selbst mit denselben Regeln wie Begleiter und Plan
 * (CoachCore `ScoreRules`, `ChallengeMetric`) und meldet nur Zahlen. Der Worker begrenzt sie so, dass Übertraining
 * nichts bringt: höchstens 100 Wochenpunkte (Plan erfüllt), Trainingsminuten höchstens 90 am Tag, Einheiten höchstens
 * eine am Tag. Unter Freunden gilt Vertrauen – der Worker prüft Grenzen, nicht Wahrheit.
 *
 * PUT    /v1/game/score {week, weekPoints, totalPoints, streak, dayStreak, level} – eigener Stand der Woche
 * GET    /v1/game/leaderboard?week=yyyy-MM-dd                                      – du und deine Freunde
 * GET    /v1/game/challenges                                                         – laufende und letzte 4 Wochen
 * POST   /v1/game/challenges {metric, week, title?, invite: [username]}              – neue Challenge (nur Freunde)
 * POST   /v1/game/challenges/<id>/join   ·   DELETE /v1/game/challenges/<id>         – beitreten / verlassen
 * PUT    /v1/game/challenges/<id>/progress {value}                                   – eigener Stand
 */
import { ensureSchema, type SqlDatabase, type SqlStatement } from "./db";
import { friendIdsSql, type Me } from "./social";
import { readLimited } from "./tasks-util";

const WEEK = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 24 * 3600 * 1000;
export const MAX_INVITES = 10;
export const MAX_OPEN_CHALLENGES = 10;

/** Messgrößen mit Obergrenze für eine Woche (Montag bis Sonntag). */
export const METRICS: Record<string, { title: string; max: number }> = {
  plan: { title: "Plan erfüllt (%)", max: 100 },
  sessions: { title: "Trainingstage", max: 7 },
  minutes: { title: "Trainingsminuten", max: 7 * 90 },
  meals: { title: "Tage mit Ernährungstagebuch", max: 7 },
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function fail(status: number, error: string, code: string): Response {
  return json(status, { error, code });
}

function clamp(value: unknown, max: number): number | null {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.min(Math.max(Math.round(value), 0), max)
    : null;
}

/** Montag (UTC-Kalendertag) der Woche, die `now` enthält. */
export function mondayOf(now: number): string {
  const date = new Date(now);
  const weekday = (date.getUTCDay() + 6) % 7;
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() - weekday))
    .toISOString()
    .slice(0, 10);
}

function weekEnd(week: string): number {
  return Date.parse(`${week}T00:00:00Z`) + 7 * DAY_MS;
}

async function readBody(request: Request): Promise<Record<string, unknown> | Response> {
  const raw = await readLimited(request, 8_192);
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

export const GAME_CLEANUP: ((db: SqlDatabase, id: string) => SqlStatement)[] = [
  (db, id) => db.prepare("DELETE FROM scores WHERE account_id = ?").bind(id),
  (db, id) => db.prepare("DELETE FROM challenge_members WHERE account_id = ?").bind(id),
  (db, id) =>
    db
      .prepare(
        "DELETE FROM challenge_members WHERE challenge_id IN (SELECT id FROM challenges WHERE creator = ?)",
      )
      .bind(id),
  (db, id) => db.prepare("DELETE FROM challenges WHERE creator = ?").bind(id),
];

interface ChallengeRow {
  id: string;
  creator: string;
  title: string;
  metric: string;
  week: string;
}

async function challengeView(db: SqlDatabase, me: Me, row: ChallengeRow, now: number) {
  const { results } = await db
    .prepare(
      `SELECT m.account_id, m.status, m.progress, a.username, a.display_name FROM challenge_members m
       JOIN accounts a ON a.id = m.account_id WHERE m.challenge_id = ? ORDER BY m.progress DESC, a.username`,
    )
    .bind(row.id)
    .all<{ account_id: string; status: string; progress: number; username: string; display_name: string }>();
  const joined = results.filter((member) => member.status === "joined");
  const finished = now >= weekEnd(row.week);
  const best = joined.length ? Math.max(...joined.map((member) => member.progress)) : 0;
  const mine = results.find((member) => member.account_id === me.id);
  return {
    id: row.id,
    title: row.title,
    metric: row.metric,
    metricTitle: METRICS[row.metric]?.title ?? row.metric,
    max: METRICS[row.metric]?.max ?? 0,
    week: row.week,
    finished,
    status: mine?.status ?? "none",
    mineCreated: row.creator === me.id,
    members: results.map((member) => ({
      username: member.username,
      displayName: member.display_name,
      status: member.status,
      progress: member.progress,
      me: member.account_id === me.id,
      // Sieger erst nach Wochenende; bei Gleichstand alle mit dem besten Wert, 0 gewinnt nie.
      winner: finished && member.status === "joined" && best > 0 && member.progress === best,
    })),
  };
}

export async function handleGame(
  request: Request,
  db: SqlDatabase | undefined,
  me: Me | null,
  now: number,
): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/v1/game/")) return null;
  if (!db) return fail(503, "Auf diesem Server nicht eingerichtet (D1 fehlt).", "game_unavailable");
  if (!me) return fail(401, "Dafür brauchst du ein Konto. Bitte anmelden.", "account_required");
  await ensureSchema(db);
  const [section, target, sub] = url.pathname.slice("/v1/game/".length).split("/").filter(Boolean);
  const method = request.method;

  if (section === "score" && method === "PUT") {
    const body = await readBody(request);
    if (body instanceof Response) return body;
    const week = typeof body.week === "string" && WEEK.test(body.week) ? body.week : "";
    if (!week) return fail(400, "Woche fehlt (yyyy-MM-dd).", "invalid_week");
    const values = {
      weekPoints: clamp(body.weekPoints, 100),
      totalPoints: clamp(body.totalPoints, 100_000),
      streak: clamp(body.streak, 520),
      dayStreak: clamp(body.dayStreak, 3_650),
      level: clamp(body.level, 1_000),
    };
    if (Object.values(values).some((value) => value === null))
      return fail(400, "Ungültige Werte.", "invalid_score");
    await db
      .prepare(
        `INSERT INTO scores (account_id, week, week_points, total_points, streak, day_streak, level, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (account_id, week) DO UPDATE SET week_points = excluded.week_points,
           total_points = excluded.total_points, streak = excluded.streak, day_streak = excluded.day_streak,
           level = excluded.level, updated_at = excluded.updated_at`,
      )
      .bind(
        me.id,
        week,
        values.weekPoints,
        values.totalPoints,
        values.streak,
        values.dayStreak,
        values.level,
        now,
      )
      .run();
    // Alte Wochen (älter als 12 Wochen) aufräumen.
    await db
      .prepare("DELETE FROM scores WHERE account_id = ? AND updated_at < ?")
      .bind(me.id, now - 84 * DAY_MS)
      .run();
    return json(200, { ok: true });
  }

  if (section === "leaderboard" && method === "GET") {
    const requested = url.searchParams.get("week") ?? "";
    const week = WEEK.test(requested) ? requested : mondayOf(now);
    const { results } = await db
      .prepare(
        `SELECT a.username, a.display_name, a.id, s.week_points, s.total_points, s.streak, s.day_streak, s.level
         FROM accounts a LEFT JOIN scores s ON s.account_id = a.id AND s.week = ?2
         WHERE a.id = ?1 OR a.id IN (${friendIdsSql("?1")})
         ORDER BY COALESCE(s.week_points, 0) DESC, COALESCE(s.total_points, 0) DESC, a.username`,
      )
      .bind(me.id, week)
      .all<{
        username: string;
        display_name: string;
        id: string;
        week_points: number | null;
        total_points: number | null;
        streak: number | null;
        day_streak: number | null;
        level: number | null;
      }>();
    return json(200, {
      week,
      entries: results.map((row, index) => ({
        rank: index + 1,
        username: row.username,
        displayName: row.display_name,
        me: row.id === me.id,
        weekPoints: row.week_points ?? 0,
        totalPoints: row.total_points ?? 0,
        streak: row.streak ?? 0,
        dayStreak: row.day_streak ?? 0,
        level: row.level ?? 0,
        reported: row.week_points !== null,
      })),
    });
  }

  if (section === "challenges" && !target && method === "GET") {
    const oldest = mondayOf(now - 28 * DAY_MS);
    const { results } = await db
      .prepare(
        `SELECT c.id, c.creator, c.title, c.metric, c.week FROM challenges c
         JOIN challenge_members m ON m.challenge_id = c.id AND m.account_id = ?
         WHERE c.week >= ? ORDER BY c.week DESC, c.created_at DESC LIMIT 30`,
      )
      .bind(me.id, oldest)
      .all<ChallengeRow>();
    const challenges = [];
    for (const row of results) challenges.push(await challengeView(db, me, row, now));
    return json(200, { challenges });
  }

  if (section === "challenges" && !target && method === "POST") {
    const body = await readBody(request);
    if (body instanceof Response) return body;
    const metric = typeof body.metric === "string" && METRICS[body.metric] ? body.metric : "";
    if (!metric) return fail(400, "Unbekannte Messgröße.", "invalid_metric");
    const current = mondayOf(now);
    const next = mondayOf(now + 7 * DAY_MS);
    const week = body.week === next ? next : current;
    const title =
      typeof body.title === "string" && body.title.trim()
        ? body.title.trim().replace(/\s+/g, " ").slice(0, 60)
        : (METRICS[metric]?.title ?? "Challenge");
    const usernames = (Array.isArray(body.invite) ? body.invite : [])
      .filter((item): item is string => typeof item === "string")
      .map((item) => item.trim().toLowerCase())
      .slice(0, MAX_INVITES);
    const open = await db
      .prepare(`SELECT COUNT(*) AS n FROM challenges WHERE creator = ? AND week >= ?`)
      .bind(me.id, current)
      .first<{ n: number }>();
    if ((open?.n ?? 0) >= MAX_OPEN_CHALLENGES)
      return fail(429, "Zu viele laufende Challenges.", "too_many_challenges");
    // Nur Freunde lassen sich einladen.
    const invited: string[] = [];
    for (const username of usernames) {
      const friend = await db
        .prepare(`SELECT id FROM accounts WHERE username = ?2 AND id IN (${friendIdsSql("?1")})`)
        .bind(me.id, username)
        .first<{ id: string }>();
      if (friend && !invited.includes(friend.id)) invited.push(friend.id);
    }
    if (invited.length === 0) return fail(400, "Lade mindestens eine befreundete Person ein.", "no_friends");
    const id = [...crypto.getRandomValues(new Uint8Array(10))]
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    await db.batch([
      db
        .prepare(
          "INSERT INTO challenges (id, creator, title, metric, week, created_at) VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(id, me.id, title, metric, week, now),
      db
        .prepare(
          "INSERT INTO challenge_members (challenge_id, account_id, status, progress, updated_at) VALUES (?, ?, 'joined', 0, ?)",
        )
        .bind(id, me.id, now),
      ...invited.map((friend) =>
        db
          .prepare(
            "INSERT INTO challenge_members (challenge_id, account_id, status, progress, updated_at) VALUES (?, ?, 'invited', 0, ?)",
          )
          .bind(id, friend, now),
      ),
    ]);
    const row = { id, creator: me.id, title, metric, week };
    return json(201, { challenge: await challengeView(db, me, row, now) });
  }

  if (section === "challenges" && target) {
    const row = await db
      .prepare(
        `SELECT c.id, c.creator, c.title, c.metric, c.week, m.status FROM challenges c
         JOIN challenge_members m ON m.challenge_id = c.id AND m.account_id = ? WHERE c.id = ?`,
      )
      .bind(me.id, target)
      .first<ChallengeRow & { status: string }>();
    if (!row) return fail(404, "Challenge nicht gefunden.", "not_found");
    const finished = now >= weekEnd(row.week);
    if (sub === "join" && method === "POST") {
      if (finished) return fail(409, "Die Challenge ist vorbei.", "finished");
      await db
        .prepare(
          "UPDATE challenge_members SET status = 'joined', updated_at = ? WHERE challenge_id = ? AND account_id = ?",
        )
        .bind(now, row.id, me.id)
        .run();
      return json(200, { challenge: await challengeView(db, me, row, now) });
    }
    if (!sub && method === "DELETE") {
      await db
        .prepare("DELETE FROM challenge_members WHERE challenge_id = ? AND account_id = ?")
        .bind(row.id, me.id)
        .run();
      if (row.creator === me.id) {
        await db.batch([
          db.prepare("DELETE FROM challenge_members WHERE challenge_id = ?").bind(row.id),
          db.prepare("DELETE FROM challenges WHERE id = ?").bind(row.id),
        ]);
      }
      return json(200, { ok: true });
    }
    if (sub === "progress" && method === "PUT") {
      if (row.status !== "joined") return fail(409, "Erst beitreten.", "not_joined");
      // Nach Wochenende noch einen Tag zum Nachtragen, dann steht das Ergebnis fest.
      if (now >= weekEnd(row.week) + DAY_MS) return fail(409, "Die Challenge ist abgeschlossen.", "finished");
      const body = await readBody(request);
      if (body instanceof Response) return body;
      const value = clamp(body.value, METRICS[row.metric]?.max ?? 0);
      if (value === null) return fail(400, "Ungültiger Wert.", "invalid_value");
      await db
        .prepare(
          "UPDATE challenge_members SET progress = ?, updated_at = ? WHERE challenge_id = ? AND account_id = ?",
        )
        .bind(value, now, row.id, me.id)
        .run();
      return json(200, { challenge: await challengeView(db, me, row, now) });
    }
  }

  return fail(404, "Nicht gefunden", "not_found");
}
