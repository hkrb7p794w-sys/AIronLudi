import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import { checkCookPlan, checkRecipes, cookPlanPrompt } from "../src/recipes";
import { handleShare, type ShareStore, sanitizeCookShare, sharePage } from "../src/share";
import { env, fakeDeps, geminiText, jsonResponse } from "./helpers";

const generate = (body: unknown) =>
  new Request("https://x/v1/ai/generate", {
    method: "POST",
    headers: { authorization: `Bearer ${env.COACH_APP_TOKEN}` },
    body: JSON.stringify(body),
  });

const recipeBody = (tage: unknown) => JSON.stringify({ tage });
const days = [{ datum: "2026-11-09", wochentag: "Montag", kcal: 2000 }];

describe("Fehlerkette der Rezeptideen", () => {
  it("wechselt bei abgeschnittener Antwort zum nächsten Anbieter", async () => {
    const deps = fakeDeps([
      () =>
        jsonResponse(200, {
          candidates: [{ content: { parts: [{ text: '{"tage": [' }] }, finishReason: "MAX_TOKENS" }],
        }),
      () =>
        jsonResponse(200, {
          choices: [
            { message: { content: recipeBody([{ datum: "2026-11-09", gerichte: [{ titel: "A" }] }]) } },
          ],
        }),
    ]);
    const response = await handle(generate({ task: "weekly_recipes", input: { days } }), env, deps);
    expect(response.status).toBe(200);
    expect(((await response.json()) as { provider: string }).provider).toBe("groq");
  });

  it("wechselt auch, wenn die Antwort kein JSON ist oder keine passenden Tage enthält", async () => {
    const deps = fakeDeps([
      () => geminiText("kein json"),
      () =>
        jsonResponse(200, {
          choices: [{ message: { content: recipeBody([{ datum: "2030-01-01", gerichte: [] }]) } }],
        }),
    ]);
    const response = await handle(generate({ task: "weekly_recipes", input: { days } }), env, deps);
    expect(response.status).toBe(502);
    const body = (await response.json()) as { error: string; code: string };
    expect(body.code).toBe("ai_invalid");
    expect(deps.calls.length).toBe(2);
  });

  it("gibt Antworttexte der Anbieter weder an die App noch ins Protokoll", async () => {
    const deps = fakeDeps([
      () => new Response("GEHEIM-DETAIL", { status: 400 }),
      () => new Response("GEHEIM-DETAIL", { status: 401 }),
    ]);
    const response = await handle(generate({ task: "ping" }), env, deps);
    expect(response.status).toBe(502);
    const text = await response.text();
    expect(text).not.toContain("GEHEIM-DETAIL");
    expect(JSON.parse(text).code).toBe("ai_unavailable");
    const logs = deps.logs.join(" ");
    expect(logs).not.toContain("GEHEIM-DETAIL");
    expect(logs).toContain("HTTP 400");
  });

  it("verlangt wenig Denk-Tokens bei großen JSON-Antworten", async () => {
    const deps = fakeDeps([
      () => geminiText(recipeBody([{ datum: "2026-11-09", gerichte: [{ titel: "A" }] }])),
    ]);
    await handle(generate({ task: "weekly_recipes", input: { days } }), env, deps);
    const sent = deps.calls[0]?.body as { generationConfig: Record<string, unknown> };
    expect(sent.generationConfig.thinkingConfig).toEqual({ thinkingLevel: "low" });
    expect(sent.generationConfig.maxOutputTokens).toBe(16000);
  });

  it("setzt bei jedem Abruf eine Zeitgrenze", async () => {
    const deps = fakeDeps([() => geminiText("pong")]);
    await handle(generate({ task: "ping" }), env, deps);
    expect(deps.calls[0]?.init?.signal).toBeInstanceOf(AbortSignal);
  });
});

const person = (label: string, teller: number, kcal: number, protein: number) => ({
  bezeichnung: label,
  teller,
  kcal,
  protein_g: protein,
});

describe("cook_plan", () => {
  it("beschreibt zwei Personen, Basisportion und Kompromiss", () => {
    const prompt = cookPlanPrompt({
      personen: [person("Person 1", 2, 720, 48), person("Person 2", 2, 540, 30)],
      mahlzeit: "abendessen",
      diet: "vegetarisch",
      allergens: ["Erdnüsse"],
      vorkochen: false,
    });
    expect(prompt).toContain("Person 1: 2 Teller; Ziel je Teller 720 kcal, 48 g Protein");
    expect(prompt).toContain("Person 2: 2 Teller; Ziel je Teller 540 kcal, 30 g Protein");
    expect(prompt).toContain("EINE Basisportion");
    expect(prompt).toContain("Nenne dort keine Namen");
    expect(prompt).toContain("frisch gegessen");
    expect(prompt).toContain("Vegetarisch");
  });

  it("verlangt beim Vorkochen geeignete Gerichte", () => {
    const prompt = cookPlanPrompt({
      personen: [person("Person 1", 3, 700, 40)],
      mahlzeit: "mittagessen",
      vorkochen: true,
      mahlzeiten_je_person: 3,
    });
    expect(prompt).toContain("an 3 Tagen");
    expect(prompt).toContain("Verdoppeln allein reicht nicht");
    expect(prompt).not.toContain("Beide essen");
  });

  it("begrenzt die Zahl der Rezepte und lehnt leere Antworten ab", () => {
    const checked = checkCookPlan({ rezepte: [{}, {}, {}, {}] }) as { rezepte: unknown[] };
    expect(checked.rezepte.length).toBe(3);
    expect(() => checkCookPlan({})).toThrow();
  });

  it("läuft als Aufgabe über den Worker", async () => {
    const deps = fakeDeps([() => geminiText(JSON.stringify({ rezepte: [{ titel: "Curry" }] }))]);
    const response = await handle(generate({ task: "cook_plan", input: { personen: [] } }), env, deps);
    expect(response.status).toBe(200);
  });
});

