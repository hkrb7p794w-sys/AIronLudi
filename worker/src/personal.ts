/**
 * Tagesnotiz für das persönliche Profil (ohne Saisonplan): Ziel, Wochenplan und die regelbasierte
 * Empfehlung aus `ScheduleAdvisor`. Keine Wettkampf-, FTP- oder Pace-Werte – die gibt es hier nicht.
 */
import { evidenceBlock, evidenceFrom, POINTS_WITH_SOURCES } from "./grounding";
import { list, text } from "./tasks-util";

const GERMAN = "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).";

function object(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

export function personalNotePrompt(input: Record<string, unknown>): string {
  const decision = object(input.decision);
  const reasons = list(decision.reasons).join("; ");
  const today = list(input.todayItems).join(", ") || "laut Plan frei";
  const missed = list(input.missed).join(", ");
  const sports = list(input.sports).join(", ") || "keine Angabe";
  const vitals = list(input.vitals)
    .map((line) => `- ${line}`)
    .join("\n");
  const event = text(input.event);
  return [
    `Du begleitest eine Person mit dem Ziel „${text(input.goal) || "fit bleiben"}“ (Sportarten: ${sports}).` +
      (event ? ` Wettkampf: ${event}.` : ""),
    "",
    `Heute ist ${text(input.weekday)}. Laut Wochenplan heute: ${today}.`,
    `Diese Woche geschafft: ${text(input.weekDone) || "0"} von ${text(input.weekPlanned) || "0"} Einheiten.` +
      (missed ? ` Verpasst: ${missed} (nicht vorwerfen, nicht nachholen lassen).` : ""),
    "",
    "Erholung:",
    vitals || "- keine Daten",
    `VERBINDLICHE Empfehlung (regelbasiert, nicht ändern): ${text(decision.label) || "keine"} - ` +
      `${text(decision.advice)}${reasons ? ` Gründe: ${reasons}.` : ""}`,
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    `Aufgabe: Erkläre die Empfehlung kurz und konkret. ${POINTS_WITH_SOURCES} ` +
      "2-3 Punkte, je ein Satz, ohne Aufzählungszeichen im Text:",
    "1. Was heute konkret ansteht (passend zur Empfehlung - bei 'lockerer' eine entschärfte Variante, bei frei nichts).",
    "2. Warum - mit den Gründen und belegten Regeln, ohne Rohzahlen aufzuzählen.",
    "3. Optional: ein Satz zum Stand der Woche, ohne zusätzliche Einheiten zu fordern.",
    GERMAN,
  ].join("\n");
}
