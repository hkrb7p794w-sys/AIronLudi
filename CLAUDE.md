# CLAUDE.md – AIronLudi

Flutter-App (Dart) für iPhone und Android: Garmin-Coaching, Ernährung und Gym-Logging. Entsteht als **1:1-Migration**
der nativen iPhone-App aus `hkrb7p794w-sys/Coach-App` (Swift, Stand `793d408`). Der Nutzer hat **keinen Mac**
(Windows-PC, iPad, iPhone): iOS wird ausschließlich in GitHub Actions gebaut und per SideStore installiert.

## Struktur

| Pfad | Inhalt |
|---|---|
| `packages/coach_core/` | Reine Logik **ohne Flutter** (Port von `CoachCore`), testbar mit `dart test` |
| `lib/app/` | App-Widget, Router (`go_router`, vier Reiter), Theme, Deep Links |
| `lib/data/` | Datenbank (drift), Einstellungen, sicherer Speicher, Repositories |
| `lib/services/`, `lib/platform/` | Dienste (Garmin, Health, KI, Mitteilungen …) und Plattformbrücken |
| `lib/features/<bereich>/` | Screens und Controller (Riverpod) je Bereich |
| `ios/Runner/`, `android/app/` | Native Konfiguration; Widgets/Live-Aktivitäten bleiben nativ (siehe Migrationsplan 4.2) |
| `docs/migrationsplan.md` | Audit und Checkliste – bei jeder PR den Stand (Abschnitt 8) nachführen |

## Grundregeln

- **Keine Funktion darf verloren gehen.** Quelle der Wahrheit ist der Swift-Code in Coach-App. Logik wird 1:1
  portiert, **mit den Swift-Tests** als Dart-Tests (gleiche Fälle, gleiche Fixtures). Abweichungen nur mit
  Begründung in `docs/decisions.md`.
- **Regeln entscheiden, KI formuliert.** Tagesampel, Ziele und Progression sind deterministisch und getestet.
- **KI-Aufrufe und KI-Keys nur im Cloudflare Worker** (bleibt in Coach-App). Garmin-Key und Tokens nur im sicheren
  Speicher (`flutter_secure_storage`). Datenschutzmodus „reduziert“ ist Standard.
- **Keine Secrets im Repo** – das Repo ist öffentlich.
- **Health ist optional** (Apple Health / Health Connect): jede Funktion hat einen Weg ohne.
- **Zwei Modi** (`UserProfile.mode`): Saisonplan und persönlich; keine Saisonwerte für andere Personen anzeigen.
  Gewichtsziele nur mit den Schutzgrenzen aus `GoalRules`.
- **Datenformate bleiben kompatibel:** `AppBackup` (Umzug von der Swift-App), Mahlzeit-Teilen, Coach-Export,
  Einstellungsschlüssel `coach.*`, Link-Schema `coach://`.
- UI-Texte auf Deutsch mit echten Umlauten, Bezeichner auf Englisch, Kommentare auf Deutsch.
- iOS 18+, Android 8.0+ (minSdk 26), nur Hochformat.

## Befehle

```sh
flutter pub get
dart format lib test packages
flutter analyze            # muss „No issues found!“ melden
flutter test
cd packages/coach_core && dart test
```

Flutter-Version: 3.47.9 (in allen Workflows festgelegt).

## CI

- `flutter.yml`: Format, Analyse, Tests (Linux, jeder PR und `main`); Fehler als PR-Kommentar.
- `android.yml`: Release-APK als Artefakt; Bereitstellung nur mit `vars.DEPLOY_ANDROID == 'true'`.
- `ios-build.yml`: unsignierte IPA (pseudo-signiert mit `ldid` und den Entitlements) per Label `ios-build`, auf
  `main` und per „Run workflow“; Bereitstellung nur mit `vars.DEPLOY_SIDESTORE == 'true'`.
- Aus Claude-Code-Cloud-Sitzungen ist die Actions-API gesperrt: Builds per Label starten, Ergebnisse über
  Check-Runs, PR-Kommentare und Releases lesen.

## Konventionen

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`, `test:`, `refactor:`), Scope optional
  (`feat(core): …`, `feat(gym): …`).
- Eine PR je Teilphase (Reihenfolge im Migrationsplan, Abschnitt 6).