function memoryStore(): ShareStore & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    get: async (key) => data.get(key) ?? null,
    put: async (key, value) => {
      data.set(key, value);
    },
    delete: async (key) => {
      data.delete(key);
    },
  };
}

const call = (method: string, path: string, body?: unknown) =>
  new Request(`https://w.example${path}`, {
    method,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
const now = new Date("2026-11-08T12:00:00Z");
const share = {
  name: "Lena",
  kcal: 1800,
  protein: 100,
  carbs: 200,
  fat: 60,
  diet: "vegetarisch",
  allergens: ["egg"],
};

describe("Freigabe für gemeinsame Rezepte", () => {
  it("speichert nur erlaubte Felder", () => {
    const clean = sanitizeCookShare({
      ...share,
      gewicht: 70,
      schlaf: 5,
      allergens: ["egg", "Böse Eingabe"],
      name: "  Lena  ",
    }) as Record<string, unknown>;
    expect(clean.gewicht).toBeUndefined();
    expect(clean.schlaf).toBeUndefined();
    expect(clean.allergens).toEqual(["egg"]);
    expect(clean.name).toBe("Lena");
  });

  it("verlangt einen Namen und verwirft unplausible Ziele", () => {
    expect(sanitizeCookShare({ kcal: 2000 })).toBe("Name fehlt");
    const clean = sanitizeCookShare({ name: "A", kcal: 50, protein: 100 }) as Record<string, unknown>;
    expect(clean.kcal).toBeUndefined();
    expect(clean.protein).toBeUndefined();
  });

  it("legt an, liefert ohne Besitzer und lässt nur den Besitzer ändern und zurückziehen", async () => {
    const store = memoryStore();
    const created = await handleShare(
      call("POST", "/v1/share/cook", share),
      store,
      now,
      "guest:lena",
      () => "abcdefghij",
    );
    expect((created as Response).status).toBe(200);

    const read = await handleShare(call("GET", "/v1/share/cook/abcdefghij"), store, now, "owner");
    const body = (await (read as Response).json()) as Record<string, unknown>;
    expect(body.name).toBe("Lena");
    expect(body.owner).toBeUndefined();

    const foreign = await handleShare(call("DELETE", "/v1/share/cook/abcdefghij"), store, now, "owner");
    expect((foreign as Response).status).toBe(403);
    const foreignUpdate = await handleShare(
      call("PUT", "/v1/share/cook/abcdefghij", { name: "X" }),
      store,
      now,
      "owner",
    );
    expect((foreignUpdate as Response).status).toBe(403);

    const update = await handleShare(
      call("PUT", "/v1/share/cook/abcdefghij", { ...share, kcal: 1700 }),
      store,
      now,
      "guest:lena",
    );
    expect((update as Response).status).toBe(200);
    const stored = JSON.parse(store.data.get("cook:abcdefghij") ?? "{}") as Record<string, unknown>;
    expect(stored.kcal).toBe(1700);

    await handleShare(call("DELETE", "/v1/share/cook/abcdefghij"), store, now, "guest:lena");
    const gone = await handleShare(call("GET", "/v1/share/cook/abcdefghij"), store, now, "owner");
    expect((gone as Response).status).toBe(404);
  });

  it("ist getrennt von geteilten Mahlzeiten", async () => {
    const store = memoryStore();
    await handleShare(call("POST", "/v1/share/cook", share), store, now, "a", () => "abcdefghij");
    const meal = await handleShare(call("GET", "/v1/share/meal/abcdefghij"), store, now, "a");
    expect((meal as Response).status).toBe(404);
  });

  it("verlangt eine Anmeldung", async () => {
    const response = await handle(call("GET", "/v1/share/cook/abcdefghij"), env, fakeDeps([]));
    expect(response.status).toBe(401);
  });

  it("Weiterleitungsseiten enthalten keine Angaben", async () => {
    const page = await (sharePage("/k/abcdefghij") as Response).text();
    expect(page).toContain("coach://cook/abcdefghij");
    expect(page).not.toContain("kcal");
    expect(await (sharePage("/k/einladen") as Response).text()).toContain("coach://open/cookShare");
    expect(sharePage("/k/zu-kurz")).toBeNull();
  });
});

describe("unvollständige Antworten", () => {
  const three = ["2026-11-09", "2026-11-10", "2026-11-11"].map((datum) => ({ datum }));

  it("lehnt eine Teilanfrage ab, wenn Tage fehlen", () => {
    expect(() =>
      checkRecipes({ tage: [{ datum: "2026-11-09", gerichte: [{ titel: "A" }] }] }, "", { days: three }),
    ).toThrow();
  });

  it("nimmt bei alten App-Versionen mit ganzer Woche auch Teilergebnisse an", () => {
    const week = [...three, ...["2026-11-12", "2026-11-13"].map((datum) => ({ datum }))];
    const checked = checkRecipes({ tage: [{ datum: "2026-11-09", gerichte: [] }] }, "", { days: week }) as {
      tage: unknown[];
    };
    expect(checked.tage.length).toBe(1);
  });
});
