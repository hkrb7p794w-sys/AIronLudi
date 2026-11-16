# coach-ai (Cloudflare Worker)

Reicht KI-Aufgaben der Coach-App an Gemini weiter (mit den Ausweichstufen aus dem Altbestand:
404-Nachfolgemodell, Wiederholung bei 429/5xx, „lite“-Ausweichmodell) und bei Ausfall an Groq.
Die KI-Keys liegen nur hier als Worker-Secrets. Die App meldet sich mit `COACH_APP_TOKEN` an (Haupt-Token) oder mit
einem Gast-Token aus einer Einladung (`src/auth.ts`). Gäste sperrt die Variable `REVOKED_GUESTS` (IDs, durch Komma
getrennt).

| Route | Zweck |
|---|---|
| `GET /v1/health` | Version, konfigurierte Anbieter (ohne Anmeldung, ohne Keys) |
| `POST /v1/invite` | nur Haupt-Token: neues Gast-Token `{id, token}` für einen Einladungslink |
| `POST /v1/ai/generate` | `{ "task": "ping", "input": {…}, "images": [{ "mimeType": "image/jpeg", "data": "<base64>" }] }` |

Die Prompts liegen in `src/tasks.ts`. Eine Prompt-Änderung braucht nur einen Worker-Deploy, keine neue App-Version.

## Entwicklung

```sh
npm ci
npm run lint && npm run typecheck && npm test
npm run format        # Biome formatiert und sortiert Importe
```

Lokal starten (`npm run dev`) braucht eine Datei `.dev.vars` mit `COACH_APP_TOKEN=…` und den KI-Keys.
Sie ist in `.gitignore` und darf nie eingecheckt werden.

## Deploy

Automatisch per `.github/workflows/worker.yml` nach dem Merge auf `main`, oder manuell über
„Actions › Worker › Run workflow“. Voraussetzungen: siehe `docs/einrichtung.md`.
