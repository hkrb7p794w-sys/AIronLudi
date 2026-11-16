import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import { TASK_ROUTES } from "../src/providers";
import {
  checkMealNow,
  checkPantryRecipes,
  checkRecipes,
  mealNowPrompt,
  pantryRecipesPrompt,
  weeklyRecipesPrompt,
} from "../src/recipes";
import { findTask } from "../src/tasks";
import { env, fakeDeps, jsonResponse } from "./helpers";

const input = {
  days: [
    {
      datum: "2026-11-02",
      wochentag: "Montag",
      training: "Lockerer Lauf",
      tagestyp: "Moderater Trainingstag",
      kcal: 2100,
      protein_g: 120,
      kohlenhydrate_g: 260,
      fett_g: 65,
    },
    { datum: "2026-11-03", wochentag: "Dienstag", training: "frei", tagestyp: "Ruhetag", kcal: 1800 },
  ],
  diet: "vegetarisch",
  goal: "Abnehmen",
  allergens: ["Erdnüsse"],
  dislikes: "keine Pilze",
  maxMinutes: 20,
  snacks: false,
  mealPrep: true,
  gaps: ["Ballaststoffe: im Schnitt 18 von 30 g (60 %)"],
  favorites: ["Skyr", "Haferflocken"],
};

describe("weekly_recipes", () => {
  it("übernimmt Ziele, Ernährungsweise und Wünsche", () => {
    const prompt = weeklyRecipesPrompt(input);
    expect(prompt).toContain("Vegetarisch: kein Fleisch");
    expect(prompt).toContain("strikt meiden, auch in Spuren als Zutat): Erdnüsse.");
    expect(prompt).toContain("Mag nicht: keine Pilze.");
    expect(prompt).toContain("höchstens 20 Minuten");
    expect(prompt).toContain("Frühstück, Mittagessen, Abendessen.");
    expect(prompt).toContain("Meal-Prep");
    expect(prompt).toContain(
      "- 2026-11-02 (Montag): Training Lockerer Lauf; Moderater Trainingstag; Ziel 2100 kcal",
    );
    expect(prompt).toContain("Ziel 1800 kcal, – g Protein");
    expect(prompt).toContain("Lücken der letzten Tage");
    expect(prompt).toContain("Skyr, Haferflocken");
  });

  it("behält nur angefragte Tage", () => {
    const checked = checkRecipes(
      {
        tage: [
          { datum: "2026-11-02", gerichte: [{ titel: "A" }] },
          { datum: "2026-11-03", gerichte: [{ titel: "B" }] },
          { datum: "2030-01-01", gerichte: [] },
        ],
      },
      "",
      input,
    ) as { tage: { datum: string }[] };
    expect(checked.tage.map((day) => day.datum)).toEqual(["2026-11-02", "2026-11-03"]);
    expect(() => checkRecipes({ tage: [] }, "", input)).toThrow("keine passenden Tage");
  });

  it("nutzt mehr Ausgabe-Tokens", async () => {
    const deps = fakeDeps([
      () =>
        jsonResponse(200, {
          candidates: [
            {
              content: {
                parts: [
                  {
                    text: JSON.stringify({
                      tage: [
                        { datum: "2026-11-02", gerichte: [] },
                        { datum: "2026-11-03", gerichte: [] },
                      ],
                    }),
                  },
                ],
              },
            },
          ],
        }),
    ]);
    const response = await handle(
      new Request("https://x/v1/ai/generate", {
        method: "POST",
        headers: { authorization: `Bearer ${env.COACH_APP_TOKEN}` },
        body: JSON.stringify({ task: "weekly_recipes", input }),
      }),
      env,
      deps,
    );
    expect(response.status).toBe(200);
    const body = deps.calls[0]?.body as { generationConfig: { maxOutputTokens: number } };
    expect(body.generationConfig.maxOutputTokens).toBe(16000);
  });
});

