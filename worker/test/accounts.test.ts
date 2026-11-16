import { describe, expect, it } from "vitest";
import {
  hashPassword,
  LOCK_MS,
  MAX_SESSIONS,
  passwordProblem,
  SESSION_TTL_MS,
  usernameProblem,
  verifyPassword,
} from "../src/accounts";
import { guestToken } from "../src/auth";
import { handle } from "../src/index";
import type { Env } from "../src/types";
import { env, fakeDeps, geminiText } from "./helpers";
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
      fakeDeps([() => geminiText('{"ok": true, "gruss": "Hallo"}')], clock),
    );
    // biome-ignore lint/suspicious/noExplicitAny: Testhilfe
    return { status: response.status, body: (await response.json()) as any };
  };
  return {
    db,
    call,
    advance: (ms: number) => {
      clock += ms;
    },
    /** Einladung vom Betreiber und Registrierung damit. */
    async register(username = "lena", password = PASSWORD) {
      const invite = await call("/v1/account/invites", { method: "POST", body: {}, token: "app-token-123" });
      return call("/v1/account/register", {
        body: { username, password, displayName: "Lena", invite: invite.body.code, device: "iPhone" },
      });
    },
  };
}

describe("Regeln", () => {
  it("prüft Benutzernamen", () => {
    expect(usernameProblem("lena")).toBeNull();
    expect(usernameProblem("max_mustermann.1")).toBeNull();
    expect(usernameProblem("ab")).not.toBeNull();
    expect(usernameProblem(".lena")).not.toBeNull();
    expect(usernameProblem("lena müller")).not.toBeNull();
    expect(usernameProblem("admin")).toBe("Dieser Benutzername ist reserviert.");
  });

  it("prüft Passwörter", () => {
    expect(passwordProblem(PASSWORD, "lena")).toBeNull();
    expect(passwordProblem("kurz", "lena")).toContain("mindestens 10");
    expect(passwordProblem("lena-passwort-1", "lena")).toContain("Benutzernamen");
    expect(passwordProblem("aaaaaaaaaaaa", "lena")).toContain("zu einfach");
  });

  it("speichert Passwörter nur als PBKDF2 mit Salz", async () => {
    const one = await hashPassword(PASSWORD, 1_000);
    const two = await hashPassword(PASSWORD, 1_000);
    expect(one).toMatch(/^pbkdf2\$sha256\$1000\$/);
    expect(one).not.toBe(two);
    expect(one).not.toContain(PASSWORD);
    expect(await verifyPassword(PASSWORD, one)).toBe(true);
    expect(await verifyPassword("falsch-falsch", one)).toBe(false);
    expect(await verifyPassword(PASSWORD, "kaputt")).toBe(false);
  });
});

