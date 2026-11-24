# AGENTS.md – AIronLudi

Anweisungen für KI-Agenten (Claude Code, Codex, Copilot, Cursor …). `CLAUDE.md` bindet diese Datei nur ein; Änderungen
an den Regeln nur hier. Für den Worker gilt zusätzlich `worker/AGENTS.md`.

Flutter-App (Dart) für iPhone und Android: Garmin-Coaching, Ernährung und Gym-Logging. Entsteht als **1:1-Migration**
der nativen iPhone-App aus `hkrb7p794w-sys/Coach-App` (Swift, Stand `793d408`). Der Nutzer hat **keinen Mac**
(Windows-PC, iPad, iPhone): iOS wird ausschließlich in GitHub Actions gebaut und per SideStore installiert.

## Struktur

| Pfad | Inhalt |
|---|---|
| `packages/coach_core/` | Reine Logik **ohne Flutter** (Port von `CoachCore`), testbar mit `dart test`; Fixtures in `test/fixtures` |
| `lib/app/` | App-Widget, Router (`go_router`, vier Reiter), Theme, Deep Links, Benutzerwechsel (`user_scope.dart`) |
| `lib/ui/` | Gemeinsame Bausteine; Designsystem „Clean Liquid Design“ in `liquid.dart`, Tokens in `tokens.dart` |
| `lib/data/` | Datenbank (drift), Einstellungen, sicherer Speicher, Repositories, Sicherung, Benutzer |
| `lib/services/`, `lib/platform/` | Dienste (Garmin, WHOOP, Health, KI, Mitteilungen …) und Plattformbrücken; Provider in `services/providers.dart` |
| `lib/features/<bereich>/` | Screens und Controller je Bereich (siehe Funktionsübersicht) |
| `ios/Runner/`, `ios/CoachWidgets/`, `android/app/` | Native Konfiguration; Widgets/Live-Aktivitäten bleiben nativ (Migrationsplan 4.2) |
| `worker/` | Cloudflare Worker „coach-ai“ (TypeScript): KI-Weiterleitung, Konten, Freunde, Kartendienste, SideStore-Quelle, Android-Download; Prompts in `src/tasks.ts` (seit 16.11.2026 hier statt in Coach-App) |
| `docs/migrationsplan.md` | Audit und Checkliste – bei jeder PR den Stand (Abschnitt 8) nachführen |
| `docs/decisions.md` | Begründete Abweichungen und Entscheidungen (ein Abschnitt `## JJJJ-MM-TT – Titel` je Entscheidung) |
| `docs/FUEL_PLANNER_SCIENCE.md` | Wissenschaftliche Grundlage und Regeln des Fuel Planners (`coach_core/src/fuel`) – Zahlen nur dort und in den Tests ändern |
| `docs/roast/` | UI-Prüfung vom 24.11.2026: `design-konzept.md` (Designregeln, Glossar), `umsetzungsplan.md`, Screenshots |
| `docs/einrichtung.md`, `docs/anleitung.md` | Einrichtung für die Betreiberin bzw. den Betreiber; Installationsanleitungen |

## Funktionsübersicht

Vier Reiter (`lib/app/router.dart`, Pfade `/heute`, `/aktivitaeten`, `/training`, `/ernaehrung`), jeder mit eigenem
Navigationsstapel; beim ersten Start der Einrichtungsassistent (`/einrichtung`, `features/onboarding`).

| Reiter / Bereich | Ordner unter `lib/features/` | Inhalt |
|---|---|---|
| Heute | `today` | Ringe Schlaf/Erholung/Belastung, Tagesampel, „Jetzt dran“, Ernährung heute, Wochenüberblick, anpassbares Dashboard |
| Aktivitäten | `activities` | Verlauf aus Garmin, Health, WHOOP, Nachgetragenem und Gym; Details wie Garmin Connect, Analyse nach dem Training |
| Training | `training`, `plan`, `endurance`, `gym`, `routes`, `fuel`, `health` | Wochenplan, Saisonplan, adaptiver Ausdauerplan, Gym-Logging (Live-Einheit), Routenplaner, Fuel Planner (Verpflegung), Morgenbericht, Body Battery, Schlaf, Mobilität, Wecker |
| Ernährung | `nutrition`, `recipes` | Tagebuch, Erfassen (Suche, Foto, Barcode, Text/Diktat), BLS und Open Food Facts, Tagesziele, Gewicht, Rezepte, Vorrat, Kochplan, Teilen |
| Übergreifend | `ai`, `settings`, `account`, `social`, `game`, `motivation`, `evidence` | KI-Coach und Chat, Einstellungen und Datenquellen, Konto, Freunde und Feed, Rangliste/Challenges, Begleiter, Quellen zu Empfehlungen |

