import { describe, expect, it } from "vitest";
import { dailyNotePrompt, findTask, list, text } from "../src/tasks";

const input = {
  weekday: "Freitag",
  phase: "Grundlage",
  phaseFocus: "aerobe Basis",
  phaseDetail: "Lauf: Z2. Schwimmen: CSS. Rad (Zwift): Sweet Spot. Kraft: Push.",
  raceName: "Challenge Almere-Amsterdam, Mitteldistanz",
  raceDate: "11.09.2027",
  raceGoal: "Finish in 5:30–6:00 h",
  daysToRace: 323,
  testValues: "Testwerte: FTP 178 W (Zwift)",
  todayItems: ["Push + Pull kombiniert (Home-Gym)"],
  openItems: ["1× Schwimmen", "1× Rad"],
  daysLeftInWeek: 2,
  volumes: { swimKm: 0, bikeKm: 30, runKm: 8.25 },
  vitals: ["HRV-Status (7-Tage-Schnitt vs. Baseline): ausgeglichen", "Schlaf: kurz"],
  decision: { label: "Locker / verkürzt", advice: "Intensität raus.", reasons: ["kurzer Schlaf"] },
};

describe("daily_note", () => {
  it("baut den Prompt aus den Werten der App", () => {
    const prompt = dailyNotePrompt(input);
    expect(prompt).toContain("Challenge Almere-Amsterdam, Mitteldistanz am 11.09.2027");
    expect(prompt).toContain(
      "Heute ist Freitag. Trainingsphase: Grundlage (Fokus: aerobe Basis). Noch 323 Tage",
    );
    expect(prompt).toContain("Diese Woche noch offen: 1× Schwimmen, 1× Rad (noch 2 Tage in der Woche)");
    expect(prompt).toContain("Rad 30,0 km, Lauf 8,3 km");
    expect(prompt).toContain("- Schlaf: kurz");
    expect(prompt).toContain(
      "VERBINDLICHE Tagesentscheidung (regelbasiert, nicht ändern): Locker / verkürzt - Intensität raus.",
    );
    expect(prompt).toContain("Testwerte: FTP 178 W (Zwift).");
    expect(prompt).not.toContain("LETZTE Tag der Woche");
  });

  it("weist am letzten Wochentag darauf hin", () => {
    expect(dailyNotePrompt({ ...input, daysLeftInWeek: 0 })).toContain("LETZTE Tag der Woche");
  });

  it("verträgt fehlende Werte", () => {
    const prompt = dailyNotePrompt({});
    expect(prompt).toContain("nichts Festes");
    expect(prompt).toContain("- keine Daten");
    expect(prompt).toContain("nicht ändern): keine");
  });

  it("begrenzt Eingaben", () => {
    expect(text("a\n  b", 10)).toBe("a b");
    expect(text("x".repeat(50), 5)).toBe("xxxxx");
    expect(text({ a: 1 })).toBe("");
    expect(list(["a", 1, null, "b"], 3)).toEqual(["a", "1"]);
  });

  it("ist als JSON-Aufgabe registriert", () => {
    expect(findTask("daily_note")).toMatchObject({ json: true, allowImages: false });
  });
});