describe("Registrieren", () => {
  it("geht nur mit Einladung, die Einladung gilt einmal", async () => {
    const app = setup();
    const without = await app.call("/v1/account/register", {
      body: { username: "lena", password: PASSWORD },
    });
    expect(without).toMatchObject({ status: 403, body: { code: "invite_required" } });

    const invite = await app.call("/v1/account/invites", {
      method: "POST",
      body: {},
      token: "app-token-123",
    });
    expect(invite.body.code).toMatch(/^[A-Z2-9]{10}$/);
    const created = await app.call("/v1/account/register", {
      body: { username: "Lena", password: PASSWORD, invite: invite.body.code.toLowerCase() },
    });
    expect(created.status).toBe(201);
    expect(created.body.account).toMatchObject({ username: "lena", displayName: "lena", isAdmin: false });
    expect(created.body.token).toMatch(/^s1\./);
    expect(created.body.recoveryCode).toMatch(/^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$/);

    const again = await app.call("/v1/account/register", {
      body: { username: "tom", password: PASSWORD, invite: invite.body.code },
    });
    expect(again).toMatchObject({ status: 403, body: { code: "invite_invalid" } });
  });

  it("speichert weder Passwort noch Token im Klartext", async () => {
    const app = setup();
    const created = await app.register();
    const dump = JSON.stringify([
      app.db.raw.prepare("SELECT * FROM accounts").all(),
      app.db.raw.prepare("SELECT * FROM sessions").all(),
    ]);
    expect(dump).not.toContain(PASSWORD);
    expect(dump).not.toContain(created.body.token);
    expect(dump).not.toContain(created.body.recoveryCode);
  });

  it("verhindert doppelte Namen und abgelaufene Einladungen", async () => {
    const app = setup();
    expect((await app.register("lena")).status).toBe(201);
    expect((await app.register("LENA")).body.code).toBe("username_taken");
    const invite = await app.call("/v1/account/invites", {
      method: "POST",
      body: {},
      token: "app-token-123",
    });
    app.advance(15 * 24 * 3600 * 1000);
    const late = await app.call("/v1/account/register", {
      body: { username: "tom", password: PASSWORD, invite: invite.body.code },
    });
    expect(late.body.code).toBe("invite_invalid");
  });

  it("mit dem Haupt-Token entsteht das Betreiberkonto, mit einem Gast-Token genau ein Konto", async () => {
    const app = setup();
    const owner = await app.call("/v1/account/register", {
      token: "app-token-123",
      body: { username: "alex", password: PASSWORD },
    });
    expect(owner.body.account.isAdmin).toBe(true);
    const guest = await guestToken("app-token-123", "abcdefghjkmn");
    const first = await app.call("/v1/account/register", {
      token: guest,
      body: { username: "lena", password: PASSWORD },
    });
    expect(first.status).toBe(201);
    const second = await app.call("/v1/account/register", {
      token: guest,
      body: { username: "tom", password: PASSWORD },
    });
    expect(second.body.code).toBe("guest_used");
  });

  it("lehnt schwache Passwörter mit verständlicher Meldung ab", async () => {
    const app = setup();
    const result = await app.register("lena", "kurz");
    expect(result).toMatchObject({ status: 400, body: { code: "weak_password" } });
    expect(result.body.error).toContain("mindestens 10 Zeichen");
  });
});

