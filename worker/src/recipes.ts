/**
 * Rezeptideen für die kommende Woche. Die App schickt je Tag Ziele aus ihren Regeln (Energie, Protein,
 * Kohlenhydrate je Trainingstag), Ernährungsweise, Allergene und Lücken der letzten Wochen. Die KI schlägt Gerichte
 * vor; die App prüft Ernährungsweise und Allergene erneut und passt die Mengen ans Tagesziel an.
 */
import { evidenceBlock, evidenceFrom, GroundingError } from "./grounding";
import { list, text, userText } from "./tasks-util";

const DIET_TEXT: Record<string, string> = {
  alles: "Mischkost (alles erlaubt).",
  pescetarisch: "Pescetarisch: kein Fleisch und keine Wurst, Fisch und Meeresfrüchte erlaubt.",
  vegetarisch: "Vegetarisch: kein Fleisch, keine Wurst, kein Fisch, keine Meeresfrüchte.",
  vegan: "Vegan: keine tierischen Produkte (kein Fleisch, Fisch, Ei, Milchprodukte, Honig).",
};

const MAX_PARTIAL_DAYS = 3;

const SHAPE = `Antwortformat (JSON):
{"tage": [{"datum": "JJJJ-MM-TT", "gerichte": [{"mahlzeit": "fruehstueck|mittagessen|abendessen|snack",
"titel": str, "minuten": number, "zubereitung": [str, ...],
"zutaten": [{"name": str, "menge_g": number, "menge_text": str,
"naehrwerte_100g": {"kcal": number, "protein_g": number, "carbs_g": number, "fat_g": number, "fiber_g": number}}]}]}]}`;

function dayLine(value: unknown): string {
  const day = (typeof value === "object" && value !== null ? value : {}) as Record<string, unknown>;
  const n = (key: string) => (typeof day[key] === "number" ? Math.round(day[key] as number) : "–");
  return (
    `- ${text(day.datum, 10)} (${text(day.wochentag, 12)}): Training ${text(day.training, 120)}; ` +
    `${text(day.tagestyp, 40)}; Ziel ${n("kcal")} kcal, ${n("protein_g")} g Protein, ` +
    `${n("kohlenhydrate_g")} g Kohlenhydrate, ${n("fett_g")} g Fett`
  );
}

