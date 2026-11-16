import { describe, expect, it } from "vitest";
import { authenticate, guestToken, newGuestID } from "../src/auth";
import { handle } from "../src/index";
import { type ReleaseStore, sidestoreKey } from "../src/sidestore";
import { env, fakeDeps } from "./helpers";

const master = env.COACH_APP_TOKEN ?? "";

describe("Anmeldung", () => {
  it("erkennt Haupt- und Gast-Token, lehnt Gefälschtes und Gesperrtes ab", async () => {
    expect(await authenticate(`Bearer ${master}`, env)).toEqual({ kind: "owner" });
    const guest = await guestToken(master, "abcdefghijk2");
    expect(guest).not.toContain(master);
    expect(await authenticate(`Bearer ${guest}`, env)).toEqual({ kind: "guest", id: "abcdefghijk2" });
    // Andere ID mit fremder Signatur, Signatur mit anderem Haupt-Token, kaputte Formate.
    const forged = guest.replace("abcdefghijk2", "abcdefghijk3");
    expect(await authenticate(`Bearer ${forged}`, env)).toBeNull();
    expect(await authenticate(`Bearer ${await guestToken("anderes", "abcdefghijk2")}`, env)).toBeNull();
    expect(await authenticate("Bearer g1.", env)).toBeNull();
    expect(await authenticate("Bearer g1.ABC.def", env)).toBeNull();
    expect(await authenticate("", env)).toBeNull();
    expect(await authenticate(`Bearer ${guest}`, { ...env, REVOKED_GUESTS: "x, abcdefghijk2" })).toBeNull();
    expect(await authenticate(`Bearer ${guest}`, { ...env, COACH_APP_TOKEN: undefined })).toBeNull();
  });

  it("Gast-IDs sind zufällig und gültig", () => {
    const id = newGuestID();
    expect(id).toMatch(/^[a-z0-9]{12}$/);
    expect(newGuestID()).not.toBe(id);
  });

  it("nur das Haupt-Token stellt Einladungen aus", async () => {
    const invite = (token: string) =>
      handle(
        new Request("https://x/v1/invite", { method: "POST", headers: { authorization: `Bearer ${token}` } }),
        env,
        fakeDeps([]),
      );
    const response = await invite(master);
    expect(response.status).toBe(200);
    const { token, id } = (await response.json()) as { token: string; id: string };
    expect(token.startsWith(`g1.${id}.`)).toBe(true);
    expect(await authenticate(`Bearer ${token}`, env)).toEqual({ kind: "guest", id });
    expect((await invite(token)).status).toBe(403);
    expect((await invite("falsch")).status).toBe(401);
  });

  it("Gast-Token öffnet die KI, aber nicht die private SideStore-Quelle", async () => {
    const guest = await guestToken(master, "abcdefghijk2");
    const ping = await handle(
      new Request("https://x/v1/ai/generate", {
        method: "POST",
        headers: { authorization: `Bearer ${guest}` },
        body: JSON.stringify({ task: "unbekannt" }),
      }),
      env,
      fakeDeps([]),
    );
    // 400 statt 401: angemeldet, nur die Aufgabe gibt es nicht.
    expect(ping.status).toBe(400);
    const releases = {
      get: async (key: string) =>
        key === "release.json" ? { version: "1", buildVersion: "1", date: "x", size: 1 } : null,
    } as unknown as ReleaseStore;
    const withReleases = { ...env, RELEASES: releases as unknown as KVNamespace };
    const source = (key: string) =>
      handle(new Request(`https://x/sidestore/${key}/source.json`), withReleases, fakeDeps([]));
    expect((await source(await sidestoreKey(guest))).status).toBe(404);
    expect((await source(await sidestoreKey(master))).status).toBe(200);
  });
});
