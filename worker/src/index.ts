/**
 * Cloudflare Worker „coach-ai“: nimmt Aufgaben der Coach-App entgegen und reicht sie an Gemini bzw.
 * Groq weiter. Die KI-Keys liegen nur hier (Worker-Secrets), nie in der App.
 *
 * GET  /sidestore/<key>/… – private SideStore-Quelle (siehe sidestore.ts)
 * GET  /android/<key>/…  – private Download-Seite der Android-App (siehe android.ts)
 * GET  /v1/app/android   – neueste Android-Version für den Update-Hinweis (siehe android.ts), mit Anmeldung
 * GET  /v1/health        – ohne Anmeldung, zeigt Version und welche Anbieter konfiguriert sind
 * /v1/league/…          – Rangliste (siehe league.ts), Authorization: Bearer <COACH_APP_TOKEN>
 * POST /v1/ai/generate   – Authorization: Bearer <COACH_APP_TOKEN> oder Gast-Token (siehe auth.ts)
 * POST /v1/invite        – nur Haupt-Token: Gast-Token für eine Einladung
 * GET  /v1/usage         – eigene KI-Nutzung heute (mit Limit) und letzte Tage (siehe usage.ts)
 * GET  /v1/usage/all     – nur Haupt-Token: Nutzung und geschätzte Kosten je Person
 * /v1/game/…            – Rangliste und Challenges unter Freunden (siehe game.ts), nur mit Sitzung
 * /v1/social/…          – Freunde und Feed zwischen Konten (siehe social.ts), nur mit Sitzung
 * /v1/whoop/…          – WHOOP-Anmeldung: Code bzw. Refresh-Token tauschen (siehe whoop.ts); GET /w/whoop ohne
 *                         Anmeldung leitet nach der Freigabe bei WHOOP in die App zurück
 * /v1/maps/…            – Rundwege (openrouteservice) und Kartenkacheln (MapTiler) mit Schlüssel im Worker (siehe
 *                         maps.ts), mit Anmeldung
 * /v1/account/…         – Konten: Registrieren mit Einladung, Anmelden, Sitzungen (siehe accounts.ts). Überall, wo ein
 *                         Gast-Token gilt, gilt auch das Sitzungs-Token eines Kontos.
 *      { "task": "ping", "input": { … }, "images": [{ "mimeType": "image/jpeg", "data": "<base64>" }] }
 */

import { handleAccount, invitePage, isSessionToken } from "./accounts";
import { AllProvidersFailed, generate, parseJsonOutput } from "./ai";
import { androidUpdateInfo, handleAndroid } from "./android";
import { authenticate, bearerToken, guestToken, newGuestID, principalKey, tokensMatch } from "./auth";
import type { SqlDatabase } from "./db";
import { handleGame } from "./game";
import { handleLeague, type LeagueStore } from "./league";
import { type CounterStore, handleMaps, type MapsCache, mapsInfo } from "./maps";
import { listPriceUsd, parsePreference, providerInfo } from "./providers";
import { handleShare, type ShareStore, sharePage } from "./share";
import { handleSideStore } from "./sidestore";
import { handleSocial } from "./social";
import { findTask } from "./tasks";
import { readLimited } from "./tasks-util";
import { type Deps, defaultDeps, type Env, type ImageInput } from "./types";
import {
  checkQuota,
  nextReset,
  ownerOverview,
  ownSummary,
  quotaMessage,
  recordUsage,
  type UsageStore,
} from "./usage";
import { handleWhoop, whoopCallbackPage, whoopConfigured } from "./whoop";

