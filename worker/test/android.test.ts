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
    expect(html).toContain('href="IronLudi-Gym.apk"');
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
});
