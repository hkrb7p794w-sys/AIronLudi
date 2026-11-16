# Einrichtung: KI-Worker, Garmin und WHOOP (Betreiber:in)

Einmalig für die Person, die den Worker betreibt (du). Alle anderen brauchen nur Links von dir
(siehe [`anleitung.md`](anleitung.md)). Keys und Tokens **nie** in Chats, Issues oder Dateien im Repo kopieren –
nur in die genannten Felder. Der Worker liegt seit dem 16.11.2026 in **diesem Repo** (`worker/`); das Repo
Coach-App wird dafür nicht mehr verwendet.

## 1. Umzug des Workers von Coach-App (einmalig, falls er dort schon lief)

Der Worker heißt weiter `coach-ai` und behält Adresse, Daten (Konten, Ranglisten, KV) und Secrets bei Cloudflare.
Neu ist nur, von wo er bereitgestellt wird.

1. **Secrets kopieren:** Alle Secrets aus *Coach-App › Settings › Secrets and variables › Actions* auch in
   *AIronLudi › Settings › Secrets and variables › Actions* anlegen (GitHub zeigt Secret-Werte nicht an – die Werte
   aus deinen Notizen bzw. neu erzeugen, siehe Abschnitt 3):
   `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `COACH_APP_TOKEN`, die KI-Keys (`GEMINI_API_KEY`,
   `GROQ_API_KEY`, `CEREBRAS_API_KEY`, `MISTRAL_API_KEY`, `GH_MODELS_TOKEN`) und ggf. `WHOOP_CLIENT_ID`,
   `WHOOP_CLIENT_SECRET`. **`COACH_APP_TOKEN` muss derselbe Wert sein**, sonst passen App-Token, Gastzugänge und die
   Links der SideStore-Quelle nicht mehr.
2. **Doppelte Bereitstellung verhindern:** In Cloudflare unter *Workers & Pages* prüfen, ob ein Worker mit
   Git-Anbindung an Coach-App existiert („Workers Builds“, Check „Workers Builds: ironludi“ in den Coach-App-PRs).
   Falls ja: dort *Settings › Build* die Git-Verbindung trennen. In Coach-App den Ordner `worker/` nicht mehr
   ändern – sonst stellt dessen Workflow `worker.yml` die alte Fassung bereit.
3. **Bereitstellen aus AIronLudi:** *Actions › Worker › Run workflow* (Branch `main`). Danach meldet die
   Zusammenfassung des Laufs die Adresse und den Health-Check.

## 2. KI-Keys

Alle optional – der Worker nutzt, was eingerichtet ist. Mindestens einer ist nötig.

| Anbieter | Wofür | Key holen |
|---|---|---|
| **Gemini** (Google) | Fotos, Gespräche, Auswertungen | <https://aistudio.google.com> › Get API key › Create API key |
| **Cerebras** | Pläne und Rezepte (lange Antworten) | <https://cloud.cerebras.ai> › API Keys › Generate (verlangt Kreditkarte) |
| **Groq** | kurze Hinweise, Ausweichstufe | <https://console.groq.com/keys> › Create API Key |
| **Mistral** | zweites Bildmodell, sehr gutes Deutsch | <https://console.mistral.ai> › Plan „Experiment“ › API Keys |
| **GitHub Models** (GPT-4.1) | auch Fotos, knappe Tageslimits | GitHub › Settings › Developer settings › Fine-grained token, nur „Models: Read-only“ |
| Workers AI | ohne Key, über Cloudflare | – |

Datenschutz: Im kostenlosen Gemini- und Mistral-Kontingent dürfen die Anbieter Eingaben auswerten. Die App schickt
deshalb standardmäßig nur Einordnungen („HRV ausgeglichen“), keine Rohwerte; „Datenschutz zuerst“ in der App
schließt beide aus.

## 3. Cloudflare und App-Token (nur bei Neueinrichtung)

1. Konto: <https://dash.cloudflare.com/sign-up>, unter *Workers & Pages* eine `workers.dev`-Subdomain wählen.
2. **Account ID** kopieren (*Workers & Pages* › Account details).
3. **API-Token:** Profil › API Tokens › Create Token › Vorlage **Edit Cloudflare Workers** › nur dein Konto ›
   Create Token.
4. **App-Token** (langes Zufallspasswort für die App), am PC in PowerShell:

   ```powershell
   $b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); ([BitConverter]::ToString($b) -replace '-','').ToLower()
   ```

## 4. GitHub-Secrets (AIronLudi)

*Settings › Secrets and variables › Actions › New repository secret*:

| Name | Wert |
|---|---|
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | aus Abschnitt 3 – auch für SideStore-Quelle und Android-Download |
| `COACH_APP_TOKEN` | App-Token |
| `GEMINI_API_KEY`, `GROQ_API_KEY`, `CEREBRAS_API_KEY`, `MISTRAL_API_KEY`, `GH_MODELS_TOKEN` | KI-Keys (Abschnitt 2) |
| `WHOOP_CLIENT_ID`, `WHOOP_CLIENT_SECRET` | optional, Abschnitt 6 |
| `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD` | Signaturschlüssel der Android-App (dieselben Werte wie in Coach-App, damit Updates die alte App ersetzen) |

Danach *Actions › Worker › Run workflow*. Fehlt ein Secret, endet der Lauf grün mit „Deploy übersprungen – fehlende
Secrets: …“.

## 5. App mit dem Worker verbinden (dein Gerät)

1. AIronLudi › **Einstellungen › Technik › KI-Worker**: Adresse (`https://coach-ai.<subdomain>.workers.dev`, steht in
   der Zusammenfassung des Worker-Laufs) und App-Token eintragen.
