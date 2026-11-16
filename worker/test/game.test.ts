import { describe, expect, it } from "vitest";
import { mondayOf } from "../src/game";
import { handle } from "../src/index";
import type { Env } from "../src/types";
import { env, fakeDeps } from "./helpers";
import { memoryDatabase } from "./sqlite";

/** Mittwoch, 11.11.2026, 12:00 UTC – Woche ab Montag, 09.11. */
const NOW = Date.UTC(2026, 10, 11, 12);
const DAY = 24 * 3600 * 1000;
const PASSWORD = "Sommer-Lauf-2026";
const base = "https://coach-ai.example.workers.dev";

function setup() {
  const db = memoryDatabase();
  const withDb = { ...env, DB: db as unknown as D1Database } as Env;
  let clock = NOW;
  const call = async (path: string, init: { method?: string; body?: unknown; token?: string } = {}) => {
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (init.token) headers.authorization = `Bearer ${init.token}`;
    const response = await handle(
      new Request(`${base}${path}`, {
        method: init.method ?? (init.body === undefined ? "GET" : "POST"),
        headers,
        body: init.body === undefined ? undefined : JSON.stringify(init.body),
      }),
      withDb,
      fakeDeps([], clock),
    );
    // biome-ignore lint/suspicious/noExplicitAny: Testhilfe
    return { status: response.status, body: (await response.json()) as any };
  };
  const person = async (username: string) => {
    const invite = await call("/v1/account/invites", { method: "POST", body: {}, token: "app-token-123" });
    const created = await call("/v1/account/register", {
      body: { username, displayName: username.toUpperCase(), password: PASSWORD, invite: invite.body.code },
    });
    return created.body.token as string;
  };
  const befriend = async (one: string, oneName: string, other: string, otherName: string) => {
    await call(`/v1/social/friends/${otherName}`, { method: "POST", body: {}, token: one });
    await call(`/v1/social/friends/${oneName}`, { method: "POST", body: {}, token: other });
  };
  return {
    db,
    call,
    person,
    befriend,
    advance: (ms: number) => {
      clock += ms;
    },
  };
}

const score = (weekPoints: number, extra: Record<string, number> = {}) => ({
  week: "2026-11-09",
  weekPoints,
  totalPoints: 300 + weekPoints,
  streak: 2,
  dayStreak: 5,
  level: 3,
  ...extra,
});

describe("Woche", () => {
  it("Montag in UTC", () => {
    expect(mondayOf(NOW)).toBe("2026-11-09");
    expect(mondayOf(Date.UTC(2026, 10, 15, 23))).toBe("2026-11-09");
    expect(mondayOf(Date.UTC(2026, 10, 16, 0))).toBe("2026-11-16");
  });
});

describe("Rangliste", () => {
  it("zeigt dich und deine Freunde, Fremde nicht; Werte werden begrenzt", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    const fremd = await app.person("fremd");
    await app.befriend(lena, "lena", tom, "tom");
    await app.call("/v1/game/score", { method: "PUT", body: score(80), token: lena });
    await app.call("/v1/game/score", { method: "PUT", body: score(500), token: tom });
    await app.call("/v1/game/score", { method: "PUT", body: score(100), token: fremd });

    const board = await app.call("/v1/game/leaderboard?week=2026-11-09", { token: lena });
    expect(board.body.entries.map((e: { username: string }) => e.username)).toEqual(["tom", "lena"]);
    expect(board.body.entries[0]).toMatchObject({ rank: 1, weekPoints: 100, me: false, reported: true });
    expect(board.body.entries[1]).toMatchObject({ rank: 2, weekPoints: 80, me: true, dayStreak: 5 });

    expect(
      (await app.call("/v1/game/score", { method: "PUT", body: { week: "x" }, token: lena })).status,
    ).toBe(400);
  });

  it("Freunde ohne Meldung stehen mit 0 dabei", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    await app.befriend(lena, "lena", tom, "tom");
    const board = await app.call("/v1/game/leaderboard", { token: lena });
    expect(board.body.week).toBe("2026-11-09");
    expect(board.body.entries).toHaveLength(2);
    expect(board.body.entries.every((e: { reported: boolean }) => !e.reported)).toBe(true);
  });

  it("nur mit Konto", async () => {
    const app = setup();
    expect((await app.call("/v1/game/leaderboard", { token: "app-token-123" })).body.code).toBe(
      "account_required",
    );
  });
});

