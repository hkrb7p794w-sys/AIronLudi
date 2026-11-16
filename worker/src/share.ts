/**
 * Mahlzeiten teilen: Die App legt eine Mahlzeit (Titel, Positionen mit Mengen und Nährwerten je 100 g) unter einem
 * zufälligen Code ab; wer denselben App-Zugang hat, holt sie mit dem Code und übernimmt sie in sein Tagebuch.
 * Gespeichert wird nur die Mahlzeit – kein Name, keine Gesundheitsdaten, kein Datum. Einträge verfallen nach 7 Tagen
 * und lassen sich vorher zurückziehen.
 *
 * POST   /v1/share/meal        – Mahlzeit ablegen, Antwort {code, expiresAt}
 * GET    /v1/share/meal/<code> – Mahlzeit holen
 * DELETE /v1/share/meal/<code> – zurückziehen
 * GET    /m/<code>             – Seite ohne Anmeldung und ohne Inhalt, öffnet coach://meal/<code> (für Messenger)
 *
 * Alle /v1-Aufrufe mit Haupt- oder Gast-Token (Prüfung in index.ts). Zurückziehen darf nur, wer geteilt hat
 * (Mahlzeiten von vor dieser Regel ohne Besitzer: jede angemeldete Person, sie verfallen ohnehin nach 7 Tagen).
 */
import { nutrientLimit, readLimited } from "./tasks-util";

export interface ShareStore {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
}

export const SHARE_TTL_SECONDS = 7 * 24 * 3600;
const MAX_BYTES = 24_000;
const MAX_ITEMS = 40;
const CODE = /^[a-z0-9]{10}$/;
const ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789";
const COOK_TTL_SECONDS = 90 * 24 * 3600;
const COOK_MAX_BYTES = 2_000;
const DIETS = new Set(["alles", "pescetarisch", "vegetarisch", "vegan"]);

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

/** Zufälliger Code aus 10 Zeichen (32er-Alphabet ohne Verwechsler, rund 50 Bit). */
export function newCode(
  random: (bytes: Uint8Array) => Uint8Array = (b) => crypto.getRandomValues(b),
): string {
  const bytes = random(new Uint8Array(10));
  return [...bytes].map((byte) => ALPHABET[byte % ALPHABET.length]).join("");
}

function finite(value: unknown, max: number): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= max ? value : null;
}

/** Nur bekannte Felder, begrenzte Längen und Zahlen – was die App nicht kennt, fällt weg. */
export function sanitizeMeal(body: unknown): Record<string, unknown> | string {
  const value = (typeof body === "object" && body !== null ? body : {}) as Record<string, unknown>;
  const title = typeof value.title === "string" ? value.title.trim().slice(0, 80) : "";
  const rawItems = Array.isArray(value.items) ? value.items.slice(0, MAX_ITEMS) : [];
  const items = rawItems.flatMap((raw) => {
    const item = (typeof raw === "object" && raw !== null ? raw : {}) as Record<string, unknown>;
    const name = typeof item.name === "string" ? item.name.trim().slice(0, 80) : "";
    const grams = finite(item.grams, 10_000);
    if (!name || grams === null || grams === 0) return [];
    const nutrients = (
      typeof item.per100g === "object" && item.per100g !== null ? item.per100g : {}
    ) as Record<string, unknown>;
    const per100g: Record<string, number> = {};
    for (const [key, amount] of Object.entries(nutrients).slice(0, 30)) {
      const number = finite(amount, nutrientLimit(key));
      if (/^[a-z0-9_]{2,20}$/.test(key) && number !== null) per100g[key] = number;
    }
    return [
      {
        name,
        grams,
        isDrink: item.isDrink === true,
        source: typeof item.source === "string" ? item.source.slice(0, 30) : "Eigene Angabe",
        per100g,
        ...(typeof item.amountText === "string" ? { amountText: item.amountText.slice(0, 60) } : {}),
      },
    ];
  });
  if (items.length === 0) return "Mahlzeit ohne Positionen";
  return {
    title:
      title ||
      items
        .map((item) => item.name)
        .join(", ")
        .slice(0, 80),
    items,
  };
}

