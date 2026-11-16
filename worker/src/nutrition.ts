/**
 * Ernährungs-Prompts (Portierung von `ernaehrung/app/analyze.py` aus dem Altbestand, ohne BLS-Abgleich).
 */
import { evidenceBlock, evidenceFrom, GroundingError, POINTS_WITH_SOURCES } from "./grounding";
import { list, nutrientLimit, text, userText } from "./tasks-util";

const MAX_ITEM_GRAMS = 5_000;

export const GROUPS = [
  "gemuese",
  "obst",
  "vollkorn",
  "getreide",
  "kartoffel",
  "huelsenfruechte",
  "nuesse",
  "milch",
  "fisch_fett",
  "fisch",
  "ei",
  "fleisch",
  "fett",
  "suess",
  "getraenk",
  "alkohol",
  "gericht",
  "sonstiges",
];

const DIET_RULES: Record<string, string> = {
  pescetarisch:
    "- Der Nutzer isst überwiegend fleischfrei, aber Fisch. Bei unklaren Gerichten (Bolognese, Burger, Lasagne, " +
    "Chili, Frikadelle) die vegetarische Variante annehmen und das im hinweis nennen; ausdrücklich genanntes " +
    "Fleisch normal erfassen.",
  vegetarisch:
    "- Der Nutzer isst vegetarisch: bei unklaren Gerichten die vegetarische Variante annehmen und im hinweis nennen.",
  vegan:
    "- Der Nutzer isst vegan: bei unklaren Gerichten und Milchprodukten die pflanzliche Variante annehmen und im " +
    "hinweis nennen.",
};

const PHOTO_RULES = `- Foto: Gehe das Bild systematisch durch: Hauptkomponente (Fleisch, Fisch, Tofu, Ei), Beilage (Reis,
  Nudeln, Kartoffeln, Brot), Gemüse/Salat, Soßen und Dressings, Fett zum Braten, Toppings (Käse, Nüsse, Kerne),
  Getränke. Jede erkennbare Komponente als eigene Position.
- Schätze Mengen über Bezugsgrößen (Teller ca. 26 cm, Besteck, Glas, Hand).
  Typische Unterschätzung bei Öl, Soßen, Dressings, Butter: sichtbare oder sehr wahrscheinliche
  Fette separat aufführen. Große Portionen werden von Bildmodellen systematisch unterschätzt -
  Teller-/Schüsselfüllung und Höhe der Speisen bewusst einbeziehen. Bei Verpackungen
  Produktname mit Marke als name.`;

const SHAPE = `Antwortformat (JSON): {"titel": str, "kategorie": str|null, "hinweis": str,
"items": [{"name": str, "suchbegriff": str, "menge_g": number, "menge_text": str, "getraenk": bool,
"sicherheit": "hoch|mittel|niedrig", "gruppe": str, "barcode": str|null,
"naehrwerte_100g": {"kcal": number, "protein_g": number, "carbs_g": number, "sugar_g": number, "fat_g": number,
"satfat_g": number, "fiber_g": number, "water_g": number, "sodium_mg": number, "potassium_mg": number,
"magnesium_mg": number, "calcium_mg": number, "iron_mg": number, "zinc_mg": number, "vitd_ug": number,
"b12_ug": number, "vitc_mg": number, "iodine_ug": number, "omega3_mg": number}}],
"vielleicht_vergessen": [str]}`;

