import { describe, expect, it } from "vitest";
import { evidenceBlock, evidenceFrom, GroundingError, groundPoints, numbersIn } from "../src/grounding";
import { handle } from "../src/index";
import { env, fakeDeps, geminiText } from "./helpers";

const facts = "Ruhepuls 52 bpm, Schwelle 4:55 /km, FTP 178 W, Schlaf 6,5 h.";

describe("numbersIn", () => {
  it("normalisiert Dezimalkomma und Nullen", () => {
    expect([...numbersIn("6,5 h, 12,0 km, 4:55")]).toEqual(["6.5", "12", "4", "55"]);
  });
});

describe("groundPoints", () => {
  it("behält belegte Punkte und verwirft erfundene Zahlen", () => {
    const result = groundPoints(
      {
        punkte: ["Heute locker bei FTP-Bezug 178 W.", "Laufe 10 km in 4:30 /km.", "2 Sätze weniger."],
        quellen: ["recovery.hrv", "erfunden.2024"],
      },
      facts,
      ["recovery.hrv"],
    );
    expect(result.punkte).toEqual(["Heute locker bei FTP-Bezug 178 W.", "2 Sätze weniger."]);
    expect(result.quellen).toEqual(["recovery.hrv"]);
    expect(result.verworfen).toBe(1);
  });

  it("wirft, wenn nichts belegt ist", () => {
    expect(() => groundPoints({ punkte: ["Mach 90 Minuten bei 250 W."] }, facts, [])).toThrow(GroundingError);
    expect(() => groundPoints({}, facts, [])).toThrow(GroundingError);
  });
});

describe("evidence", () => {
  it("liest Regeln aus der Eingabe und baut den Block", () => {
    const items = evidenceFrom({
      evidence: [
        { id: "run.4x4", statement: "4×4 bei 90–95 % HFmax." },
        { id: "", statement: "x" },
        "kaputt",
      ],
    });
    expect(items).toEqual([{ id: "run.4x4", statement: "4×4 bei 90–95 % HFmax." }]);
    expect(evidenceBlock(items)).toContain("- run.4x4: 4×4 bei 90–95 % HFmax.");
    expect(evidenceBlock([])).toBe("");
  });
});

describe("daily_note über den Worker", () => {
  const post = (body: unknown) =>
    new Request("https://x/v1/ai/generate", {
      method: "POST",
      headers: { authorization: `Bearer ${env.COACH_APP_TOKEN}` },
      body: JSON.stringify(body),
    });
  const input = {
    weekday: "Montag",
    testValues: "FTP 178 W",
    evidence: [{ id: "recovery.hrv", statement: "HRV im 7-Tage-Schnitt." }],
  };

  it("schickt Systemanweisung und niedrige Temperatur, filtert die Antwort", async () => {
    const deps = fakeDeps([
      () =>
        geminiText(
          '{"punkte": ["Locker rollen, Bezug FTP 178 W.", "Heute 3x 20 min bei 260 W."], "quellen": ["recovery.hrv", "x"]}',
        ),
    ]);
    const response = await handle(post({ task: "daily_note", input }), env, deps);
    expect(response.status).toBe(200);
    const body = (await response.json()) as { output: unknown };
    expect(body.output).toEqual({
      punkte: ["Locker rollen, Bezug FTP 178 W."],
      quellen: ["recovery.hrv"],
      verworfen: 1,
    });
    const sent = JSON.stringify(deps.calls[0]?.body);
    expect(sent).toContain("systemInstruction");
    expect(sent).toContain('"temperature":0.2');
    expect(sent).toContain("recovery.hrv: HRV im 7-Tage-Schnitt.");
  });

  it("meldet 502, wenn nichts belegt ist", async () => {
    const deps = fakeDeps([() => geminiText('{"punkte": ["Heute 250 W für 90 Minuten."]}')]);
    const response = await handle(post({ task: "daily_note", input }), env, deps);
    expect(response.status).toBe(502);
  });
});
