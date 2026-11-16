import { describe, expect, it } from "vitest";
import { GroundingError } from "../src/grounding";
import { handle } from "../src/index";
import { findTask } from "../src/tasks";
import { env, fakeDeps, geminiText } from "./helpers";

// R5B-01: Die Prüfung vergleicht nur Zahlen und Quellen. Ein Text ohne Zahlen, der der Regelentscheidung
// widerspricht, kommt heute durch. Beide Tests schlagen mit dem aktuellen Code fehl.
describe("KI-Text darf der Tagesampel nicht widersprechen", () => {
  const post = (body: unknown) =>
    new Request("https://x/v1/ai/generate", {
      method: "POST",
      headers: { authorization: `Bearer ${env.COACH_APP_TOKEN}` },
      body: JSON.stringify(body),
    });

  it("daily_note verwirft „hart trainieren“ bei Ampel Ruhetag", async () => {
    const input = {
      weekday: "Montag",
      decision: {
        label: "Ruhetag oder sehr locker",
        advice: "Heute Ruhetag – höchstens 20–30 min sehr locker bewegen.",
        reasons: ["nur 4,5 h Schlaf"],
      },
    };
    const deps = fakeDeps([
      () =>
        geminiText(
          '{"punkte": ["Heute hart trainieren: volle Intervalle.", "Deine Erholung ist gerade knapp."]}',
        ),
    ]);
    const response = await handle(post({ task: "daily_note", input }), env, deps);
    if (response.status === 200) {
      const body = (await response.json()) as { output: unknown };
      expect(JSON.stringify(body.output)).not.toMatch(/hart trainieren|Intervalle/i);
    } else {
      expect(response.status).toBe(502);
    }
  });

  it("coach_chat verwirft „trainiere hart“ bei Ampel Ruhetag", () => {
    const input = {
      question: "Soll ich heute hart trainieren?",
      facts: ["Tagesampel heute: Ruhetag oder sehr locker (nur 4,5 h Schlaf)."],
    };
    const task = findTask("coach_chat");
    expect(() =>
      task?.ground?.(
        { antwort: "Ja, trainiere heute ruhig hart, volle Intervalle.", quellen: [] },
        "4,5",
        input,
      ),
    ).toThrow(GroundingError);
  });
});