export function mealPrompt(input: Record<string, unknown>, hasImage: boolean): string {
  const diet = DIET_RULES[text(input.diet, 20)] ?? "";
  const personal = list(input.personalFoods, 40, 80).join(", ") || "(keine)";
  const meal = text(input.text, 1000) || (hasImage ? "(siehe Foto)" : "");
  return `Du bist ein präziser Ernährungsassistent für eine deutsche Ernährungs-App.
Zerlege die Mahlzeit in einzelne Lebensmittel und Getränke und antworte NUR mit JSON.

Regeln:
- menge_g: verzehrte Menge in Gramm, so wie gegessen (gekochte Nudeln/Reis = Gewicht gekocht).
  Getränke in ml, als Zahl in menge_g (1 ml = 1 g). Vom Nutzer genannte Mengen haben Vorrang.
- menge_text: kurz und menschlich, z. B. "2 Stück", "1 Scheibe", "1 Tasse (200 ml)".
- suchbegriff: generische deutsche Bezeichnung wie im Bundeslebensmittelschlüssel (BLS), Hauptwort zuerst,
  dann Sorte und Zubereitung, ohne Marke (z. B. "Hühnerei gekocht", "Teigwaren eifrei, gekocht",
  "Reis poliert, gekocht", "Vollmilch 3,5 % Fett", "Weizenbrötchen", "Kartoffel geschält, gekocht",
  "Hähnchen Brust, gebraten", "Colagetränk koffeinhaltig", "Pilsner Bier"). Die App holt damit die Nährwerte
  aus dem BLS; naehrwerte_100g ist die Rückfall-Schätzung.
- Zusammengesetztes: in Bestandteile zerlegen, wenn das die Schätzung verbessert
  (Kaffee mit Milch = Kaffee + Milch; Müsli = Haferflocken + Milch + Obst; Rührei = Ei + Butter/Öl).
  Klassische Gerichte (Pizza, Lasagne, Döner, Currywurst) als Ganzes lassen.
- Typische Portionen, wenn nichts angegeben: Ei (M) ohne Schale 55 g, Scheibe Brot 45 g,
  Brötchen 60 g, Tasse Kaffee 200 ml, Becher 300 ml, Glas 250 ml, Schuss Milch 30 ml,
  EL Öl 10 g, TL Butter 5 g, Portion Nudeln/Reis gekocht 250 g, Apfel 150 g, Banane (geschält) 120 g,
  Scheibe Käse 25 g, Scheibe Wurst 15 g, Proteinshake-Pulver 30 g.
- naehrwerte_100g: deine beste Schätzung je 100 g so wie verzehrt (kcal, protein_g, carbs_g,
  sugar_g, fat_g, satfat_g, fiber_g, water_g, sodium_mg, potassium_mg, magnesium_mg, calcium_mg,
  iron_mg, zinc_mg, vitd_ug, b12_ug, vitc_mg, iodine_ug, omega3_mg = EPA+DHA). Unbekanntes als null.
- gruppe: Lebensmittelgruppe, genau einer von: ${GROUPS.join(", ")}.
  fisch_fett = Lachs, Hering, Makrele, Sardine u. ä.; vollkorn nur bei echtem Vollkorn.
- sicherheit: "hoch" bei klaren Angaben, "mittel" bei Standardportion, "niedrig" bei Unsicherheit.
- barcode: nur wenn auf dem Foto eine Strichcode-Nummer vollständig lesbar ist, sonst null.
- kategorie: nur setzen, wenn der Nutzer die Mahlzeit ausdrücklich nennt ("zum Frühstück",
  "als Snack", "Mittagessen") -> fruehstueck, mittagessen, abendessen, snack; bei reinen Getränken
  oder Supplements -> sonstiges. Sonst null (dann entscheidet die Uhrzeit).
- titel: kurzer deutscher Titel (max. 40 Zeichen).
- Mehrere Mahlzeiten in einer Eingabe (z. B. Frühstück und Mittag): alle Positionen in EIN JSON-Objekt mit einer
  gemeinsamen items-Liste; titel fasst zusammen, kategorie null.
- hinweis: ein kurzer Satz zu Unsicherheiten (z. B. verdeckte Zutaten, Ölmenge), sonst "".
- vielleicht_vergessen: bis zu 4 kurze Bestandteile, die oft dabei sind, aber nicht sicher zu sehen oder genannt
  sind (z. B. "Bratöl", "Soße", "Dressing", "Getränk") – nicht in items aufnehmen. Sonst [].
${hasImage ? `${PHOTO_RULES}\n` : ""}${diet ? `${diet}\n` : ""}Häufige eigene Lebensmittel des Nutzers (Namen so übernehmen, wenn sie passen): ${personal}

${SHAPE}

${userText(`Mahlzeit: ${meal}`)}`;
}

/** Bestehende Positionen einer Mahlzeit (Name und Menge), die beim Ergänzen nicht angefasst werden. */
function existingItems(input: Record<string, unknown>): { name: string; grams: number }[] {
  const raw = Array.isArray(input.bestand) ? input.bestand.slice(0, 40) : [];
  return raw.flatMap((entry) => {
    const record = (typeof entry === "object" && entry !== null ? entry : {}) as Record<string, unknown>;
    const name = text(record.name, 80);
    const grams = typeof record.menge_g === "number" && Number.isFinite(record.menge_g) ? record.menge_g : 0;
    return name ? [{ name, grams }] : [];
  });
}

