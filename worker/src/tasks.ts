/**
 * Aufgaben (Prompts) liegen im Worker, nicht in der App: Prompt-Änderungen brauchen so nur einen
 * Worker-Deploy und keine neue App-Version. Die App schickt nur abgeleitete Werte (Datenschutzmodus
 * „reduziert“ entscheidet die App, bevor sie sendet).
 *
 * Regel aus dem Altbestand: Die Regeln entscheiden, die KI formuliert nur.
 */

import { CHAT_SYSTEM, chatPrompt, groundChat } from "./chat";
import {
  evidenceBlock,
  evidenceFrom,
  GROUNDING_SYSTEM,
  groundPoints,
  POINTS_WITH_SOURCES,
  restrictedToday,
} from "./grounding";
import { checkGymPlan, gymHintsPrompt, gymPlanPrompt } from "./gym";
import { groundInsights, INSIGHTS_SYSTEM, insightsPrompt } from "./insights";
import {
  groundAmend,
  groundMeal,
  labelPrompt,
  mealAmendPrompt,
  mealPrompt,
  nutritionReviewPrompt,
} from "./nutrition";
import { personalNotePrompt } from "./personal";
import { athleteProfile } from "./profile";
import {
  checkCookPlan,
  checkMealNow,
  checkPantryRecipes,
  checkRecipes,
  cookPlanPrompt,
  mealNowPrompt,
  pantryRecipesPrompt,
  weeklyRecipesPrompt,
} from "./recipes";
import { list, text, USER_TEXT_RULE } from "./tasks-util";

export { list, text } from "./tasks-util";

export interface TaskDefinition {
  json: boolean;
  allowImages: boolean;
  /** Niedrig für sachliche Texte: weniger Ausschmückung, weniger Erfundenes. */
  temperature?: number;
  /** Mehr Platz für lange Antworten (Standard 4096 Tokens). */
  maxOutputTokens?: number;
  /** Große JSON-Antworten: wenig Denk-Tokens, damit das Antwortlimit für den Inhalt reicht. */
  lowThinking?: boolean;
  build(input: Record<string, unknown>, images: number): { system?: string; prompt: string };
  /** Prüft die Antwort gegen die Anfrage (siehe grounding.ts); wirft GroundingError, wenn nichts belegt ist. */
  ground?(output: unknown, requestText: string, input: Record<string, unknown>): unknown;
}

/** Punkte nur mit Zahlen aus der Anfrage und Quellen aus den mitgeschickten Regeln. */
function groundedPoints(output: unknown, requestText: string, input: Record<string, unknown>): unknown {
  return groundPoints(
    output,
    requestText,
    evidenceFrom(input).map((item) => item.id),
    restrictedToday(input),
  );
}

const GERMAN = "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).";