export const VERSION = "0.4.0";
export const MAX_BODY_BYTES = 8 * 1024 * 1024;
export const MAX_IMAGES = 4;
/** Die App wartet 120 s; vorher soll eine verständliche Antwort kommen statt eines Abbruchs. */
export const AI_DEADLINE_MS = 105_000;
const IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/heic", "image/webp"]);

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function parseImages(value: unknown): ImageInput[] | string {
  if (value === undefined) return [];
  if (!Array.isArray(value)) return "images muss eine Liste sein";
  if (value.length > MAX_IMAGES) return `höchstens ${MAX_IMAGES} Bilder`;
  const images: ImageInput[] = [];
  for (const item of value) {
    const { mimeType, data } = (item ?? {}) as Record<string, unknown>;
    if (typeof mimeType !== "string" || !IMAGE_TYPES.has(mimeType)) return "ungültiger Bildtyp";
    if (typeof data !== "string" || data.length === 0) return "Bilddaten fehlen";
    images.push({ mimeType, data });
  }
  return images;
}

export { tokensMatch };

/** Cloudflare-Cache, falls vorhanden (in Tests und lokal ohne Cache). */
function defaultCache(): MapsCache | undefined {
  const storage = (globalThis as { caches?: { default?: MapsCache } }).caches;
  return storage?.default;
}