Logik dazu liegt in `packages/coach_core/lib/src/<bereich>/` mit gleichem Namen. Wo eine Funktion herkommt, zeigt
der Swift-Code in Coach-App; was schon portiert ist, Abschnitt 8 des Migrationsplans.

## Grundregeln

- **Keine Funktion darf verloren gehen.** Quelle der Wahrheit ist der Swift-Code in Coach-App. Logik wird 1:1
  portiert, **mit den Swift-Tests** als Dart-Tests (gleiche Fälle, gleiche Fixtures). Abweichungen nur mit
  Begründung in `docs/decisions.md`.
- **Regeln entscheiden, KI formuliert.** Tagesampel, Ziele und Progression sind deterministisch und getestet.
- **KI-Aufrufe und KI-Keys nur im Cloudflare Worker** (`worker/` in diesem Repo). **Alle Änderungen nur in
  AIronLudi** (Auftrag des Nutzers vom 16.11.2026) – Coach-App wird nicht mehr geändert, auch nicht der Worker
  dort. Garmin-Key und Tokens nur im sicheren Speicher (`flutter_secure_storage`). Datenschutzmodus „reduziert“ ist
  Standard.
- **Keine Secrets im Repo** – das Repo ist öffentlich.
- **Health ist optional** (Apple Health / Health Connect): jede Funktion hat einen Weg ohne.
- **Zwei Modi** (`UserProfile.mode`): Saisonplan und persönlich; keine Saisonwerte für andere Personen anzeigen.
  Gewichtsziele nur mit den Schutzgrenzen aus `GoalRules`.
- **Datenformate bleiben kompatibel:** `AppBackup` (Umzug von der Swift-App), Mahlzeit-Teilen, Coach-Export,
  Einstellungsschlüssel `coach.*`, Link-Schemata `coach://` und `ironludi://` (Android, bisherige App).
  Bundle-/Application-ID nicht ändern (die Flutter-App ersetzt die bisherigen Apps).
- UI-Texte auf Deutsch mit echten Umlauten, Bezeichner auf Englisch, Kommentare auf Deutsch.
- iOS 18+, Android 8.0+ (minSdk 26), nur Hochformat.

## Architektur

- **Wohin mit Code:** Rechnen, Regeln, Parser, JSON → `coach_core` (kein `import 'package:flutter/…'`). Netzwerk,
  Speicher, Plattform → `lib/services` bzw. `lib/data`. Nur Darstellung und Zustand des Screens → `lib/features`.
- **Zustand:** Controller sind `ChangeNotifier` (Ports der Swift-ViewModels), bereitgestellt über Riverpod-Provider.
  Dienste kommen nur über Provider (`lib/services/providers.dart`), nie direkt instanziiert in Widgets.
- **Mehrere Benutzer:** Jeder Benutzer hat eigene Datenbank, Einstellungen und einen eigenen Provider-Container
  (`UserScope`, `UserSession`). Neue Daten strikt je Benutzer speichern; nichts global zwischenspeichern, was nach
  einem Benutzerwechsel sichtbar bliebe.
- **Datenbank (drift):** Bei Schemaänderungen `schemaVersion` erhöhen, Schritt in `onUpgrade` ergänzen, Test mit
  SQLite schreiben; neue Tabellen in `AppBackup` aufnehmen, ohne das bisherige Format zu brechen. Nach Änderungen an
  Tabellen `dart run build_runner build --delete-conflicting-outputs`; `database.g.dart` wird eingecheckt.
- **Native Brücken:** `MethodChannel`s `aironludi/widgets`, `aironludi/activities`, `aironludi/alarm` – Namen auf
  Dart-, Swift- und Kotlin-Seite gemeinsam ändern. Ohne native Gegenseite (Tests) gilt „nicht unterstützt“.

## UI-Regeln

Grundlage: `docs/roast/design-konzept.md` (Abschnitt 3 und Glossar).

- In `lib/features` **keine rohen Farben** (`Colors.*` außer `transparent`, `Color(0x…)`) und **keine festen
  Schriftgrößen** (`fontSize:`). Stattdessen `AppColors` (`good`/`caution`/`alert`/`info`, `muted`) und `AppText`
  (`lib/ui/tokens.dart`), Abstände `LiquidSpacing`, Radien `LiquidRadii`, Bewegung `LiquidMotion` (`lib/ui/liquid.dart`).
  `test/ui/ui_tokens_test.dart` ist eine Sperrklinke: der Bestand darf nur schrumpfen. Nach dem Umstellen einer Datei:
  `flutter test test/ui/ui_tokens_test.dart --dart-define=UPDATE_TOKEN_BASELINE=true`.
