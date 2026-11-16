import { describe, expect, it } from "vitest";
import { androidKey, downloadPage } from "../src/android";
import { guestToken } from "../src/auth";
import { handle } from "../src/index";
import type { ReleaseStore } from "../src/sidestore";
import { env, fakeDeps } from "./helpers";

const info = { versionName: "1.0.12", versionCode: 12, date: "2026-11-02T16:00:00Z", size: 7_340_032 };

function store(values: Record<string, unknown>): ReleaseStore {
  return {
    get: (async (key: string, type: string) => {
      const value = values[key];
      if (value === undefined) return null;
      if (type === "stream") return new Response(value as string).body;
      return value;
    }) as ReleaseStore["get"],
  };
}

describe("android", () => {
  it("liefert Seite und APK nur unter dem geheimen Pfad", async () => {
    const key = await androidKey(env.COACH_APP_TOKEN ?? "");
    expect(key).toMatch(/^[0-9a-f]{32}$/);
    // Gleicher Wert wie in der iPhone-App (NetworkClientTests.androidDownloadMatchesWorker).
    expect(await androidKey("app-token-123")).toBe("3d5b0ebdcfa5865d774ee00e8f93d04d");
    const withKV = {
      ...env,
      RELEASES: store({ "android.json": info, "android.apk": "apk" }) as unknown as KVNamespace,
    };
    const base = `https://coach-ai.example.workers.dev/android/${key}`;

    const page = await handle(new Request(`${base}/`), withKV, fakeDeps([]));
    expect(page.status).toBe(200);
    const html = await page.text();
    expect(html).toContain("Version 1.0.12");
    expect(html).toContain('href="AIronLudi.apk"');
    expect(html).toContain("7,0 MB");
    // Verbinden nur über den Anker im Browser; die Seite selbst enthält kein Token.
    expect(html).toContain("ironludi://connect?worker=");
    expect(html).not.toContain(env.COACH_APP_TOKEN ?? "x");

    const apk = await handle(new Request(`${base}/IronLudi-Gym.apk`), withKV, fakeDeps([]));
    expect(apk.status).toBe(200);
    expect(apk.headers.get("content-type")).toBe("application/vnd.android.package-archive");
    expect(await apk.text()).toBe("apk");

    const redirect = await handle(new Request(base), withKV, fakeDeps([]));
    expect(redirect.status).toBe(301);
    expect(redirect.headers.get("location")).toBe(`${base}/`);

    const wrong = await handle(new Request(`https://x/android/${"0".repeat(32)}/`), withKV, fakeDeps([]));
    expect(wrong.status).toBe(404);
    // Ein Gast-Token ergibt keinen gültigen Pfad.
    const guestKey = await androidKey(await guestToken(env.COACH_APP_TOKEN ?? "", "abcdefghijk2"));
    expect((await handle(new Request(`https://x/android/${guestKey}/`), withKV, fakeDeps([]))).status).toBe(
      404,
    );
  });

  it("meldet fehlende Version und lehnt andere Methoden ab", async () => {
    const key = await androidKey(env.COACH_APP_TOKEN ?? "");
    const empty = { ...env, RELEASES: store({}) as unknown as KVNamespace };
    expect((await handle(new Request(`https://x/android/${key}/`), empty, fakeDeps([]))).status).toBe(503);
    const post = new Request(`https://x/android/${key}/`, { method: "POST" });
    expect((await handle(post, empty, fakeDeps([]))).status).toBe(404);
  });

  it("maskiert Text in der Seite", () => {
    expect(downloadPage({ ...info, versionName: "<b>1</b>" })).toContain("&lt;b&gt;1&lt;/b&gt;");
  });

  it("holt die APK aus dem privaten Release, ohne das Token weiterzugeben", async () => {
    const key = await androidKey(env.COACH_APP_TOKEN ?? "");
    const release = { ...info, asset: { repo: "owner/aironludi-releases", id: 42 } };
    const base = `https://coach-ai.example.workers.dev/android/${key}`;
    const calls: { url: string; init?: RequestInit }[] = [];
    const github = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      calls.push({ url, init });
      if (url.startsWith("https://api.github.com/")) {
        return new Response(null, {
          status: 302,
          headers: { location: "https://objects.example/signed?x=1" },
        });
      }
      return new Response("apk-aus-github", { headers: { "content-length": "14" } });
    }) as typeof fetch;
    const withKV = {
      ...env,
      RELEASES_READ_TOKEN: "lese-token",
      RELEASES: store({ "android.json": release }) as unknown as KVNamespace,
    };
    const apk = await handle(new Request(`${base}/AIronLudi.apk`), withKV, {
      ...fakeDeps([]),
      fetch: github,
    });
    expect(apk.status).toBe(200);
    expect(await apk.text()).toBe("apk-aus-github");
    expect(apk.headers.get("content-length")).toBe("14");
    expect(calls[0]?.url).toBe("https://api.github.com/repos/owner/aironludi-releases/releases/assets/42");
    expect(new Headers(calls[0]?.init?.headers).get("authorization")).toBe("Bearer lese-token");
    expect(calls[0]?.init?.redirect).toBe("manual");
    // Die signierte Adresse bekommt kein Token.
    expect(calls[1]?.url).toBe("https://objects.example/signed?x=1");
    expect(new Headers(calls[1]?.init?.headers).get("authorization")).toBeNull();
    // Alter Dateiname geht weiter.
    expect(
      (await handle(new Request(`${base}/IronLudi-Gym.apk`), withKV, { ...fakeDeps([]), fetch: github }))
        .status,
    ).toBe(200);

    // Ohne Lese-Token bzw. mit kaputter Angabe: klare Antwort statt leerer Datei.
    const noToken = { ...withKV, RELEASES_READ_TOKEN: undefined };
    expect((await handle(new Request(`${base}/AIronLudi.apk`), noToken, fakeDeps([]))).status).toBe(503);
    const broken = {
      ...withKV,
      RELEASES: store({
        "android.json": { ...info, asset: { repo: "../x", id: 1 } },
      }) as unknown as KVNamespace,
    };
    expect((await handle(new Request(`${base}/AIronLudi.apk`), broken, fakeDeps([]))).status).toBe(503);
    const failing = (async () => new Response("nein", { status: 404 })) as typeof fetch;
    expect(
      (await handle(new Request(`${base}/AIronLudi.apk`), withKV, { ...fakeDeps([]), fetch: failing }))
        .status,
    ).toBe(502);
  });

  it("meldet der App die neueste Version mit Link zur Download-Seite", async () => {
    const key = await androidKey(env.COACH_APP_TOKEN ?? "");
    const withKV = {
      ...env,
      RELEASES: store({
        "android.json": { ...info, notes: "Neu: Update-Hinweis" },
      }) as unknown as KVNamespace,
    };
    const url = "https://coach-ai.example.workers.dev/v1/app/android";
    const guest = await guestToken(env.COACH_APP_TOKEN ?? "", "abcdefghijk2");
    const response = await handle(
      new Request(url, { headers: { authorization: `Bearer ${guest}` } }),
      withKV,
      fakeDeps([]),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      versionName: "1.0.12",
      versionCode: 12,
      date: "2026-11-02T16:00:00Z",
      notes: "Neu: Update-Hinweis",
      url: `https://coach-ai.example.workers.dev/android/${key}/`,
    });

    // Ohne Anmeldung nichts, auch nicht der geheime Pfad.
    const anonymous = await handle(new Request(url), withKV, fakeDeps([]));
    expect(anonymous.status).toBe(401);
    expect(await anonymous.text()).not.toContain(key);
    const auth = { authorization: `Bearer ${env.COACH_APP_TOKEN}` };
    const post = new Request(url, { method: "POST", headers: auth });
    expect((await handle(post, withKV, fakeDeps([]))).status).toBe(405);
    const empty = { ...env, RELEASES: store({}) as unknown as KVNamespace };
    expect((await handle(new Request(url, { headers: auth }), empty, fakeDeps([]))).status).toBe(404);
  });
});
