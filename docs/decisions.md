# Entscheidungen

## 2026-11-13 – Migration nach Flutter

- **Auftrag:** Die native iPhone-App (Coach-App) vollständig nach Flutter migrieren, eine Codebasis für iOS und
  Android, 100 % Funktionsumfang. Audit und Checkliste: `migrationsplan.md`.
- **Flutter 3.47.9** (Dart 3.13.7) statt der zwei Tage alten 3.50.0: zwei Wochen alt, Patch-Stand, auf allen
  Runnern verfügbar. Quelle: <https://docs.flutter.dev/release/archive>.
- **Logik als eigenes Dart-Paket** (`packages/coach_core`, ohne Flutter) wie `CoachCore` als Swift-Paket: läuft
  mit `dart test` auf Linux, die Swift-Tests werden mit übertragen.
- **State Management Riverpod 3, Navigation go_router** (`StatefulShellRoute.indexedStack` = Reiter mit eigenem
  Stapel wie `TabView` + `NavigationStack`). Quellen: <https://riverpod.dev>,
  <https://pub.dev/documentation/go_router/latest/go_router/StatefulShellRoute-class.html>.
- **Gleiche App-Identität:** iOS `io.github.hkrb7p794w.coach`, Android `io.github.hkrb7p794w.gym`; Android
  `versionCode` = 10 000 + Laufnummer, iOS-Version 2.0.x (über der Swift-App 0.x), damit beide Stores (SideStore,
  Android-Paketinstallation) die Flutter-App als Update erkennen. Android verlangt dafür denselben Schlüssel.
  Quelle: <https://developer.android.com/studio/publish/app-signing#app-signing-google-play>.
- **Bereitstellung hinter Repo-Variablen** (`DEPLOY_SIDESTORE`, `DEPLOY_ANDROID`): Solange die Migration nicht
  fertig ist, darf kein Build die genutzten Apps ersetzen.
- **`MainActivity` erbt von `FlutterFragmentActivity`:** Voraussetzung des Pakets `health` für Health Connect.
  Quelle: <https://pub.dev/packages/health#android>.
- **Health-Connect-Datenschutz-Activity** (`ACTION_SHOW_PERMISSIONS_RATIONALE`, ab Android 14 `activity-alias` mit
  `VIEW_PERMISSION_USAGE`). Quelle: <https://developer.android.com/health-and-fitness/guides/health-connect/develop/get-started>.
- **Geheimnisse von Android-Backups ausgeschlossen** (`FlutterSecureStorage.xml`), wie in der Kotlin-App.
- **Native Teile, die nativ bleiben:** Widgets (SwiftUI/Glance), Live-Aktivitäten, App Intents, AlarmKit, Ordner-
  Sicherung mit Bookmark – Begründung und Ersatz in `migrationsplan.md`, Abschnitt 4.2.
- **Native Registrierung im `AppDelegate`** (workmanager, Mitteilungs-Delegate) kommt mit den Diensten, nicht
  vorab: Ohne Mac lässt sich Swift-Code nur im iOS-Build prüfen, also jeweils zusammen mit der Funktion.

## 2026-11-13 – JSON lesen wie Swift-`Codable`

- **Gleiches Verhalten bei unbekannten Werten:** Synthetisiertes `Decodable` in Swift verwirft eine ganze Liste bzw.
  ein ganzes Objekt, wenn ein Element nicht lesbar ist (z. B. `sports: ["x"]` → Standard `[run, strength]`); eigene
  `init(from:)` mit `try?` fallen je Feld auf den Standard zurück. Der Dart-Port bildet beides nach
  (`enumListStrict`, `listStrict`, je Feld tolerant), damit Sicherungen der Swift-App gleich gelesen werden.
- **Unveränderliche Wertobjekte**, wo Swift `struct` mit `let` nutzt; `WeekSchedule.set` wird zu `withSlots` (Kopie).
  Veränderliche Einstellungen (`UserProfile`, `NutritionSettings`) bleiben veränderlich wie die Swift-`var`-Felder,
  mit `copy()` für Kopien.

## 2026-11-13 – Rundung und Entpacken wie im Original

- **Bankers Rounding** (`roundHalfEven`): Swift nutzt in den Analysen `.toNearestOrEven`, weil die Regeln aus dem
  Python-Altbestand stammen (`round()` rundet dort zur geraden Zahl). Dart `round()` rundet von null weg; ohne eigene
  Rundung wichen Pace-Check und Entkopplung in Grenzfällen ab. Geprüft mit den Referenzfällen aus
  `analysis-cases.json`.
- **Eigener Inflate statt Paket `archive`:** `archive` liefert bei ungültigen Blöcken leere Daten statt eines Fehlers.
  Der Port der Swift-Umsetzung (nach `puff.c`) erkennt kaputte Daten wie bisher.
