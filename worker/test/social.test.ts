import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import { MAX_POSTS_PER_DAY, POST_TTL_MS, sanitizePost } from "../src/social";
import type { Env } from "../src/types";
import { env, fakeDeps } from "./helpers";
import { memoryDatabase } from "./sqlite";

const NOW = Date.UTC(2026, 10, 9, 12);
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
  const person = async (username: string, displayName = username) => {
    const invite = await call("/v1/account/invites", { method: "POST", body: {}, token: "app-token-123" });
    const created = await call("/v1/account/register", {
      body: { username, displayName, password: PASSWORD, invite: invite.body.code },
    });
    return created.body.token as string;
  };
  const befriend = async (one: string, other: string, otherName: string, oneName: string) => {
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

const workout = { kind: "workout", sport: "run", title: "Lockerer Lauf", durationMin: 45, distanceKm: 8.2 };

describe("Beiträge prüfen", () => {
  it("behält nur bekannte Felder, keine Körperwerte", () => {
    const post = sanitizePost({ ...workout, heartRate: 150, weightKg: 80, hrv: 60, sport: "fliegen" });
    expect(post).toEqual({
      kind: "workout",
      payload: { sport: "other", title: "Lockerer Lauf", durationMin: 45, distanceKm: 8.2 },
    });
    expect(sanitizePost({ kind: "geheim" })).toBe("Unbekannte Art von Beitrag");
    expect(sanitizePost({ kind: "workout" })).toBe("Titel fehlt");
    const meal = sanitizePost({
      kind: "meal",
      note: "Lecker!",
      meal: { title: "Bowl", items: [{ name: "Reis", grams: 150, per100g: { kcal: 130, protein: 2.7 } }] },
    });
    expect(meal).toMatchObject({ kind: "meal", payload: { note: "Lecker!", meal: { title: "Bowl" } } });
  });
});

describe("Freunde", () => {
  it("nur mit Konto; Gäste und Betreiber-Token bekommen eine klare Meldung", async () => {
    const app = setup();
    const result = await app.call("/v1/social/friends", { token: "app-token-123" });
    expect(result).toMatchObject({ status: 401, body: { code: "account_required" } });
    expect((await app.call("/v1/social/friends")).status).toBe(401);
  });

  it("finden über den Benutzernamen, anfragen, annehmen", async () => {
    const app = setup();
    const lena = await app.person("lena", "Lena");
    const tom = await app.person("tom", "Tom");
    await app.person("tobi");

    const search = await app.call("/v1/social/search?q=@TO", { token: lena });
    expect(search.body.people.map((p: { username: string }) => p.username)).toEqual(["tobi", "tom"]);
    expect(search.body.people[1]).toEqual({ username: "tom", displayName: "Tom", relation: "none" });
    expect((await app.call("/v1/social/search?q=t", { token: lena })).body.people).toEqual([]);

    const asked = await app.call("/v1/social/friends/tom", { method: "POST", body: {}, token: lena });
    expect(asked.body.relation).toBe("outgoing");
    const tomView = await app.call("/v1/social/friends", { token: tom });
    expect(tomView.body.incoming).toEqual([
      expect.objectContaining({ username: "lena", displayName: "Lena" }),
    ]);
    const accepted = await app.call("/v1/social/friends/lena", { method: "POST", body: {}, token: tom });
    expect(accepted.body.relation).toBe("friends");
    const lenaView = await app.call("/v1/social/friends", { token: lena });
    expect(lenaView.body.friends.map((p: { username: string }) => p.username)).toEqual(["tom"]);
    expect(lenaView.body.outgoing).toEqual([]);
  });

  it("ablehnen und entfernen; Sperren verhindert neue Anfragen und blendet aus der Suche aus", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    await app.call("/v1/social/friends/tom", { method: "POST", body: {}, token: lena });
    await app.call("/v1/social/friends/lena", { method: "DELETE", token: tom });
    expect((await app.call("/v1/social/friends", { token: lena })).body.outgoing).toEqual([]);

    await app.call("/v1/social/blocks/lena", { method: "POST", body: {}, token: tom });
    const again = await app.call("/v1/social/friends/tom", { method: "POST", body: {}, token: lena });
    expect(again.status).toBe(403);
    expect((await app.call("/v1/social/search?q=to", { token: lena })).body.people).toEqual([]);
    expect((await app.call("/v1/social/people/tom", { token: lena })).status).toBe(404);
    await app.call("/v1/social/blocks/lena", { method: "DELETE", token: tom });
    expect(
      (await app.call("/v1/social/friends/tom", { method: "POST", body: {}, token: lena })).body.relation,
    ).toBe("outgoing");
  });
});

