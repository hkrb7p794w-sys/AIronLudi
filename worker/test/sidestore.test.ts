import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import { type ReleaseStore, sidestoreKey } from "../src/sidestore";
import { env, fakeDeps } from "./helpers";

const info = {
  version: "0.5.30",
  buildVersion: "30",
  date: "2026-10-26T13:00:00Z",
  notes: "feat: x",
  size: 3,
};

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

describe("sidestore", () => {
  it("liefert Quelle, IPA und Icon nur unter dem geheimen Pfad", async () => {
    const key = await sidestoreKey(env.COACH_APP_TOKEN ?? "");
    expect(key).toMatch(/^[0-9a-f]{32}$/);
    // Gleicher Wert wie in der App (NetworkClientTests.sideStoreSourceMatchesWorker).
    expect(await sidestoreKey("app-token-123")).toBe("ee99266b889655b045c7352ceb212936");
    const releases = store({ "release.json": info, "Coach.ipa": "ipa", "icon.png": "png" });
    const withKV = { ...env, RELEASES: releases as unknown as KVNamespace };
    const base = `https://coach-ai.example.workers.dev/sidestore/${key}`;

    const source = await handle(new Request(`${base}/source.json`), withKV, fakeDeps([]));
    expect(source.status).toBe(200);
    const body = (await source.json()) as {
      apps: { versions: { version: string; downloadURL: string }[] }[];
    };
    expect(body.apps[0]?.versions[0]?.version).toBe("0.5.30");
    expect(body.apps[0]?.versions[0]?.downloadURL).toBe(`${base}/Coach.ipa`);

    const ipa = await handle(new Request(`${base}/Coach.ipa`), withKV, fakeDeps([]));
    expect(await ipa.text()).toBe("ipa");
    expect(ipa.headers.get("content-type")).toBe("application/octet-stream");

    const wrong = await handle(
      new Request(`https://x/sidestore/${"0".repeat(32)}/Coach.ipa`),
      withKV,
      fakeDeps([]),
    );
    expect(wrong.status).toBe(404);
  });

  it("meldet fehlende Version und fehlenden Speicher", async () => {
    const key = await sidestoreKey(env.COACH_APP_TOKEN ?? "");
    const url = `https://x/sidestore/${key}/source.json`;
    const empty = { ...env, RELEASES: store({}) as unknown as KVNamespace };
    expect((await handle(new Request(url), empty, fakeDeps([]))).status).toBe(503);
    expect((await handle(new Request(url), env, fakeDeps([]))).status).toBe(404);
  });
});
