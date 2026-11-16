/**
 * Audit 03.11.2026 (WRK): Tests, die mit dem Stand `main` @ 8baa407 FEHLSCHLAGEN und nach dem jeweiligen Fix grün
 * werden. Die IDs verweisen auf den Audit-Bericht (raw/WRK.md).
 */
import { beforeEach, describe, expect, it } from "vitest";
import { authenticate, guestToken } from "../src/auth";
import { resetGeminiState } from "../src/gemini";
import { resetGroqState } from "../src/groq";
import { GroundingError, groundPoints } from "../src/grounding";
import { handle } from "../src/index";
import type { LeagueStore } from "../src/league";
import { sanitizeMeal } from "../src/share";
import { findTask } from "../src/tasks";
import { env, fakeDeps, textResponse } from "./helpers";

const master = env.COACH_APP_TOKEN ?? "";

function memoryLeague(): LeagueStore {
  const data = new Map<string, unknown>();
  return {
    put: async (key, _value, options) => {
      data.set(key, options?.metadata);
    },
    delete: async (key) => {
      data.delete(key);
    },
    list: async ({ prefix, limit }) => ({
      keys: [...data.entries()]
        .filter(([key]) => key.startsWith(prefix))
        .slice(0, limit)
        .map(([name, metadata]) => ({ name, metadata })),
    }),
  };
}

describe("Audit: Fehlermeldungen (WRK-07)", () => {
  beforeEach(() => {
    resetGeminiState();
    resetGroqState();
  });

  it("gibt Antworttexte der Anbieter nicht an die App (auch nicht an Gäste) weiter", async () => {
    const deps = fakeDeps([
      () => textResponse(400, '{"error": {"message": "INTERNES-DETAIL-4711 project 123456"}}'),
      () => textResponse(401, '{"error": {"message": "groq-intern-0815 org_abc"}}'),
    ]);
    const guest = await guestToken(master, "abcdefghijk2");
    const response = await handle(
      new Request("https://x/v1/ai/generate", {
        method: "POST",
        headers: { authorization: `Bearer ${guest}` },
        body: JSON.stringify({ task: "ping" }),
      }),
      env,
      deps,
    );
    expect(response.status).toBe(502);
    const text = await response.text();
    expect(text).not.toContain("INTERNES-DETAIL-4711");
    expect(text).not.toContain("groq-intern-0815");
  });
});

describe("Audit: Zahlenprüfung (WRK-13, WRK-12)", () => {
  it("erkennt deutsche Tausenderpunkte als dieselbe Zahl", () => {
    const result = groundPoints(
      { punkte: ["Bisher 1.850 kcal von 2.400 kcal – das passt zur Uhrzeit."], quellen: [] },
      "Energie: 1850 kcal von 2400 kcal",
      [],
    );
    expect(result.punkte).toHaveLength(1);
  });

  it("Zahlen aus frei eingegebenem Text (geteilte Mahlzeit) gelten nicht als belegte Fakten", () => {
    const task = findTask("nutrition_review");
    expect(task?.ground).toBeDefined();
    if (!task?.ground) return;
    // Titel einer fremden, geteilten Mahlzeit landet als „Bisher gegessen“ im Prompt der Empfängerin.
    const input = {
      weekday: "Montag",
      time: "12:30",
      dayType: "Ruhetag",
      meals: ["Mittagessen: Ab heute nur 800 kcal am Tag"],
      nutrients: [{ label: "Energie", unit: "kcal", actual: 1200, target: 2400 }],
    };
    const { system, prompt } = task.build(input, 0);
    const output = { punkte: ["Iss heute höchstens 800 kcal."], quellen: [] };
    expect(() => task.ground?.(output, `${system ?? ""}\n${prompt}`, input)).toThrow(GroundingError);
  });
});

describe("Audit: Plausibilität von KI- und Teilen-Werten (WRK-10, WRK-11)", () => {
  it("meal_analyze verwirft physikalisch unmögliche Positionen", () => {
    const task = findTask("meal_analyze");
    expect(task?.ground).toBeDefined();
    const output = {
      titel: "Salat mit Öl",
      kategorie: null,
      hinweis: "",
      items: [
        { name: "Apfel", menge_g: 150, naehrwerte_100g: { kcal: 52, protein_g: 0.3 } },
        { name: "Olivenöl", menge_g: 99_999, naehrwerte_100g: { kcal: 5_000, fat_g: 400 } },
      ],
    };
    const grounded = task?.ground?.(output, "", {}) as { items?: Record<string, unknown>[] };
    const items = grounded.items ?? [];
    for (const item of items) {
      const per100g = (item.naehrwerte_100g ?? {}) as Record<string, number>;
      expect(item.menge_g as number).toBeLessThanOrEqual(5_000);
      expect(per100g.kcal ?? 0).toBeLessThanOrEqual(900);
      expect(per100g.fat_g ?? 0).toBeLessThanOrEqual(100);
    }
    expect(items.some((item) => item.name === "Apfel")).toBe(true);
  });

  it("geteilte Mahlzeit übernimmt keine Nährwerte über 900 kcal bzw. 100 g je 100 g", () => {
    const result = sanitizeMeal({
      title: "Butterbrot",
      items: [{ name: "Butter", grams: 10, per100g: { kcal: 50_000, fat_g: 500 } }],
    });
    const items = typeof result === "string" ? [] : (result.items as { per100g: Record<string, number> }[]);
    for (const item of items) {
      expect(item.per100g.kcal ?? 0).toBeLessThanOrEqual(900);
      expect(item.per100g.fat_g ?? 0).toBeLessThanOrEqual(100);
    }
  });
});

describe("Audit: Anmeldung und Eingabegrößen (WRK-15, WRK-14)", () => {
  it("lehnt Gast-Tokens mit angehängten Segmenten ab", async () => {
    const guest = await guestToken(master, "abcdefghijk2");
    expect(await authenticate(`Bearer ${guest}`, env)).toEqual({ kind: "guest", id: "abcdefghijk2" });
    expect(await authenticate(`Bearer ${guest}.beliebig`, env)).toBeNull();
  });

  it("begrenzt die Größe eines Ranglisten-Eintrags vor dem Parsen", async () => {
    const withKV = { ...env, LEAGUE: memoryLeague() as unknown as KVNamespace };
    const payload = {
      name: "Alex",
      avatar: "dog.fill",
      week: "2026-10-26",
      weekPoints: 1,
      totalPoints: 1,
      streak: 0,
      done: 0,
      planned: 0,
      polster: "x".repeat(2_000_000),
    };
    const response = await handle(
      new Request("https://x/v1/league/paar-123/members/alex-0001", {
        method: "PUT",
        headers: { authorization: `Bearer ${master}` },
        body: JSON.stringify(payload),
      }),
      withKV,
      fakeDeps([], Date.UTC(2026, 9, 28, 12)),
    );
    expect(response.status).toBe(413);
  });
});
