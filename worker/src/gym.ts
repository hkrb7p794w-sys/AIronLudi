/**
 * Hinweise zur Gewichtssteigerung im Krafttraining. Die Regeln der App (Doppelprogression mit Wiederholungen in
 * Reserve) haben je Übung entschieden; die KI fasst das in kurze, motivierende Hinweise für die nächste Einheit.
 */
import { evidenceBlock, evidenceFrom, GroundingError, numbersIn, POINTS_WITH_SOURCES } from "./grounding";
import { list, text, userText, withoutUserText } from "./tasks-util";

export function gymHintsPrompt(input: Record<string, unknown>): string {
  const exercises = list(input.exercises, 10, 500);
  return [
    "Du bist Krafttrainer. Die App hat je Übung mit festen Regeln entschieden, ob das Gewicht steigt, " +
      "gleich bleibt oder sinkt. Diese Entscheidungen übernimmst du unverändert.",
    `Ziel: ${text(input.goal, 80) || "nicht angegeben"}. Erholung heute: ${text(input.recovery, 120)}.`,
    "",
    "Übungen mit Entscheidung der Regeln:",
    ...(exercises.length ? exercises.map((line) => `- ${line}`) : ["- keine Übungen mit Verlauf"]),
    "",
    "Sätze je Muskel (7 Tage):",
    ...list(input.volume, 10, 80).map((line) => `- ${line}`),
    ...(list(input.observations, 6, 300).length
      ? ["", "Beobachtungen der Regeln (Stillstand, Volumen, Häufigkeit):"]
      : []),
    ...list(input.observations, 6, 300).map((line) => `- ${line}`),
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    `Aufgabe: ${POINTS_WITH_SOURCES} 2-4 Punkte, je ein bis zwei Sätze:`,
    "1. Für die Übungen mit „Erhöhen“: nenne Übung und neues Gewicht genau wie in den Fakten und einen " +
      "Technik- oder Ausführungstipp für die Steigerung (z. B. erst bei der Untergrenze beginnen).",
    "2. Für „Gewicht halten oder senken“ bzw. „Wiedereinstieg“: kurz, warum, ohne Vorwurf.",
    "3. Wenn vorhanden: die wichtigste Beobachtung der Regeln (Stillstand, zu wenig oder zu viele Sätze, nur ein " +
      "Trainingstag je Muskel) mit einem konkreten nächsten Schritt.",
    "4. Optional: ein Hinweis zur Nähe am Muskelversagen (Wiederholungen in Reserve) – nur wenn es aus den Fakten " +
      "hervorgeht.",
    "Nenne keine Gewichte, Prozente oder Wiederholungen, die nicht in den Fakten stehen. Keine zusätzlichen Sätze " +
      "oder Einheiten fordern. Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ].join("\n");
}

const PLAN_SHAPE = `Antwortformat (JSON):
{"routinen": [{"name": str, "uebungen": [{"id": str, "saetze": number, "wdh_min": number, "wdh_max": number,
"pause": number}]}], "hinweise": [str, ...]}`;

/** Erlaubte Übungs-IDs aus den Bibliothekszeilen „id | Name | Muskel | …“. */
function libraryIDs(input: Record<string, unknown>): Set<string> {
  return new Set(list(input.library, 200, 160).map((line) => line.split("|")[0]?.trim() ?? ""));
}

/**
 * Individueller Trainingsplan. Die App schickt Fragebogen, erlaubte Übungen (nach Ausstattung gefiltert), letzte
 * Gewichte, Beobachtungen der Regeln und die Evidenz. Die KI wählt Übungen und Aufteilung; die App prüft Sätze,
 * Wiederholungen, Pausen und das Wochenvolumen erneut.
 */
export function gymPlanPrompt(input: Record<string, unknown>): string {
  const days = typeof input.days === "number" ? Math.min(Math.max(Math.round(input.days), 1), 6) : 3;
  const minutes = typeof input.minutes === "number" ? Math.round(input.minutes) : 60;
  const focus = list(input.focus, 9, 40);
  const favorites = list(input.favorites, 40, 60);
  const lastWeights = list(input.lastWeights, 30, 80);
  const observations = list(input.observations, 8, 300);
  const sports = list(input.otherSports, 6, 40);
  const notes = list(input.exerciseNotes, 30, 200);
  const recent = list(input.recentPerformance, 40, 120);
  return [
    "Du bist erfahrener Krafttrainer und erstellst einen individuellen Trainingsplan für das Fitnessstudio.",
    `Ziel: ${text(input.goal, 80) || "Muskelaufbau"}. Erfahrung: ${text(input.experience, 40) || "unbekannt"}.`,
    `Trainingstage pro Woche: ${days}, je etwa ${minutes} Minuten.`,
    `Wiederholungsbereich für Grundübungen: ${text(input.repRange, 20) || "6–12"}.`,
    focus.length ? `Schwerpunkt: ${focus.join(", ")}.` : "",
    sports.length
      ? `Weitere Sportarten (Beine nicht vor harten Einheiten überlasten): ${sports.join(", ")}.`
      : "",
    userText(
      `Einschränkungen/Beschwerden (Übungen meiden, die das belasten): ${text(input.limitations, 300) || "keine"}.`,
    ),
    favorites.length ? `Bisher genutzte Übungen (bevorzugen): ${favorites.join(", ")}.` : "",
    lastWeights.length ? `Letzte Gewichte: ${lastWeights.join("; ")}.` : "",
    recent.length
      ? `Tatsächlich geschafft über alle Pläne (neueste zuerst, Maßstab für die Startgewichte): ${recent.join("; ")}.`
      : "",
    notes.length ? `Notizen zu Übungen: ${notes.join("; ")}.` : "",
    observations.length ? "Beobachtungen der Regeln:" : "",
    ...observations.map((line) => `- ${line}`),
    "",
    "Erlaubte Übungen (id | Name | Muskel | Messung | Art) – nur diese IDs verwenden:",
    ...list(input.library, 200, 160).map((line) => `- ${line}`),
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    "Regeln:",
    `- Genau ${days} Routinen (eine je Trainingstag) mit kurzen Namen (max. 30 Zeichen).`,
    "- Jeden großen Muskel (Brust, Rücken, Schultern, Beine) an mindestens zwei Tagen pro Woche, insgesamt " +
      "etwa 10–20 Sätze pro Muskel und Woche; Schwerpunkt-Muskeln eher am oberen Ende.",
    "- Grundübungen zuerst, Isolationsübungen danach. 2–4 Sätze je Übung, so viele Übungen, dass die Zeit reicht " +
      "(etwa 8 Minuten je Übung inkl. Pausen).",
    "- pause in Sekunden: Grundübungen 120–180, Isolation 60–90. Bei Messung „Sekunden“ sind wdh_min/wdh_max " +
      "Sekunden.",
    "- hinweise: 2–4 kurze Sätze zur Umsetzung (Aufteilung, Steigerung, Erholung), keine erfundenen Zahlen.",
    `Antworte ausschließlich mit JSON. ${PLAN_SHAPE}`,
    "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ]
    .filter((line) => line !== "")
    .join("\n");
}

/** Form prüfen: nur erlaubte IDs, Listen begrenzt; Hinweise mit fremden Zahlen fallen weg. */
export function checkGymPlan(output: unknown, promptText: string, input: Record<string, unknown>): unknown {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const allowed = libraryIDs(input);
  const routinen = (Array.isArray(record.routinen) ? record.routinen : [])
    .slice(0, 6)
    .map((raw) => {
      const value = (typeof raw === "object" && raw !== null ? raw : {}) as Record<string, unknown>;
      const uebungen = (Array.isArray(value.uebungen) ? value.uebungen : [])
        .filter((item) => allowed.has(text((item as Record<string, unknown> | null)?.id, 60)))
        .slice(0, 12);
      return { name: text(value.name, 40), uebungen };
    })
    .filter((routine) => routine.uebungen.length > 0);
  if (routinen.length === 0) throw new GroundingError("KI-Antwort enthielt keine gültigen Routinen");
  const known = numbersIn(withoutUserText(promptText));
  const hinweise = list(record.hinweise, 5, 300).filter((line) =>
    [...numbersIn(line)].every((n) => known.has(n)),
  );
  return { routinen, hinweise };
}

/** Muskelgruppen wie `MuscleGroup` in der App (Rohwerte). */
const MUSCLE_GROUPS = [
  "Brust",
  "Rücken",
  "Schultern",
  "Bizeps",
  "Trizeps",
  "Beine",
  "Rumpf",
  "Unterarme",
  "Sonstige",
];

const IMPORT_SHAPE = `Antwortformat (JSON):
{"titel": str, "tag": number|null, "monat": number|null, "jahr": number|null, "start": "HH:MM"|null,
"ende": "HH:MM"|null, "uebungen": [{"name": str, "id": str|null, "gruppe": str|null,
"saetze": [{"wdh": number|null, "kg": number|null, "sekunden": number|null}]}]}`;

/**
 * Krafttraining von Screenshots einer anderen App ablesen (z. B. WHOOP Strength Trainer, dessen Sätze die WHOOP-API
 * nicht herausgibt). Die App schickt ihre Übungsbibliothek („id | Name“), damit die KI bekannte Übungen zuordnet;
 * Unbekanntes legt die App als eigene Übung an. Die KI liest nur ab, sie schätzt nichts.
 */
export function gymImportPrompt(input: Record<string, unknown>, images: number): string {
  const library = list(input.library, 200, 120);
  const note = text(input.text, 300);
  return [
    `Du liest ein Krafttraining von ${images > 1 ? `${images} Screenshots` : "einem Screenshot"} einer ` +
      "Trainings-App ab (z. B. WHOOP Strength Trainer, Hevy, Strong) und antwortest NUR mit JSON.",
    images > 1
      ? "Die Screenshots gehören zu derselben Einheit; Übungen, die auf zwei Bildern stehen, nur einmal."
      : "",
    "",
    "Regeln:",
    "- Nur übernehmen, was zu lesen ist. Nichts schätzen oder ergänzen; Unleserliches als null.",
    "- Jeder Satz einzeln: „3 × 10 @ 60 kg“ sind drei Sätze mit 10 Wdh. und 60 kg. Aufwärmsätze mitnehmen.",
    "- Gewicht in kg; lbs umrechnen (× 0,4536). Körpergewicht ohne Zusatzgewicht: kg = 0.",
    "- Zeitübungen (Plank, Halten): sekunden statt wdh.",
    "- Summen (Volumenlast, Wiederholungen insgesamt, Kalorien, Strain, Herzfrequenz) sind keine Sätze.",
    "- name: Übungsname wie auf dem Bild (auf Deutsch übersetzen, wenn er englisch ist).",
    "- id: passende Übung aus der Bibliothek unten, nur bei gleichem Bewegungsablauf und Gerät; sonst null.",
    `- gruppe: bei id null die Hauptmuskelgruppe, genau eines von: ${MUSCLE_GROUPS.join(", ")}; sonst null.`,
    "- Datum und Uhrzeit nur, wenn sie auf dem Bild stehen (z. B. „19. Nov. 07:16 bis 08:09“ → tag 19, monat 11, " +
      'start "07:16", ende "08:09"); jahr nur, wenn es dasteht.',
    '- titel: Name der Einheit, falls zu sehen (z. B. „Oberkörper“), sonst "".',
    "",
    "Bibliothek (id | Name):",
    ...(library.length ? library.map((line) => `- ${line}`) : ["- keine"]),
    ...(note ? ["", `Hinweis der Person: ${userText(note)}`] : []),
    "",
    IMPORT_SHAPE,
  ]
    .filter((line, index, all) => line !== "" || all[index - 1] !== "")
    .join("\n");
}

function bounded(value: unknown, max: number, integer = false): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > max) return null;
  return integer ? Math.round(value) : Math.round(value * 100) / 100;
}