describe("meal_now", () => {
  it("nennt das Ziel der Mahlzeit, Vorrat und Allergene", () => {
    const prompt = mealNowPrompt({
      mahlzeit: "abendessen",
      kcal: 650,
      protein_g: 45,
      carbs_g: 60,
      fat_g: 20,
      diet: "vegetarisch",
      allergens: ["Nüsse"],
      pantry: ["Linsen", "Spinat"],
    });
    expect(prompt).toContain("Mahlzeit: Abendessen.");
    expect(prompt).toContain("650 kcal, 45 g Protein");
    expect(prompt).toContain("Vegetarisch");
    expect(prompt).toContain("Nüsse");
    expect(prompt).toContain("Linsen, Spinat");
    expect(findTask("meal_now")?.allowImages).toBe(false);
  });

  it("begrenzt auf drei Gerichte und verlangt mindestens eins", () => {
    const four = { gerichte: [1, 2, 3, 4].map((i) => ({ titel: `G${i}` })) };
    expect((checkMealNow(four) as { gerichte: unknown[] }).gerichte).toHaveLength(3);
    expect(() => checkMealNow({ gerichte: [] })).toThrow();
  });
});

describe("pantry_recipes", () => {
  const input = {
    mahlzeit: "abendessen",
    diet: "vegetarisch",
    allergens: ["Nüsse"],
    vorrat: ["Reis"],
    erkannt: [],
    bestaetigt: [],
    nicht_da: [],
    max_fehlend: 2,
    anzahl: 4,
  };

  it("erste Anfrage mit Foto: erkennen, kleine fehlende Zutaten nennen statt verwerfen", () => {
    const prompt = pantryRecipesPrompt(input, 1);
    expect(prompt).toContain("Erkenne die Lebensmittel");
    expect(prompt).toContain("Außerdem im Vorrat: Reis.");
    expect(prompt).toContain("Verwirf ein sonst passendes Gericht NICHT");
    expect(prompt).toContain("höchstens 2 je Gericht");
    expect(prompt).toContain("Bis zu 4");
    expect(prompt).toContain("Vegetarisch");
    expect(prompt).toContain("Nüsse");
    expect(prompt).toContain('"fehlt"');
    expect(prompt).not.toContain("NICHT vorhanden");
  });

  it("zweite Anfrage: korrigierte Liste und Antworten auf die Rückfragen", () => {
    const prompt = pantryRecipesPrompt(
      { ...input, erkannt: ["Eier", "Spinat"], bestaetigt: ["Salz"], nicht_da: ["Butter"], max_fehlend: 9 },
      1,
    );
    expect(prompt).toContain("es gilt diese Liste: Eier, Spinat.");
    expect(prompt).toContain("Sicher vorhanden: Salz.");
    expect(prompt).toContain("Sicher NICHT vorhanden – nicht verwenden: Butter.");
    expect(prompt).toContain("höchstens 2 je Gericht");
    const withoutPhoto = pantryRecipesPrompt({ ...input, erkannt: ["Eier"] }, 0);
    expect(withoutPhoto).toContain("Vorhanden (von der Person bestätigt): Eier.");
  });

  it("nimmt Fotos an, Bildmodelle zuerst; Antwort mit Liste und höchstens vier Gerichten", () => {
    expect(findTask("pantry_recipes")?.allowImages).toBe(true);
    expect(TASK_ROUTES.pantry_recipes?.[0]).toBe("gemini");
    expect(TASK_ROUTES.pantry_recipes).not.toContain("cerebras");
    const five = { erkannt: ["Eier", 3, " "], gerichte: [1, 2, 3, 4, 5].map((i) => ({ titel: `G${i}` })) };
    const checked = checkPantryRecipes(five) as { erkannt: unknown[]; gerichte: unknown[] };
    expect(checked.erkannt).toEqual(["Eier"]);
    expect(checked.gerichte).toHaveLength(4);
    expect(checkPantryRecipes({ erkannt: ["Eier"] })).toEqual({ erkannt: ["Eier"], gerichte: [] });
    expect(() => checkPantryRecipes({})).toThrow();
  });
});