function object(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function km(value: unknown): string {
  return typeof value === "number" && Number.isFinite(value)
    ? `${value.toFixed(1).replace(".", ",")} km`
    : "–";
}

/** Tages-Coaching-Notiz (Portierung von `generate_coaching_note`, garmin_ai_coach/ai_coach.py). */
export function dailyNotePrompt(input: Record<string, unknown>): string {
  const decision = object(input.decision);
  const volumes = object(input.volumes);
  const today = list(input.todayItems).join(", ") || "nichts Festes";
  const open = list(input.openItems).join(", ") || "nichts";
  const daysLeft = typeof input.daysLeftInWeek === "number" ? input.daysLeftInWeek : undefined;
  const reasons = list(decision.reasons).join("; ");
  const decisionText = decision.label
    ? `${text(decision.label)} - ${text(decision.advice)} Gründe: ${reasons}.`
    : "keine";
  const vitals = list(input.vitals)
    .map((line) => `- ${line}`)
    .join("\n");

  return [
    "Du bist ein Ausdauersport-Coach für einen Age-Group-Athleten in der Vorbereitung auf die " +
      `${text(input.raceName)} am ${text(input.raceDate)}. Zielzeit: ${text(input.raceGoal)}.`,
    "",
    athleteProfile(text(input.testValues)),
    "",
    `Heute ist ${text(input.weekday)}. Trainingsphase: ${text(input.phase)} (Fokus: ${text(input.phaseFocus)}). ` +
      `Noch ${text(input.daysToRace)} Tage bis zum Rennen.`,
    `Plan dieser Phase: ${text(input.phaseDetail, 1500)}`,
    `Laut Wochenrahmen heute: ${today}. Diese Woche noch offen: ${open} ` +
      `(noch ${daysLeft ?? "?"} Tage in der Woche).`,
    ...(daysLeft === 0
      ? [
          "Heute ist der LETZTE Tag der Woche: Offenes kann nicht mehr nachgeholt werden - nichts auf spätere " +
            'Tage dieser Woche verschieben und nicht von einem "frischen Tag" sprechen; was bei der ' +
            "Tagesentscheidung nicht mehr geht, entfällt diese Woche.",
        ]
      : []),
    `Wochenvolumen bisher: Schwimmen ${km(volumes.swimKm)}, Rad ${km(volumes.bikeKm)}, Lauf ${km(volumes.runKm)}.`,
    "",
    "Erholung:",
    vitals || "- keine Daten",
    `VERBINDLICHE Tagesentscheidung (regelbasiert, nicht ändern): ${decisionText}`,
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    `Aufgabe: Formuliere daraus eine kurze, konkrete Umsetzung für heute. ${POINTS_WITH_SOURCES} ` +
      "2-3 Punkte, je ein Satz, ohne Aufzählungszeichen im Text:",
    "1. Was heute konkret trainiert wird (passend zu Wochentag, offener Woche und der " +
      "Tagesentscheidung - bei 'locker' eine entschärfte Variante, bei 'Ruhetag' nichts Hartes). " +
      "Einheiten mit dem Zusatz 'schon erledigt' nicht noch einmal verordnen.",
    "2. Ein Satz zur Einordnung der Erholung (keine Rohzahlen aufzählen).",
    "3. Optional: ein Hinweis, wie die offene Woche im bestehenden Rahmen noch sinnvoll " +
      "aufgeht - keine zusätzlichen Einheiten fordern.",
    GERMAN,
  ].join("\n");
}

export const TASKS: Record<string, TaskDefinition> = {
  /** Verbindungstest aus den App-Einstellungen. */
  ping: {
    json: true,
    allowImages: false,
    build: () => ({
      prompt: `Antworte ausschließlich mit JSON der Form {"ok": true, "gruss": "<ein kurzer Satz>"}. ${GERMAN}`,
    }),
  },
  /** Tagesnotiz zur regelbasierten Tagesampel. */
  daily_note: {
    json: true,
    allowImages: false,
    temperature: 0.2,
    build: (input) => ({ system: GROUNDING_SYSTEM, prompt: dailyNotePrompt(input) }),
    ground: groundedPoints,
  },
  /** Tagesnotiz für das persönliche Profil (ohne Saisonplan). */
  personal_note: {
    json: true,
    allowImages: false,
    temperature: 0.2,
    build: (input) => ({ system: GROUNDING_SYSTEM, prompt: personalNotePrompt(input) }),
    ground: groundedPoints,
  },
  /** Mahlzeit per Foto und/oder Text in Positionen mit Nährwerten zerlegen. */
  meal_analyze: {
    json: true,
    allowImages: true,
    temperature: 0.2,
    // Je Position rund 20 Nährwerte; mehrere Mahlzeiten in einer Eingabe sprengen sonst das Standardbudget.
    maxOutputTokens: 12000,
    build: (input, images) => ({ system: USER_TEXT_RULE, prompt: mealPrompt(input, images > 0) }),
    ground: groundMeal,
  },
  /** Erkannte Mahlzeit ergänzen („noch 150 g Hähnchen und 1 EL Öl“): nur neue Positionen. */
  meal_amend: {
    json: true,
    allowImages: true,
    temperature: 0.2,
    maxOutputTokens: 6000,
    build: (input, images) => ({ system: USER_TEXT_RULE, prompt: mealAmendPrompt(input, images > 0) }),
    ground: groundAmend,
  },
  /** Nährwerttabelle vom Foto ablesen (Barcode unbekannt); nur Bild, keine Gesundheitsdaten. */
  nutrition_label: {
    json: true,
    allowImages: true,
    temperature: 0,
    build: () => ({ prompt: labelPrompt() }),
  },
  /** Ernährung und Training des Tages gemeinsam auswerten. */
  nutrition_review: {
    json: true,
    allowImages: false,
    temperature: 0.2,
    build: (input) => ({ system: GROUNDING_SYSTEM, prompt: nutritionReviewPrompt(input) }),
    ground: groundedPoints,
  },
  /** Hinweise zur Gewichtssteigerung aus den Progressionsregeln. */
  gym_hints: {
    json: true,
    allowImages: false,
    temperature: 0.2,
    build: (input) => ({ system: GROUNDING_SYSTEM, prompt: gymHintsPrompt(input) }),
    ground: groundedPoints,
  },
  /** Individueller Trainingsplan aus Fragebogen und Verlauf; die App prüft ihn mit ihren Regeln. */
  gym_plan: {
    json: true,
    allowImages: false,
    temperature: 0.3,
    maxOutputTokens: 8000,
    build: (input) => ({ system: USER_TEXT_RULE, prompt: gymPlanPrompt(input) }),
    ground: checkGymPlan,
  },
  /** Chat mit dem Coach, nur aus den Fakten der App. */
  coach_chat: {
    json: true,
    allowImages: false,
    temperature: 0.3,
    // Denk-Tokens zählen mit; 4.096 führten bei längeren Antworten zum Abschneiden.
    maxOutputTokens: 8000,
    build: (input) => ({ system: CHAT_SYSTEM, prompt: chatPrompt(input) }),
    ground: groundChat,
  },
  /** Reiter „AI“: Empfehlungen nach Themen aus nummerierten Fakten, jede mit Belegen. */
  ai_insights: {
    json: true,
    allowImages: false,
    temperature: 0.2,
    maxOutputTokens: 6000,
    build: (input) => ({ system: INSIGHTS_SYSTEM, prompt: insightsPrompt(input) }),
    ground: groundInsights,
  },
  /** „Was jetzt?“: drei Gerichte zu den übrigen Tagesmakros (Ziele rechnet die App). */
  meal_now: {
    json: true,
    allowImages: false,
    temperature: 0.6,
    maxOutputTokens: 6000,
    lowThinking: true,
    build: (input) => ({ system: USER_TEXT_RULE, prompt: mealNowPrompt(input) }),
    ground: checkMealNow,
  },
  /** Rezeptideen für die kommende Woche zu den Tageszielen der App. */
  weekly_recipes: {
    json: true,
    allowImages: false,
    temperature: 0.6,
    maxOutputTokens: 16000,
    lowThinking: true,
    build: (input) => ({ system: USER_TEXT_RULE, prompt: weeklyRecipesPrompt(input) }),
    ground: checkRecipes,
  },
  /** Rezepte aus dem Foto von Kühlschrank oder Vorrat, mit kleinen fehlenden Zutaten für die Rückfrage der App. */
  pantry_recipes: {
    json: true,
    allowImages: true,
    temperature: 0.5,
    maxOutputTokens: 9000,
    lowThinking: true,
    build: (input, images) => ({ system: USER_TEXT_RULE, prompt: pantryRecipesPrompt(input, images) }),
    ground: checkPantryRecipes,
  },
  /** Kochen für eine oder zwei Personen, auch zum Vorkochen. Teller und Mengen rechnet die App. */
  cook_plan: {
    json: true,
    allowImages: false,
    temperature: 0.6,
    maxOutputTokens: 8000,
    lowThinking: true,
    build: (input) => ({ system: USER_TEXT_RULE, prompt: cookPlanPrompt(input) }),
    ground: checkCookPlan,
  },
};

export function findTask(name: unknown): TaskDefinition | undefined {
  return typeof name === "string" && Object.hasOwn(TASKS, name) ? TASKS[name] : undefined;
}