- Vorhandene Bausteine verwenden (`LiquidCard`, `LiquidSurface`, `LiquidMetric`, `LiquidPressable`, `KpiRing`,
  `lib/ui/components.dart`, Diagramm-Achsen `chart_axes.dart`), statt eigene zu bauen. Symbole über `AppSymbols`
  (SF-Symbol-Namen wie in Swift).
- Ampelfarben nur für Bewertungen, nie für Mengen ohne Bewertung (Belastung 0,0 ist neutral).
- Jeder datengetriebene Baustein hat die Zustände Laden, Leer (ein Satz + ein Knopf) und Fehler (was ist passiert,
  was kann ich tun, „Erneut versuchen“).
- **Barrierefreiheit:** Tap-Flächen ≥ 44 pt, jede Tap-Fläche beschriftet, Kontrast ≥ 4,5 : 1, nichts unter 12 pt,
  Ringe und Balken mit `Semantics(label: …)`, große Schrift ohne Abschneiden (geprüft in `test/a11y/` und
  `test/features/layout_overflow_test.dart`).
- **Begriffe** (eine Schreibweise je Sache): KI, Belastung (0–21), Erholung, Einheit (geplant) / Aktivität
  (aufgezeichnet), Kraft (Sportart) / Gym (Live-Einheit), Verpflegung, Morgenbericht.
- Eine Linie für beide Plattformen mit iOS-Grammatik; plattformgerecht nur bei Schaltern, Zurück-Geste,
  Datums-/Zeitwählern, Teilen und Haptik.

## Befehle

```sh
flutter pub get
dart format lib test packages
flutter analyze            # muss „No issues found!“ melden
flutter test
cd packages/coach_core && dart test
cd worker && npm ci && npm run lint && npm run typecheck && npm test   # Node 22
```

Flutter-Version: 3.47.9 (in allen Workflows festgelegt). Zeilenenden: LF (`.gitattributes`), auch unter Windows.
Tests müssen auch unter Windows laufen (Pfade mit `package:path`, Temp-Ordner über `Directory.systemTemp`).
Widget-Tests starten die App über `app(onboarded: …, overrides: …)` aus `test/app_test.dart`.

Screenshot-Prüfstand (nicht im normalen Testlauf; Bilder und Übersicht in `docs/roast/`):

```sh
flutter test --tags screenshots --dart-define=SCREENSHOTS=true --update-goldens test/screenshots
bash test/screenshots/make_index.sh
```

## CI

- `flutter.yml`: Format, Analyse, Tests (Linux, jeder PR und `main`); Fehler als PR-Kommentar.
- `android.yml`: Release-APK als Artefakt; Bereitstellung nur mit `vars.DEPLOY_ANDROID == 'true'`.
- `worker.yml`: Lint, Typen, Tests bei PRs mit Änderungen in `worker/`; Bereitstellung auf `main` bzw. per
  „Run workflow“, sofern die Secrets gesetzt sind (`docs/einrichtung.md`). `worker-smoke.yml`: Prüfung gegen den
  bereitgestellten Worker, nur manuell.
- `ios-build.yml`: unsignierte IPA (pseudo-signiert mit `ldid` und den Entitlements) per Label `ios-build`, auf
  `main` und per „Run workflow“; Bereitstellung nur mit `vars.DEPLOY_SIDESTORE == 'true'`.
- **PRs merged der Agent selbst und automatisch** (Auftrag des Nutzers vom 13.11.2026): sobald `check` und `apk`
  grün sind (bei Änderungen an `ios/` zusätzlich der iOS-Build per Label), per Merge-Commit. Gestapelte PRs danach
  auf `main` umstellen.
- **Ohne Rückfrage weiterarbeiten** (Auftrag des Nutzers vom 13.11.2026): nach dem Merge direkt die nächste
  Teilphase aus dem Migrationsplan beginnen, nicht auf „weiter“ warten.
- Aus Claude-Code-Cloud-Sitzungen ist die Actions-API gesperrt: Builds per Label starten, Ergebnisse über
  Check-Runs, PR-Kommentare und Releases lesen.

## Konventionen

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`, `test:`, `refactor:`), Scope optional
  (`feat(core): …`, `feat(gym): …`).
- Eine PR je Teilphase (Reihenfolge im Migrationsplan, Abschnitt 6).
- Jede PR: Zeile in Abschnitt 8 von `docs/migrationsplan.md`; bei Abweichungen vom Swift-Verhalten oder neuen
  Funktionen ein Abschnitt in `docs/decisions.md`.
- Neue Funktion = Test dazu (Logik in `packages/coach_core/test`, Screens in `test/features`).