2. **Speichern und testen** – darunter erscheint ein Gruß der KI mit Anbieter und Modell. Ab dann gibt es dort auch
   „SideStore-Quelle teilen“ und „Android-Link erstellen“ für andere.

Andere Personen tragen nichts von Hand ein: Sie bekommen einen Einladungslink mit eigenem Gastzugang
(*Einstellungen › Begleiter & Rangliste › Einladungslink erstellen*) bzw. den Android-Link.

## 6. WHOOP (optional, einmal zentral)

**Einmal für alle, von dir als Betreiber:in.** WHOOP verlangt für die Anmeldung ein Client-Secret, das nicht in die
App gehört; deshalb tauscht der Worker die Anmeldung. Du legst **eine** Developer-App an und hinterlegst sie im
Worker. Jede Person, die WHOOP nutzt, verbindet danach in der App nur **ihr eigenes WHOOP-Konto** („Mit WHOOP
verbinden“) – sie braucht kein Developer-Konto, und jede sieht nur ihre eigenen Daten (eigene Tokens, im sicheren
Speicher ihres Geräts bzw. ihres Benutzers in der App).

1. <https://developer-dashboard.whoop.com> mit deinem WHOOP-Konto öffnen (beim ersten Mal ein „Team“ anlegen).
2. **Create App**: Name z. B. `AIronLudi`; Scopes `read:recovery`, `read:cycles`, `read:workout`, `read:sleep`,
   `read:profile`, `read:body_measurement`; **Redirect URL** `https://coach-ai.<subdomain>.workers.dev/w/whoop`.
3. **Client ID** und **Client Secret** als Secrets `WHOOP_CLIENT_ID`, `WHOOP_CLIENT_SECRET` anlegen, Worker
   bereitstellen. Der Health-Check (`/v1/health`) zeigt dann `"whoop": true`.
4. In der App: *Einstellungen › Training und Fitness › WHOOP › Mit WHOOP verbinden*.

Grenzen der WHOOP-API gelten je Developer-App, also für alle zusammen: 100 Anfragen je Minute, 10 000 je Tag – ein
Abruf braucht wenige Anfragen, für eine Familie oder einen Freundeskreis reicht das. Ob WHOOP neue Apps auf eine
Zahl von Nutzer:innen begrenzt, bis sie freigegeben sind, zeigt das Developer-Dashboard.

## 7. Garmin (je Person, auf dem eigenen Gerät)

Garmin hat keinen zentralen Zugang – jede Person meldet sich selbst an:

- **Garmin-Konto** (empfohlen, mehr Werte): *Einstellungen › Training und Fitness › Garmin-Konto* › E-Mail und
  Passwort, ggf. Bestätigungscode. Gespeichert wird nur das Anmelde-Token.
- **Personal API Key** (offizieller Rückfall): in Safari <https://connect.garmin.com/app/settings/personalApiToken> ›
  Create › 1 Jahr › Key kopieren (nur einmal sichtbar) › *Einstellungen › Technik › Garmin Personal API (Rückfall)* ›
  einfügen › **Speichern und verbinden**. Garmin und die App warnen vor dem Ablauf.

Probleme: *Einstellungen › Technik › Diagnose › Garmin-Diagnose*.