/**
 * Freigabe für gemeinsame Rezepte: nur Anzeigename, Tagesziele, Ernährungsweise, Allergene und Abneigungen. Was nicht
 * in dieser Liste steht, wird nicht gespeichert. Fehlende Felder bedeuten: nicht freigegeben.
 */
export function sanitizeCookShare(body: unknown): Record<string, unknown> | string {
  const value = (typeof body === "object" && body !== null ? body : {}) as Record<string, unknown>;
  const name = typeof value.name === "string" ? value.name.trim().slice(0, 30) : "";
  if (!name) return "Name fehlt";
  const result: Record<string, unknown> = { name };
  const kcal = finite(value.kcal, 8_000);
  if (kcal !== null && kcal >= 800) {
    result.kcal = kcal;
    for (const key of ["protein", "carbs", "fat"]) {
      const amount = finite(value[key], 1_000);
      if (amount !== null) result[key] = amount;
    }
  }
  if (typeof value.diet === "string" && DIETS.has(value.diet)) result.diet = value.diet;
  result.allergens = (Array.isArray(value.allergens) ? value.allergens : [])
    .filter((item): item is string => typeof item === "string" && /^[a-z_]{2,20}$/.test(item))
    .slice(0, 12);
  result.dislikes = typeof value.dislikes === "string" ? value.dislikes.trim().slice(0, 200) : "";
  return result;
}

/** Bearbeitet /v1/share/cook…: nur wer freigegeben hat, ändert oder zieht zurück. */
async function handleCookShare(
  request: Request,
  store: ShareStore,
  now: Date,
  caller: string,
  code: () => string,
  id: string | undefined,
): Promise<Response> {
  const expiresAt = new Date(now.getTime() + COOK_TTL_SECONDS * 1000).toISOString();
  const read = async (): Promise<Record<string, unknown> | Response> => {
    const raw = await readLimited(request, COOK_MAX_BYTES);
    if (raw === null) return json(413, { error: "Freigabe zu groß" });
    try {
      const share = sanitizeCookShare(JSON.parse(raw));
      return typeof share === "string" ? json(400, { error: share }) : share;
    } catch {
      return json(400, { error: "Ungültiges JSON" });
    }
  };
  const save = (shareCode: string, share: Record<string, unknown>) =>
    store.put(`cook:${shareCode}`, JSON.stringify({ ...share, expiresAt, owner: caller }), {
      expirationTtl: COOK_TTL_SECONDS,
    });

  if (id === undefined) {
    if (request.method !== "POST") return json(405, { error: "Nur POST" });
    const share = await read();
    if (share instanceof Response) return share;
    const shareCode = code();
    await save(shareCode, share);
    return json(200, { code: shareCode, expiresAt });
  }
  if (!CODE.test(id)) return json(400, { error: "Ungültiger Code" });
  if (!["GET", "PUT", "DELETE"].includes(request.method))
    return json(405, { error: "Nur GET, PUT oder DELETE" });
  const stored = await store.get(`cook:${id}`);
  if (!stored) {
    return request.method === "DELETE"
      ? json(200, { ok: true })
      : json(404, { error: "Freigabe unbekannt oder zurückgezogen" });
  }
  const { owner, ...share } = JSON.parse(stored) as Record<string, unknown>;
  if (request.method === "GET") return json(200, share);
  if (owner !== caller) return json(403, { error: "Nur wer freigegeben hat, kann das ändern" });
  if (request.method === "DELETE") {
    await store.delete(`cook:${id}`);
    return json(200, { ok: true });
  }
  const updated = await read();
  if (updated instanceof Response) return updated;
  await save(id, updated);
  return json(200, { code: id, expiresAt });
}