describe("Challenges", () => {
  it("anlegen nur mit Freunden, beitreten, Fortschritt begrenzt, Sieger nach Wochenende", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    const fremd = await app.person("fremd");
    await app.befriend(lena, "lena", tom, "tom");

    const onlyStrangers = await app.call("/v1/game/challenges", {
      token: lena,
      body: { metric: "minutes", invite: ["fremd"] },
    });
    expect(onlyStrangers.body.code).toBe("no_friends");

    const created = await app.call("/v1/game/challenges", {
      token: lena,
      body: { metric: "minutes", title: "Minuten-Duell", invite: ["tom", "fremd"] },
    });
    expect(created.status).toBe(201);
    const id = created.body.challenge.id;
    expect(created.body.challenge).toMatchObject({
      week: "2026-11-09",
      metricTitle: "Trainingsminuten",
      max: 630,
    });
    expect(created.body.challenge.members.map((m: { username: string }) => m.username).sort()).toEqual([
      "lena",
      "tom",
    ]);

    expect((await app.call("/v1/game/challenges", { token: fremd })).body.challenges).toEqual([]);
    const tomList = await app.call("/v1/game/challenges", { token: tom });
    expect(tomList.body.challenges[0].status).toBe("invited");
    const early = await app.call(`/v1/game/challenges/${id}/progress`, {
      method: "PUT",
      body: { value: 50 },
      token: tom,
    });
    expect(early.body.code).toBe("not_joined");
    await app.call(`/v1/game/challenges/${id}/join`, { body: {}, token: tom });

    // Übertraining bringt nichts: höchstens 90 Minuten am Tag.
    const capped = await app.call(`/v1/game/challenges/${id}/progress`, {
      method: "PUT",
      body: { value: 2_000 },
      token: tom,
    });
    expect(capped.body.challenge.members.find((m: { me: boolean }) => m.me).progress).toBe(630);
    await app.call(`/v1/game/challenges/${id}/progress`, { method: "PUT", body: { value: 200 }, token: tom });
    await app.call(`/v1/game/challenges/${id}/progress`, {
      method: "PUT",
      body: { value: 240 },
      token: lena,
    });

    const running = (await app.call("/v1/game/challenges", { token: lena })).body.challenges[0];
    expect(running.finished).toBe(false);
    expect(running.members.some((m: { winner: boolean }) => m.winner)).toBe(false);

    app.advance(5 * DAY);
    const done = (await app.call("/v1/game/challenges", { token: tom })).body.challenges[0];
    expect(done.finished).toBe(true);
    expect(done.members).toEqual([
      expect.objectContaining({ username: "lena", progress: 240, winner: true }),
      expect.objectContaining({ username: "tom", progress: 200, winner: false }),
    ]);
    app.advance(2 * DAY);
    const late = await app.call(`/v1/game/challenges/${id}/progress`, {
      method: "PUT",
      body: { value: 300 },
      token: tom,
    });
    expect(late.body.code).toBe("finished");
  });

  it("nächste Woche planen, verlassen, Ersteller löscht für alle", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    await app.befriend(lena, "lena", tom, "tom");
    const created = await app.call("/v1/game/challenges", {
      token: lena,
      body: { metric: "plan", week: "2026-11-16", invite: ["tom"] },
    });
    expect(created.body.challenge.week).toBe("2026-11-16");
    const id = created.body.challenge.id;
    await app.call(`/v1/game/challenges/${id}`, { method: "DELETE", token: tom });
    expect((await app.call("/v1/game/challenges", { token: tom })).body.challenges).toEqual([]);
    await app.call(`/v1/game/challenges/${id}`, { method: "DELETE", token: lena });
    expect(app.db.raw.prepare("SELECT COUNT(*) AS n FROM challenges").get()).toEqual({ n: 0 });
  });

  it("Konto löschen räumt Punkte und Challenges auf", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    await app.befriend(lena, "lena", tom, "tom");
    await app.call("/v1/game/score", { method: "PUT", body: score(50), token: lena });
    await app.call("/v1/game/challenges", { token: lena, body: { metric: "sessions", invite: ["tom"] } });
    await app.call("/v1/account/delete", { body: { password: PASSWORD }, token: lena });
    for (const table of ["scores", "challenges", "challenge_members"]) {
      expect(app.db.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()).toEqual({ n: 0 });
    }
  });
});
