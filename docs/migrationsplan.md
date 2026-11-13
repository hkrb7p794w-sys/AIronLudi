# AIronLudi (Flutter): Audit und Migrationsplan, Phase 1

Stand 13.11.2026. Grundlage: `hkrb7p794w-sys/Coach-App`, Commit `793d408` (main). Noch kein Code geschrieben.

## 0. Umfang in Zahlen

| Teil | Dateien | Zeilen | Ziel in Flutter |
|---|---|---|---|
| App-Oberfläche und Dienste (`ios/Coach`) | 120 | ≈ 28 500 Swift | Dart (Flutter-Widgets, Riverpod) |
| Reine Logik (`CoachCore`) | 140 | ≈ 26 000 Swift + 10 000 Datenzeilen | Dart-Paket ohne Flutter (`packages/coach_core`) |
| Tests der Logik | 90 | ≈ 11 000 Swift | Dart-Tests, gleiche Fälle und Fixtures |
| Widgets und Live-Aktivitäten (`CoachWidgets`, `Shared`) | 6 | ≈ 1 400 Swift | **bleibt nativ** (SwiftUI bzw. Kotlin/Glance), siehe 4.2 |
| Worker (`worker/`) | – | TypeScript | **unverändert**, bleibt im Coach-App-Repo |

314 SwiftUI-Ansichten, 6 SwiftData-Modelle, 40 Einstellungsbereiche in UserDefaults, 5 Keychain-Einträge,
14 Aufgaben im KI-Worker, 16 Garmin-Endpunkte (offiziell) und ein inoffizieller Garmin-Connect-Login.

**Was die App nicht nutzt** (also auch nicht migriert werden muss): Remote-Push (APNs/FCM), Biometrie
(Face ID), Standort/GPS des Geräts (Karten zeigen nur aufgezeichnete Strecken), Bluetooth, NFC, In-App-Käufe,
iCloud/CloudKit.

---

## 1. Screens, Navigation und UI-Komponenten

### 1.1 Navigation

- [ ] **Vier Reiter** (`RootView`): Heute · Aktivitäten (mit Zähler für Freundschaftsanfragen) · Training · Ernährung.
      Jeder Reiter hat einen eigenen Navigationsstapel. → `go_router` mit `StatefulShellRoute.indexedStack`
- [ ] **Onboarding** als Vollbild, bis das Profil fertig ist (`OnboardingView`).
- [ ] **Deep Links**, Schema `coach://`:
      `open/<route>` (today, health, nutrition, logMeal?mahlzeit=…, gym, startWorkout, ai, aiAnalysis),
      `join?worker&token&league` (Rangliste), `meal/<code>` (geteilte Mahlzeit), `account?…` (Konto-Einladung),
      Kochpartner-Links (`CookLink`). Auf Android zusätzlich `ironludi://connect|account` (bisherige Android-App).
- [ ] **Pending-Route-Logik** (`AppRouter`): Ziel erst nach dem Onboarding ausführen, Gym-Ziele nur mit Krafttraining.
- [ ] **Sheets, die die Wurzel öffnet:** empfangene Mahlzeit, Konto-Einladung, „schon angemeldet“, Kochpartner,
      Ligabeitritt, „Einheit verschieben“ (aus einer Mitteilung), „Nächste Woche planen“ (aus der Sonntags-Mitteilung).
- [ ] **Speicherwarnung** als Banner oben, wenn die Datenbank nicht geöffnet werden konnte.
- [ ] **Darstellung:** Wie System / Hell / Dunkel (`AppAppearance`). → `ThemeMode`
- [ ] Nur Hochformat, nur Telefon.

### 1.2 Screens nach Bereich (Ansichten je Datei aus dem Code gezählt)

| Bereich | Wichtigste Screens und Komponenten | Ansichten |
|---|---|---|
| **Heute** | TodayView (Saison- und persönlicher Modus), Jetzt dran / Fokus, Vorschläge mit Diff und Regelprüfung, Wochenrückblick, Hinweise, Coach-Notiz, Rest der Woche, Wochenübersicht, Sync-Status, Chat mit dem Coach, Tag anpassen (verschieben/auslassen) | 33 |
| **AI** | Empfehlungen nach Themen (neu/gelesen/umgesetzt/verworfen), Grundlage einer Empfehlung, Prompt-Bibliothek mit eigenen Prompts | 7 |
| **Aktivitäten / Social** | Eigene Trainings und Freundes-Feed, Beiträge mit Reaktionen und Kommentaren, Freundesliste, Suche, Anfragen, Sperren, Profil einer Person, Teilen mit Freunden | 12 |
| **Training** | TrainingView mit Erholung, Trendkarten, Schlafphasen, km/Woche, Pulszonen, Intensität; Aktivitätsfeed und -detail (Karte, Verlauf, Runden, Splits, Laufdynamik, Schwimmwerte, Trainingseffekt); aerobe Entkopplung, Pace-Check; Seiten Schwimmen/Rad/Laufen/Almere/Marathon mit Tests, Trends und Prognosen; Fitness/Form, Wochenbericht, Trends mit Zoom; Schlaf-Coach; Nach-dem-Training-Karte | 40 |
| **Plan** | Saisonplan nach Wochen, Einheitsdetail mit Anleitung und Glossar, Meine Woche (persönlich) mit Summen und Zusatzaktivitäten, Plan-Editor, Nächste Woche planen, verpasste Einheiten, Training nachtragen, an die Garmin-Uhr senden | 22 |
| **Gym** | Hub (heute, Fortschritt, Volumen, Kalender, Verlauf), **laufende Einheit** (`ActiveWorkoutView`, 1 700 Zeilen: Fokus-Karte, Übungsleiste, Satz-Editor mit Ziffernblock, Halte-Stoppuhr mit Korrektur, Pausen-Panel, RIR-Abfrage, Rückgängig, Supersätze, Satzarten, Ersetzen/Reihenfolge, Plan geschafft, Abschluss mit Vergleich und „Nächstes Mal“), Übungsbibliothek mit Filter und Anleitung, eigene Übungen, Routinen, Ausrüstung (Stange/Scheiben), Muskel-Heatmap mit Körperkarte, Übungsverlauf (Diagramme mit Zoom), KI-Plan mit Fragebogen, GymBook-Import, Garmin-Verknüpfung | 58 |
| **Health** | Health-Dashboard mit konfigurierbaren Karten, Morning Report, Body Battery (Tagesverlauf, Verlauf), Mobility mit Selbsttests, Wecker zur Aufstehzeit | 21 |
| **Ernährung** | NutritionView (Tagesstreifen, Budget, Kalorienring, Makrobalken, Kacheln, konfigurierbares Dashboard, Nährstoffe, Mahlzeiten, Schnell-Eintrag, Wasser), Erfassen (Foto, Kamera, Text, Diktat, Barcode, Suche in BLS, Zuletzt/Häufig/Favoriten/Wie gestern), Mahlzeit-Editor mit Entwurf und Positionsdetail, fehlende Barcodes, Ergänzen per Text, gegessene Menge anpassen, „Was esse ich jetzt?“, eigene Rezepte/Meal-Prep, Gewichtsverlauf mit Prognose, Mahlzeit teilen/empfangen | 36 |
| **Rezepte** | Rezeptideen für frei wählbaren Zeitraum, Rezeptdetail, Einkaufsliste nach Abteilung, Vorlieben, gemeinsam kochen (Kochplan, Partner, Freigabe) | 8 |
| **Einstellungen** | Bereiche Konto, Disziplinen (Gym: Pausen je Übung, Aufwärmen, Ton/Vibration; Ausdauer: Pulszonen), Ernährung (Erinnerungen je Mahlzeit), Saison, Erinnerungen, Apple-Health-Import, Datenquellen mit Vorrang und Integrationsmatrix, KI (Anbieter-Stufen, Nutzung), Trainingspause/Urlaub, Datensicherung, Export/Import für externe KI, Android-Link, Quellen (Evidenz) und eigene Quellen, Diagnose (HealthKit, Garmin-Rohantworten) | 40 |
| **Konto** | Registrieren (nur mit Einladung), Anmelden, Wiederherstellungscode, Kontodetails, Passwort ändern, „überall abmelden“, Konto löschen | 6 |
| **Motivation / Spiel** | Begleiter (Hund „Daisy“ als gezeichneter Avatar oder eigenes Foto), Rangliste, Liga beitreten; Serie mit Joker, Stufen, 18 Abzeichen, Wochen-Challenges | 11 |
| **Onboarding** | Assistent: Ziele, Prioritäten, Tracker, Sportarten, Wochenplan-Editor, Eingabeprüfung | 10 |