/** Ergänzen einer erkannten Mahlzeit: nur NEUE Positionen aus der Beschreibung des Nutzers. */
export function mealAmendPrompt(input: Record<string, unknown>, hasImage: boolean): string {
  const diet = DIET_RULES[text(input.diet, 20)] ?? "";
  const existing = existingItems(input)
    .map((item) => `- ${item.name} (${Math.round(item.grams)} g)`)
    .join("\n");
  return `Du ergänzt eine bereits erfasste Mahlzeit in einer deutschen Ernährungs-App. Antworte NUR mit JSON.

Schon erfasst (NICHT wiederholen, NICHT ändern):
${existing || "(nichts)"}

${userText(`Ergänzung des Nutzers: ${text(input.text, 600)}`)}

Regeln:
- Liefere in items NUR die Bestandteile, die der Nutzer ergänzen möchte. Bestehende Positionen nie erneut aufführen.
- Nennt der Nutzer Mengen ("150 g", "1 EL"), übernimm sie genau. EL Öl 10 g, TL 5 g, Schuss 30 ml.
- Für jede neue Position wie bei der Analyse: name, suchbegriff (Stil des Bundeslebensmittelschlüssels), menge_g,
  menge_text, getraenk, sicherheit, gruppe (${GROUPS.join(", ")}), naehrwerte_100g (Schätzung je 100 g).
- titel: "" (der Titel der Mahlzeit bleibt), kategorie: null, hinweis: kurzer Satz zu Unsicherheiten oder "".
- Ist die Ergänzung unverständlich oder keine Lebensmittelangabe, liefere items: [] und erkläre es im hinweis.
${hasImage ? "- Das Foto zeigt die Mahlzeit; nutze es nur, um Mengen der genannten Ergänzungen einzuschätzen.\n" : ""}${diet ? `${diet}\n` : ""}
${SHAPE}`;
}

/** Wiederholte Positionen (gleicher Name, etwa gleiche Menge wie im Bestand) fallen weg – nur Neues bleibt. */
export function groundAmend(output: unknown, _requestText: string, input: Record<string, unknown>): unknown {
  const merged = mergeMeals(output);
  const record = (typeof merged === "object" && merged !== null ? merged : {}) as Record<string, unknown>;
  const items = Array.isArray(record.items) ? record.items : [];
  const normalize = (value: string) => value.toLowerCase().replace(/[^a-zäöüß0-9]/g, "");
  const existing = existingItems(input);
  const fresh = items.filter((item) => {
    const entry = (typeof item === "object" && item !== null ? item : {}) as Record<string, unknown>;
    const name = normalize(text(entry.name, 80));
    const grams = typeof entry.menge_g === "number" ? entry.menge_g : 0;
    return !existing.some(
      (old) => normalize(old.name) === name && Math.abs(old.grams - grams) <= Math.max(5, old.grams * 0.1),
    );
  });
  return { ...limitItems(record, fresh), verworfen: items.length - fresh.length };
}

function plausibleItem(item: unknown): boolean {
  const entry = (typeof item === "object" && item !== null ? item : {}) as Record<string, unknown>;
  const grams = entry.menge_g;
  if (typeof grams === "number" && (!Number.isFinite(grams) || grams <= 0 || grams > MAX_ITEM_GRAMS))
    return false;
  const per100g = (
    typeof entry.naehrwerte_100g === "object" && entry.naehrwerte_100g !== null ? entry.naehrwerte_100g : {}
  ) as Record<string, unknown>;
  return Object.entries(per100g).every(
    ([key, value]) => typeof value !== "number" || (value >= 0 && value <= nutrientLimit(key)),
  );
}

/** Unmögliche Positionen fallen weg und werden im Hinweis genannt. */
function limitItems(record: Record<string, unknown>, items: unknown[]): Record<string, unknown> {
  const kept = items.filter(plausibleItem);
  if (kept.length === items.length) return { ...record, items };
  if (kept.length === 0) throw new GroundingError("KI-Antwort enthielt nur unmögliche Mengen oder Nährwerte");
  const note = "Eine Position hatte unmögliche Werte und fehlt.";
  return { ...record, items: kept, hinweis: `${text(record.hinweis, 200)} ${note}`.trim() };
}

/** Mahlzeit zusammenführen und Mengen sowie Nährwerte auf das physikalisch Mögliche prüfen. */
export function groundMeal(output: unknown): unknown {
  const merged = mergeMeals(output);
  if (typeof merged !== "object" || merged === null || Array.isArray(merged)) return merged;
  const record = merged as Record<string, unknown>;
  return Array.isArray(record.items) ? limitItems(record, record.items) : record;
}

function fmt(value: unknown, unit: string): string {
  return typeof value === "number" && Number.isFinite(value) ? `${Math.round(value)} ${unit}` : "–";
}

