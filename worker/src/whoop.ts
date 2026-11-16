/**
 * WHOOP-Anbindung (offizielle API v2, OAuth 2.0): Der Worker hält das Client-Secret und tauscht nur Codes und
 * Refresh-Tokens; die App ruft die Daten danach selbst bei WHOOP ab (wie bei Garmin direkt vom Gerät).
 * Quelle: https://developer.whoop.com/docs/developing/oauth und die OpenAPI-Beschreibung
 * https://api.prod.whoop.com/developer/doc/openapi.json (Stand 14.11.2026).
 *
 * POST /v1/whoop/authorize – Anmelde-Adresse bei WHOOP (mit Zufalls-`state`, den die App prüft)
 * GET  /w/whoop            – Rückkehr von WHOOP (im Developer-Dashboard als Redirect-URL eintragen), öffnet die App
 * POST /v1/whoop/token     – { grant_type: "authorization_code", code } bzw. { grant_type: "refresh_token",
 *                             refresh_token } → Antwort von WHOOP (access_token, expires_in, refresh_token, scope)
 */

import type { Deps, Env } from "./types";

export const WHOOP_AUTHORIZE_URL = "https://api.prod.whoop.com/oauth/oauth2/auth";
export const WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
/** `offline` liefert das Refresh-Token; ohne es müsste man sich stündlich neu anmelden. */
export const WHOOP_SCOPES = [
  "offline",
  "read:recovery",
  "read:cycles",
  "read:workout",
  "read:sleep",
  "read:profile",
  "read:body_measurement",
];
export const WHOOP_CALLBACK_PATH = "/w/whoop";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

export function whoopConfigured(env: Env): boolean {
  return Boolean(env.WHOOP_CLIENT_ID && env.WHOOP_CLIENT_SECRET);
}

/** Zufälliger `state` (WHOOP verlangt mindestens acht Zeichen). */
export function newState(): string {
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function redirectUri(origin: string): string {
  return `${origin}${WHOOP_CALLBACK_PATH}`;
}

const escapeHtml = (text: string) => text.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

/** Rückkehr von WHOOP: Code und `state` unverändert an die App weiterreichen (die App tauscht den Code). */
export function whoopCallbackPage(pathname: string, search: URLSearchParams): Response | null {
  if (pathname !== WHOOP_CALLBACK_PATH) return null;
  const params = new URLSearchParams();
  for (const key of ["code", "state", "error", "error_description"]) {
    const value = search.get(key);
    if (value) params.set(key, value.slice(0, 2_000));
  }
  const target = `coach://whoop?${params.toString()}`;
  const failed = params.has("error");
  const title = failed ? "WHOOP nicht verbunden" : "WHOOP verbunden";
  const hint = failed
    ? "WHOOP hat die Anmeldung abgebrochen. Du kannst es in der App unter Einstellungen › WHOOP erneut versuchen."
    : "Öffnet IronLudi und schließt die Verbindung ab.";
  const html = `<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<meta http-equiv="refresh" content="0;url=${escapeHtml(target)}"></head>
<body style="font-family:-apple-system,system-ui,sans-serif;padding:24px;line-height:1.5">
<h1 style="font-size:22px">${title}</h1><p>${hint}</p>
<p><a href="${escapeHtml(target)}" style="font-size:18px">In IronLudi öffnen</a></p></body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "x-robots-tag": "noindex",
      "referrer-policy": "no-referrer",
    },
  });
}

/** Geschützte Endpunkte (`/v1/whoop/…`); die Anmeldung prüft index.ts vorher. */
export async function handleWhoop(request: Request, env: Env, deps: Deps): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/v1/whoop/")) return null;
  if (request.method !== "POST") return json(405, { error: "Nur POST" });
  if (!whoopConfigured(env))
    return json(503, {
      error: "WHOOP ist im Worker nicht eingerichtet (WHOOP_CLIENT_ID und WHOOP_CLIENT_SECRET fehlen).",
      code: "whoop_not_configured",
    });
  const clientID = env.WHOOP_CLIENT_ID as string;
  const secret = env.WHOOP_CLIENT_SECRET as string;

  if (url.pathname === "/v1/whoop/authorize") {
    const state = newState();
    const target = new URL(WHOOP_AUTHORIZE_URL);
    target.searchParams.set("response_type", "code");
    target.searchParams.set("client_id", clientID);
    target.searchParams.set("redirect_uri", redirectUri(url.origin));
    target.searchParams.set("scope", WHOOP_SCOPES.join(" "));
    target.searchParams.set("state", state);
    return json(200, { url: target.toString(), state });
  }

  if (url.pathname !== "/v1/whoop/token") return json(404, { error: "Nicht gefunden" });
  let body: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(await request.text());
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
      throw new Error("kein Objekt");
    body = parsed as Record<string, unknown>;
  } catch {
    return json(400, { error: "Ungültiges JSON" });
  }
  const form = new URLSearchParams({ client_id: clientID, client_secret: secret });
  if (body.grant_type === "authorization_code" && typeof body.code === "string" && body.code.length > 0) {
    form.set("grant_type", "authorization_code");
    form.set("code", body.code);
    form.set("redirect_uri", redirectUri(url.origin));
  } else if (
    body.grant_type === "refresh_token" &&
    typeof body.refresh_token === "string" &&
    body.refresh_token.length > 0
  ) {
    form.set("grant_type", "refresh_token");
    form.set("refresh_token", body.refresh_token);
    form.set("scope", "offline");
  } else {
    return json(400, { error: "grant_type mit code bzw. refresh_token fehlt" });
  }

  let response: Response;
  try {
    response = await deps.fetch(WHOOP_TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
      body: form.toString(),
    });
  } catch {
    return json(502, { error: "WHOOP nicht erreichbar", code: "whoop_unreachable" });
  }
  const text = await response.text();
  let payload: Record<string, unknown> = {};
  try {
    const parsed: unknown = JSON.parse(text);
    if (typeof parsed === "object" && parsed !== null) payload = parsed as Record<string, unknown>;
  } catch {
    // Kein JSON: nur den Status melden.
  }
  if (!response.ok) {
    // 400/401 von WHOOP: Code abgelaufen oder Refresh-Token schon verbraucht – neu verbinden.
    const invalid = response.status === 400 || response.status === 401;
    deps.log(`whoop token ${response.status}`);
    return json(invalid ? 400 : 502, {
      error: invalid
        ? "WHOOP hat die Anmeldung abgelehnt. Bitte WHOOP in den Einstellungen neu verbinden."
        : `WHOOP antwortet mit Fehler ${response.status}.`,
      code: invalid ? "whoop_invalid_grant" : "whoop_error",
    });
  }
  const { access_token, expires_in, refresh_token, scope, token_type } = payload;
  if (typeof access_token !== "string")
    return json(502, { error: "Antwort von WHOOP unvollständig", code: "whoop_error" });
  return json(200, { access_token, expires_in, refresh_token, scope, token_type });
}
