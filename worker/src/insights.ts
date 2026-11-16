/**
 * KI-Analyse für den Reiter „AI“: Die App schickt nummerierte Fakten (f1, f2 …), fehlende Daten und die
 * Empfehlungen ihrer Regeln. Die KI fasst daraus Empfehlungen nach Themen; jede muss Fakten nennen, Zahlen müssen in
 * der Anfrage stehen, und den Regeln darf sie nicht widersprechen. Quellen und Datensätze gehören nicht in den Text.
 */
import { GroundingError, numbersIn } from "./grounding";
import { list, text } from "./tasks-util";

const TOPICS = [
  "training",
  "plan",
  "leistung",
  "erholung",
  "ernaehrung",
  "fortschritt",
  "stagnation",
  "handlung",
];
const DIRECTIONS = ["mehr", "weniger", "halten", "aendern", "pruefen"];
const FREE_NUMBERS = new Set(["0", "1", "2", "3", "4", "5", "6", "7", "14", "30"]);
/** Technische Herkunft gehört nicht in die Ansicht („laut Garmin Connect, Datensatz …“). */
const TECHNICAL =
  /\b(datensatz|datenquelle|datenbank|garmin connect|healthkit|apple health|json|fakt(en)? ?f\d+)\b/i;

export const INSIGHTS_SYSTEM = [
  "Du bist ein sachlicher Trainings-, Erholungs- und Ernährungscoach. Feste Regeln der App entscheiden; du fasst " +
    "zusammen und gibst daraus Empfehlungen.",
  "Verbindlich:",
  "- Nur aus den nummerierten Fakten folgern. Keine Werte, Zeiträume, Studien oder Ursachen erfinden.",
  '- Fehlen Daten, sag das in der Empfehlung (sicherheit "niedrig") statt zu raten.',
  "- Den Empfehlungen der Regeln nicht widersprechen und sie nicht wiederholen.",
  "- Schreibe direkt an die Person (du), kurz und konkret: Erkenntnis und was sie tun kann.",
  '- Keine Datenquellen, Geräte, Datensätze oder Fakten-IDs im Text nennen – die gehören nur in "belege".',
  "- Keine Diagnosen, keine Medikamente, keine Nahrungsergänzung ohne Anlass in den Fakten.",
  "Schreibe in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
].join("\n");

function object(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

export function insightsPrompt(input: Record<string, unknown>): string {
  const topic = text(input.thema, 20) || "alle";
  const facts = (Array.isArray(input.fakten) ? input.fakten : []).slice(0, 60).map((item) => {
    const fact = object(item);
    return `${text(fact.id, 6)}: ${text(fact.text, 300)}`;
  });
  const missing = list(input.fehlend, 15, 120);
  const rules = (Array.isArray(input.regeln) ? input.regeln : []).slice(0, 20).map((item) => {
    const rule = object(item);
    return `- ${text(rule.titel, 100)} (Betreff ${text(rule.betreff, 40)}, Richtung ${text(rule.richtung, 10)})`;
  });
  const closed = (Array.isArray(input.bearbeitet) ? input.bearbeitet : []).slice(0, 20).map((item) => {
    const entry = object(item);
    return `- ${text(entry.titel, 100)} (Betreff ${text(entry.betreff, 40)}, ${text(entry.stand, 12)})`;
  });
  return [
    topic === "alle"
      ? "Analysiere alle Bereiche und gib die wichtigsten Empfehlungen (höchstens 6)."
      : `Analysiere nur das Thema „${topic}“ und gib höchstens 4 Empfehlungen.`,
    "",
    "Fakten:",
    facts.length ? facts.join("\n") : "(keine)",
    "",
    "Fehlende Daten:",
    missing.length ? missing.map((line) => `- ${line}`).join("\n") : "(keine)",
    "",
    "Empfehlungen der Regeln (nicht widersprechen, nicht wiederholen):",
    rules.length ? rules.join("\n") : "(keine)",
    "",
    "Bereits bearbeitet (Verworfenes nicht erneut vorschlagen; bei Umgesetztem die Wirkung bewerten, wenn Fakten sie zeigen):",
    closed.length ? closed.join("\n") : "(keine)",
    "",
    `Themen: ${TOPICS.join(", ")}. Richtung: ${DIRECTIONS.join(", ")}.`,
    'Antwortformat (JSON): {"empfehlungen": [{"thema": str, "betreff": str (1–3 Wörter, z. B. "bankdrücken", ' +
      '"schlaf", "protein"), "titel": str (max. 60 Zeichen), "text": str (1–3 Sätze), "richtung": str, ' +
      '"prioritaet": 1|2|3, "gueltig_tage": 1–14, "sicherheit": "hoch|mittel|niedrig", "belege": ["f1", …]}]}',
  ].join("\n");
}

/** Prüft jede Empfehlung: bekannte Belege, belegte Zahlen, kein Widerspruch zu einer Regel, kein Technik-Jargon. */
/** Andere Wörter für dasselbe Thema, sonst widerspricht „nachtschlaf“ einer Regel zu „schlaf“ unbemerkt. */
const SAME_SUBJECT: [RegExp, string][] = [
  [/schlaf|bettzeit/, "schlaf"],
  [/protein|eiwei/, "protein"],
  [/kalorien|energie|kcal/, "kalorien"],
  [/erholung|regeneration|ruhetag/, "erholung"],
  [/gewicht|abnehm|zunehm/, "gewicht"],
];

function sameSubject(value: string): string {
  const lower = value.toLowerCase();
  return SAME_SUBJECT.find(([pattern]) => pattern.test(lower))?.[1] ?? lower;
}

export function groundInsights(
  output: unknown,
  requestText: string,
  input: Record<string, unknown>,
): unknown {
  const record = object(output);
  const raw = Array.isArray(record.empfehlungen) ? record.empfehlungen.slice(0, 8) : [];
  const factIDs = new Set(
    (Array.isArray(input.fakten) ? input.fakten : []).map((item) => text(object(item).id, 6)).filter(Boolean),
  );
  const rules = (Array.isArray(input.regeln) ? input.regeln : []).map((item) => object(item));
  const known = numbersIn(requestText);
  const empfehlungen = raw
    .map((item) => object(item))
    .filter((item) => {
      if (!TOPICS.includes(text(item.thema, 20))) return false;
      const belege = list(item.belege, 8, 6).filter((id) => factIDs.has(id));
      if (belege.length === 0) return false;
      item.belege = belege;
      const body = `${text(item.titel, 120)} ${text(item.text, 600)}`;
      if (TECHNICAL.test(body)) return false;
      if (![...numbersIn(body)].every((n) => known.has(n) || FREE_NUMBERS.has(n))) return false;
      const subject = sameSubject(text(item.betreff, 40));
      const direction = text(item.richtung, 10);
      return !rules.some(
        (rule) => sameSubject(text(rule.betreff, 40)) === subject && text(rule.richtung, 10) !== direction,
      );
    });
  if (empfehlungen.length === 0) throw new GroundingError("KI-Antwort enthielt keine belegte Empfehlung");
  return { empfehlungen, verworfen: raw.length - empfehlungen.length };
}
