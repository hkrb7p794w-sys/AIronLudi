import { describe, expect, it } from "vitest";
import { GroundingError } from "../src/grounding";
import { checkGymPlan, gymHintsPrompt, gymPlanPrompt } from "../src/gym";
import { findTask } from "../src/tasks";

const input = {
  goal: "Muskeln aufbauen",
  recovery: "gut",
  exercises: [
    "Bankdrücken: zuletzt 60 kg × 10/10/10 Wdh., Ziel 6–10 → Erhöhen auf 62,5 kg (+4,2 %). alle Sätze am Ziel.",
    "Kniebeuge: zuletzt 80 kg × 7/6 Wdh., Ziel 6–10 → Bei 80 kg bleiben. noch 4 Wdh. bis zur Obergrenze.",
  ],
  volume: ["Brust: 6 Sätze in 7 Tagen", "Beine: 3 Sätze in 7 Tagen"],
  evidence: [{ id: "gym.progression", statement: "Doppelprogression." }],
};

describe("gym_hints", () => {
  it("übernimmt die Entscheidungen der Regeln in den Prompt", () => {
    const prompt = gymHintsPrompt(input);
    expect(prompt).toContain("- Bankdrücken: zuletzt 60 kg × 10/10/10 Wdh.");
    expect(prompt).toContain("Ziel: Muskeln aufbauen. Erholung heute: gut.");
    expect(prompt).toContain("- Beine: 3 Sätze in 7 Tagen");
    expect(prompt).toContain("- gym.progression: Doppelprogression.");
  });

  it("verträgt fehlende Werte", () => {
    expect(gymHintsPrompt({})).toContain("- keine Übungen mit Verlauf");
  });

  it("verwirft Hinweise mit erfundenen Gewichten", () => {
    const task = findTask("gym_hints");
    expect(task).toMatchObject({ json: true, allowImages: false });
    const prompt = gymHintsPrompt(input);
    const grounded = task?.ground?.(
      {
        punkte: [
          "Bankdrücken: Gehe auf 62,5 kg und starte wieder bei 6 Wdh.",
          "Kniebeuge auf 90 kg erhöhen.",
        ],
        quellen: ["gym.progression", "erfunden"],
      },
      prompt,
      input,
    ) as { punkte: string[]; quellen: string[] };
    expect(grounded.punkte).toEqual(["Bankdrücken: Gehe auf 62,5 kg und starte wieder bei 6 Wdh."]);
    expect(grounded.quellen).toEqual(["gym.progression"]);
    expect(() => task?.ground?.({ punkte: ["Nimm 100 kg."], quellen: [] }, prompt, input)).toThrow(
      GroundingError,
    );
  });
});

const planInput = {
  goal: "Muskelaufbau",
  days: 2,
  minutes: 60,
  experience: "Fortgeschritten",
  repRange: "6–12",
  focus: ["Brust"],
  limitations: "Schulter links",
  library: [
    "bankdruecken | Bankdrücken | Brust | Wiederholungen | Grundübung",
    "latziehen | Latziehen | Rücken | Wiederholungen | Grundübung",
    "plank | Unterarmstütz | Rumpf | Sekunden | Isolation",
  ],
  lastWeights: ["bankdruecken: 52,5 kg × 12"],
  observations: ["Brust: 4 Sätze in 7 Tagen – unter 10."],
  evidence: [{ id: "gym.volume", statement: "Mehr Sätze, mehr Zuwachs." }],
};

describe("gym_plan", () => {
  it("baut den Prompt aus Fragebogen, Bibliothek und Verlauf", () => {
    const prompt = gymPlanPrompt(planInput);
    expect(prompt).toContain("Trainingstage pro Woche: 2, je etwa 60 Minuten.");
    expect(prompt).toContain("- bankdruecken | Bankdrücken | Brust | Wiederholungen | Grundübung");
    expect(prompt).toContain("Schulter links");
    expect(prompt).toContain("Letzte Gewichte: bankdruecken: 52,5 kg × 12.");
    expect(prompt).toContain("Genau 2 Routinen");
    expect(gymPlanPrompt({})).toContain("Trainingstage pro Woche: 3");
  });

  it("verwirft unbekannte Übungen und Hinweise mit erfundenen Zahlen", () => {
    const task = findTask("gym_plan");
    expect(task).toMatchObject({ json: true, allowImages: false });
    const prompt = gymPlanPrompt(planInput);
    const checked = checkGymPlan(
      {
        routinen: [
          {
            name: "Oberkörper",
            uebungen: [
              { id: "bankdruecken", saetze: 3 },
              { id: "erfunden", saetze: 3 },
            ],
          },
          { name: "Leer", uebungen: [{ id: "kniebeuge" }] },
        ],
        hinweise: ["Steigere Bankdrücken von 52,5 kg aus.", "Gehe auf 70 kg."],
      },
      prompt,
      planInput,
    ) as { routinen: { name: string; uebungen: { id: string }[] }[]; hinweise: string[] };
    expect(checked.routinen).toHaveLength(1);
    expect(checked.routinen[0]?.uebungen.map((item) => item.id)).toEqual(["bankdruecken"]);
    expect(checked.hinweise).toEqual(["Steigere Bankdrücken von 52,5 kg aus."]);
    expect(() => checkGymPlan({ routinen: [] }, prompt, planInput)).toThrow(GroundingError);
  });
});
