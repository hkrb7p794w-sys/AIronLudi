/**
 * Schutz gegen erfundene Inhalte: Die KI formuliert nur, was die App als Fakten schickt.
 *
 * 1. Systemanweisung: nur Fakten aus der Anfrage, keine neuen Zahlen, Einheiten oder Quellen.
 * 2. Prüfung der Antwort: Jede Zahl in einem Punkt muss in der Anfrage vorkommen (0–3 sind als
 *    Zählwörter frei), genannte Quellen müssen zu den mitgeschickten Regeln gehören. Unbelegte
 *    Punkte werden verworfen; bleibt keiner übrig, gilt die Antwort als unbelegt und die App
 *    zeigt die regelbasierte Notiz.
 */
import { list, text, USER_TEXT_RULE, withoutUserText } from "./tasks-util";

export const GROUNDING_SYSTEM = [
  "Du bist ein sachlicher Ausdauer- und Ernährungscoach. Du FORMULIERST nur – entschieden haben feste Regeln.",
  "Verbindlich:",
  "- Verwende ausschließlich Fakten, Zahlen und Einheiten aus der Anfrage. Erfinde keine Werte, Paces, Wattzahlen, " +
    "Zeiten, Studien oder Quellen.",
  "- Begründungen nur mit den mitgeschickten belegten Regeln (Abschnitt „Belegte Regeln“). Wenn etwas dort nicht " +
    "steht, lass es weg statt zu spekulieren.",
  "- Keine Diagnosen, keine Medikamente, keine Nahrungsergänzung ohne Anlass in den Fakten.",
  "- Nie mehr Training oder zusätzliche Einheiten fordern; verpasste Einheiten nicht vorwerfen.",
  "- Lieber kurz und richtig als ausführlich.",
  `- ${USER_TEXT_RULE}`,
].join("\n");

export interface EvidenceItem {
  id: string;
  statement: string;
}

/** Belegte Regeln aus der App-Eingabe (`evidence: [{id, statement}]`). */
export function evidenceFrom(input: Record<string, unknown>): EvidenceItem[] {
  if (!Array.isArray(input.evidence)) return [];
  return input.evidence.slice(0, 20).flatMap((item) => {
    const record = (typeof item === "object" && item !== null ? item : {}) as Record<string, unknown>;
    const id = text(record.id, 60);
    const statement = text(record.statement, 400);
    return id && statement ? [{ id, statement }] : [];
  });
}

export function evidenceBlock(items: EvidenceItem[]): string {
  if (items.length === 0) return "";
  return ["Belegte Regeln (id: Aussage):", ...items.map((item) => `- ${item.id}: ${item.statement}`)].join(
    "\n",
  );
}

export const POINTS_WITH_SOURCES =
  'Antworte AUSSCHLIESSLICH mit JSON der Form {"punkte": ["...", "..."], "quellen": ["<id>", ...]}. ' +
  '"quellen" enthält nur ids aus „Belegte Regeln“, auf die sich deine Punkte stützen (oder eine leere Liste).';

export class GroundingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GroundingError";
  }
}

/** Liest eine Zahl in deutscher Schreibweise („4,8“ → 4.8, „1.200“ → 1200). */
function parseNumber(value: string): number {
  return /^\d{1,3}(\.\d{3})+$/.test(value)
    ? Number(value.replace(/\./g, ""))
    : Number(value.replace(",", "."));
}

/** Zahlen eines Textes, normalisiert („4,8“ → „4.8“, „12,0“ → „12“). */
export function numbersIn(value: string): Set<string> {
  const result = new Set<string>();
  for (const match of value.matchAll(/\d{1,3}(?:\.\d{3})+(?!\d)|\d+(?:[.,]\d+)?/g)) {
    const normalized = parseNumber(match[0]);
    if (Number.isFinite(normalized)) result.add(String(normalized));
  }
  return result;
}

export interface Measure {
  value: number;
  unit: string;
}

const UNITS: Record<string, string> = { minuten: "min", stunden: "h", std: "h", prozent: "%" };
const MEASURE =
  /(\d+(?:[.,]\d+)?)\s*(kg|kcal|km|minuten|min|stunden|std|prozent|%|bpm|ms|g|h)(?![a-zäöüß])/gi;

/** Zahlen mit Einheit: Nur gleiche Einheiten dürfen miteinander verrechnet werden. */
export function measuresIn(value: string): Measure[] {
  return [...value.matchAll(MEASURE)].map((match) => {
    const unit = (match[2] ?? "").toLowerCase();
    return { value: parseNumber(match[1] ?? ""), unit: UNITS[unit] ?? unit };
  });
}

