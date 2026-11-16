import { describe, expect, it } from "vitest";
import { GroundingError } from "../src/grounding";
import { groundInsights, insightsPrompt } from "../src/insights";
import { findTask } from "../src/tasks";

const input = {
  thema: "alle",
  fakten: [
    { id: "f1", text: "Ruhepuls 7-Tage-Schnitt 58, heute 64" },
    { id: "f2", text: "Bankdrücken: dreimal 80 kg × 8" },
  ],
  fehlend: ["Keine Schlafdaten der letzten 7 Tage"],
  regeln: [{ betreff: "bankdruecken", titel: "Bankdrücken: Stillstand", richtung: "aendern" }],
};

function item(overrides: Record<string, unknown>) {
  return {
    thema: "erholung",
    betreff: "ruhepuls",
    titel: "Erholung reduziert",
    text: "Dein Ruhepuls liegt mit 64 über deinem Schnitt von 58. Plane heute locker.",
    richtung: "weniger",
    prioritaet: 1,
    gueltig_tage: 2,
    sicherheit: "mittel",
    belege: ["f1"],
    ...overrides,
  };
}

describe("ai_insights", () => {
  it("Aufgabe ist registriert, Prompt enthält Fakten, Lücken und Regeln", () => {
    expect(findTask("ai_insights")).toBeDefined();
    const prompt = insightsPrompt(input);
    expect(prompt).toContain("f1: Ruhepuls");
    expect(prompt).toContain("Keine Schlafdaten");
    expect(prompt).toContain("Bankdrücken: Stillstand");
  });

  it("behält belegte Empfehlungen, verwirft Unbelegtes, Erfundenes, Technisches und Widersprüche", () => {
    const prompt = insightsPrompt(input);
    const output = {
      empfehlungen: [
        item({}),
        item({ betreff: "a", belege: ["f9"] }),
        item({ betreff: "b", text: "Dein Ruhepuls ist um 12 Schläge erhöht." }),
        item({ betreff: "c", text: "Laut Garmin Connect Datensatz ist alles gut." }),
        item({ thema: "stagnation", betreff: "bankdruecken", richtung: "mehr", belege: ["f2"] }),
        item({ thema: "unbekannt", betreff: "d" }),
      ],
    };
    const result = groundInsights(output, prompt, input) as { empfehlungen: unknown[]; verworfen: number };
    expect(result.empfehlungen).toHaveLength(1);
    expect(result.verworfen).toBe(5);
  });

  it("ohne belegte Empfehlung ein Fehler", () => {
    expect(() => groundInsights({ empfehlungen: [] }, insightsPrompt(input), input)).toThrow(GroundingError);
  });
});