### 1.3 Gemeinsame UI-Bausteine

- [ ] Designsystem: Farben je Sportart (`SportStyle`), Karten, Chips, Ringe, Plaketten, Hell/Dunkel.
- [ ] **Diagramme** (Swift Charts, in 14 Dateien): Linien, Balken, Flächen, Zonenbänder, Zoom mit zwei Fingern
      (Trends, Übungsverlauf). → `fl_chart` plus eigene Zoom-Geste (`ChartZoom` steckt schon als Logik in CoachCore)
- [ ] **Karte** der Aktivitätsstrecke (MapKit). → `flutter_map` (OpenStreetMap, kein API-Schlüssel nötig)
- [ ] Gezeichneter Avatar „Daisy“ (`DaisyGeometry` in CoachCore). → `CustomPainter`
- [ ] Körperkarte für die Muskel-Heatmap. → `CustomPainter`
- [ ] Haptik (`sensoryFeedback`) bei Auswahl, erledigtem Satz, Pausenende. → `HapticFeedback` aus Flutter
- [ ] Wischaktionen in Listen, Kontextmenüs, Ziffernblock, Stepper. → Flutter-Bordmittel (`Dismissible`, `MenuAnchor`)

---

## 2. Datenmodelle, Speicher und Schnittstellen

### 2.1 Lokale Datenbank (heute SwiftData)

| Modell | Schlüssel | Inhalt |
|---|---|---|
| `DailyMetricsRecord` | dayKey | Tageswerte (JSON `DailyMetrics`) |
| `ActivityRecord` | garminID | Aktivität (JSON `GarminActivity`) |
| `RawResponseRecord` | endpoint | Garmin-Rohantwort (Diagnose) |
| `SourceRecord` | key | Einträge je Quelle mit Hash und Status (Zusammenführen, Doppelte) |
| `MealRecord` | id (UUID) | Mahlzeit mit Positionen (JSON) |
| `FoodRecord` | key | Eigene/zuletzt genutzte Lebensmittel |
| `GymSessionRecord` | id (UUID) | Krafteinheit (JSON), Status Health/Garmin |

→ **`drift`** (SQLite, typisiert, Migrationen, läuft auf iOS und Android gleich). Die Payload-Spalten bleiben JSON,
damit Sicherungen kompatibel bleiben. Rückfall wie heute: lässt sich die Datenbank nicht öffnen, dann im Speicher
weiterarbeiten und das Warnbanner zeigen.

### 2.2 Einstellungen (heute UserDefaults, 40 Schlüssel `coach.*` als JSON)

Profil, Saison, Plananpassungen, Erinnerungen, Gym, Ernährung, KI, Nutzung, Empfehlungen, Gewichte, Schlaf,
Dashboards, Mobility, Quellen, eigene Rezepte, Vorrat, Kochpartner usw. Dazu die laufende Gym-Einheit
(übersteht ein Beenden der App), die Offline-Warteschlange der Mahlzeiten-Analyse (Text in den Einstellungen,
Foto als Datei), Rezept- und Kochpläne als JSON-Dateien und Garmin-Sicherungen als Dateien.

→ Eine **Key-Value-Tabelle in drift** mit denselben Schlüsseln (eine Quelle der Wahrheit, gehört zur Sicherung).
Dateien unter `path_provider` (Application Support). Kleine Komfortwerte (z. B. eingeklappte Panels) →
`shared_preferences`.

### 2.3 Geheimnisse (heute Keychain, „nur dieses Gerät, nach erstem Entsperren“)

`garminAPIKey`, `garminBearerToken`, `garminConnectToken`, `aiAppToken`, `accountSession`.
→ **`flutter_secure_storage`**: iOS Keychain mit `first_unlock_this_device`, Android Keystore. Auf Android von
Auto Backup ausgeschlossen (`data_extraction_rules.xml`), wie heute in der Kotlin-App.

### 2.4 Externe Schnittstellen

- [ ] **Garmin Personal API** (offiziell, `personal.connectapi.garmin.com`, Key des Nutzers): Tageswerte,
      Schlaf, HRV, Stress, Body Battery, SpO2, Puls, Gewicht, Fitnessalter, Pulszonen, Aktivitätsliste und -details,
      FIT-Download.
- [ ] **Garmin Connect** (inoffizieller Login mit MFA-Code, Cookies, Token-Erneuerung, zufällige Pause gegen
      Cloudflare-429): Readiness, Trainingsstatus, Prognosen, **FIT-Upload** der Krafteinheit mit Sätzen,
      **Workouts an die Uhr senden**. → `dio` + `cookie_jar`.
      ⚠️ Risiko: Cloudflare unterscheidet Clients auch am TLS-Fingerabdruck. Ob der Dart-HTTP-Client wie
      `URLSession` durchkommt, muss früh in Phase 2 getestet werden. Rückfall: `cupertino_http` (iOS nutzt dann
      `URLSession`) bzw. `cronet_http` (Android).
- [ ] **Cloudflare Worker** (bleibt unverändert): `v1/ai/generate` mit 14 Aufgaben (ping, daily_note, personal_note,
      meal_analyze, meal_amend, nutrition_label, nutrition_review, gym_hints, gym_plan, coach_chat, ai_insights,
      meal_now, weekly_recipes, cook_plan), `v1/account/*`, `v1/social/*`, `v1/game/*`, `v1/league/*`,
      `v1/share/meal|cook`, `v1/invite`, `v1/usage`, `v1/health`, SideStore-Quelle, Android-Download-Seite.