/** Steht genau dieser Wert mit dieser Einheit in den belegten Angaben? */
export function hasMeasure(claim: Measure, known: Measure[]): boolean {
  return known.some((item) => item.unit === claim.unit && item.value === claim.value);
}

/** Ist die Zahl das Ergebnis einer einfachen Rechnung aus belegten Werten derselben Einheit? */
export function isDerived(claim: Measure, known: Measure[]): boolean {
  const close = (a: number, b: number) => Math.abs(a - b) < 0.051;
  if (claim.unit === "%") {
    return known.some((a) =>
      known.some(
        (b) =>
          a.unit === b.unit &&
          b.value > 0 &&
          (Math.round((a.value / b.value) * 100) === claim.value ||
            Math.round((Math.abs(a.value - b.value) / b.value) * 100) === claim.value),
      ),
    );
  }
  const same = known.filter((item) => item.unit === claim.unit);
  return same.some((a) =>
    same.some(
      (b) => close(Math.abs(a.value - b.value), claim.value) || close(a.value + b.value, claim.value),
    ),
  );
}

const COUNTED =
  /(\d{1,2})(?:\s*(?:-|–|bis)\s*(\d{1,2}))?\s*(?:sätze|satz|wiederholungen|wdh|tage|tagen|wochen|einheiten|mahlzeiten|portionen|nächte|nächten|monate|monaten|mal)(?![a-zäöüß])/gi;

/** Kleine Mengen vor einer Zählgröße („8–12 Wiederholungen“) sind Empfehlungen, keine Messwerte. */
export function countsIn(value: string): Set<string> {
  const result = new Set<string>();
  for (const match of value.matchAll(COUNTED)) {
    for (const part of [match[1], match[2]]) {
      if (part && Number(part) <= 20) result.add(String(Number(part)));
    }
  }
  return result;
}

const HARD_EFFORT = /\b(hart(e[nrsm]?)?|intervall\w*|schwelle\w*|tempo\w*|durchziehen|vollgas)\b/i;
const NOT_TODAY =
  /\b(nicht|kein\w*|statt|anstatt|ohne|lieber|verzicht\w*|vermeide\w*|weniger|nein|verschieb\w*|morgen|nächste\w*|später|wenn|falls|locker\w*)\b/i;

/** Hat die Tagesampel heute nur lockeres Training oder Ruhe erlaubt? */
export function restrictedToday(input: Record<string, unknown>): boolean {
  const decision = input.decision;
  const label =
    typeof decision === "object" && decision !== null
      ? text((decision as Record<string, unknown>).label, 80)
      : text(decision, 80);
  const line = list(input.facts, 60, 300).find((fact) => /Tagesampel heute/i.test(fact)) ?? "";
  return [label, text(input.recovery, 120), line].some((value) => /ruhetag|locker/i.test(value));
}

/** Fordert ein Satz hartes Training für heute, obwohl die Regel das ausschließt? Verneinungen zählen nicht. */
export function contradictsRestriction(value: string): boolean {
  return value.split(/[.!?]+/).some((sentence) => HARD_EFFORT.test(sentence) && !NOT_TODAY.test(sentence));
}

const FREE_NUMBERS = new Set(["0", "1", "2", "3"]);

export interface GroundedPoints {
  punkte: string[];
  quellen: string[];
  verworfen: number;
}

/** Prüft `{"punkte": [...], "quellen": [...]}` gegen den Anfragetext und die erlaubten Quellen. */
export function groundPoints(
  output: unknown,
  promptText: string,
  allowedSources: string[],
  restricted = false,
): GroundedPoints {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const raw = list(Array.isArray(record.punkte) ? record.punkte : output, 6, 600);
  const known = numbersIn(withoutUserText(promptText));
  const punkte = raw.filter(
    (point) =>
      [...numbersIn(point)].every((n) => known.has(n) || FREE_NUMBERS.has(n)) &&
      !(restricted && contradictsRestriction(point)),
  );
  if (punkte.length === 0) throw new GroundingError("KI-Antwort enthielt nur unbelegte Aussagen");
  const allowed = new Set(allowedSources);
  const quellen = [...new Set(list(record.quellen, 10, 60))].filter((id) => allowed.has(id));
  return { punkte, quellen, verworfen: raw.length - punkte.length };
}
