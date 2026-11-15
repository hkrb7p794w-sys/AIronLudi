# Worker-Aufgabe `pantry_recipes` (Rezepte aus dem Kühlschrank-Foto)

Die App ruft wie bei allen KI-Aufgaben `POST v1/ai/generate` auf. Der Worker liegt in `hkrb7p794w-sys/Coach-App`
(`worker/`) und muss diese Aufgabe kennen. Art: **planning** (wie `meal_now`), mit Foto – also an einen Anbieter mit
Bildeingabe (z. B. Gemini oder Mistral, nicht Cerebras/eigener Server ohne Fotos).

## Anfrage

```json
{
  "task": "pantry_recipes",
  "provider": "auto",
  "images": [{ "mimeType": "image/jpeg", "data": "<base64, ohne Metadaten, längste Seite ≤ 1280 px>" }],
  "input": {
    "mahlzeit": "abendessen",
    "kcal": 600,
    "diet": "vegetarisch",
    "dietLabel": "Vegetarisch",
    "allergens": ["Nüsse"],
    "dislikes": "Koriander",
    "maxMinutes": 30,
    "vorrat": ["Reis", "Olivenöl"],
    "erkannt": ["Eier", "Paprika"],
    "bestaetigt": ["Salz"],
    "nicht_da": ["Butter"],
    "max_fehlend": 2,
    "anzahl": 4
  }
}
```

- `kcal` fehlt meist (eine Portion für eine Person).
- `images` fehlt, wenn die Person ohne neues Foto „Neu vorschlagen“ tippt – dann zählt `erkannt`.
- `erkannt`, `bestaetigt`, `nicht_da` sind bei der ersten Anfrage leer.

## Vorschlag für den Prompt

> Du siehst ein Foto von Kühlschrank, Vorratsschrank oder Arbeitsplatte. Erkenne die Lebensmittel (deutsche Namen,
> Grundform, ohne Marken). Ist `erkannt` nicht leer, gilt diese Liste statt deiner Erkennung; `vorrat` und
> `bestaetigt` sind ebenfalls vorhanden, `nicht_da` ist sicher nicht vorhanden – verwende es nicht.
> Schlage bis zu `anzahl` naheliegende, alltagstaugliche Gerichte für `mahlzeit` vor, die überwiegend aus dem
> Vorhandenen bestehen, in höchstens `maxMinutes` Minuten, passend zu `diet`, ohne `allergens` und `dislikes`.
> Verwirf ein sonst passendes Gericht **nicht**, nur weil ein oder zwei kleine Standardzutaten fehlen (z. B. Butter,
> Salz, Pfeffer, Milch, Öl, Zwiebel, Knoblauch, Mehl, Zucker, Gewürze). Nimm sie in die Zutaten auf und nenne sie
> zusätzlich unter `fehlt` (höchstens `max_fehlend`). Hauptzutaten dürfen nicht fehlen. Mengen für eine Person,
> Nährwerte je 100 g geschätzt. Antworte nur mit JSON.

## Antwort (`output`)

```json
{
  "erkannt": ["Eier", "Paprika", "Feta", "Spinat"],
  "gerichte": [
    {
      "titel": "Spinat-Omelett mit Feta",
      "mahlzeit": "abendessen",
      "minuten": 15,
      "zutaten": [
        { "name": "Eier", "menge_g": 180, "naehrwerte_100g": { "kcal": 137, "protein_g": 12, "carbs_g": 1, "fat_g": 9 } },
        { "name": "Butter", "menge_g": 10, "naehrwerte_100g": { "kcal": 741, "fat_g": 83 } }
      ],
      "zubereitung": ["Eier verquirlen.", "In Butter stocken lassen.", "Spinat und Feta darauf."],
      "fehlt": ["Butter"]
    }
  ]
}
```

Zutaten haben dasselbe Format wie bei `weekly_recipes` und `meal_now` (`name`, `menge_g`, `naehrwerte_100g`, optional
`menge_text`, `suchbegriff`); die App ersetzt die Nährwerte, wo der BLS einen Eintrag hat. Die App prüft und verwirft
selbst (Ernährungsweise, Allergene, unplausible Nährwerte, mehr als zwei Einträge unter `fehlt`) und stellt die
Rückfragen („Ist noch Butter da?“) – der Worker muss nicht nachfragen.