- [ ] **Open Food Facts** (Barcode).
- [ ] **Datenformate, die gleich bleiben müssen:** `AppBackup` (Sicherung, auch zum Umzug von der alten App),
      CoachExport/CoachImport (externe KI), Mahlzeit-Teilen (iPhone ↔ Android), FIT (Kodieren/Dekodieren, Inflate,
      ZIP), GymBook-Backup (SQLite, nur lesen).

### 2.5 Mitgelieferte Daten

`bls.tsv` (BLS 4.0, 7 000 Lebensmittel), `season-plan.json`, Übungsbibliothek und -katalog, Evidenz-Regeln mit DOI,
deutsche Feiertage, 3 Pausentöne (`rest-beep|bell|chime.wav`), App-Icon. → Flutter-Assets.

---

## 3. Business-Logik und State-Management

### 3.1 CoachCore: 1:1-Port nach `packages/coach_core` (reines Dart, ohne Flutter)

Jedes Modul wird mit seinen Tests übertragen. Die Tests sind der Nachweis der Parität: kein Modul gilt als fertig,
solange nicht alle übertragenen Tests grün sind.

- [ ] **Coach** (13 Dateien): Tagesampel/Empfehlung, Pulszonen, Fitness/Form, Saisonplan, Schlaf-Coach, Trends,
      Wochenbericht/-rückblick, Coaching-Notizen, Chat-Kontext und Chat-Router
- [ ] **Profile** (16): UserProfile (Modus Saison/persönlich), **GoalRules (Schutzgrenzen)**, Eingabeprüfung,
      Belastungsprüfung, Personalisierung, Plananpassungen, Planvorschläge, Laufplan, Wochenplan und -planer,
      Zuordnung Soll/Ist (`SessionMatch`), Wochenlast, Trainingspause, Nach dem Training
- [ ] **Plan** (5): Disziplinen, Saison-Zeitplan, Tagesfokus, Tagesplan, Einheitsanleitungen
- [ ] **Gym** (17): Progression (Doppelprogression), Coach-Hinweise, Routinen, Plan, Ablauf der Einheit,
      Bearbeitungen/Rückgängig, Statistik, Muskelbelastung, Werkzeuge (Stange/Scheiben, 1RM), GymBook-Import, Bibliothek
- [ ] **Nutrition** (19): Tagesziele, BLS-Suche und -Zuordnung, Portionen, Schnell-Eintrag, Wasser, Verbrauch,
      Gewichtstrend und -prognose, Check-in, Rezeptplanung, Kochplan, Mahlzeiten-Erinnerungen, Teilen, Open Food Facts
- [ ] **Health** (9): Body Battery, Morning Report, persönliche Normalbereiche, Health-Dashboard, Health-Import und
      -Aufzeichnung, Zugriffsdiagnose, Weckplan, Feiertage
- [ ] **Analysis** (8): Aktivitätsdetails, -analyse, -bericht, Feed (Doppelte zusammenführen), aerobe Entkopplung,
      Pace-Check, Chart-Zoom
- [ ] **Garmin** (10): Endpunkte, Tageswerte, Aktivitäten, Connect-Ablauf, Token, Workouts, Kraft-Sync, JSONValue, Sync-Plan
- [ ] **Fit** (4): FIT-Dekoder/-Enkoder, Inflate, ZIP → Inflate/ZIP über das Paket `archive`, FIT selbst portiert
- [ ] **Integration** (3): Datenquellen mit Vorrang, Zusammenführen, Sync-Protokoll
- [ ] **AI** (3): KI-Richtlinie und Datenschutzstufen, Nutzung, Empfehlungen
- [ ] **Report** (6): AppBackup, CoachExport/Import, DataExport, Musterpersonen-Bericht (`coach-report`), Prompt-Bibliothek
- [ ] **Mobility, Motivation, Game, Social, Account, Evidence, Widgets, App** (Routen, Darstellung, Widget-Snapshot)

### 3.2 App-Dienste (heute `Coach/Core`) → Riverpod-Provider

| Heute (Swift, `@Observable`) | Aufgabe | Flutter |
|---|---|---|
| `AppModel` | zentrale Abhängigkeiten, Sync-Steuerung, Backoff | Provider-Graph + `SyncController` |
| `GarminClient`, `GarminConnectSession`, `GarminSyncService` | Abruf, Login, Speichern | `garmin/` Dienste |
| `HealthImportService`, `HealthKitProbe`, `WorkoutWriter` | Health lesen/schreiben | `health/` Dienst (siehe 4.1) |
| `SourceStore` | Vorrang, Doppelte, Sync-Status | `sources/` Repository |
| `AIClient` | Worker-Aufrufe, Datenschutz, Nutzungsprotokoll | `ai/` Client |
| `CoachSettings` | 40 Einstellungsbereiche | `settings/` Repository + Provider je Bereich |
| `ReminderService` | Mitteilungen der nächsten 14 Tage | `notifications/` |
| `AccountService`, `SocialService`, `GameService`, `LeagueService` | Konto, Freunde, Spiel, Liga | jeweils ein Dienst |
| `BackupService` | Sicherung, Einspielen, täglicher Ordner | `backup/` |
| `WidgetPublisher`, `MealsActivityController`, `WorkoutActivityController` | Widgets/Live-Aktivitäten | `widgets/` (Plattformbrücke) |
| `WakeAlarmService` | Wecker | `alarm/` (Plattformbrücke) |
| `Dictation` | Diktat | `speech/` |
| `GymBookReader` | Import aus SQLite | `gym/` mit `sqlite3` |
| `SocialAutoShare`, `DayChange` | automatisches Teilen, Tageswechsel | Provider |
| ViewModels (Today, Training, Plan, Gym, Nutrition, Recipe, AI, Settings, Diagnostics) | Screen-Zustand | je ein `Notifier` |

**Abläufe, die gleich bleiben müssen:** Sync beim Öffnen nur wenn fällig (Backoff 1 min bis 6 h), erst Garmin,
dann Health; danach Doppelte entfernen, Gym-Sätze zu Garmin nachtragen, Erinnerungen neu planen, Widgets
aktualisieren. Beim Wechsel in den Hintergrund: Hintergrundabruf planen, höchstens einmal täglich in den Ordner
sichern, Schnellaktionen aktualisieren. Erinnerungen neu planen bei Plan-, Profil- oder Zeitzonenwechsel und bei
Start oder Ende einer Einheit. Nie begonnene Gym-Einheiten verwerfen. Tageswechsel um Mitternacht.

---

## 4. Systemfunktionen: Flutter-Paket und Android-Gegenstück

### 4.1 Mit Cross-Platform-Paketen abbildbar