describe("Feed", () => {
  it("Beiträge sehen nur Freunde und die Person selbst", async () => {
    const app = setup();
    const lena = await app.person("lena", "Lena");
    const tom = await app.person("tom");
    const fremd = await app.person("fremd");
    await app.befriend(lena, tom, "tom", "lena");

    const created = await app.call("/v1/social/posts", { body: workout, token: lena });
    expect(created.status).toBe(201);
    expect(created.body.post).toMatchObject({ kind: "workout", mine: true, author: { username: "lena" } });

    const tomFeed = await app.call("/v1/social/feed", { token: tom });
    expect(tomFeed.body.posts).toHaveLength(1);
    expect(tomFeed.body.posts[0]).toMatchObject({
      mine: false,
      payload: { title: "Lockerer Lauf", distanceKm: 8.2 },
    });
    expect((await app.call("/v1/social/feed", { token: fremd })).body.posts).toEqual([]);
    expect((await app.call("/v1/social/people/lena", { token: fremd })).body).toMatchObject({
      relation: "none",
      posts: [],
    });
    expect((await app.call("/v1/social/people/lena", { token: tom })).body.posts).toHaveLength(1);

    const id = created.body.post.id;
    expect((await app.call(`/v1/social/posts/${id}/comments`, { token: fremd })).status).toBe(404);
    expect((await app.call(`/v1/social/posts/${id}`, { method: "DELETE", token: tom })).status).toBe(403);
  });

  it("nach dem Entfernen der Freundschaft sind die Beiträge weg", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    await app.befriend(lena, tom, "tom", "lena");
    await app.call("/v1/social/posts", { body: workout, token: lena });
    await app.call("/v1/social/friends/lena", { method: "DELETE", token: tom });
    expect((await app.call("/v1/social/feed", { token: tom })).body.posts).toEqual([]);
  });

  it("Reaktionen und Kommentare", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom", "Tom");
    await app.befriend(lena, tom, "tom", "lena");
    const id = (await app.call("/v1/social/posts", { body: workout, token: lena })).body.post.id;

    expect(
      (
        await app.call(`/v1/social/posts/${id}/reaction`, {
          method: "PUT",
          body: { emoji: "💩" },
          token: tom,
        })
      ).status,
    ).toBe(400);
    await app.call(`/v1/social/posts/${id}/reaction`, { method: "PUT", body: { emoji: "🔥" }, token: tom });
    await app.call(`/v1/social/posts/${id}/reaction`, { method: "PUT", body: { emoji: "💪" }, token: tom });
    await app.call(`/v1/social/posts/${id}/reaction`, { method: "PUT", body: { emoji: "👏" }, token: lena });
    const feed = await app.call("/v1/social/feed", { token: tom });
    expect(feed.body.posts[0]).toMatchObject({ reactions: 2, myReaction: "💪" });
    const who = await app.call(`/v1/social/posts/${id}/reactions`, { token: lena });
    expect(who.body.reactions).toContainEqual({ emoji: "💪", username: "tom", displayName: "Tom" });

    await app.call(`/v1/social/posts/${id}/comments`, { body: { text: "  Stark!  " }, token: tom });
    const comments = await app.call(`/v1/social/posts/${id}/comments`, { token: lena });
    expect(comments.body.comments).toEqual([
      expect.objectContaining({
        text: "Stark!",
        author: { username: "tom", displayName: "Tom" },
        canDelete: true,
      }),
    ]);
    // Wer den Beitrag geschrieben hat, darf Kommentare darunter löschen.
    await app.call(`/v1/social/comments/${comments.body.comments[0].id}`, { method: "DELETE", token: lena });
    expect((await app.call("/v1/social/feed", { token: tom })).body.posts[0].comments).toBe(0);
  });

  it("geteilte Mahlzeit enthält Positionen mit Nährwerten zum Übernehmen", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    await app.befriend(lena, tom, "tom", "lena");
    await app.call("/v1/social/posts", {
      token: lena,
      body: {
        kind: "meal",
        meal: {
          title: "Overnight Oats",
          items: [{ name: "Haferflocken", grams: 60, per100g: { kcal: 370, protein: 13 } }],
        },
      },
    });
    const post = (await app.call("/v1/social/feed", { token: tom })).body.posts[0];
    expect(post.payload.meal.items[0]).toMatchObject({
      name: "Haferflocken",
      grams: 60,
      per100g: { kcal: 370 },
    });
  });

  it("höchstens 30 Beiträge am Tag, nach 90 Tagen weg, Seiten über before", async () => {
    const app = setup();
    const lena = await app.person("lena");
    for (let i = 0; i < MAX_POSTS_PER_DAY; i++) {
      app.advance(1_000);
      expect(
        (await app.call("/v1/social/posts", { body: { ...workout, title: `Lauf ${i}` }, token: lena }))
          .status,
      ).toBe(201);
    }
    const limited = await app.call("/v1/social/posts", { body: workout, token: lena });
    expect(limited.body.code).toBe("too_many_posts");

    const page = await app.call("/v1/social/feed", { token: lena });
    expect(page.body.posts).toHaveLength(30);
    expect(page.body.posts[0].payload.title).toBe("Lauf 29");
    const older = await app.call(`/v1/social/feed?before=${Date.parse(page.body.posts[9].createdAt)}`, {
      token: lena,
    });
    expect(older.body.posts[0].payload.title).toBe("Lauf 19");

    app.advance(POST_TTL_MS + 1);
    expect((await app.call("/v1/social/feed", { token: lena })).body.posts).toEqual([]);
    await app.call("/v1/social/posts", { body: workout, token: lena });
    const rows = app.db.raw.prepare("SELECT COUNT(*) AS n FROM posts").get() as { n: number };
    expect(rows.n).toBe(1);
  });

  it("Konto löschen entfernt Freundschaften, Beiträge, Reaktionen und Kommentare", async () => {
    const app = setup();
    const lena = await app.person("lena");
    const tom = await app.person("tom");
    await app.befriend(lena, tom, "tom", "lena");
    const id = (await app.call("/v1/social/posts", { body: workout, token: tom })).body.post.id;
    await app.call(`/v1/social/posts/${id}/reaction`, { method: "PUT", body: { emoji: "🔥" }, token: lena });
    await app.call(`/v1/social/posts/${id}/comments`, { body: { text: "Super" }, token: lena });
    await app.call("/v1/social/posts", { body: workout, token: lena });
    await app.call("/v1/account/delete", { body: { password: PASSWORD }, token: lena });
    for (const table of ["friendships", "reactions", "comments"]) {
      expect(app.db.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()).toEqual({ n: 0 });
    }
    expect(app.db.raw.prepare("SELECT COUNT(*) AS n FROM posts").get()).toEqual({ n: 1 });
  });
});
