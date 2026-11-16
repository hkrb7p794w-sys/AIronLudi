/**
 * Chat mit dem Coach: Die App schickt die Frage, die letzten Nachrichten und eine Liste fester Fakten aus ihren
 * Regeln (Tagesampel, Plan, Ziele, Schlaf, Ernährung). Die KI antwortet aus diesen Fakten; Zahlen, die weder in
 * der Anfrage stehen noch daraus in derselben Einheit berechnet sind, führen zum Verwerfen der Antwort.
 */
import {
  contradictsRestriction,
  countsIn,
  evidenceBlock,
  evidenceFrom,
  GroundingError,
  hasMeasure,
  isDerived,
  measuresIn,
  numbersIn,
  restrictedToday,
} from "./grounding";
import { list, text, USER_TEXT_RULE } from "./tasks-util";

export const CHAT_SYSTEM = [
  "Du bist ein persönlicher Trainings- und Ernährungscoach. Die Tagesampel und die Ziele entscheiden feste Regeln, " +
    "du erklärst und wendest sie auf die konkrete Frage an.",
  "Verbindlich:",
  "- Beantworte zuerst genau die gestellte Frage, im ersten Satz. Nutze dafür die Fakten mit ihren Zahlen und Daten.",
  "- Erfinde keine Werte. Du darfst Zahlen aus den Fakten addieren, subtrahieren und vergleichen.",
  "- Unterscheide: „gemessen“ und „erfasst“ sind Daten, „berechnet“ ist abgeleitet, „KI-Schätzung“ ist unsicher. " +
    "Fehlt etwas, sage genau, was fehlt, statt allgemein zu antworten.",
  "- Die Herkunftsangaben in Klammern sind Hinweise für dich: nicht in die Antwort übernehmen, außer ein Wert ist " +
    "eine KI-Schätzung.",
  "- Bei einer Empfehlung: konkret, was heute oder morgen zu tun ist, und warum. Der Tagesampel nie widersprechen.",
  "- Bezieht sich die Frage auf das Gespräch („das“, „dann“, „und morgen?“), knüpfe an die letzte Antwort an.",
  "- Beantworte nur Fragen zu Training, Erholung, Schlaf, Ernährung und zur App. Bei anderen Themen sag freundlich, " +
    "wobei du helfen kannst.",
  "- Allgemeine Fachfragen darfst du aus deinem Wissen beantworten, ohne persönliche Zahlen.",
  "- Bei Schmerzen, Brustdruck, Schwindel, Ohnmacht, Verletzungen oder Essstörungen: keine Ferndiagnose, sondern zu " +
    "ärztlicher Abklärung raten und Training bis dahin ruhen lassen. Keine Medikamente.",
  "- Länge passend zur Frage: einfache Fragen ein bis drei Sätze, Analysen höchstens etwa 180 Wörter. Du-Form, keine " +
    "Überschriften, keine Wiederholung der Frage.",
  `- ${USER_TEXT_RULE}`,
].join("\n");

const FREE_NUMBERS = new Set(["0", "1", "2", "3"]);

export function chatPrompt(input: Record<string, unknown>): string {
  const history = Array.isArray(input.history) ? input.history.slice(-10) : [];
  const older = list(input.olderQuestions, 6, 100);
  const lines = history.flatMap((entry) => {
    const record = (typeof entry === "object" && entry !== null ? entry : {}) as Record<string, unknown>;
    const said = text(record.text, 800);
    if (!said) return [];
    return [`${record.role === "coach" ? "Coach" : "Person"}: ${said}`];
  });
  return [
    "Fakten aus der App (zur Frage ausgewählt):",
    ...list(input.facts, 60, 300).map((line) => `- ${line}`),
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    ...(older.length ? [`Frühere Fragen in diesem Gespräch: ${older.join(" | ")}`, ""] : []),
    ...(lines.length ? ["Bisheriger Verlauf:", ...lines, ""] : []),
    `Frage: ${text(input.question, 600) || "(leer)"}`,
    "",
    'Antworte AUSSCHLIESSLICH mit JSON der Form {"antwort": "...", "quellen": ["<id>", ...]}. "quellen" enthält ' +
      "nur ids aus „Belegte Regeln“, auf die sich die Antwort stützt (oder eine leere Liste). Schreibe durchgängig " +
      "in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ].join("\n");
}

/** Prüft die Antwort: nur bekannte Zahlen, nur mitgeschickte Quellen. */
export function groundChat(output: unknown, requestText: string, input: Record<string, unknown>): unknown {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const antwort = text(record.antwort, 1500);
  if (!antwort) throw new GroundingError("Leere Chat-Antwort");
  if (restrictedToday(input) && contradictsRestriction(antwort))
    throw new GroundingError("Chat-Antwort widerspricht der Tagesampel");
  const known = numbersIn(requestText);
  const facts = measuresIn(requestText);
  // Belegt sind Werte aus der Anfrage, Rechnungen daraus in derselben Einheit und Zählgrößen.
  const derived = measuresIn(antwort)
    .filter((claim) => isDerived(claim, facts))
    .map((claim) => String(claim.value));
  const backed = new Set([...known, ...FREE_NUMBERS, ...derived, ...countsIn(antwort)]);
  // Eine Zahl kann belegt sein und trotzdem falsch verwendet werden („8 Wiederholungen“ wird zu „8 kg“).
  const wrongUnit = measuresIn(antwort)
    .filter((claim) => claim.value > 3 && !hasMeasure(claim, facts) && !isDerived(claim, facts))
    .map((claim) => `${claim.value} ${claim.unit}`);
  const unknown = [...[...numbersIn(antwort)].filter((n) => !backed.has(n)), ...wrongUnit];
  if (unknown.length > 0)
    throw new GroundingError(`Chat-Antwort mit unbelegten Zahlen: ${unknown.join(", ")}`);
  const allowed = new Set(evidenceFrom(input).map((item) => item.id));
  const quellen = [...new Set(list(record.quellen, 10, 60))].filter((id) => allowed.has(id));
  return { antwort, quellen };
}