| iOS heute | Flutter-Paket (pub.dev) | iOS-Konfiguration | Android-Gegenstück und -Konfiguration |
|---|---|---|---|
| **HealthKit** lesen: Workouts mit Puls, Strecke und Leistung, Schlaf, Ruhepuls, HRV, aktive Energie, Gewicht; schreiben: Krafttraining als Workout | `health` | Capability HealthKit, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` | **Health Connect**: Berechtigungen `health.READ_*`/`WRITE_EXERCISE`, Activity-Alias für die Datenschutzerklärung, `minSdk 26`, `queries` für das Health-Connect-Paket. ⚠️ Strecke (Route) und Pulsreihe je Workout: Abdeckung im Paket in Phase 2 prüfen, sonst eine kleine Plattformbrücke |
| **Lokale Mitteilungen** mit Kalender-Auslöser, Kategorien und Aktionen (Erledigt / Verschieben … / Diese Woche auslassen), Pausenende-Mitteilung | `flutter_local_notifications` + `timezone` + `flutter_timezone` | Kategorien bei der Initialisierung (`DarwinNotificationCategory`) | Kanäle, Aktionen, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` bzw. `USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED` (Neuplanung nach Neustart) |
| **Hintergrundabruf** (`BGAppRefreshTask` alle ≥ 2 h) | `workmanager` | `UIBackgroundModes: fetch`, `BGTaskSchedulerPermittedIdentifiers`, Registrierung im `AppDelegate` | WorkManager, periodisch, mit Netz-Bedingung |
| **Keychain** | `flutter_secure_storage` | Accessibility `first_unlock_this_device` | Android Keystore; vom Backup ausschließen |
| **Kamera** für Mahlzeit-Fotos, **Fotoauswahl** | `image_picker` | `NSCameraUsageDescription` (Fotoauswahl braucht unter iOS 14+ keine Berechtigung) | System-Fotoauswahl (Photo Picker, ohne Berechtigung), Kamera über `ACTION_IMAGE_CAPTURE` |
| **Barcode-Scanner** (VisionKit DataScanner), Eingabe von Hand als Rückfall | `mobile_scanner` | `NSCameraUsageDescription` | ML Kit, Berechtigung `CAMERA` (die bisherige Kotlin-App kam über den Google-Code-Scanner ohne sie aus) |
| **Diktat** auf Deutsch, wenn möglich auf dem Gerät | `speech_to_text` | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` | `SpeechRecognizer`, `RECORD_AUDIO`, `queries` für `RecognitionService` |
| **Teilen** (Dateien, Links, Text) | `share_plus` | – | Share-Sheet, `FileProvider` |
| **Zwischenablage** | Flutter `Clipboard` | – | – |
| **Datei importieren/exportieren** (Sicherung, GymBook) | `file_picker`, `file_saver` | – | Storage Access Framework |
| **Bildschirm an** während der Einheit | `wakelock_plus` | – | `FLAG_KEEP_SCREEN_ON` |
| **Pausentöne** (Ambient, Lautlos-Schalter beachten), Systemton | `audioplayers` + `audio_session` | Kategorie `ambient` | `AudioAttributes` USAGE_NOTIFICATION |
| **Haptik** | `HapticFeedback` (Flutter); bei Bedarf `vibration` für Muster | – | `VIBRATE` |
| **Schnellaktionen am App-Icon** (dynamisch, max. 4) | `quick_actions` | – | App Shortcuts (dynamisch) |
| **Deep Links** `coach://` | `app_links` | `CFBundleURLTypes` | `intent-filter` je Host (`coach://open|join|meal|account`, `ironludi://connect|account`) |
| **Karte** | `flutter_map` + `latlong2` (OSM-Kacheln, Nutzungsrichtlinie beachten, Quellenangabe) | – | – |
| **Diagramme** | `fl_chart` | – | – |
| **SQLite** (GymBook lesen) | `sqlite3` (über drift ohnehin dabei) | – | – |
| **Darstellung** System/Hell/Dunkel | `ThemeMode` | – | – |
| Netz | `dio`, `cookie_jar` (Garmin), bei Bedarf `cupertino_http`/`cronet_http` | ATS-Standard reicht (nur HTTPS) | `INTERNET` |
| Datum/Zahlen auf Deutsch | `intl` (de_DE) | `CFBundleDevelopmentRegion de` | – |
| Eigenes Foto für den Begleiter | `image_picker` | – | – |

### 4.2 Nicht vollständig in Dart möglich: nativer Teil nötig (ehrlich benannt)

Diese Funktionen haben in Flutter kein reines Dart-Gegenstück. Die **Daten und die Logik** liegen trotzdem im
gemeinsamen Dart-Code; nur die Darstellung oder der Systemaufruf ist plattformspezifisch.

| Funktion | Lösung iOS | Lösung Android |
|---|---|---|
| **Homescreen- und Sperrbildschirm-Widgets** (Heute, Ernährung, Mahlzeiten, Health, Gym; konfigurierbar; Wasser-Knopf; „+“ je Mahlzeit) | Paket `home_widget` für den Datenaustausch über die App Group; die Widget-Oberflächen bleiben **SwiftUI** in einer Widget-Erweiterung (heutiger Code wird übernommen). ⚠️ SideStore benennt die App Group um (`group.<id>.<TEAMID>`): die tatsächliche Gruppe wird wie heute aus dem Provisioning-Profil gelesen (kleine Swift-Brücke) | Paket `home_widget`, Widgets mit **Jetpack Glance** (Kotlin): gleiche Kacheln, Konfiguration über eine Configure-Activity, Wasser-Knopf als interaktive Aktion |
| **Live-Aktivität Gym** (Pause, nächster Satz, Gewicht/Wdh. ±, „Satz erledigt“ und „Pause überspringen“ ohne Entsperren) und **Live-Aktivität Mahlzeiten** | Paket `live_activities` für Start/Aktualisierung aus Dart; Oberfläche und `LiveActivityIntent`-Knöpfe bleiben **Swift** (heutiger Code). Die Knöpfe schreiben in die App Group, Dart übernimmt die Änderung | **Laufende Mitteilung** (Foreground-Service-Typ `shortService`/`specialUse` bzw. Android-16-„Live Update“) mit Aktionen „Satz erledigt“, ±, „Pause überspringen“ über `flutter_local_notifications` + Hintergrund-Isolate; `FOREGROUND_SERVICE` |
| **Siri-Kurzbefehle / App Shortcuts** (Training starten, Mahlzeit erfassen, Health, KI-Analyse) | 4 kleine `AppIntent`s in Swift im Runner, öffnen `coach://open/…` (kein gepflegtes Flutter-Paket für App Intents) | Gegenstück sind die App Shortcuts aus `quick_actions` (Google Assistant liest sie mit) |
| **Wecker zur Aufstehzeit** (AlarmKit, klingelt auch im Lautlos- und Fokus-Modus, mit Ersatzweg) | Plattformbrücke zu AlarmKit (iOS 26), Rückfall wie heute | `AlarmManager.setAlarmClock` + Vollbild-Intent; Paket `alarm` oder eigene Brücke; `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT` |
| **Täglich in einen gewählten Ordner sichern** (Security-Scoped Bookmark, z. B. iCloud Drive) | Plattformbrücke (Bookmark speichern und auflösen), kein gepflegtes Paket | Storage Access Framework mit dauerhafter URI-Berechtigung (`takePersistableUriPermission`), Paket `shared_storage` oder eigene Brücke |

