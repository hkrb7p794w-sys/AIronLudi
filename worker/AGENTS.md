# AGENTS.md – Worker „coach-ai“

Ergänzt die `AGENTS.md` im Wurzelverzeichnis (deren Regeln gelten auch hier). Überblick und Routen: `README.md`.

## Befehle (Node 22)

```sh
npm ci
npm run lint && npm run typecheck && npm test
npm run format        # Biome formatiert und sortiert Importe
```

## Aufbau

- `src/index.ts`: Einstieg und Weiterleitung nach Pfad (`/v1/…`); Anmeldung in `src/auth.ts` (Haupt-Token,
  Gast-Token, Sitzungen). Neue Routen dort einhängen; standardmäßig nur mit Anmeldung (`authenticate`, sonst 401),
  ohne Anmeldung nur mit Begründung (wie `/v1/health` oder Anmelden/Registrieren).
- `src/tasks.ts`: alle KI-Aufgaben mit Prompts (`TASKS`). Eine Prompt-Änderung braucht nur einen Worker-Deploy.
  Neue Aufgabe = Eintrag in `TASKS` + Test in `test/tasks.test.ts`; der Name muss
  zur App passen (`AIClient`, `AIPolicy` in `coach_core`).
- `src/providers.ts`: Anbieter und Reihenfolge je Aufgabe (`TASK_ROUTES`); einzelne Anbieter in `gemini.ts`,
  `groq.ts`, `workers-ai.ts`, `openai-compat.ts`.
- `src/types.ts`: `Env` mit allen Secrets, Bindings (KV `RELEASES`, `LEAGUE`, D1 `DB`, `AI`) und Variablen.
- `src/db.ts`: D1-Schema, legt der Worker selbst an (`CREATE TABLE IF NOT EXISTS`). Spalten nur ergänzen, nie
  umbenennen oder löschen – ältere App-Versionen müssen weiterlaufen.

## Regeln

- **Keine Secrets im Code oder in `wrangler.jsonc`** – nur als Worker-Secrets (Deploy-Workflow, `docs/einrichtung.md`).
  Lokal `.dev.vars` (in `.gitignore`).
- Die App schickt nur abgeleitete Werte (Datenschutzmodus „reduziert“); Prompts dürfen keine Rohdaten verlangen.
  Keine personenbezogenen Daten loggen.
- Antworten bleiben abwärtskompatibel zur App: Felder ergänzen, nicht umbenennen oder entfernen.
- Tests ohne Netz: `fakeDeps` aus `test/helpers.ts` (simuliertes `fetch`, Uhr), D1 über `test/sqlite.ts`.
- `VERSION` in `src/index.ts` und `package.json` gemeinsam erhöhen, wenn sich die Schnittstelle ändert.
