/**
 * Private SideStore-Quelle: Das Repo ist privat, GitHub-Release-Dateien sind ohne Anmeldung nicht
 * ladbar. Der iOS-Build legt deshalb IPA, Icon und Versionsangaben in Workers KV ab (Namespace
 * „coach-releases“), und der Worker liefert sie unter einem geheimen Pfad aus:
 *
 * GET /sidestore/<key>/source.json – SideStore-Quelle (AltStore-Format, ohne Berechtigungsprüfung)
 * GET /sidestore/<key>/Coach.ipa   – aktuelle App
 * GET /sidestore/<key>/icon.png    – App-Icon
 *
 * <key> = die ersten 32 Hex-Zeichen von SHA-256("sidestore:" + COACH_APP_TOKEN). Die App zeigt den
 * fertigen Link in den Einstellungen; ohne Token gibt es keinen gültigen Pfad.
 */

export interface ReleaseInfo {
  version: string;
  buildVersion: string;
  date: string;
  notes: string;
  size: number;
}

export interface ReleaseStore {
  get(key: string, type: "json"): Promise<unknown>;
  get(key: string, type: "stream"): Promise<ReadableStream | null>;
}

export const BUNDLE_ID = "io.github.hkrb7p794w.coach";

export async function sidestoreKey(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`sidestore:${token}`));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 32);
}

function isReleaseInfo(value: unknown): value is ReleaseInfo {
  const info = value as Partial<ReleaseInfo> | null;
  return (
    typeof info?.version === "string" &&
    typeof info.buildVersion === "string" &&
    typeof info.date === "string" &&
    typeof info.size === "number"
  );
}

export function sourceJSON(base: string, info: ReleaseInfo): unknown {
  const icon = `${base}/icon.png`;
  return {
    name: "AIronLudi (privat)",
    identifier: `${BUNDLE_ID}.source`,
    sourceURL: `${base}/source.json`,
    iconURL: icon,
    apps: [
      {
        name: "AIronLudi",
        bundleIdentifier: BUNDLE_ID,
        developerName: "Alex",
        subtitle: "Triathlon, Ernährung, Gym",
        localizedDescription:
          "Persönliche Coaching-App: Garmin-Werte, Tagesempfehlung, Plan, Ernährung und Gym.",
        iconURL: icon,
        tintColor: "1E4FA3",
        category: "utilities",
        versions: [
          {
            version: info.version,
            buildVersion: info.buildVersion,
            date: info.date,
            localizedDescription: (info.notes ?? "").slice(0, 2000),
            downloadURL: `${base}/Coach.ipa`,
            size: info.size,
            minOSVersion: "18.0",
          },
        ],
      },
    ],
    news: [],
  };
}

/** Antwort für /sidestore/…, oder `null`, wenn der Pfad nicht dazugehört. */
export async function handleSideStore(
  request: Request,
  token: string | undefined,
  store: ReleaseStore | undefined,
): Promise<Response | null> {
  const url = new URL(request.url);
  const match = /^\/sidestore\/([0-9a-f]{32})\/(source\.json|Coach\.ipa|icon\.png)$/.exec(url.pathname);
  if (!url.pathname.startsWith("/sidestore/")) return null;
  const notFound = new Response("Nicht gefunden", { status: 404 });
  if (request.method !== "GET" || !match || !token || !store) return notFound;
  const [, key, file] = match;
  // Gleiche Laufzeit für jeden falschen Schlüssel: Vergleich über den vollen Hash.
  const expected = await sidestoreKey(token);
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ (key?.charCodeAt(i) ?? 0);
  if (diff !== 0) return notFound;

  if (file === "source.json") {
    const info = await store.get("release.json", "json");
    if (!isReleaseInfo(info)) return new Response("Noch keine Version hochgeladen", { status: 503 });
    const base = `${url.origin}/sidestore/${key}`;
    return new Response(JSON.stringify(sourceJSON(base, info), null, 2), {
      headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
    });
  }
  const stream = await store.get(file === "Coach.ipa" ? "Coach.ipa" : "icon.png", "stream");
  if (!stream) return notFound;
  return new Response(stream, {
    headers: {
      "content-type": file === "Coach.ipa" ? "application/octet-stream" : "image/png",
      "cache-control": "no-store",
    },
  });
}