### 4.3 Info.plist und AndroidManifest (Zielbild für Phase 2)

**iOS (`ios/Runner/Info.plist` + Entitlements):** `CFBundleDisplayName` AIronLudi, Entwicklungsregion de,
nur Hochformat, `CFBundleURLTypes` (coach), `NSSupportsLiveActivities`, `UIBackgroundModes` (fetch),
`BGTaskSchedulerPermittedIdentifiers`, die sechs Usage-Descriptions (Health lesen/schreiben, AlarmKit, Kamera,
Mikrofon, Spracherkennung, Texte unverändert übernommen), `ITSAppUsesNonExemptEncryption = false`;
Entitlements HealthKit und App Group; Widget-Erweiterung `CoachWidgets` mit derselben App Group; iOS 18.0.

**Android (`AndroidManifest.xml`, `build.gradle.kts`):** `INTERNET`, `CAMERA`, `RECORD_AUDIO`, `VIBRATE`,
`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM`,
`USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE` (+ Typ), `WAKE_LOCK` (WorkManager), Health-Connect-Berechtigungen;
`intent-filter` für die Deep Links; `queries` (Health Connect, Spracherkennung, Kamera); Glance-Widget-Receiver;
Backup-Regeln ohne Geheimnisse; `minSdk 26`, `targetSdk 35`; Release-Signatur aus GitHub-Secrets.

---

## 5. Ordnerstruktur für AIronLudi

```
AIronLudi/
├── pubspec.yaml                 # App
├── analysis_options.yaml        # strenge Lints (flutter_lints + eigene Regeln)
├── packages/
│   └── coach_core/              # reines Dart, ohne Flutter: Port von CoachCore
│       ├── lib/src/<modul>/     # coach, profile, plan, gym, nutrition, health, analysis,
│       │                        # garmin, fit, integration, ai, report, mobility, motivation,
│       │                        # game, social, account, evidence, widgets, app
│       ├── assets/              # bls.tsv, season-plan.json
│       ├── test/                # übertragene Tests, gleiche Namen wie in Swift
│       │   └── fixtures/        # dieselben Fixtures wie CoachCoreTests
│       └── bin/coach_report.dart  # Prüfbericht mit Musterpersonen
├── lib/
│   ├── main.dart
│   ├── app/                     # App-Widget, Router (go_router), Theme, Darstellung, Deep Links,
│   │                            # Lebenszyklus (Vordergrund/Hintergrund)
│   ├── data/
│   │   ├── db/                  # drift: Tabellen, DAOs, Migrationen
│   │   ├── settings/            # Key-Value-Repository (coach.*-Schlüssel)
│   │   ├── secure/              # flutter_secure_storage
│   │   └── repositories/        # Meals, Gym, Activities, Metrics, Sources
│   ├── services/                # garmin/, health/, ai/, account/, social/, game/, league/,
│   │                            # notifications/, background/, backup/, speech/, widgets/,
│   │                            # live_activity/, alarm/, share/
│   ├── platform/                # MethodChannel-Brücken (App Group, Bookmarks, AlarmKit, App Intents)
│   ├── features/<bereich>/      # today, activities, training, plan, gym, health, nutrition,
│   │   ├── view/                # recipes, ai, settings, account, motivation, game,
│   │   ├── controller/          # onboarding, evidence, diagnostics
│   │   └── widgets/
│   └── ui/                      # Designsystem, Diagramm-Bausteine, Karte, Avatar, Körperkarte
├── assets/                      # sounds/, images/, App-Icon-Quellen
├── ios/
│   ├── Runner/                  # Info.plist, Entitlements, AppDelegate, AppIntents (Swift)
│   └── CoachWidgets/            # Widgets + Live-Aktivitäten (SwiftUI, übernommen)
├── android/
│   └── app/src/main/kotlin/…/widgets/   # Glance-Widgets, laufende Mitteilung
├── test/                        # Widget- und Controller-Tests der App
├── integration_test/            # Abläufe (Onboarding, Mahlzeit erfassen, Gym-Einheit)
├── docs/                        # decisions.md, migrationsplan.md (diese Checkliste, wird mitgeführt)
└── .github/workflows/           # analyze+test (Linux), Android-APK, iOS-IPA für SideStore (macOS)
```

---

## 6. Vorschlag für die Reihenfolge (Phasen 2 und 3 in PRs)

Der Umfang (≈ 65 000 Zeilen) passt nicht in eine PR. Vorschlag: je PR ein Teil, jeweils mit Tests und
`flutter analyze` ohne Warnungen.

1. **Phase 2a:** Projekt, Abhängigkeiten, Info.plist/Manifest/Gradle, CI (Linux, Android-APK, iOS-IPA), leere
   Reiter-Navigation. Früher Test: Garmin-Connect-Login über `dio` (TLS-Risiko).
2. **Phase 2b–2e:** `coach_core` modulweise mit allen Tests (Profile/Coach/Plan → Gym → Nutrition/BLS →
   Health/Analysis/Garmin/Fit → Rest).
3. **Phase 2f:** Datenbank, Einstellungen, Geheimnisse, AppBackup-Kompatibilität, API-Clients, Provider.
4. **Phase 3a–3k:** Bereiche: Onboarding und Einstellungen → Ernährung → Gym → Heute → Training/Plan → Health →
   AI und Chat → Social, Spiel, Konto → Rezepte → Widgets/Live-Aktivitäten nativ → Feinschliff und Abgleich mit
   dieser Checkliste.

---

## 7. Entscheidungen (freigegeben am 13.11.2026)

1. **Schreibzugriff** auf AIronLudi: erteilt.
2. **Sichtbarkeit:** AIronLudi bleibt vorerst öffentlich (Actions-Minuten auch für macOS kostenlos). Keine Secrets
   im Repo; die Worker-Adresse steht nicht im Code, sie wird wie bisher in der App eingegeben bzw. per Link übergeben.
   Auf privat stellen geht jederzeit unter Settings › General › Danger Zone.
3. **App-Identität:** iOS-Bundle-ID `io.github.hkrb7p794w.coach` (ersetzt die Swift-App in SideStore), Android
   `io.github.hkrb7p794w.gym` (ersetzt die Kotlin-App, gleicher Signaturschlüssel, `versionCode` = 10 000 + Lauf).
   Umzug der Daten über die Sicherung (`AppBackup`, Format bleibt gleich).