/** Gemeinsame Auswertung von Ernährung und Training für den Tag. */
export function nutritionReviewPrompt(input: Record<string, unknown>): string {
  const rows = Array.isArray(input.nutrients) ? input.nutrients.slice(0, 25) : [];
  const table = rows
    .map((row) => {
      const r = (typeof row === "object" && row !== null ? row : {}) as Record<string, unknown>;
      const unit = text(r.unit, 6);
      const kind = r.upperLimit === true ? " (Obergrenze)" : "";
      return `- ${text(r.label, 40)}: ${fmt(r.actual, unit)} von ${fmt(r.target, unit)}${kind}`;
    })
    .join("\n");
  return [
    "Du bist Sporternährungs-Coach für einen Ausdauerathleten (Marathon und Mitteldistanz-Triathlon).",
    `Heute: ${text(input.weekday)}, Uhrzeit ${text(input.time, 10)}. Tagestyp für die Ernährung: ${text(input.dayType)} ` +
      `(${text(input.dayTypeSource)}). Trainingsphase: ${text(input.phase)}.`,
    `Training heute: ${list(input.training).join("; ") || "noch nichts aufgezeichnet"}.`,
    `Laut Wochenrahmen heute: ${list(input.planned).join(", ") || "nichts Festes"}.`,
    `Tagesampel Erholung: ${text(input.recovery)}.`,
    `Ernährungsziel: ${text(input.goal)}, Ernährungsweise: ${text(input.diet)}.`,
    userText(
      `Bisher gegessen (${text(input.mealCount)} Mahlzeiten): ${list(input.meals, 12, 120).join("; ") || "nichts"}.`,
    ),
    "",
    "Stand gegenüber den Tageszielen:",
    table || "- keine Daten",
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    `Aufgabe: Werte Ernährung und Training gemeinsam aus. ${POINTS_WITH_SOURCES} ` +
      "2-4 Punkte, je ein bis zwei Sätze:",
    "1. Passt die Energie- und Kohlenhydratzufuhr zum Training (vor, während, nach der Einheit)? " +
      "Berücksichtige die Uhrzeit: Ziele sind Tagesziele, morgens ist wenig erreicht normal.",
    "2. Protein: Verteilung über den Tag (0,25-0,4 g/kg je Mahlzeit) und was noch fehlt.",
    "3. Ein konkreter, alltagstauglicher Vorschlag für die nächste Mahlzeit passend zur Ernährungsweise.",
    "4. Optional: auffällige Mikronährstoff-Lücke (nur wenn deutlich), ohne Panik.",
    "Keine Diagnosen, keine Supplement-Empfehlungen ohne klaren Anlass. " +
      "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ].join("\n");
}

/** Nährwerttabelle vom Foto lesen (Barcode bei Open Food Facts unbekannt). Nur ablesen, nichts schätzen. */
export function labelPrompt(): string {
  return `Du liest die Nährwerttabelle einer Lebensmittelverpackung vom Foto ab und antwortest NUR mit JSON.

Regeln:
- Werte je 100 g bzw. 100 ml genau so übernehmen, wie sie auf dem Etikett stehen. Nichts schätzen, nichts runden.
- Steht nur „je Portion“ da, auf 100 g umrechnen, wenn die Portionsgröße in Gramm angegeben ist; sonst null.
- Energie in kcal (nicht kJ). Salz in Natrium umrechnen: Natrium mg = Salz g × 400.
- Unleserliches oder Fehlendes als null.
- name: Produktname mit Marke, falls lesbar, sonst "".
- portion_name und portion_g: Portionsangabe vom Etikett (z. B. "Riegel", 45), sonst null.
- getraenk: true bei Getränken.

Antwortformat (JSON): {"name": str, "portion_name": str|null, "portion_g": number|null, "getraenk": bool,
"naehrwerte_100g": {"kcal": number|null, "protein_g": number|null, "carbs_g": number|null,
"sugar_g": number|null, "fat_g": number|null, "satfat_g": number|null, "fiber_g": number|null,
"sodium_mg": number|null}}`;
}

/**
 * Mehrere Mahlzeiten als Liste von Objekten (statt einem) zu einer zusammenführen: Positionen hintereinander,
 * Titel und Hinweise verbunden. Ein einzelnes Objekt bleibt unverändert.
 */
export function mergeMeals(output: unknown): unknown {
  const meals = Array.isArray(output) ? output : null;
  if (!meals) return output;
  const objects = meals.filter(
    (meal): meal is Record<string, unknown> =>
      typeof meal === "object" && meal !== null && !Array.isArray(meal),
  );
  if (objects.length === 0) return output;
  if (objects.length === 1) return objects[0];
  const titles = objects.map((meal) => text(meal.titel, 40)).filter(Boolean);
  const hints = objects.map((meal) => text(meal.hinweis, 200)).filter(Boolean);
  const categories = new Set(objects.map((meal) => meal.kategorie ?? null));
  return {
    titel: titles.join(" + ").slice(0, 40) || "Mahlzeiten",
    kategorie: categories.size === 1 ? [...categories][0] : null,
    hinweis: hints.join(" "),
    items: objects.flatMap((meal) => (Array.isArray(meal.items) ? meal.items : [])),
  };
}