/** Bearbeitet /v1/share/meal… und /v1/share/cook…; `null`, wenn der Pfad nicht passt. */
export async function handleShare(
  request: Request,
  store: ShareStore | undefined,
  now: Date,
  caller = "owner",
  code: () => string = () => newCode(),
): Promise<Response | null> {
  const { pathname } = new URL(request.url);
  const cook = /^\/v1\/share\/cook(?:\/([^/]+))?$/.exec(pathname);
  if (cook) {
    if (!store) return json(503, { error: "Teilen nicht eingerichtet (KV fehlt)" });
    return handleCookShare(request, store, now, caller, code, cook[1]);
  }
  const match = /^\/v1\/share\/meal(?:\/([^/]+))?$/.exec(pathname);
  if (!match) return null;
  if (!store) return json(503, { error: "Teilen nicht eingerichtet (KV fehlt)" });
  const [, id] = match;

  if (id === undefined) {
    if (request.method !== "POST") return json(405, { error: "Nur POST" });
    const raw = await readLimited(request, MAX_BYTES);
    if (raw === null) return json(413, { error: "Mahlzeit zu groß" });
    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      return json(400, { error: "Ungültiges JSON" });
    }
    const meal = sanitizeMeal(body);
    if (typeof meal === "string") return json(400, { error: meal });
    const shareCode = code();
    const expiresAt = new Date(now.getTime() + SHARE_TTL_SECONDS * 1000).toISOString();
    await store.put(
      `share:${shareCode}`,
      JSON.stringify({ ...meal, sharedAt: now.toISOString(), expiresAt, owner: caller }),
      {
        expirationTtl: SHARE_TTL_SECONDS,
      },
    );
    return json(200, { code: shareCode, expiresAt });
  }

  if (!CODE.test(id)) return json(400, { error: "Ungültiger Code" });
  if (request.method !== "GET" && request.method !== "DELETE")
    return json(405, { error: "Nur GET oder DELETE" });
  const stored = await store.get(`share:${id}`);
  if (!stored) {
    return request.method === "DELETE"
      ? json(200, { ok: true })
      : json(404, { error: "Code unbekannt oder abgelaufen" });
  }
  const { owner, ...meal } = JSON.parse(stored) as Record<string, unknown>;
  if (request.method === "DELETE") {
    if (owner !== undefined && owner !== caller)
      return json(403, { error: "Nur wer geteilt hat, kann zurückziehen" });
    await store.delete(`share:${id}`);
    return json(200, { ok: true });
  }
  return new Response(JSON.stringify(meal), {
    status: 200,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function redirectPage(title: string, target: string, hint: string): Response {
  const html = `<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>${title}</title>
<meta http-equiv="refresh" content="0;url=${target}"></head>
<body style="font-family:-apple-system,system-ui,sans-serif;padding:24px;line-height:1.5">
<h1 style="font-size:22px">${title}</h1><p>${hint}</p>
<p><a href="${target}" style="font-size:18px">In IronLudi öffnen</a></p></body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "x-robots-tag": "noindex",
    },
  });
}

/** Öffentliche Weiterleitungsseite ohne Inhalt der Mahlzeit (Messenger verlinken nur https). */
export function sharePage(pathname: string): Response | null {
  if (pathname === "/k/einladen") {
    return redirectPage(
      "Gemeinsam kochen",
      "coach://open/cookShare",
      "Öffnet IronLudi. Dort entscheidest du selbst, welche Angaben du für gemeinsame Rezepte freigibst.",
    );
  }
  const cook = /^\/k\/([a-z0-9]{10})$/.exec(pathname);
  if (cook) {
    return redirectPage(
      "Freigabe für gemeinsame Rezepte",
      `coach://cook/${cook[1]}`,
      `Öffnet IronLudi. Falls nicht: In der App unter Rezeptideen › Gemeinsam kochen den Code <strong>${cook[1]}</strong> eingeben.`,
    );
  }
  const match = /^\/m\/([a-z0-9]{10})$/.exec(pathname);
  if (!match) return null;
  const target = `coach://meal/${match[1]}`;
  const html = `<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Geteilte Mahlzeit</title>
<meta http-equiv="refresh" content="0;url=${target}"></head>
<body style="font-family:-apple-system,system-ui,sans-serif;padding:24px;line-height:1.5">
<h1 style="font-size:22px">Geteilte Mahlzeit</h1>
<p>Öffnet IronLudi. Falls nicht: App öffnen › Ernährung › „Geteilte Mahlzeit öffnen“ und den Code
<strong>${match[1]}</strong> eingeben.</p>
<p><a href="${target}" style="font-size:18px">In IronLudi öffnen</a></p></body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "x-robots-tag": "noindex",
    },
  });
}