4. **Auslieferung:** Worker bleibt im Coach-App-Repo. AIronLudi lädt in denselben KV-Speicher hoch (Schlüssel
   `Coach.ipa`, `release.json`, `android.apk`, `android.json`), aber **erst, wenn die Repo-Variablen
   `DEPLOY_SIDESTORE` bzw. `DEPLOY_ANDROID` auf `true` stehen** – also nach erreichter Parität. Bis dahin bleiben
   die genutzten Apps unangetastet. Dafür braucht AIronLudi die Secrets `CLOUDFLARE_API_TOKEN`,
   `CLOUDFLARE_ACCOUNT_ID`, `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD` (Settings › Secrets and variables ›
   Actions, dieselben Werte wie in Coach-App).
5. **Coach-App** bekommt während der Migration nur noch Fehlerbehebungen.

## 8. Stand der Umsetzung

| Teil | Stand |
|---|---|
| Phase 2a: Projekt, Abhängigkeiten, Info.plist/Entitlements, AndroidManifest/Gradle, CI, vier Reiter, Deep Links `coach://open/…`, Darstellung, App-Icon | in PR |
| coach_core: `CalendarDay`/`DateRange`, `AppRoute`/`AppTab`/`QuickActions`, `AppAppearance`, `MealCategory` (mit Tests) | in PR |
| coach_core Ernährung (Teil 1): `JsonValue`, `GermanFormat`, `Nutrient`/`NutrientValues`, `MealItem`/`Portion`/`MealAnalysis`/`NutritionSummary`, `PortionGuess`, `NutrientCheck`, `NutritionLabel`, `OpenFoodFacts`, `Hydration`/`MealSplit`, `BLS` mit Suche und Zuordnung (alle 17 Zuordnungsfälle), JSON kompatibel zu Swift | in PR |
| coach_core Profil (Teil 1): `UserProfile` mit allen Enums, `WeekSchedule`/`SessionSlot`/`Weekday`, `PersonalGoals`/`TrackerSetup`/`Personalization` (Ableitung, Ernährungsrichtung, Prioritäten, KI-Kontext), `GoalRules` (alle Schutzgrenzen), `NutritionSettings`/`DayType`/`NutritionGoal`/`Diet`/`BodyProfile`, `WeightEntry` + `WeightTrend.merged`, `DataProvider`/`DataKind`; Lesen wie Swift-`Codable` | in PR |
| coach_core Tagesziele: `NutritionPlanner` (Tagestyp, Plan-Tagestyp, Energie, Makros, Mikros, Wasser, alle Schutzgrenzen im Rechenweg), `NutritionTargets`, `DayClassification`; dazu `GarminActivity` mit Parser (Liste und Details), `GarminProfile`, `RecoveryLevel`, `TemplateItem`, `ActivitySource`, `StrengthDuplicates`, `SessionMatcher.defaultMinutes/sport`, `WeekSchedule.templateItems`, `TrainingSport.garminSport`, `NutritionSettings.profile` | in PR |
| coach_core Saisonplan: `SeasonConfig` (Lesen wie Swift), `TrainingPhase`, Phasengrenzen, Wochen-Soll je Phase, Musterwoche, `PlanState`, `WeeklyVolume` (mit Gym-Tagen der App), `TestPaces`, `PhasePlanTexts`; `UserProfile.personalDraft` | in PR |
| coach_core Wochen-Soll/Ist: `SessionMatcher` (Zuordnung, Ersatz, Gym-Tage, Summen), `SessionStatus`, `PlannedSession`, `SessionResult`, `MissedSessions` (verpasst, Nachholtag, Krankheit), `ManualActivity`; `PlanAdjustments` (Auslassen, Verschieben, Wochenplan je Woche), `PlanMoveAdvisor`, `ReminderPlanner.personal/body/weekPlanning`, `TrainingLog`, `ScheduledNote`; `ScheduleCheck` mit allen Hinweisen; `TrainingBreak`; `SessionKind`, `AerobicDecoupling.highZoneShare` | in PR |
| coach_core Tagesampel: `DailyMetrics` mit allen Feldern und `GarminMetricsParser` (Tageszusammenfassung, HRV, Schlaf mit Zeiten, Body Battery mit Verlauf, Stress, SpO2, Fitnessalter, Zusammenführen), `RecoveryEvaluator` (Ampel, Tageszustand mit Rückfall auf die letzte Nacht), `Recommendation` mit Form-Grenze, `FitnessForm`, `LoadCheck` (Wochenumfang, Einzellauf), `WeekLoad.load`, `Personalization.maxLoadIncrease/adjustCounts` | in PR |
| coach_core Aktivitätsverlauf: `ActivityFeed` (Zusammenführen von Garmin, Health, Nachgetragenem und Gym-Einheiten, Filter, Kernwerte, Tempo, Zonen, Fehlendes), `ActivityDetails` (Abschnitte wie Garmin Connect, Formate), `ChartZoom`, `WeekLoad.check` | in PR |
| coach_core FIT und Analysen: `FitDecoder` (Records, Runden, Sätze; beide Byte-Reihenfolgen, komprimierte Zeitstempel, Entwicklerfelder), `ZipArchive`, eigener `Inflate` (wie Swift, erkennt kaputte Daten), `AerobicDecoupling` vollständig, `PaceCheck`, `ActivityAnalysis`/`ActivityAnalysisPlanner`, `ActivityDetails.samples/route`; Rundung wie Python (`roundHalfEven`). Alle Referenzfälle aus dem Altbestand stimmen | in PR |
| Datenschicht Teil 1 (Phase 2f-1): drift-Datenbank mit den sieben Modellen der Swift-App (`DailyMetricsRecords`, `ActivityRecords`, `RawResponseRecords`, `SourceRecords`, `MealRecords`, `FoodRecords`, `GymSessionRecords`) und `SettingRecords` für alle UserDefaults-Schlüssel (typisiert wie `AppBackup.Value`); `SettingsStore` mit allen Schlüsseln (`SettingsKeys`), `SecretStore` (Schlüsselbund/Keystore, gleiche Kontennamen), `BackupService` (Erstellen, zusammenführendes Einspielen, Ordner mit Vorversion), `AppStorage.open` mit Rückfall im Arbeitsspeicher, Provider. Tests mit SQLite (Neustart, Sicherung der Swift-App einspielen, Rückfall) | in PR |
| coach_core Berichte und Sicherung (Phase 2v): `AppBackup` (Format der Swift-App: sortierte Schlüssel, ISO-Datum, `Data` als Base64; Umzug in beide Richtungen), `CoachExport` (Markdown für den manuellen KI-Coach), `DataExport` (Markdown, JSON wie `JSONEncoder` mit `.prettyPrinted`/`.sortedKeys`, CSV), `CoachImport` (Block ```ironludi```, Prüfung über `GymCoach.validatePlan`, Auswahl je Routine/Tag/Hinweis), `PromptLibrary`, `PersonaReport` (alle Schutzregeln für sechs Musterpersonen). Dazu die letzten offenen Teile: `Personalization.healthWidgets`/`insightTopics`, `ReminderPlanner.season`/`swimEquipment`, `TrainingLog.seasonPlan`. Tests: `AppBackupTests`, `CoachExportImportTests`, `CoachImportSelectionTests`, `DataExportTests`, `PersonaTests`, `prioritiesOrderDashboardAndInsights`, `seasonRemindersUseFixedDays`, Saisonplan-Fälle aus `ReminderExtrasTests`/`ReminderDoneTests`. Damit hat jede öffentliche Struktur aus `CoachCore` ein Dart-Gegenstück | in PR |
| coach_core Mobilität, Spiel, Social und Widgets (Phase 2u): `MobilityArea`/`ComplaintArea`/`MobilityContext`, `MobilityLibrary` (20 Übungen), `MobilityTest` (4 Selbsttests), `MobilitySettings`, `MobilityPlanner` (Schwerpunkte, Einheit im Zeitbudget, Vorschlag); `DailyStreak` (Joker je Woche), `GameStats`, `BadgeRules`, `GameLevel`, `ChallengeMetric`, `LeaderboardEntry`, `Challenge`; `SocialPerson`/`SocialFriends`/`SocialReaction`/`SocialPost`/`SocialComment`, `WorkoutShare` (ohne Körperwerte), `MealPostShare`, `SocialFormat`, `SocialTimeline`; `WidgetSnapshot` mit Anzeige am Folgetag, `WidgetActionQueue`, `HealthMetric`, `AppGroupProfile`, `MealHeadline`. Tests: `MobilityTests`, `GameTests`, `SocialTests`, `SocialTimelineTests`, `WidgetSnapshotTests`, `MealHeadlineTests`. Widget-Dateien schreiben Zeitpunkte wie der Standard-`JSONEncoder` (Sekunden seit 2001), damit die nativen Widgets sie lesen; `AppGroupProfile.groups` liest das Profil ohne Plist-Parser; Zeiten in Gerätezeit (Tests in vier Zeitzonen geprüft) | in PR |
| coach_core Integration, Konto und Motivation (Phase 2t): `SourcePreferences` (Reihenfolge je Datenart, tolerant gelesen), `MetricsMerge` (je Datenart eine Quelle als ganze Gruppe), `ActivityMerge` (Doppelte über Anbieter, `localID` FNV-1a wie Swift, in Python nachgerechnet), `SyncLedger`/`SourceEntry` (neu, geändert, gelöscht, ersetzt; Prüfsumme über JSON mit sortierten Schlüsseln wie `JSONEncoder`), `ProviderSyncState` (Wartezeiten, Nachholzeitraum); `AccountRules`/`AccountInvite`; `WeekAdherence`, `ScoreRules`, `MotivationSummary`, `LeagueEntry`, `LeagueInvite` (Token-Schutz bei fremdem Server), `GuestToken`, `AndroidLink`, `LeagueCode`, `CompanionSettings`/`CompanionVoice`, `DaisyGeometry`. Tests: `DataSourceTests`, `AccountRulesTests`, `MotivationTests`. Links: Query-Werte wie `URLComponents` (`+` bleibt Plus) | in PR |
| coach_core Ernährung Teil 3 (Phase 2s): `MealNow`, `OwnRecipe`, `NutritionWeek`, `ShoppingAisle`, Abend-Erinnerung; `RecipePlan` (`Allergen`, `RecipePreferences`, `RecipeDayTarget`, `Recipe`, `RecipeDay`, `WeeklyRecipePlan`, `RecipePlanner` mit Ernährungsweise, versteckten Allergenen, Plausibilität, Lücken, Einkaufsliste, Zeiträumen); `CookPlan` (`CookShare`/`CookShareFields`/`CookPartner`/`CookRelease`, `CookLink`, `CookAmount` mit JSON wie Swift `{"portions":{"_0":3}}`, `CookPerson`, `CookPlan`, `CookPlanner`), Abfragen in Teilen, `AIErrorText`. Tests: `MealPlanningTests`, `RecipeTests`, `StricterRecipeTests`, `CookPlanTests`, Rezept-Fall aus `MealLibraryTests`. Einkaufsliste sortiert wie `localizedCompare` (Umlaute wie Grundbuchstabe) | in PR |
| coach_core Ernährung Teil 2 (Phase 2r): `QuickLog` (`MealEntry`, `MealSuggestions`, `FoodSearch.rank`, `NutritionBudget`, Schnell-Eintrag), `MealLibrary` (`FavoriteMeal`, `MealShortcuts`, `MealPortion`), `MealShare` (`SharedMeal`, Codes aus Links), `NutritionCheckIn`, `Expenditure`, `WeightForecast`, `MealReminderSettings` mit Erinnerungen, `NutritionDashboard`/`NutritionDaySummary`. Tests: `QuickLogTests`, `MealLibraryTests` (Rezept-Fall in Phase 2s), `MealShareTests`, `NutritionCheckInTests`, `ExpenditureTests`, `WeightForecastTests`, `MealReminderTests`, `NutritionDashboardTests`, Verbrauchs-Test aus `GoalGuardTests`. | in PR |
| coach_core Coach-Rest und KI (Phase 2q): `ActivityReport` (Runden, Splits, Hälften, Standzeit, Kadenz; JSON wie Swift mit Rundenintensität als Zahl), `ActivityReportBuilder`, `ActivityFindings` (Tempo-Einteilung, Puls-Drift, Intervalle, Standzeit, Zonen; ohne Pulswerte im Modus „reduziert“), `ActivityReportPlanner`; `ChatContext`/`ChatRouter` (Themen, Fakten je Frage mit Herkunft, Schutzgrenzen), `PersonalNote`, `WeeklyReport`, `WeeklyReview`, `TrainingTrends`; KI: `AIMode`/`AIPolicy`/`AIProviderChoice`/`AISettings`, `AIUsageLog`, `Insight`/`InsightInbox`/`InsightRules`/`InsightAnalysis`; Rest von `WeightTrend` (Trendlinie, Vorschlag mit Schutzstufen, Garmin-Wägungen). Tests: `ActivityReportTests`, die zwei offenen Fälle aus `HealthRecordingTests`, `InsightsTests`, `AIPolicyTests`, `ChatRouterTests`, `ChatContextTests`, `PersonalNoteTests`, `WeeklyReportTests`, `WeightTrendTests`, Vorschlags-Test aus `GoalGuardTests`. `WeeklyReview`/`TrainingTrends` rechnen in der Gerätezeitzone (wie `WeekLoad`) | erledigt |
| coach_core Health und Schlaf: `PersonalNorm`, `BodyBatteryAnalysis` (Aufwachwert, Verlauf, Zusammenhänge mit Schlaf und Stress), `GermanState`/`GermanHolidays`, `WakePlan`, `HealthAccessDiagnosis`, `HealthRecording` (Workout-Verlauf als FIT-Aufzeichnung), `HealthImport` (Tageswerte, Nächte mit Phasen, Workouts ohne Doppel, Wägungen; Uhrzeiten in Ortszeit oder mit festem UTC-Abstand), `HealthDashboard`, `MorningReport` mit Mitteilung, `SleepCoach`/`SleepSettings`/`SleepAlarm`. Tests: `SleepCoachTests`, `HealthAccessDiagnosisTests`, `BodyBatteryTests`, `HealthImportTests`, `HealthRecordingTests`, `HealthDashboardTests`, `WakePlanTests`, `MorningReportTests` | erledigt |
| coach_core Garmin und FIT-Export: `GarminEndpoint` (Personal API mit Bereichsgrenzen), `GarminBearerToken`, `GarminAPIError`, `SyncPlan`, `GarminConnect` (mobile Anmeldung mit Bestätigungscode, DI-OAuth2-Token, Abrufe, Upload), `ConnectEndpoint`, `GarminConnectMetrics` (Readiness, Trainingsstatus, Endurance Score), `GarminWorkout` (Workouts aus dem Plantext und Schwimmschritten, Garmin-JSON), `SentWorkouts`, `GarminStrengthSync` (Sätze füllen oder ersetzen, Zuordnung zur Uhr-Aufzeichnung, Warte-/Upload-Logik), `FitEncoder`, `StrengthFitExport`, `GarminExerciseMapping`, `GymItem.fromSession`. Tests: `GarminEndpointTests`, `SyncPlanTests`, `GarminConnectTests`, `GarminWorkoutTests`, `GarminStrengthSyncTests`, FIT-Fälle aus `GymBookTests`, Endpunkt-Pfade aus `MetricsAndZonesTests`, Readiness aus `BodyBatteryTests` | in PR |
| coach_core Profil vollständig: `SchedulePlanner` (Einheiten nach Ziel, Wettkampf und Erfahrung, Kürzen nach Priorität, beste Verteilung auf die freien Tage), `RunPlanner` (Laufwoche mit 10-%-Grenze, Entlastung, Tapering, Grenze am längsten Lauf), `InputCheck` (Körperwerte, Gewichtsziele, Zielzeit gegen die Prognose der Uhr), `RacePredictions`, `PostWorkout` (Auswertung und morgen entschärfen), `PlanSuggestion` (Diff mit Regelkonflikten aus Tagesform, Belastung, Nach-dem-Training und Wochenrückblick). Tests: `SchedulePlannerTests`, `ProfileEvidenceTests`, `RunPlanTests`, `InputCheckTests`, `PostWorkoutTests`, Planvorschläge aus `TrainingTodayTests`, Planer-Fälle aus `AuditR4APlanTests` und `Phase78Tests` | in PR |
| coach_core Plan-Modul: `SeasonSchedule` (48 Wochen aus `assets/season-plan.json`, Schwimmschritte, Zwift-Workouts, Phasen), `PlanTokens` (Platzhalter §T§, §I§, §E§, §S±n§, §Wnn§, §MP§, §R§), `PlannedUnit` mit Wettkampf-Entscheidungen, `PlanProgress`, `SwimStepText`, `TestRecord`/`TestHistory`, `SwimPaces`/`BikeZones`/`RunPaces`, `RaceEstimate`, `MarathonOutlook`, `WeekFrame`/`TodayPlan`/`FilledWeek`, `TodayFocus` (beide Modi), `UnitGuides` (Saisonplan und eigener Wochenplan). Tests: `DisciplineTests`, `PlanScheduleTests`, `TodayPlanTests` (alle über 2000 Vergleichsfälle mit den Original-Templates), `UnitGuideTests`, `ScheduleAdvisorTests`, „Jetzt dran“-Fälle aus `TrainingTodayTests` und `AuditR4APlanTests` | in PR |
| coach_core Gym vollständig und Belege: `WorkoutFlow` (Fokus-Satz, Supersätze mit Kürzeln, Vorschau, Zusammenfassung), `NumberPad`, `ActiveSessionState`, `WorkoutEdits` (später, verschieben, Supersatz, ersetzen, Alternativen, Aufwärmsätze, Satzgewicht, überspringen), `SetCheck`, `RestAdvisor`, `ExerciseUnits`, `PlateCalculator`, `WarmUp`, `RestText`, `HoldTimer`, `Routine`/`RoutineItem`/`RoutineTemplates` (GymBook-Pläne, Vorlagen nach Krafttagen), `GymSettings` (alle Felder, nachsichtiger Decoder), `CompleteOnEdit`, `RestSound`, `GymTarget`, `RoutineRotation`, `SessionComparison`, `GymCalendar`, `MuscleMap`/`MuscleLoad` (Heatmap, Erholung), `GymCoach` (Beobachtungen, KI-Plan mit Fragebogen und Prüfung), `GymHints`, `GymBookImport` (stabile IDs wie Swift, in Python nachgerechnet); `Evidence` (75 Studien, 47 Regeln), `UserSources`, `CoachingNote` mit `PrivacyMode`. KI-Eingaben sind `Map<String, Object?>`. Tests aus allen Gym-Testdateien außer FIT-Rundreise und Garmin-Übungscodes (folgen mit `FitEncoder`/`GarminExerciseMapping`), dazu `UserSourcesTests` und `everyEvidenceIDExists` | in PR |
| coach_core Gym-Grundlagen: `ExerciseCatalog` (47 Garmin-Regeln, Reihenfolge wie im Altbestand), `ExerciseLibrary` (59 Übungen mit Anleitung), `ExerciseInfo` (eigene Übungen), `GymPlan` (Standardplan, flexible Beintage, Zielbereiche), `GymSession`/`LoggedExercise`/`LoggedSet`/`GarminLink` mit JSON wie die Swift-Sicherung (ISO-8601, nachsichtige Decoder), `ExerciseAliases`, `MuscleVolume`, `GymProgression` (Doppelprogression A–D, Wiedereinstieg, Warnsignal), `GymStats` (Epley, Verlauf, Bestwerte, letzte Leistungen); Tests aus `GymTests` und `GymLibraryTests` (ohne Routinen/Einstellungen/Hinweise, folgen in 2l). Die Pace-Check-Zeile heißt jetzt `PaceCheckRow`, damit `PaceRow` frei für die Tempotabellen ist | in PR |
| coach_core Pulszonen und Verläufe: `HeartRateZoneCalculator` (Friel-Zonen, Zonen der Uhr, bestätigter Höchstpuls, eigene Werte vor Garmin, Schätzung, Verteilung locker/mittel/hart je Woche, Hinweise), `HeartRateOverrides`, `MetricTrend`, `WeekVolume`, `VO2MaxHistory`; Tests aus `MetricsAndZonesTests` (ohne Endpunkt-Pfade, folgen mit dem Garmin-Client) | in PR |
| Offen aus bisherigen Dateien: alle nachgezogen (zuletzt in Phase 2v) | erledigt |
| Native Registrierung im `AppDelegate` (Hintergrundabruf, Mitteilungs-Delegate), Widget-Erweiterung, Plattformbrücken | folgt mit den jeweiligen Diensten (Phase 2f/3), geprüft per iOS-Build |
| Alles Weitere | offen, Reihenfolge siehe Abschnitt 6 |
