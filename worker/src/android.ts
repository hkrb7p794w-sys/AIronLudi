/**
 * Private Download-Seite der Android-App „IronLudi Gym“ (Gym-Logging, `android/` im Repo). Wie die SideStore-Quelle:
 * Die CI (`.github/workflows/android.yml`) legt APK und Versionsangaben in Workers KV ab (Namespace „coach-releases“),
 * der Worker liefert sie unter einem geheimen Pfad aus.
 *
 * GET /android/<key>/                   – Seite mit Version und Download-Knopf (zum Öffnen auf dem Handy); mit
 *                                         `#zugang=<Gast-Token>` zusätzlich „In der App verbinden“ (KI-Zugang)
 * GET /android/<key>/IronLudi-Gym.apk   – aktuelle App
 *
 * <key> = die ersten 32 Hex-Zeichen von SHA-256("android:" + COACH_APP_TOKEN). Die iPhone-App zeigt den fertigen Link
 * in den Einstellungen (nur mit Haupt-Token). Die Android-App selbst braucht weder Token noch Internet.
 */
import type { ReleaseStore } from "./sidestore";

export interface AndroidRelease {
  versionName: string;
  versionCode: number;
  date: string;
  size: number;
  notes?: string;
}

export const APK_NAME = "IronLudi-Gym.apk";

export async function androidKey(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`android:${token}`));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 32);
}

function isRelease(value: unknown): value is AndroidRelease {
  const info = value as Partial<AndroidRelease> | null;
  return (
    typeof info?.versionName === "string" &&
    typeof info.versionCode === "number" &&
    typeof info.date === "string" &&
    typeof info.size === "number"
  );
}

function escapeHTML(text: string): string {
  return text.replace(
    /[&<>"']/g,
    (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char] ?? char,
  );
}

export function downloadPage(info: AndroidRelease): string {
  const date = new Date(info.date);
  const day = Number.isNaN(date.getTime())
    ? info.date
    : date.toLocaleDateString("de-DE", {
        day: "numeric",
        month: "long",
        year: "numeric",
        timeZone: "Europe/Berlin",
      });
  const megabytes = (info.size / 1_048_576).toFixed(1).replace(".", ",");
  return `<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex">
<title>IronLudi Gym für Android</title>
<style>
:root{color-scheme:light dark;--bg:#f6f8f7;--fg:#13201c;--muted:#52615c;--accent:#1f6f5c;--card:#fff}
@media (prefers-color-scheme:dark){:root{--bg:#0f1513;--fg:#e4ece9;--muted:#9fb0aa;--accent:#7fd6bf;--card:#18211e}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,system-ui,Roboto,sans-serif}
main{max-width:560px;margin:0 auto;padding:24px 16px}
.card{background:var(--card);border-radius:16px;padding:20px;margin:16px 0}
a.button{display:block;text-align:center;background:var(--accent);color:var(--bg);text-decoration:none;
font-weight:600;padding:14px;border-radius:12px;font-size:18px}
small,.muted{color:var(--muted)} ol{padding-left:20px} li{margin:6px 0}
</style></head><body><main>
<h1>IronLudi Gym</h1>
<p class="muted">Gym-Logging für Android · Version ${escapeHTML(info.versionName)} vom ${escapeHTML(day)} · ${megabytes} MB</p>
<div class="card"><a class="button" href="${APK_NAME}" download>App herunterladen</a></div>
<div class="card"><strong>Installieren</strong><ol>
<li>„App herunterladen“ tippen und die Datei öffnen (Benachrichtigung oder „Downloads“).</li>
<li>Fragt Android nach „Unbekannte Apps installieren“: für den Browser bzw. „Dateien“ erlauben, zurück, „Installieren“.</li>
<li>Warnt Google Play Protect („App nicht geprüft“): „Weitere Details“ › „Trotzdem installieren“.</li>
</ol>
<strong>Aktualisieren</strong><p>Diese Seite wieder öffnen und die neue Version genauso installieren – die Trainings bleiben erhalten.</p></div>
<div class="card" id="connect" hidden><strong>2. KI verbinden</strong>
<p>Nach der Installation hier tippen – die App übernimmt deinen persönlichen Zugang für Foto- und Textauswertung.</p>
<a class="button" id="connect-link" href="#">In der App verbinden</a></div>
<p><small>Privater Link – bitte nicht öffentlich teilen.</small></p>
<script>
// Der Zugang steht im Anker (#zugang=…) und wird nie an den Server geschickt.
(function () {
  var match = /[#&]zugang=([^&]+)/.exec(location.hash);
  if (!match) return;
  var link = "ironludi://connect?worker=" + encodeURIComponent(location.origin) + "&token=" + match[1];
  document.getElementById("connect-link").setAttribute("href", link);
  document.getElementById("connect").hidden = false;
})();
</script>
</main></body></html>`;
}

/** Antwort für /android/…, oder `null`, wenn der Pfad nicht dazugehört. */
export async function handleAndroid(
  request: Request,
  token: string | undefined,
  store: ReleaseStore | undefined,
): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith("/android/")) return null;
  const notFound = new Response("Nicht gefunden", { status: 404 });
  const match = /^\/android\/([0-9a-f]{32})(\/|\/IronLudi-Gym\.apk)?$/.exec(url.pathname);
  if (request.method !== "GET" || !match || !token || !store) return notFound;
  const [, key, rest] = match;
  // Gleiche Laufzeit für jeden falschen Schlüssel: Vergleich über den vollen Hash.
  const expected = await androidKey(token);
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ (key?.charCodeAt(i) ?? 0);
  if (diff !== 0) return notFound;
  // Ohne Schrägstrich am Ende würde der relative Download-Link ins Leere zeigen.
  if (rest === undefined) return Response.redirect(`${url.origin}/android/${key}/`, 301);

  const info = await store.get("android.json", "json");
  if (!isRelease(info)) return new Response("Noch keine Android-Version hochgeladen", { status: 503 });
  if (rest === "/") {
    return new Response(downloadPage(info), {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
        "x-robots-tag": "noindex",
      },
    });
  }
  const stream = await store.get("android.apk", "stream");
  if (!stream) return notFound;
  return new Response(stream, {
    headers: {
      "content-type": "application/vnd.android.package-archive",
      "content-disposition": `attachment; filename="${APK_NAME}"`,
      "cache-control": "no-store",
    },
  });
}
