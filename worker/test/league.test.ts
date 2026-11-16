import { describe, expect, it } from "vitest";
import { guestToken } from "../src/auth";
import { handle } from "../src/index";
import { type LeagueEntry, type LeagueStore, MAX_MEMBERS, mondayOf, parseEntry, ranked } from "../src/league";
import { env, fakeDeps } from "./helpers";

/** Mittwoch, 28.10.2026, 12:00 UTC. */
const NOW = Date.UTC(2026, 9, 28, 12);
const WEEK = "2026-10-26";

function memoryStore(): LeagueStore & { data: Map<string, unknown> } {
  const data = new Map<string, unknown>();
  return {
    data,
    put: async (key, _value, options) => {
      data.set(key, options?.metadata);
    },
    delete: async (key) => {
      data.delete(key);
    },
    list: async ({ prefix, limit }) => ({
      keys: [...data.entries()]
        .filter(([key]) => key.startsWith(prefix))
        .slice(0, limit)
        .map(([name, metadata]) => ({ name, metadata })),
    }),
  };
}

const body = (name: string, weekPoints: number, week = WEEK) => ({
  name,
  avatar: "dog.fill",
  week,
  weekPoints,
  totalPoints: weekPoints * 3,
  streak: 2,
  done: 2,
  planned: 3,
});

function request(path: string, method = "GET", payload?: unknown, token = env.COACH_APP_TOKEN): Request {
  return new Request(`https://x${path}`, {
    method,
    headers: { authorization: `Bearer ${token}` },
    body: payload === undefined ? undefined : JSON.stringify(payload),
  });
}