export function weeklyRecipesPrompt(input: Record<string, unknown>): string {
  const days = Array.isArray(input.days) ? input.days.slice(0, 7) : [];
  const allergens = list(input.allergens, 10, 40);
  const gaps = list(input.gaps, 8, 120);
  const favorites = list(input.favorites, 15, 60);
  const minutes = typeof input.maxMinutes === "number" ? Math.round(input.maxMinutes) : 30;
  const meals =
    input.snacks === false
      ? "Frühstück, Mittagessen, Abendessen"
      : "Frühstück, Mittagessen, Abendessen, Snack";
  return [
    "Du bist Sporternährungs-Coach und Koch. Erstelle alltagstaugliche Rezeptideen für die genannten Tage.",
    `Ernährungsweise: ${DIET_TEXT[text(input.diet, 20)] ?? "Mischkost."}`,
    `Ziel: ${text(input.goal, 80) || "Gewicht halten"}.`,
    `Allergene/Unverträglichkeiten (strikt meiden, auch in Spuren als Zutat): ${allergens.join(", ") || "keine"}.`,
    userText(`Mag nicht: ${text(input.dislikes, 200) || "nichts angegeben"}.`),
    `Zubereitung höchstens ${minutes} Minuten pro Gericht. Mahlzeiten pro Tag: ${meals}.`,
    input.mealPrep === true
      ? "Meal-Prep: Das Abendessen darf als Mittagessen am Folgetag wiederverwendet werden (gleiches Gericht)."
      : "",
    favorites.length ? `Isst gern bzw. oft (gern einbauen): ${favorites.join(", ")}.` : "",
    gaps.length ? `Lücken der letzten Tage (gezielt ausgleichen): ${gaps.join("; ")}.` : "",
    "",
    "Tagesziele (fest von der App berechnet, nicht ändern). Liefere für JEDEN dieser Tage Gerichte:",
    ...(days.length ? days.map(dayLine) : ["- keine Tage"]),
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    "Regeln:",
    "- Die Gerichte eines Tages zusammen sollen das Energie- und Proteinziel des Tages etwa treffen (±10 %).",
    "- Protein auf die Mahlzeiten verteilen (je Hauptmahlzeit eine gute Proteinquelle).",
    "- An Trainingstagen mit „Harter“ oder „Sehr harter Trainingstag“ mehr Kohlenhydrate (Reis, Nudeln, " +
      "Kartoffeln, Haferflocken, Obst); an Ruhetagen mehr Gemüse.",
    "- Saisonal, abwechslungsreich, mit Zutaten aus dem deutschen Supermarkt; Zutaten über die Woche wiederverwenden, " +
      "damit wenig übrig bleibt.",
    "- menge_g: Menge für eine Person in Gramm (roh, wie eingekauft; Flüssigkeiten in ml = g).",
    "- naehrwerte_100g: deine beste Schätzung je 100 g der Zutat so wie angegeben.",
    "- zubereitung: 2–6 kurze Schritte. titel: max. 40 Zeichen.",
    "- Keine Nahrungsergänzungsmittel, außer der Nutzer nennt sie als Lieblingslebensmittel.",
    `Antworte ausschließlich mit JSON. ${SHAPE}`,
    "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ]
    .filter((line) => line !== "")
    .join("\n");
}

/** Form prüfen: nur Tage aus der Anfrage, Listen begrenzt. Inhaltliche Prüfung macht die App. */
export function checkRecipes(output: unknown, _request: string, input: Record<string, unknown>): unknown {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const wanted = new Set(
    (Array.isArray(input.days) ? input.days : []).map((day) =>
      text((day as Record<string, unknown> | null)?.datum, 10),
    ),
  );
  const tage = (Array.isArray(record.tage) ? record.tage : [])
    .filter((day) => wanted.has(text((day as Record<string, unknown> | null)?.datum, 10)))
    .slice(0, 7)
    .map((day) => {
      const value = day as Record<string, unknown>;
      const gerichte = (Array.isArray(value.gerichte) ? value.gerichte : []).slice(0, 6);
      return { datum: value.datum, gerichte };
    });
  if (tage.length === 0) throw new GroundingError("KI-Antwort enthielt keine passenden Tage");
  // Teilanfragen (bis 3 Tage) müssen vollständig sein; der nächste Anbieter liefert sonst die fehlenden Tage.
  if (wanted.size <= MAX_PARTIAL_DAYS && tage.length < wanted.size) {
    throw new GroundingError(`KI-Antwort enthielt nur ${tage.length} von ${wanted.size} Tagen`);
  }
  return { tage };
}

const MEAL_LABEL: Record<string, string> = {
  fruehstueck: "Frühstück",
  mittagessen: "Mittagessen",
  abendessen: "Abendessen",
  snack: "Snack",
};

const NOW_SHAPE = `Antwortformat (JSON):
{"gerichte": [{"mahlzeit": "fruehstueck|mittagessen|abendessen|snack", "titel": str, "minuten": number,
"zubereitung": [str, ...], "zutaten": [{"name": str, "menge_g": number, "menge_text": str, "gruppe": str,
"naehrwerte_100g": {"kcal": number, "protein_g": number, "carbs_g": number, "fat_g": number, "fiber_g": number}}]}]}`;

/** „Was jetzt?“: drei Gerichte für die nächste Mahlzeit, passend zu dem, was heute noch übrig ist. */
export function mealNowPrompt(input: Record<string, unknown>): string {
  const n = (key: string) => (typeof input[key] === "number" ? Math.round(input[key] as number) : "–");
  const allergens = list(input.allergens, 10, 40);
  const pantry = list(input.pantry, 30, 60);
  const favorites = list(input.favorites, 15, 60);
  const minutes = typeof input.maxMinutes === "number" ? Math.round(input.maxMinutes) : 30;
  const meal = MEAL_LABEL[text(input.mahlzeit, 20)] ?? "nächste Mahlzeit";
  return [
    "Du bist Sporternährungs-Coach und Koch. Schlage genau drei Gerichte für die nächste Mahlzeit vor.",
    `Mahlzeit: ${meal}.`,
    `Ziel dieser Mahlzeit (von der App berechnet, nicht ändern): ${n("kcal")} kcal, ${n("protein_g")} g Protein, ` +
      `${n("carbs_g")} g Kohlenhydrate, ${n("fat_g")} g Fett.`,
    `Ernährungsweise: ${DIET_TEXT[text(input.diet, 20)] ?? "Mischkost."}`,
    `Allergene/Unverträglichkeiten (strikt meiden): ${allergens.join(", ") || "keine"}.`,
    userText(`Mag nicht: ${text(input.dislikes, 200) || "nichts angegeben"}.`),
    `Zubereitung höchstens ${minutes} Minuten.`,
    pantry.length
      ? `Vorrat (vorrangig verwenden, mindestens ein Gericht nur daraus plus Grundzutaten): ${pantry.join(", ")}.`
      : "",
    favorites.length ? `Isst gern: ${favorites.join(", ")}.` : "",
    "",
    "Regeln:",
    "- Jedes Gericht soll das Ziel etwa treffen (±10 %), vor allem Energie und Protein.",
    "- Drei unterschiedliche Ideen (z. B. schnell, warm, ohne Kochen).",
    "- menge_g: Menge für eine Person in Gramm (roh, wie eingekauft; Flüssigkeiten in ml = g).",
    "- naehrwerte_100g: deine beste Schätzung je 100 g der Zutat so wie angegeben.",
    "- gruppe: gemuese, obst, vollkorn, getreide, kartoffel, huelsenfruechte, nuesse, milch, fisch_fett, fisch, " +
      "ei, fleisch, fett, suess, getraenk oder sonstiges.",
    "- zubereitung: 2–5 kurze Schritte. titel: max. 40 Zeichen.",
    `Antworte ausschließlich mit JSON. ${NOW_SHAPE}`,
    "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ]
    .filter((line) => line !== "")
    .join("\n");
}

/** Form prüfen: höchstens drei Gerichte. Ernährungsweise, Allergene und Mengen prüft die App. */
export function checkMealNow(output: unknown): unknown {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const gerichte = (Array.isArray(record.gerichte) ? record.gerichte : []).slice(0, 3);
  if (gerichte.length === 0) throw new GroundingError("KI-Antwort enthielt keine Gerichte");
  return { gerichte };
}

const PANTRY_SHAPE = `Antwortformat (JSON):
{"erkannt": [str, ...], "gerichte": [{"mahlzeit": "fruehstueck|mittagessen|abendessen|snack", "titel": str,
"minuten": number, "zubereitung": [str, ...], "zutaten": [{"name": str, "menge_g": number, "menge_text": str,
"gruppe": str, "naehrwerte_100g": {"kcal": number, "protein_g": number, "carbs_g": number, "fat_g": number,
"fiber_g": number}}], "fehlt": [str, ...]}]}`;

/**
 * Rezepte aus einem Foto von Kühlschrank oder Vorratsschrank. Die KI erkennt die Lebensmittel und schlägt
 * naheliegende Gerichte vor; fehlen nur ein oder zwei kleine Standardzutaten, nennt sie diese unter `fehlt`, statt
 * das Gericht zu verwerfen – die App fragt dann nach („Ist noch Butter da?“) und prüft Ernährungsweise, Allergene
 * und die Zahl der fehlenden Zutaten selbst (`PantryRecipes` in der App).
 */
export function pantryRecipesPrompt(input: Record<string, unknown>, images: number): string {
  const allergens = list(input.allergens, 12, 40);
  const pantry = list(input.vorrat, 30, 60);
  const detected = list(input.erkannt, 40, 60);
  const confirmed = list(input.bestaetigt, 20, 40);
  const denied = list(input.nicht_da, 20, 40);
  const minutes = typeof input.maxMinutes === "number" ? Math.round(input.maxMinutes) : 30;
  const maxMissing =
    typeof input.max_fehlend === "number" ? Math.min(Math.max(Math.round(input.max_fehlend), 0), 2) : 2;
  const count = typeof input.anzahl === "number" ? Math.min(Math.max(Math.round(input.anzahl), 1), 4) : 4;
  const kcal = typeof input.kcal === "number" ? Math.round(input.kcal) : null;
  const meal = MEAL_LABEL[text(input.mahlzeit, 20)] ?? "nächste Mahlzeit";
  return [
    "Du bist Koch und Sporternährungs-Coach. Schlage Gerichte aus dem vor, was die Person zu Hause hat.",
    images > 0
      ? detected.length
        ? "Das Foto zeigt Kühlschrank oder Vorrat. Die Person hat die erkannten Lebensmittel korrigiert – es gilt " +
          `diese Liste: ${detected.join(", ")}.`
        : "Das Foto zeigt Kühlschrank, Vorratsschrank oder Arbeitsplatte. Erkenne die Lebensmittel (deutsche " +
          "Namen in Grundform, ohne Marken) und liste sie unter erkannt."
      : `Vorhanden (von der Person bestätigt): ${detected.join(", ") || "nichts angegeben"}.`,
    pantry.length ? `Außerdem im Vorrat: ${pantry.join(", ")}.` : "",
    confirmed.length ? `Sicher vorhanden: ${confirmed.join(", ")}.` : "",
    denied.length ? `Sicher NICHT vorhanden – nicht verwenden: ${denied.join(", ")}.` : "",
    `Mahlzeit: ${meal}.`,
    kcal !== null ? `Ziel je Gericht etwa ${kcal} kcal (von der App berechnet).` : "",
    `Ernährungsweise: ${DIET_TEXT[text(input.diet, 20)] ?? "Mischkost."}`,
    `Allergene/Unverträglichkeiten (strikt meiden): ${allergens.join(", ") || "keine"}.`,
    userText(`Mag nicht: ${text(input.dislikes, 200) || "nichts angegeben"}.`),
    `Zubereitung höchstens ${minutes} Minuten.`,
    "",
    "Regeln:",
    `- Bis zu ${count} naheliegende, alltagstaugliche Gerichte, die überwiegend aus dem Vorhandenen bestehen.`,
    "- Verwirf ein sonst passendes Gericht NICHT, nur weil kleine Standardzutaten fehlen (z. B. Butter, Salz, " +
      "Pfeffer, Milch, Öl, Zwiebel, Knoblauch, Mehl, Zucker, Gewürze). Nimm sie in die Zutaten auf und nenne sie " +
      `zusätzlich unter fehlt (höchstens ${maxMissing} je Gericht). Hauptzutaten dürfen nicht fehlen.`,
    "- Was vorhanden oder sicher vorhanden ist, gehört nicht unter fehlt.",
    "- menge_g: Menge für eine Person in Gramm (roh, wie eingekauft; Flüssigkeiten in ml = g).",
    "- naehrwerte_100g: deine beste Schätzung je 100 g der Zutat so wie angegeben.",
    "- gruppe: gemuese, obst, vollkorn, getreide, kartoffel, huelsenfruechte, nuesse, milch, fisch_fett, fisch, " +
      "ei, fleisch, fett, suess, getraenk oder sonstiges.",
    "- zubereitung: 2–6 kurze Schritte. titel: max. 40 Zeichen.",
    `Antworte ausschließlich mit JSON. ${PANTRY_SHAPE}`,
    "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ]
    .filter((line) => line !== "")
    .join("\n");
}

/** Form prüfen: Liste der erkannten Lebensmittel, höchstens vier Gerichte. Den Inhalt prüft die App. */
export function checkPantryRecipes(output: unknown): unknown {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const erkannt = (Array.isArray(record.erkannt) ? record.erkannt : [])
    .filter((item): item is string => typeof item === "string" && item.trim() !== "")
    .slice(0, 40);
  const gerichte = (Array.isArray(record.gerichte) ? record.gerichte : []).slice(0, 4);
  if (gerichte.length === 0 && erkannt.length === 0) {
    throw new GroundingError("KI-Antwort enthielt weder Lebensmittel noch Gerichte");
  }
  return { erkannt, gerichte };
}

const COOK_SHAPE = `Antwortformat (JSON):
{"rezepte": [{"titel": str, "minuten": number, "zubereitung": [str, ...],
"zutaten": [{"name": str, "menge_g": number, "menge_text": str, "gruppe": str,
"naehrwerte_100g": {"kcal": number, "protein_g": number, "carbs_g": number, "fat_g": number, "fiber_g": number}}],
"vorkochen_geeignet": bool, "haltbarkeit_tage": number, "einfrierbar": bool, "lagerung": str, "aufwaermen": str,
"kompromiss": str}]}`;

function personLine(value: unknown): string {
  const person = (typeof value === "object" && value !== null ? value : {}) as Record<string, unknown>;
  const n = (key: string) => (typeof person[key] === "number" ? Math.round(person[key] as number) : "–");
  return (
    `- ${text(person.bezeichnung, 12)}: ${n("teller")} Teller; Ziel je Teller ${n("kcal")} kcal, ` +
    `${n("protein_g")} g Protein, ${n("kohlenhydrate_g")} g Kohlenhydrate, ${n("fett_g")} g Fett`
  );
}

/** Rezeptideen für eine oder zwei Personen. Die App rechnet Tellergrößen und Gesamtmengen aus der Basisportion. */
export function cookPlanPrompt(input: Record<string, unknown>): string {
  const people = Array.isArray(input.personen) ? input.personen.slice(0, 2) : [];
  const allergens = list(input.allergens, 12, 40);
  const favorites = list(input.favorites, 10, 60);
  const minutes = typeof input.maxMinutes === "number" ? Math.round(input.maxMinutes) : 30;
  const meals = typeof input.mahlzeiten_je_person === "number" ? Math.round(input.mahlzeiten_je_person) : 1;
  const prep = input.vorkochen === true;
  return [
    "Du bist Sporternährungs-Coach und Koch. Schlage genau drei unterschiedliche Rezepte vor.",
    `Mahlzeit: ${MEAL_LABEL[text(input.mahlzeit, 20)] ?? "Hauptmahlzeit"}.`,
    `Ernährungsweise (gilt für alle): ${DIET_TEXT[text(input.diet, 20)] ?? "Mischkost."}`,
    `Allergene/Unverträglichkeiten (strikt meiden, auch in Spuren als Zutat): ${allergens.join(", ") || "keine"}.`,
    userText(`Mag nicht: ${text(input.dislikes, 200) || "nichts angegeben"}.`),
    `Zubereitung höchstens ${minutes} Minuten.`,
    favorites.length ? `Isst gern: ${favorites.join(", ")}.` : "",
    "",
    "Personen (Ziele fest von der App berechnet, nicht ändern):",
    ...(people.length ? people.map(personLine) : ["- keine Angaben"]),
    "",
    "Regeln:",
    "- Beschreibe EINE Basisportion: menge_g ist die Menge für einen Teller in Gramm (roh, wie eingekauft; " +
      "Flüssigkeiten in ml = g). Die App rechnet die Teller und Gesamtmengen selbst aus, vervielfache nichts.",
    people.length > 1
      ? "- Beide essen dasselbe Gericht, nur unterschiedlich viel. Wähle eine Zusammensetzung, die beide Ziele " +
        'möglichst gut trifft, besonders das Protein je Kalorie. "kompromiss": ein bis zwei Sätze, welche Ziele ' +
        "besser und welche schlechter getroffen werden und warum. Nenne dort keine Namen."
      : '- "kompromiss": leerer Text.',
    prep
      ? `- Gegessen wird an ${meals} Tagen. Schlage nur Gerichte vor, die aufgewärmt gut bleiben (z. B. Eintopf, ` +
        "Curry, Chili, Ofengemüse mit Hülsenfrüchten). Ungeeignet sind etwa Salate mit Dressing, Gerichte mit " +
        "panierter Kruste, Spiegelei oder Gerichte, die sofort gegessen werden müssen. Verdoppeln allein reicht nicht."
      : "- Das Gericht wird frisch gegessen.",
    '- "vorkochen_geeignet": true nur, wenn das Gericht aufgewärmt wirklich gut bleibt und sicher ist.',
    '- "haltbarkeit_tage": Tage im Kühlschrank nach dem Kochen (höchstens 3).',
    '- "einfrierbar": true nur, wenn das Gericht nach dem Auftauen noch gut ist. "lagerung": kurz, wie aufbewahren. ' +
      '"aufwaermen": kurz, wie aufwärmen; beides leer, wenn frisch gegessen.',
    "- naehrwerte_100g: deine beste Schätzung je 100 g der Zutat so wie angegeben.",
    "- gruppe: gemuese, obst, vollkorn, getreide, kartoffel, huelsenfruechte, nuesse, milch, fisch_fett, fisch, " +
      "ei, fleisch, fett, suess, getraenk oder sonstiges.",
    "- zubereitung: 2–6 kurze Schritte. titel: max. 40 Zeichen.",
    `Antworte ausschließlich mit JSON. ${COOK_SHAPE}`,
    "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ]
    .filter((line) => line !== "")
    .join("\n");
}

/** Form prüfen: höchstens drei Rezepte. Inhalt, Mengen und Haltbarkeit prüft die App. */
export function checkCookPlan(output: unknown): unknown {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const rezepte = (Array.isArray(record.rezepte) ? record.rezepte : []).slice(0, 3);
  if (rezepte.length === 0) throw new GroundingError("KI-Antwort enthielt keine Rezepte");
  return { rezepte };
}