describe("Anmelden und Sitzungen", () => {
  it("meldet an, und nur das eigene Token öffnet das eigene Konto", async () => {
    const app = setup();
    const lena = await app.register("lena");
    const tom = await app.register("tom");
    const meLena = await app.call("/v1/account/me", { token: lena.body.token });
    expect(meLena.body.account.username).toBe("lena");
    expect(meLena.body.sessions).toEqual([expect.objectContaining({ device: "iPhone", current: true })]);
    const meTom = await app.call("/v1/account/me", { token: tom.body.token });
    expect(meTom.body.account.username).toBe("tom");

    const login = await app.call("/v1/account/login", {
      body: { username: "LENA ", password: PASSWORD, device: "iPad" },
    });
    expect(login.status).toBe(200);
    expect(login.body.token).not.toBe(lena.body.token);
    const sessions = await app.call("/v1/account/me", { token: login.body.token });
    expect(sessions.body.sessions).toHaveLength(2);

    expect((await app.call("/v1/account/me", { token: "s1.erfundenerfundenerfundenerfunden" })).status).toBe(
      401,
    );
    expect((await app.call("/v1/account/me")).status).toBe(401);
  });

  it("gleiche Meldung für falsches Passwort und unbekannten Namen", async () => {
    const app = setup();
    await app.register("lena");
    const wrong = await app.call("/v1/account/login", {
      body: { username: "lena", password: "falsch-falsch" },
    });
    const unknown = await app.call("/v1/account/login", {
      body: { username: "niemand", password: "falsch-falsch" },
    });
    expect(wrong).toEqual(unknown);
    expect(wrong.status).toBe(401);
  });

  it("sperrt nach 5 Fehlversuchen für 15 Minuten, auch mit richtigem Passwort", async () => {
    const app = setup();
    await app.register("lena");
    for (let i = 0; i < 5; i++) {
      await app.call("/v1/account/login", { body: { username: "lena", password: "falsch-falsch" } });
    }
    const locked = await app.call("/v1/account/login", { body: { username: "lena", password: PASSWORD } });
    expect(locked).toMatchObject({ status: 429, body: { code: "locked" } });
    expect(locked.body.error).toContain("15 Minuten");
    app.advance(LOCK_MS + 1);
    expect(
      (await app.call("/v1/account/login", { body: { username: "lena", password: PASSWORD } })).status,
    ).toBe(200);
  });

  it("abmelden beendet nur dieses Gerät, „überall“ alle", async () => {
    const app = setup();
    const first = await app.register("lena");
    const second = await app.call("/v1/account/login", { body: { username: "lena", password: PASSWORD } });
    await app.call("/v1/account/logout", { token: first.body.token, body: {} });
    expect((await app.call("/v1/account/me", { token: first.body.token })).status).toBe(401);
    expect((await app.call("/v1/account/me", { token: second.body.token })).status).toBe(200);
    const third = await app.call("/v1/account/login", { body: { username: "lena", password: PASSWORD } });
    await app.call("/v1/account/logout", { token: third.body.token, body: { all: true } });
    expect((await app.call("/v1/account/me", { token: second.body.token })).status).toBe(401);
  });

  it("Sitzungen verfallen nach 180 Tagen ohne Nutzung, höchstens 10 je Konto", async () => {
    const app = setup();
    const created = await app.register("lena");
    app.advance(SESSION_TTL_MS + 1);
    expect((await app.call("/v1/account/me", { token: created.body.token })).status).toBe(401);
    for (let i = 0; i < MAX_SESSIONS + 2; i++) {
      app.advance(1_000);
      await app.call("/v1/account/login", { body: { username: "lena", password: PASSWORD } });
    }
    const count = app.db.raw.prepare("SELECT COUNT(*) AS n FROM sessions").get() as { n: number };
    expect(count.n).toBe(MAX_SESSIONS);
  });

  it("Passwort ändern beendet die anderen Sitzungen", async () => {
    const app = setup();
    const first = await app.register("lena");
    const other = await app.call("/v1/account/login", { body: { username: "lena", password: PASSWORD } });
    const wrong = await app.call("/v1/account/password", {
      token: first.body.token,
      body: { oldPassword: "falsch-falsch", newPassword: "Neues-Passwort-9" },
    });
    expect(wrong.status).toBe(401);
    const changed = await app.call("/v1/account/password", {
      token: first.body.token,
      body: { oldPassword: PASSWORD, newPassword: "Neues-Passwort-9" },
    });
    expect(changed.status).toBe(200);
    expect((await app.call("/v1/account/me", { token: first.body.token })).status).toBe(200);
    expect((await app.call("/v1/account/me", { token: other.body.token })).status).toBe(401);
    expect(
      (await app.call("/v1/account/login", { body: { username: "lena", password: PASSWORD } })).status,
    ).toBe(401);
  });
});

describe("Wiederherstellen und Löschen", () => {
  it("Wiederherstellungscode setzt ein neues Passwort, gilt einmal und beendet alle Sitzungen", async () => {
    const app = setup();
    const created = await app.register("lena");
    const code = created.body.recoveryCode as string;
    const recovered = await app.call("/v1/account/recover", {
      body: {
        username: "lena",
        recoveryCode: code.toLowerCase().replace(/-/g, " "),
        newPassword: "Neues-Passwort-9",
      },
    });
    expect(recovered.status).toBe(200);
    expect(recovered.body.recoveryCode).not.toBe(code);
    expect((await app.call("/v1/account/me", { token: created.body.token })).status).toBe(401);
    const reuse = await app.call("/v1/account/recover", {
      body: { username: "lena", recoveryCode: code, newPassword: "Anderes-Passwort-7" },
    });
    expect(reuse.status).toBe(401);
  });

  it("der Betreiber stellt einen neuen Wiederherstellungscode aus, Gäste und Konten nicht", async () => {
    const app = setup();
    const created = await app.register("lena");
    const denied = await app.call("/v1/account/admin/reset", {
      token: created.body.token,
      body: { username: "lena" },
    });
    expect(denied.status).toBe(403);
    const reset = await app.call("/v1/account/admin/reset", {
      token: "app-token-123",
      body: { username: "lena" },
    });
    expect(reset.body.recoveryCode).toMatch(/^[A-Z2-9]{4}-/);
    const recovered = await app.call("/v1/account/recover", {
      body: { username: "lena", recoveryCode: reset.body.recoveryCode, newPassword: "Neues-Passwort-9" },
    });
    expect(recovered.status).toBe(200);
  });

  it("Konto löschen verlangt das Passwort und entfernt alles", async () => {
    const app = setup();
    const created = await app.register("lena");
    await app.call("/v1/account/invites", { method: "POST", token: created.body.token, body: {} });
    const wrong = await app.call("/v1/account/delete", {
      token: created.body.token,
      body: { password: "falsch-falsch" },
    });
    expect(wrong.status).toBe(401);
    expect(
      (await app.call("/v1/account/delete", { token: created.body.token, body: { password: PASSWORD } }))
        .status,
    ).toBe(200);
    for (const table of ["accounts", "sessions"]) {
      expect(app.db.raw.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get()).toEqual({ n: 0 });
    }
    expect(app.db.raw.prepare("SELECT COUNT(*) AS n FROM invites WHERE used_by IS NULL").get()).toEqual({
      n: 0,
    });
  });
});

