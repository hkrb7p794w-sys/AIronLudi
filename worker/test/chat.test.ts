import { describe, expect, it } from "vitest";
import { CHAT_SYSTEM, chatPrompt } from "../src/chat";
import { GroundingError } from "../src/grounding";
import { findTask } from "../src/tasks";

const input = {
  question: "Soll ich heute hart laufen?",
  history: [
    { role: "user", text: "Wie war mein Schlaf?" },
    { role: "coach", text: "Im Schnitt 6,4 Stunden." },
  ],
  facts: ["Tagesampel: locker (HRV unter dem Normalbereich)", "Geplant heute: Qualitätslauf, 45 min"],
  evidence: [{ id: "recovery.hrv", statement: "HRV im Wochenmittel." }],
};

describe("coach_chat", () => {
  it("baut Fakten, Verlauf und Frage in den Prompt", () => {
    const prompt = chatPrompt(input);
    expect(prompt).toContain("- Tagesampel: locker (HRV unter dem Normalbereich)");
    expect(prompt).toContain("Person: Wie war mein Schlaf?");
    expect(prompt).toContain("Coach: Im Schnitt 6,4 Stunden.");
    expect(prompt).toContain("Frage: Soll ich heute hart laufen?");
    expect(prompt).toContain("- recovery.hrv: HRV im Wochenmittel.");
    expect(CHAT_SYSTEM).toContain("ärztlicher Abklärung");
  });

  it("lässt belegte Antworten durch und filtert Quellen", () => {
    const task = findTask("coach_chat");
    const prompt = `${CHAT_SYSTEM}\n${chatPrompt(input)}`;
    const result = task?.ground?.(
      {
        antwort: "Heute lieber locker: 45 min ruhig statt Intervallen.",
        quellen: ["recovery.hrv", "erfunden"],
      },
      prompt,
      input,
    );
    expect(result).toEqual({
      antwort: "Heute lieber locker: 45 min ruhig statt Intervallen.",
      quellen: ["recovery.hrv"],
    });
  });

  it("verwirft Antworten mit erfundenen Zahlen oder ohne Text", () => {
    const task = findTask("coach_chat");
    const prompt = chatPrompt(input);
    expect(() => task?.ground?.({ antwort: "Lauf 12 km in 5:10 /km.", quellen: [] }, prompt, input)).toThrow(
      GroundingError,
    );
    expect(() => task?.ground?.({ antwort: "" }, prompt, input)).toThrow(GroundingError);
  });

  it("erlaubt Rechnungen aus belegten Werten derselben Einheit", () => {
    const task = findTask("coach_chat");
    const facts = { ...input, facts: ["Heute erfasst: 70 g Protein", "Tagesziel: 150 g Protein, 2400 kcal"] };
    const prompt = chatPrompt(facts);
    const ok = "Dir fehlen noch 80 g Protein von 2.400 kcal Tagesziel.";
    expect(task?.ground?.({ antwort: ok, quellen: [] }, prompt, facts)).toMatchObject({ antwort: ok });
    // 2330 wäre kcal minus Gramm: verschiedene Einheiten dürfen nicht verrechnet werden.
    expect(() => task?.ground?.({ antwort: "Noch 2330 kcal.", quellen: [] }, prompt, facts)).toThrow(
      GroundingError,
    );
    expect(() => task?.ground?.({ antwort: "Noch 77 g Protein.", quellen: [] }, prompt, facts)).toThrow(
      GroundingError,
    );
  });

  it("verwirft belegte Zahlen mit falscher Einheit", () => {
    const task = findTask("coach_chat");
    const facts = {
      ...input,
      facts: ["Bankdrücken: von 75 kg für 8 Wiederholungen auf 80 kg für 8 Wiederholungen"],
    };
    const prompt = chatPrompt(facts);
    expect(() =>
      task?.ground?.({ antwort: "Eine Steigerung von 75 kg auf 8 kg.", quellen: [] }, prompt, facts),
    ).toThrow(GroundingError);
    const ok = "Eine Steigerung von 75 kg auf 80 kg, also 5 kg mehr bei 8 Wiederholungen.";
    expect(task?.ground?.({ antwort: ok, quellen: [] }, prompt, facts)).toMatchObject({ antwort: ok });
  });

  it("erlaubt Satz- und Wiederholungszahlen, aber keine freien Lastwerte", () => {
    const task = findTask("coach_chat");
    const prompt = chatPrompt(input);
    const ok = "Mach morgen 4 Sätze mit 8–12 Wiederholungen.";
    expect(task?.ground?.({ antwort: ok, quellen: [] }, prompt, input)).toMatchObject({ antwort: ok });
    expect(() => task?.ground?.({ antwort: "Nimm 8 kg mehr.", quellen: [] }, prompt, input)).toThrow(
      GroundingError,
    );
  });
});
