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

## 2026-11-13 – Datenschicht (Phase 2f)

- **Einstellungen als typisierte Werte in drift** (`SettingRecords`: Schlüssel, Typ, Bytes) statt in
  `shared_preferences`: Jeder Wert bleibt wie in den UserDefaults der Swift-App erhalten (`data`, `string`, `bool`,
  `int`, `double`) und geht unverändert in die Sicherung (`AppBackup.Value`). Gerätestand (`garmin.lastSync`,
  `gym.activeSession` …) liegt in derselben Tabelle, `AppBackup.isBackedUp` filtert ihn beim Sichern heraus.
- **Payload-Spalten bleiben Bytes** (JSON), wie die `Data`-Felder der SwiftData-Modelle. Eingespielte Einträge der
  Swift-App behalten ihre Bytes unverändert; die Dart-Modelle lesen Zeitpunkte als ISO-Text und als Sekunden seit 2001
  (Standard-`JSONEncoder`).
- **Richtung Flutter → Swift:** Die Dart-Modelle schreiben Zeitpunkte als ISO-Text. Eine Sicherung aus der
  Flutter-App lässt sich in der Swift-App einspielen, deren Standard-`JSONDecoder` liest Zeitpunkte in Einstellungen
  und Payloads aber nur als Zahl. Betroffen sind nur Werte mit Datum (z. B. Empfehlungen, KI-Protokoll); der Umzug
  ist ohnehin für die Richtung Swift → Flutter gedacht (`CLAUDE.md`).
- **Rückfall im Arbeitsspeicher** (`AppStorage.open`): Lässt sich die Datei nicht öffnen, startet die App mit einer
  leeren Datenbank im Speicher und zeigt das Warnbanner – wie `CoachSchema.makeContainer` in Swift.
- **Sicherungsordner:** Statt eines Security-Scoped Bookmarks speichert die App den Pfad (`backup.folder`); die
  Ordnerwahl mit dauerhaftem Zugriff folgt mit der Oberfläche (iOS-Bookmark bleibt nativ, Migrationsplan 4.2).

## 2026-11-13 – Netzwerk-Clients (Phase 2g)

- **Eine HTTP-Schicht für alle Dienste** (`HttpTransport`, umgesetzt mit dio): Jeder Status ist eine Antwort, nur
  fehlende Antworten werfen (wie `URLSession`). Tests ersetzen den Transport durch `FakeHttpTransport` statt
  `StubURLProtocol`. Eine Anmeldung bekommt einen eigenen Transport mit Cookie-Speicher (wie eine eigene
  `.ephemeral`-Sitzung).
- **Geheimnisse synchron lesbar** (`Secrets`): Der sichere Speicher von Flutter ist asynchron. Die App lädt alle
  Schlüssel beim Start einmal; danach liest sie synchron wie `SecretStore.string(for:)`, und Schreiben speichert
  sofort. So bleiben Abfragen wie `isConfigured` und `isLoggedIn` wie in Swift Eigenschaften.
- **Query-Parameter an den Worker** werden streng kodiert (`percentEncodeUnreserved`). `URLQueryItem` ließe `+`
  stehen, und der Worker würde es als Leerzeichen lesen.
- **Kaputte Antworten** von Garmin gelten als `GarminAPIError.invalidResponse`, die des Workers als
  `AIClientError.network("Unerwartete Antwort des Workers.")`. In Swift erscheint hier der englische Text des
  `DecodingError`.
- **Swift-Test `aiClientMapsUnauthorized`:** Dort liegt das App-Token vor dem ersten `configure`. Der Aufruf gilt dann als
  Serverwechsel und löscht das Token, sodass `notConfigured` statt `unauthorized` käme. Der Dart-Test setzt das Token
  deshalb mit der Adresse; das Verhalten von `configure` bleibt unverändert.
- **Swift-Test `syncStoresDaysActivitiesAndProfile`:** Er erwartet `activitiesUpdated == 1`. Der portierte Ablauf zählt
  dieselbe Aktivität im einmaligen 13-Wochen-Nachladen (`garmin.activityBackfill`) aber noch einmal, so wie der
  Swift-Code es auch tut. Der Dart-Test erwartet deshalb 2 und prüft zusätzlich, dass die Aktivität nur einmal
  gespeichert ist. Am Ablauf ändert sich nichts.
- **Gerätestand mit Datum** (`garmin.lastSync`) liegt als ISO-Text in den Einstellungen statt als `Date`-Objekt der
  UserDefaults. Diese Schlüssel gehören nicht zur Sicherung. Listen (`garmin.reportFailures`) werden als JSON
  gespeichert.