describe("Einladungen und Zusammenspiel", () => {
  it("Konten laden selbst ein, höchstens 5 offene Einladungen", async () => {
    const app = setup();
    const lena = await app.register("lena");
    for (let i = 0; i < 5; i++) {
      expect(
        (await app.call("/v1/account/invites", { method: "POST", token: lena.body.token, body: {} })).status,
      ).toBe(200);
    }
    const sixth = await app.call("/v1/account/invites", { method: "POST", token: lena.body.token, body: {} });
    expect(sixth.body.code).toBe("too_many_invites");
    const list = await app.call("/v1/account/invites", { token: lena.body.token });
    expect(list.body.invites).toHaveLength(5);
    await app.call(`/v1/account/invites/${list.body.invites[0].code}`, {
      method: "DELETE",
      token: lena.body.token,
    });
    expect((await app.call("/v1/account/invites", { token: lena.body.token })).body.invites).toHaveLength(4);
    const friend = await app.call("/v1/account/register", {
      body: { username: "tom", password: PASSWORD, invite: list.body.invites[1].code },
    });
    expect(friend.status).toBe(201);
  });

  it("das Sitzungs-Token gilt für die KI wie ein Gast-Token", async () => {
    const app = setup();
    const lena = await app.register("lena");
    const ai = await app.call("/v1/ai/generate", { token: lena.body.token, body: { task: "ping" } });
    expect(ai.status).toBe(200);
    const invite = await app.call("/v1/invite", { token: lena.body.token, body: {} });
    expect(invite.status).toBe(403);
  });

  it("ohne D1 sagt der Worker, dass Konten fehlen", async () => {
    const response = await handle(
      new Request(`${base}/v1/account/login`, { method: "POST", body: "{}" }),
      env,
      fakeDeps([], NOW),
    );
    expect(response.status).toBe(503);
  });

  it("Anzeigename lässt sich ändern", async () => {
    const app = setup();
    const lena = await app.register("lena");
    const changed = await app.call("/v1/account/profile", {
      method: "PATCH",
      token: lena.body.token,
      body: { displayName: "  Lena  Sommer " },
    });
    expect(changed.body.account.displayName).toBe("Lena Sommer");
    expect((await app.call("/v1/account/me", { token: lena.body.token })).body.account.displayName).toBe(
      "Lena Sommer",
    );
  });
});

describe("Einladungsseite", () => {
  it("bietet iPhone- und Android-Link mit Server und Code", async () => {
    const response = await handle(new Request(`${base}/i/ABCDEFGHJK`), env, fakeDeps([], NOW));
    const html = await response.text();
    expect(response.status).toBe(200);
    expect(html).toContain(
      `coach://account?worker=${encodeURIComponent(base)}&amp;invite=ABCDEFGHJK`.replace("&amp;", "&"),
    );
    expect(html).toContain("ironludi://account?");
    expect((await handle(new Request(`${base}/i/kurz`), env, fakeDeps([], NOW))).status).toBe(404);
  });
});
