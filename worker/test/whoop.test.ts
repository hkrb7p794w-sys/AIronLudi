import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import type { Deps, Env } from "../src/types";
import { WHOOP_SCOPES, WHOOP_TOKEN_URL, whoopCallbackPage } from "../src/whoop";
import { env as baseEnv } from "./helpers";

const env: Env = { ...baseEnv, WHOOP_CLIENT_ID: "client-1", WHOOP_CLIENT_SECRET: "secret-1" };

/** fetch-Attrappe für den Token-Endpunkt (Formular statt JSON). */
function deps(
  respond: (body: URLSearchParams) => Response,
): Deps & { bodies: URLSearchParams[]; urls: string[] } {
  const bodies: URLSearchParams[] = [];
  const urls: string[] = [];
  return {
    bodies,
    urls,
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      urls.push(String(input));
      const body = new URLSearchParams(String(init?.body ?? ""));
      bodies.push(body);
      return respond(body);
    }) as typeof fetch,
    sleep: async () => {},
    now: () => 1_000_000,
    log: () => {},
  };
}

const post = (path: string, body?: unknown, token = "app-token-123") =>
  new Request(`https://w.example${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

describe("WHOOP", () => {
  it("Anmelde-Adresse mit allen Scopes, offline und Rücksprung zum Worker", async () => {
    const response = await handle(
      post("/v1/whoop/authorize"),
      env,
      deps(() => new Response("")),
    );
    expect(response.status).toBe(200);
    const { url, state } = (await response.json()) as { url: string; state: string };
    expect(state.length).toBeGreaterThanOrEqual(8);
    const target = new URL(url);
    expect(target.origin + target.pathname).toBe("https://api.prod.whoop.com/oauth/oauth2/auth");
    expect(target.searchParams.get("client_id")).toBe("client-1");
    expect(target.searchParams.get("redirect_uri")).toBe("https://w.example/w/whoop");
    expect(target.searchParams.get("scope")?.split(" ")).toEqual(WHOOP_SCOPES);
    expect(target.searchParams.get("state")).toBe(state);
    expect(url).not.toContain("secret-1");
  });

  it("Code tauschen: Secret nur im Worker, Antwort ohne Fremdfelder", async () => {
    const fake = deps(() =>
      Response.json({
        access_token: "a1",
        expires_in: 3600,
        refresh_token: "r1",
        scope: "offline",
        token_type: "bearer",
        extra: "x",
      }),
    );
    const response = await handle(
      post("/v1/whoop/token", { grant_type: "authorization_code", code: "c1" }),
      env,
      fake,
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      access_token: "a1",
      expires_in: 3600,
      refresh_token: "r1",
      scope: "offline",
      token_type: "bearer",
    });
    expect(fake.urls).toEqual([WHOOP_TOKEN_URL]);
    expect(Object.fromEntries(fake.bodies[0] ?? [])).toEqual({
      client_id: "client-1",
      client_secret: "secret-1",
      grant_type: "authorization_code",
      code: "c1",
      redirect_uri: "https://w.example/w/whoop",
    });
  });

  it("Refresh mit scope offline; abgelehntes Token heißt neu verbinden", async () => {
    const fake = deps((body) =>
      body.get("refresh_token") === "alt"
        ? new Response("{}", { status: 400 })
        : Response.json({ access_token: "a2", refresh_token: "r2", expires_in: 3600 }),
    );
    const ok = await handle(
      post("/v1/whoop/token", { grant_type: "refresh_token", refresh_token: "neu" }),
      env,
      fake,
    );
    expect(ok.status).toBe(200);
    expect(fake.bodies[0]?.get("scope")).toBe("offline");
    const rejected = await handle(
      post("/v1/whoop/token", { grant_type: "refresh_token", refresh_token: "alt" }),
      env,
      fake,
    );
    expect(rejected.status).toBe(400);
    expect(((await rejected.json()) as { code: string }).code).toBe("whoop_invalid_grant");
  });

  it("ohne Anmeldung, ohne Einrichtung und mit falschem Inhalt abgelehnt", async () => {
    const fake = deps(() => new Response(""));
    expect((await handle(post("/v1/whoop/authorize", undefined, "falsch"), env, fake)).status).toBe(401);
    const missing = await handle(post("/v1/whoop/authorize"), baseEnv, fake);
    expect(missing.status).toBe(503);
    expect(((await missing.json()) as { code: string }).code).toBe("whoop_not_configured");
    expect((await handle(post("/v1/whoop/token", { grant_type: "password" }), env, fake)).status).toBe(400);
    expect(fake.urls).toEqual([]);
  });

  it("Rücksprung-Seite reicht Code und state an die App weiter, maskiert HTML", async () => {
    const page = whoopCallbackPage(
      "/w/whoop",
      new URLSearchParams({ code: "c<1>", state: "abcdefgh", other: "x" }),
    );
    const html = await page?.text();
    expect(html).toContain("coach://whoop?code=c%3C1%3E&#38;state=abcdefgh");
    expect(html).not.toContain("other");
    const response = await handle(
      new Request("https://w.example/w/whoop?error=access_denied"),
      env,
      deps(() => new Response("")),
    );
    expect(await response.text()).toContain("WHOOP nicht verbunden");
    expect(whoopCallbackPage("/w/anders", new URLSearchParams())).toBeNull();
  });
});
