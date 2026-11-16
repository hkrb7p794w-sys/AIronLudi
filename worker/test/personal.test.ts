import { describe, expect, it } from "vitest";
import { personalNotePrompt } from "../src/personal";
import { findTask } from "../src/tasks";

const input = {
  goal: "Fitter werden",
  sports: ["Laufen", "Krafttraining"],
  weekday: "Mittwoch",
  todayItems: ["Lockerer Lauf (heute)"],
  weekDone: 2,
  weekPlanned: 4,
  missed: ["Krafttraining"],
  vitals: ["Schlaf: kurz"],
  decision: { label: "Heute lockerer", advice: "Kürzer und ruhiger.", reasons: ["kurzer Schlaf"] },
  evidence: [{ id: "recovery.sleep", statement: "Wenig Schlaf mindert die Leistung." }],
};

describe("personal_note", () => {
  it("baut den Prompt ohne Saisonwerte", () => {
    const prompt = personalNotePrompt(input);
    expect(prompt).toContain("Ziel „Fitter werden“ (Sportarten: Laufen, Krafttraining)");
    expect(prompt).toContain("Laut Wochenplan heute: Lockerer Lauf (heute).");
    expect(prompt).toContain("Diese Woche geschafft: 2 von 4 Einheiten. Verpasst: Krafttraining");
    expect(prompt).toContain("nicht ändern): Heute lockerer - Kürzer und ruhiger. Gründe: kurzer Schlaf.");
    expect(prompt).toContain("recovery.sleep");
    expect(prompt).not.toContain("FTP");
    expect(prompt).not.toContain("Almere");
  });

  it("verträgt fehlende Werte", () => {
    const prompt = personalNotePrompt({});
    expect(prompt).toContain("„fit bleiben“");
    expect(prompt).toContain("laut Plan frei");
    expect(prompt).toContain("- keine Daten");
  });

  it("ist als belegte JSON-Aufgabe registriert", () => {
    const task = findTask("personal_note");
    expect(task).toMatchObject({ json: true, allowImages: false });
    expect(task?.ground).toBeTypeOf("function");
  });
});