describe("league", () => {
  it("speichert Einträge und liefert sie sortiert", async () => {
    const store = memoryStore();
    const withKV = { ...env, LEAGUE: store as unknown as KVNamespace };
    const deps = () => fakeDeps([], NOW);
    const put = await handle(
      request("/v1/league/paar-123/members/alex-0001", "PUT", body("Alex", 30)),
      withKV,
      deps(),
    );
    expect(put.status).toBe(200);
    await handle(request("/v1/league/paar-123/members/lea-00001", "PUT", body("Lea", 50)), withKV, deps());
    await handle(request("/v1/league/andere-1/members/xyz-00001", "PUT", body("X", 99)), withKV, deps());

    const list = await handle(request(`/v1/league/paar-123?week=${WEEK}`), withKV, deps());
    const { members } = (await list.json()) as { members: LeagueEntry[] };
    expect(members.map((m) => m.name)).toEqual(["Lea", "Alex"]);
    expect(members[0]?.updatedAt).toBe("2026-10-28T12:00:00.000Z");

    const left = await handle(request("/v1/league/paar-123/members/lea-00001", "DELETE"), withKV, deps());
    expect(left.status).toBe(200);
    const after = (await (await handle(request("/v1/league/paar-123"), withKV, deps())).json()) as {
      members: LeagueEntry[];
    };
    expect(after.members.map((m) => m.name)).toEqual(["Alex"]);
  });

  it("verlangt das App-Token und gültige Werte", async () => {
    const withKV = { ...env, LEAGUE: memoryStore() as unknown as KVNamespace };
    const unauthorized = await handle(
      request("/v1/league/paar-123", "GET", undefined, "falsch"),
      withKV,
      fakeDeps([]),
    );
    expect(unauthorized.status).toBe(401);
    const badCode = await handle(request("/v1/league/AB"), withKV, fakeDeps([]));
    expect(badCode.status).toBe(400);
    const badBody = await handle(
      request("/v1/league/paar-123/members/alex-0001", "PUT", { ...body("Alex", 30), weekPoints: -5 }),
      withKV,
      fakeDeps([]),
    );
    expect(badBody.status).toBe(400);
    const post = await handle(request("/v1/league/paar-123", "POST", {}), withKV, fakeDeps([]));
    expect(post.status).toBe(405);
    const noStore = await handle(request("/v1/league/paar-123"), env, fakeDeps([]));
    expect(noStore.status).toBe(503);
  });

  it("Gäste können nur ihren eigenen Eintrag ändern oder löschen", async () => {
    const store = memoryStore();
    const withKV = { ...env, LEAGUE: store as unknown as KVNamespace };
    const deps = () => fakeDeps([], NOW);
    const master = env.COACH_APP_TOKEN ?? "";
    const lea = await guestToken(master, "leaaaaaaaaaa");
    const tom = await guestToken(master, "tomaaaaaaaaa");
    const path = "/v1/league/paar-123/members/lea-00001";
    expect((await handle(request(path, "PUT", body("Lea", 50), lea), withKV, deps())).status).toBe(200);
    // Fremder Gast und sogar das Haupt-Token: weder überschreiben noch löschen.
    expect((await handle(request(path, "PUT", body("Fake", 999), tom), withKV, deps())).status).toBe(403);
    expect((await handle(request(path, "DELETE", undefined, tom), withKV, deps())).status).toBe(403);
    expect((await handle(request(path, "DELETE", undefined, master), withKV, deps())).status).toBe(403);
    const list = await handle(request("/v1/league/paar-123"), withKV, deps());
    const members = ((await list.json()) as { members: Record<string, unknown>[] }).members;
    expect(members.map((m) => m.name)).toEqual(["Lea"]);
    expect(members[0]?.owner).toBeUndefined();
    expect((await handle(request(path, "DELETE", undefined, lea), withKV, deps())).status).toBe(200);
  });

  it("Einträge von vor der Besitzregel übernimmt der nächste Schreibzugriff", async () => {
    const store = memoryStore();
    const withKV = { ...env, LEAGUE: store as unknown as KVNamespace };
    const old = parseEntry("alex-0001", body("Alex", 10), new Date(NOW));
    store.data.set("league:paar-123:alex-0001", old);
    const path = "/v1/league/paar-123/members/alex-0001";
    const put = await handle(request(path, "PUT", body("Alex", 20)), withKV, fakeDeps([], NOW));
    expect(put.status).toBe(200);
    expect((store.data.get("league:paar-123:alex-0001") as { owner?: string }).owner).toBe("owner");
  });

  it("begrenzt die Zahl der Mitglieder", async () => {
    const store = memoryStore();
    for (let i = 0; i < MAX_MEMBERS; i++) store.data.set(`league:paar-123:member-${1000 + i}`, {});
    const withKV = { ...env, LEAGUE: store as unknown as KVNamespace };
    const full = await handle(
      request("/v1/league/paar-123/members/neu-000001", "PUT", body("Neu", 1)),
      withKV,
      fakeDeps([], NOW),
    );
    expect(full.status).toBe(409);
    const update = await handle(
      request("/v1/league/paar-123/members/member-1000", "PUT", body("Alt", 1)),
      withKV,
      fakeDeps([], NOW),
    );
    expect(update.status).toBe(200);
  });

  it("kürzt Namen, prüft Symbole und wertet alte Wochen mit 0", () => {
    const now = new Date(NOW);
    const entry = parseEntry(
      "alex-0001",
      { ...body("  Ein sehr sehr sehr langer Name, wirklich  ", 10), avatar: "<b>" },
      now,
    );
    expect(typeof entry).toBe("object");
    if (typeof entry === "string") return;
    expect(entry.name.length).toBe(30);
    expect(entry.avatar).toBe("person");
    expect(parseEntry("x", { ...body("A", 1), week: "gestern" }, now)).toBe("week ungültig");

    const old = { ...entry, name: "Alt", week: "2026-10-19", weekPoints: 90 };
    const current = { ...entry, name: "Neu", weekPoints: 10 };
    const result = ranked([old, current], WEEK);
    expect(result.map((e) => [e.name, e.weekPoints])).toEqual([
      ["Neu", 10],
      ["Alt", 0],
    ]);
    expect(mondayOf(now)).toBe(WEEK);
    expect(mondayOf(new Date(Date.UTC(2026, 10, 1, 23)))).toBe(WEEK);
  });
});