function clock(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return hour < 24 && minute < 60 ? `${String(hour).padStart(2, "0")}:${match[2]}` : null;
}

/**
 * Antwort auf das Format prüfen: nur Sätze mit Wiederholungen oder Sekunden in plausiblen Grenzen, IDs nur aus der
 * Bibliothek. Ohne eine einzige Übung mit Satz ist nichts erkannt.
 */
export function checkGymImport(
  output: unknown,
  _promptText: string,
  input: Record<string, unknown>,
): unknown {
  const root = typeof output === "object" && output !== null && !Array.isArray(output) ? output : {};
  const value = root as Record<string, unknown>;
  const ids = new Set(list(input.library, 200, 120).map((line) => line.split("|")[0]?.trim() ?? ""));
  const exercises = (Array.isArray(value.uebungen) ? value.uebungen : []).slice(0, 40).flatMap((raw) => {
    if (typeof raw !== "object" || raw === null) return [];
    const item = raw as Record<string, unknown>;
    const name = text(item.name, 80);
    if (!name) return [];
    const sets = (Array.isArray(item.saetze) ? item.saetze : []).slice(0, 20).flatMap((rawSet) => {
      if (typeof rawSet !== "object" || rawSet === null) return [];
      const set = rawSet as Record<string, unknown>;
      const wdh = bounded(set.wdh, 200, true);
      const sekunden = bounded(set.sekunden, 3600, true);
      if (!wdh && !sekunden) return [];
      return [{ wdh, kg: bounded(set.kg, 1000) ?? 0, sekunden }];
    });
    if (sets.length === 0) return [];
    const id = typeof item.id === "string" && ids.has(item.id.trim()) ? item.id.trim() : null;
    const gruppe =
      !id && typeof item.gruppe === "string" && MUSCLE_GROUPS.includes(item.gruppe) ? item.gruppe : null;
    return [{ name, id, gruppe, saetze: sets }];
  });
  if (exercises.length === 0)
    throw new GroundingError("Auf den Bildern wurden keine Übungen mit Sätzen erkannt.");
  const day = bounded(value.tag, 31, true);
  const month = bounded(value.monat, 12, true);
  const year = bounded(value.jahr, 2100, true);
  return {
    titel: text(value.titel, 60),
    tag: day && day >= 1 ? day : null,
    monat: month && month >= 1 ? month : null,
    jahr: year && year >= 2000 ? year : null,
    start: clock(value.start),
    ende: clock(value.ende),
    uebungen: exercises,
  };
}