export async function handle(
  request: Request,
  env: Env,
  deps: Deps = defaultDeps,
  cache?: MapsCache,
): Promise<Response> {
  const { pathname } = new URL(request.url);

  const sidestore = await handleSideStore(request, env.COACH_APP_TOKEN, env.RELEASES);
  if (sidestore) return sidestore;
  const android = await handleAndroid(request, env.COACH_APP_TOKEN, env.RELEASES, {
    token: env.RELEASES_READ_TOKEN,
    fetch: deps.fetch,
  });
  if (android) return android;

  if (request.method === "GET" && pathname === "/v1/health") {
    return json(200, {
      status: "ok",
      version: VERSION,
      providers: {
        gemini: Boolean(env.GEMINI_API_KEY),
        cerebras: Boolean(env.CEREBRAS_API_KEY),
        groq: Boolean(env.GROQ_API_KEY),
        mistral: Boolean(env.MISTRAL_API_KEY),
        github: Boolean(env.GH_MODELS_TOKEN),
      },
      providerList: providerInfo(env),
      configured: Boolean(env.COACH_APP_TOKEN),
      whoop: whoopConfigured(env),
      maps: mapsInfo(env),
    });
  }

  if (request.method === "GET") {
    const url = new URL(request.url);
    const page =
      sharePage(pathname) ??
      invitePage(pathname, url.origin) ??
      whoopCallbackPage(pathname, url.searchParams);
    if (page) return page;
  }

  if (pathname.startsWith("/v1/whoop/")) {
    if (!env.COACH_APP_TOKEN)
      return json(503, { error: "Worker ist nicht konfiguriert (COACH_APP_TOKEN fehlt)" });
    // Wer die App nutzen darf (Haupt-, Gast- oder Sitzungs-Token), darf auch WHOOP verbinden.
    const principal = await authenticate(request.headers.get("authorization") ?? "", env, deps.now());
    if (!principal) return json(401, { error: "Nicht autorisiert", code: "unauthorized" });
    return (await handleWhoop(request, env, deps)) ?? json(404, { error: "Nicht gefunden" });
  }

  if (pathname.startsWith("/v1/maps/")) {
    if (!env.COACH_APP_TOKEN)
      return json(503, { error: "Worker ist nicht konfiguriert (COACH_APP_TOKEN fehlt)" });
    const principal = await authenticate(request.headers.get("authorization") ?? "", env, deps.now());
    if (!principal) return json(401, { error: "Nicht autorisiert", code: "unauthorized" });
    return (
      (await handleMaps(request, {
        env,
        deps,
        principal: principalKey(principal),
        cache: cache ?? defaultCache(),
        counters: env.LEAGUE as unknown as CounterStore | undefined,
      })) ?? json(404, { error: "Nicht gefunden" })
    );
  }

  if (pathname === "/v1/app/android") {
    if (request.method !== "GET") return json(405, { error: "Nur GET" });
    if (!env.COACH_APP_TOKEN)
      return json(503, { error: "Worker ist nicht konfiguriert (COACH_APP_TOKEN fehlt)" });
    const principal = await authenticate(request.headers.get("authorization") ?? "", env, deps.now());
    if (!principal) return json(401, { error: "Nicht autorisiert", code: "unauthorized" });
    const info = await androidUpdateInfo(new URL(request.url).origin, env.COACH_APP_TOKEN, env.RELEASES);
    return info ? json(200, info) : json(404, { error: "Noch keine Android-Version hochgeladen" });
  }

  if (pathname.startsWith("/v1/account/")) {
    if (!env.COACH_APP_TOKEN)
      return json(503, { error: "Worker ist nicht konfiguriert (COACH_APP_TOKEN fehlt)" });
    const header = request.headers.get("authorization") ?? "";
    const token = bearerToken(header);
    const accountPrincipal = token ? await authenticate(header, env, deps.now()) : null;
    // Ein abgelaufenes Token darf Anmelden und Registrieren nicht verhindern; alles andere prüft accounts.ts.
    const open = /^\/v1\/account\/(login|register|recover)$/.test(pathname);
    if (token && !accountPrincipal && !open)
      return json(401, { error: "Nicht autorisiert", code: "unauthorized" });
    return (
      (await handleAccount(request, {
        db: env.DB as unknown as SqlDatabase | undefined,
        now: deps.now(),
        principal: accountPrincipal,
        sessionToken: isSessionToken(token) ? token : undefined,
      })) ?? json(404, { error: "Nicht gefunden" })
    );
  }

  if (pathname.startsWith("/v1/social/") || pathname.startsWith("/v1/game/")) {
    if (!env.COACH_APP_TOKEN)
      return json(503, { error: "Worker ist nicht konfiguriert (COACH_APP_TOKEN fehlt)" });
    const principal = await authenticate(request.headers.get("authorization") ?? "", env, deps.now());
    if (!principal) return json(401, { error: "Nicht autorisiert", code: "unauthorized" });
    const me = principal.kind === "account" ? { id: principal.id, username: principal.username } : null;
    return (
      (await handleSocial(request, env.DB as unknown as SqlDatabase | undefined, me, deps.now())) ??
      (await handleGame(request, env.DB as unknown as SqlDatabase | undefined, me, deps.now())) ??
      json(404, { error: "Nicht gefunden" })
    );
  }

  const isLeague = pathname.startsWith("/v1/league/");
  const isShare = pathname.startsWith("/v1/share/");
  const isInvite = pathname === "/v1/invite";
  const isUsage = pathname === "/v1/usage" || pathname === "/v1/usage/all";
  if (pathname !== "/v1/ai/generate" && !isLeague && !isShare && !isInvite && !isUsage)
    return json(404, { error: "Nicht gefunden" });
  if (isUsage && request.method !== "GET") return json(405, { error: "Nur GET" });
  if (!isLeague && !isShare && !isUsage && request.method !== "POST") return json(405, { error: "Nur POST" });

  if (!env.COACH_APP_TOKEN)
    return json(503, { error: "Worker ist nicht konfiguriert (COACH_APP_TOKEN fehlt)" });
  const principal = await authenticate(request.headers.get("authorization") ?? "", env, deps.now());
  if (!principal) return json(401, { error: "Nicht autorisiert" });

  if (isInvite) {
    // Nur wer den Worker betreibt, lädt ein; Gäste geben den Ranglisten-Code weiter.
    if (principal.kind !== "owner") return json(403, { error: "Nur mit dem Haupt-Token" });
    const id = newGuestID();
    return json(200, { id, token: await guestToken(env.COACH_APP_TOKEN, id) });
  }

  if (isUsage) {
    const usageStore = env.LEAGUE as unknown as UsageStore | undefined;
    if (pathname === "/v1/usage/all") {
      if (principal.kind !== "owner") return json(403, { error: "Nur mit dem Haupt-Token" });
      return json(200, await ownerOverview(usageStore, deps.now()));
    }
    return json(200, await ownSummary(env, usageStore, principal, deps.now()));
  }

  if (isShare) {
    const store = env.LEAGUE as unknown as ShareStore | undefined;
    return (
      (await handleShare(request, store, new Date(deps.now()), principalKey(principal))) ??
      json(404, { error: "Nicht gefunden" })
    );
  }

  if (isLeague) {
    const store = env.LEAGUE as unknown as LeagueStore | undefined;
    return (
      (await handleLeague(request, store, new Date(deps.now()), principalKey(principal))) ??
      json(404, { error: "Nicht gefunden" })
    );
  }

  const raw = await readLimited(request, MAX_BODY_BYTES);
  if (raw === null) return json(413, { error: "Anfrage zu groß" });

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
      throw new Error("kein Objekt");
    body = parsed as Record<string, unknown>;
  } catch {
    return json(400, { error: "Ungültiges JSON" });
  }

  const task = findTask(body.task);
  if (!task) return json(400, { error: "Unbekannte Aufgabe" });
  const input = body.input ?? {};
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    return json(400, { error: "input muss ein Objekt sein" });
  }
  const images = parseImages(body.images);
  if (typeof images === "string") return json(400, { error: images });
  if (images.length > 0 && !task.allowImages)
    return json(400, { error: "Diese Aufgabe nimmt keine Bilder an" });

  // Tageslimit je Person (Gäste); der Verbindungstest „ping“ zählt nicht.
  const usageStore = env.LEAGUE as unknown as UsageStore | undefined;
  const counted = body.task !== "ping";
  const quota = await checkQuota(env, counted ? usageStore : undefined, principal, deps.now());
  if (!quota.allowed) {
    return json(429, {
      error: quotaMessage(quota),
      code: "quota_exceeded",
      used: quota.used,
      limit: quota.limit,
      resetsAt: nextReset(deps.now()),
    });
  }

  const { system, prompt } = task.build(input as Record<string, unknown>, images.length);
  // Unbrauchbare Antworten (kein JSON, nichts belegt) gelten als Ausfall des Anbieters: Der nächste kommt dran.
  const accept = (text: string): unknown => {
    const output: unknown = task.json ? parseJsonOutput(text) : text;
    return task.ground
      ? task.ground(output, `${system ?? ""}\n${prompt}`, input as Record<string, unknown>)
      : output;
  };
  try {
    const result = await generate(
      {
        system,
        prompt,
        json: task.json,
        images,
        temperature: task.temperature,
        maxOutputTokens: task.maxOutputTokens,
        lowThinking: task.lowThinking,
        deadline: deps.now() + AI_DEADLINE_MS,
        task: String(body.task),
      },
      env,
      deps,
      parsePreference(body.provider),
      accept,
    );
    const priceUsd = listPriceUsd(result.provider, result.model, result.usage) ?? 0;
    if (usageStore && counted) {
      try {
        await recordUsage(usageStore, principal, deps.now(), String(body.task), result.provider, priceUsd);
      } catch (error) {
        // Zähler nie zur Fehlerquelle machen (z. B. KV-Schreibgrenze).
        deps.log(`[usage] Zählen fehlgeschlagen: ${String(error)}`);
      }
    }
    return json(200, {
      output: result.output,
      model: result.model,
      provider: result.provider,
      ...(quota.limit > 0 && counted && usageStore
        ? { quota: { used: quota.used + 1, limit: quota.limit } }
        : {}),
      ...(result.usage
        ? {
            usage: {
              ...result.usage,
              listPriceUsd: listPriceUsd(result.provider, result.model, result.usage),
            },
          }
        : {}),
    });
  } catch (error) {
    if (error instanceof AllProvidersFailed) {
      // Einzelheiten nur ins Protokoll: Antworttexte der Anbieter gehören nicht in die App.
      deps.log(`[worker] ${String(body.task)}: ${error.message}`);
      return json(502, {
        error:
          error.code === "ai_invalid" ? "KI-Antwort war nicht brauchbar" : "KI-Anbieter nicht erreichbar",
        code: error.code,
      });
    }
    deps.log(`[worker] Unerwarteter Fehler: ${String(error)}`);
    return json(500, { error: "Interner Fehler" });
  }
}

export default {
  fetch: (request, env) => handle(request, env),
} satisfies ExportedHandler<Env>;
