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

- [x] **Vier Reiter** (`RootView`): Heute · Aktivitäten (mit Zähler für Freundschaftsanfragen) · Training · Ernährung.
      Jeder Reiter hat einen eigenen Navigationsstapel. → `go_router` mit `StatefulShellRoute.indexedStack`
- [x] **Onboarding** als Vollbild, bis das Profil fertig ist (`OnboardingView`).
- [x] **Deep Links**, Schema `coach://`:
      `open/<route>` (today, health, nutrition, logMeal?mahlzeit=…, gym, startWorkout, ai, aiAnalysis),
      `join?worker&token&league` (Rangliste), `meal/<code>` (geteilte Mahlzeit), `account?…` (Konto-Einladung),
      Kochpartner-Links (`CookLink`). Auf Android zusätzlich `ironludi://connect|account` (bisherige Android-App).
- [x] **Pending-Route-Logik** (`AppRouter`): Ziel erst nach dem Onboarding ausführen, Gym-Ziele nur mit Krafttraining.
- [x] **Sheets, die die Wurzel öffnet:** empfangene Mahlzeit, Konto-Einladung, „schon angemeldet“, Kochpartner,
      Ligabeitritt, „Einheit verschieben“ (aus einer Mitteilung), „Nächste Woche planen“ (aus der Sonntags-Mitteilung).
- [x] **Speicherwarnung** als Banner oben, wenn die Datenbank nicht geöffnet werden konnte.
- [x] **Darstellung:** Wie System / Hell / Dunkel (`AppAppearance`). → `ThemeMode`
- [x] Nur Hochformat, nur Telefon.

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

- [x] Designsystem: Farben je Sportart (`SportStyle`), Karten, Chips, Ringe, Plaketten, Hell/Dunkel.
- [x] **Diagramme** (Swift Charts, in 14 Dateien): Linien, Balken, Flächen, Zonenbänder, Zoom mit zwei Fingern
      (Trends, Übungsverlauf). → `fl_chart` plus eigene Zoom-Geste (`ChartZoom` steckt schon als Logik in CoachCore)
- [x] **Karte** der Aktivitätsstrecke (MapKit). → `flutter_map` (OpenStreetMap, kein API-Schlüssel nötig)
- [x] Gezeichneter Avatar „Daisy“ (`DaisyGeometry` in CoachCore). → `CustomPainter`
- [x] Körperkarte für die Muskel-Heatmap. → `CustomPainter` (anatomische Vektorzeichnung, `tool/body_map_art.py`)
- [x] Haptik (`sensoryFeedback`) bei Auswahl, erledigtem Satz, Pausenende. → `HapticFeedback` aus Flutter
- [x] Wischaktionen in Listen, Kontextmenüs, Ziffernblock, Stepper. → Flutter-Bordmittel (`Dismissible`, `MenuAnchor`)

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

- [x] **Garmin Personal API** (offiziell, `personal.connectapi.garmin.com`, Key des Nutzers): Tageswerte,
      Schlaf, HRV, Stress, Body Battery, SpO2, Puls, Gewicht, Fitnessalter, Pulszonen, Aktivitätsliste und -details,
      FIT-Download.
- [x] **Garmin Connect** (inoffizieller Login mit MFA-Code, Cookies, Token-Erneuerung, zufällige Pause gegen
      Cloudflare-429): Readiness, Trainingsstatus, Prognosen, **FIT-Upload** der Krafteinheit mit Sätzen,
      **Workouts an die Uhr senden**. → `dio` + `cookie_jar`.
      ⚠️ Risiko: Cloudflare unterscheidet Clients auch am TLS-Fingerabdruck. Ob der Dart-HTTP-Client wie
      `URLSession` durchkommt, muss früh in Phase 2 getestet werden. Rückfall: `cupertino_http` (iOS nutzt dann
      `URLSession`) bzw. `cronet_http` (Android).
- [x] **Cloudflare Worker** (bleibt unverändert): `v1/ai/generate` mit 14 Aufgaben (ping, daily_note, personal_note,
      meal_analyze, meal_amend, nutrition_label, nutrition_review, gym_hints, gym_plan, coach_chat, ai_insights,
      meal_now, weekly_recipes, cook_plan), `v1/account/*`, `v1/social/*`, `v1/game/*`, `v1/league/*`,
      `v1/share/meal|cook`, `v1/invite`, `v1/usage`, `v1/health`, SideStore-Quelle, Android-Download-Seite.
- [x] **Open Food Facts** (Barcode).
- [x] **Datenformate, die gleich bleiben müssen:** `AppBackup` (Sicherung, auch zum Umzug von der alten App),
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

- [x] **Coach** (13 Dateien): Tagesampel/Empfehlung, Pulszonen, Fitness/Form, Saisonplan, Schlaf-Coach, Trends,
      Wochenbericht/-rückblick, Coaching-Notizen, Chat-Kontext und Chat-Router
- [x] **Profile** (16): UserProfile (Modus Saison/persönlich), **GoalRules (Schutzgrenzen)**, Eingabeprüfung,
      Belastungsprüfung, Personalisierung, Plananpassungen, Planvorschläge, Laufplan, Wochenplan und -planer,
      Zuordnung Soll/Ist (`SessionMatch`), Wochenlast, Trainingspause, Nach dem Training
- [x] **Plan** (5): Disziplinen, Saison-Zeitplan, Tagesfokus, Tagesplan, Einheitsanleitungen
- [x] **Gym** (17): Progression (Doppelprogression), Coach-Hinweise, Routinen, Plan, Ablauf der Einheit,
      Bearbeitungen/Rückgängig, Statistik, Muskelbelastung, Werkzeuge (Stange/Scheiben, 1RM), GymBook-Import, Bibliothek
- [x] **Nutrition** (19): Tagesziele, BLS-Suche und -Zuordnung, Portionen, Schnell-Eintrag, Wasser, Verbrauch,
      Gewichtstrend und -prognose, Check-in, Rezeptplanung, Kochplan, Mahlzeiten-Erinnerungen, Teilen, Open Food Facts
- [x] **Health** (9): Body Battery, Morning Report, persönliche Normalbereiche, Health-Dashboard, Health-Import und
      -Aufzeichnung, Zugriffsdiagnose, Weckplan, Feiertage
- [x] **Analysis** (8): Aktivitätsdetails, -analyse, -bericht, Feed (Doppelte zusammenführen), aerobe Entkopplung,
      Pace-Check, Chart-Zoom
- [x] **Garmin** (10): Endpunkte, Tageswerte, Aktivitäten, Connect-Ablauf, Token, Workouts, Kraft-Sync, JSONValue, Sync-Plan
- [x] **Fit** (4): FIT-Dekoder/-Enkoder, Inflate, ZIP → Inflate/ZIP über das Paket `archive`, FIT selbst portiert
- [x] **Integration** (3): Datenquellen mit Vorrang, Zusammenführen, Sync-Protokoll
- [x] **AI** (3): KI-Richtlinie und Datenschutzstufen, Nutzung, Empfehlungen
- [x] **Report** (6): AppBackup, CoachExport/Import, DataExport, Musterpersonen-Bericht (`coach-report`), Prompt-Bibliothek
- [x] **Mobility, Motivation, Game, Social, Account, Evidence, Widgets, App** (Routen, Darstellung, Widget-Snapshot)

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
   `io.github.hkrb7p794w.gym` (`versionCode` = 10 000 + Lauf). Seit 16.11.2026 eigener Signaturschlüssel (Alias
   `aironludi`): Die Kotlin-App muss vor der Installation deinstalliert werden, ein Update über sie geht nicht.
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
| Phase 2a: Projekt, Abhängigkeiten, Info.plist/Entitlements, AndroidManifest/Gradle, CI, vier Reiter, Deep Links `coach://open/…`, Darstellung, App-Icon | erledigt |
| coach_core: `CalendarDay`/`DateRange`, `AppRoute`/`AppTab`/`QuickActions`, `AppAppearance`, `MealCategory` (mit Tests) | erledigt |
| coach_core Ernährung (Teil 1): `JsonValue`, `GermanFormat`, `Nutrient`/`NutrientValues`, `MealItem`/`Portion`/`MealAnalysis`/`NutritionSummary`, `PortionGuess`, `NutrientCheck`, `NutritionLabel`, `OpenFoodFacts`, `Hydration`/`MealSplit`, `BLS` mit Suche und Zuordnung (alle 17 Zuordnungsfälle), JSON kompatibel zu Swift | erledigt |
| coach_core Profil (Teil 1): `UserProfile` mit allen Enums, `WeekSchedule`/`SessionSlot`/`Weekday`, `PersonalGoals`/`TrackerSetup`/`Personalization` (Ableitung, Ernährungsrichtung, Prioritäten, KI-Kontext), `GoalRules` (alle Schutzgrenzen), `NutritionSettings`/`DayType`/`NutritionGoal`/`Diet`/`BodyProfile`, `WeightEntry` + `WeightTrend.merged`, `DataProvider`/`DataKind`; Lesen wie Swift-`Codable` | erledigt |
| coach_core Tagesziele: `NutritionPlanner` (Tagestyp, Plan-Tagestyp, Energie, Makros, Mikros, Wasser, alle Schutzgrenzen im Rechenweg), `NutritionTargets`, `DayClassification`; dazu `GarminActivity` mit Parser (Liste und Details), `GarminProfile`, `RecoveryLevel`, `TemplateItem`, `ActivitySource`, `StrengthDuplicates`, `SessionMatcher.defaultMinutes/sport`, `WeekSchedule.templateItems`, `TrainingSport.garminSport`, `NutritionSettings.profile` | erledigt |
| coach_core Saisonplan: `SeasonConfig` (Lesen wie Swift), `TrainingPhase`, Phasengrenzen, Wochen-Soll je Phase, Musterwoche, `PlanState`, `WeeklyVolume` (mit Gym-Tagen der App), `TestPaces`, `PhasePlanTexts`; `UserProfile.personalDraft` | erledigt |
| coach_core Wochen-Soll/Ist: `SessionMatcher` (Zuordnung, Ersatz, Gym-Tage, Summen), `SessionStatus`, `PlannedSession`, `SessionResult`, `MissedSessions` (verpasst, Nachholtag, Krankheit), `ManualActivity`; `PlanAdjustments` (Auslassen, Verschieben, Wochenplan je Woche), `PlanMoveAdvisor`, `ReminderPlanner.personal/body/weekPlanning`, `TrainingLog`, `ScheduledNote`; `ScheduleCheck` mit allen Hinweisen; `TrainingBreak`; `SessionKind`, `AerobicDecoupling.highZoneShare` | erledigt |
| coach_core Tagesampel: `DailyMetrics` mit allen Feldern und `GarminMetricsParser` (Tageszusammenfassung, HRV, Schlaf mit Zeiten, Body Battery mit Verlauf, Stress, SpO2, Fitnessalter, Zusammenführen), `RecoveryEvaluator` (Ampel, Tageszustand mit Rückfall auf die letzte Nacht), `Recommendation` mit Form-Grenze, `FitnessForm`, `LoadCheck` (Wochenumfang, Einzellauf), `WeekLoad.load`, `Personalization.maxLoadIncrease/adjustCounts` | erledigt |
| coach_core Aktivitätsverlauf: `ActivityFeed` (Zusammenführen von Garmin, Health, Nachgetragenem und Gym-Einheiten, Filter, Kernwerte, Tempo, Zonen, Fehlendes), `ActivityDetails` (Abschnitte wie Garmin Connect, Formate), `ChartZoom`, `WeekLoad.check` | erledigt |
| coach_core FIT und Analysen: `FitDecoder` (Records, Runden, Sätze; beide Byte-Reihenfolgen, komprimierte Zeitstempel, Entwicklerfelder), `ZipArchive`, eigener `Inflate` (wie Swift, erkennt kaputte Daten), `AerobicDecoupling` vollständig, `PaceCheck`, `ActivityAnalysis`/`ActivityAnalysisPlanner`, `ActivityDetails.samples/route`; Rundung wie Python (`roundHalfEven`). Alle Referenzfälle aus dem Altbestand stimmen | erledigt |
| Datenschicht Teil 1 (Phase 2f-1): drift-Datenbank mit den sieben Modellen der Swift-App (`DailyMetricsRecords`, `ActivityRecords`, `RawResponseRecords`, `SourceRecords`, `MealRecords`, `FoodRecords`, `GymSessionRecords`) und `SettingRecords` für alle UserDefaults-Schlüssel (typisiert wie `AppBackup.Value`); `SettingsStore` mit allen Schlüsseln (`SettingsKeys`), `SecretStore` (Schlüsselbund/Keystore, gleiche Kontennamen), `BackupService` (Erstellen, zusammenführendes Einspielen, Ordner mit Vorversion), `AppStorage.open` mit Rückfall im Arbeitsspeicher, Provider. Tests mit SQLite (Neustart, Sicherung der Swift-App einspielen, Rückfall) | erledigt |
| Datenschicht Teil 2 (Phase 2f-2): Repositories für Tageswerte (zusammenführend), Aktivitäten, Rohantworten, Mahlzeiten (Wasser ausgenommen), eigene Lebensmittel (Merken wie `remember`: Menge/Portion übernehmen, KI-Nährwerte ersetzen; Open-Food-Facts-Zwischenspeicher), Gym (Status bleibt, `ExerciseAliases` beim Lesen, Garmin-Verbindung roh gesetzt); `SourceStore` 1:1 (Synchronisierungsstatus `sources.syncStates`, einmalige Übernahme `sources.migrated`, `ingestDays`, `rebuild`, Herkunft je Tag, `recordActivities` mit Löschungen, `deduplicateActivities`), Provider. Tests mit SQLite | erledigt |
| Netzwerk Teil 1 (Phase 2g-1): `HttpTransport` (dio, Cookies je Anmeldung, Fake für Tests), `Secrets` (synchron lesbarer sicherer Speicher), `GarminClient` (Personal API mit Token-Tausch und einmaliger Erneuerung, Konto zuerst mit Rückfall, Zählung der Quellen), `GarminConnectSession` (Anmeldung mit Bestätigungscode, Token-Erneuerung, GET/JSON/FIT-Upload), `AIClient` (Adresse/Token, Sitzung vor App-Token, SideStore-/Android-Pfade, KI-Stufe, Nutzungsprotokoll, Fehlertexte), `AccountService` (Registrieren, Anmelden, Wiederherstellen, Sitzungen, Einladungen); fehlende Einstellungsschlüssel ergänzt. Swift-Tests aus `NetworkClientTests` und `GarminConnectSessionTests` portiert | erledigt |
| Netzwerk Teil 2 (Phase 2g-2): `GarminSyncService` 1:1 (Endpunkte einzeln abgesichert, Blöcke 180/28 Tage, Einzeltage, Konto-Extras inkl. Readiness/Trainingsstatus/Endurance/Wettkampfprognosen/Gewichte, Aktivitätsseiten mit Herkunft, einmaliges 13-Wochen-Nachladen, Profil täglich, FIT-Auswertung und Aktivitätsberichte mit Budget, Rohantworten), `ActivityAnalysisStore`/`ActivityReportStore` (JSON-Dateien, FIT-Zwischenspeicher), FIT-Lesen im Isolate. Swift-Test portiert | erledigt |
| Netzwerk Teil 3 (Phase 2g-3): `SocialService` (Freunde, Feed mit Nachladen ohne Doppelte, Suche, Profil, Blockieren, Teilen von Training/Mahlzeit, Reaktion sofort sichtbar mit Rücknahme bei Fehler, Kommentare), `SharedPostStore`, `GameService` (Rangliste, Challenges, Stand nur bei Änderung melden, Fortschritt je Challenge), `SocialPost.copyWith` in `coach_core`. `LeagueService` folgt mit den App-Einstellungen (`CoachSettings`) | erledigt |
| App-Einstellungen (Phase 2h): `CoachSettings` 1:1 (alle `coach.*`-Schlüssel, tolerante Standardwerte, Profil-Übernahme für Bestandsnutzer, stabile Mitglieds-ID, Ausnahmen der Vorwochen beim Start entfernt, `applyProfileToNutrition`, `refreshGoalGuards`, `record`, `logWeight`, `schedule`), `ReminderSettings`/`LeagueSettings`/`ImportedNotes` in `coach_core`, `LeagueService`, KI-Client mit KI-Stufe, eigenen Quellen und Nutzungsprotokoll verbunden. App-Tests aus `PersonalizationAppTests`, `DisciplineAppTests`, `MotivationAppTests` und `ReminderAppTests` (soweit ohne Erinnerungsdienst) portiert | erledigt |
| Dienste Teil 1 (Phase 2i): `OpenFoodFactsClient` (Prüfziffer, eigene Kennung, Fehlertexte), `PendingAnalysisStore` (wartende KI-Auswertungen mit Foto-Datei), `GarminWorkoutService` (Workout in den Garmin-Kalender, erneutes Senden ersetzt), `GarminStrengthService` (Abgleich wartender Krafteinheiten: Sätze in die Uhr-Aufzeichnung mit Sicherung des Originals, Rückfall ohne Übungsnamen, Hochladen als FIT, Wiederherstellen). Fotoverkleinerung (`MealPhoto`) folgt mit der Bildauswahl in der Oberfläche | erledigt |
| Erinnerungen (Phase 2j): `ReminderService` 1:1 (Erlaubnis beim ersten Mal, eigene Mitteilungen neu planen, keine Erinnerung für heute während einer Krafteinheit oder in einer Pause, Ausrüstung, Wochenplanung, Tagesauswertung, Mahlzeiten, Morning Report, Auslassen/Verschieben, Antworten aus Mitteilungen), Plattformbrücke `NotificationCenterBridge` mit `flutter_local_notifications` (Aktionen wie die iOS-Kategorien, Zeitzone des Geräts, Kennungen der Swift-App in der Nutzlast). App-Tests aus `ReminderAppTests` portiert | erledigt |
| Health (Phase 2k): `HealthImportService` (Tageswerte, Schlaf, Workouts ohne eigene, Gewicht, Herkunft in der Quellen-Ablage, Verlauf je Workout als Bericht, Meldung mit nicht lesbaren Datenarten) hinter `HealthSource` (Paket `health`: HealthKit/Health Connect), `HealthWorkoutWriter` (Krafteinheit als Workout), `HealthProbe` (Diagnose). Lücken des Pakets in `docs/decisions.md`; Wecker (AlarmKit) bleibt nativ | erledigt |
| GymBook und Diktat (Phase 2l): `GymBookReader` (SQLite-Backup nur lesend über eine Kopie, Einheiten einmal übernehmen, eigene Übungen anlegen, Meldungen wie in Swift), `Dictation` (Deutsch, Text wächst beim Sprechen, Fehler nur ohne Text) hinter `SpeechEngine` (`speech_to_text`). `WidgetPublisher` folgt mit den ViewModels (Phase 3) | erledigt |
| App-Zustand (Phase 3a-1): `AppModel` 1:1 (Start mit Übernahme des Altbestands, Abruf erst Garmin dann Health mit Status je Quelle, Doppelte entfernen, Krafteinheiten mit Garmin abgleichen, Erinnerungen mit Trainingslog/erfassten Mahlzeiten/Morning-Report-Satz, Planerfüllung auch im Saisonplan und mit Pausen, Schutzgrenzen, Quellen-Einstellungen anwenden), Saisonplan aus dem Asset in `main`, Schnittstelle `ActiveGym` für die laufende Krafteinheit. Hintergrundabruf (`workmanager`) folgt mit der Plattform-Einrichtung | erledigt |
| Onboarding (Phase 3b): Einrichtungsassistent 1:1 (9 Schritte: Sportarten, Ziele, Prioritäten, Fokus/Wettkampf, Erfahrung, Körperdaten mit Sicherheits-Check und Eingabeprüfung, Wochenplan mit Vorschlag/Editor/Plan-Check, Tracker, Zusammenfassung; Übernahme in Profil, Ernährung, Gesundheits-Widgets, primäres Gerät, Health-Import), Weiterleitung beim ersten Start, „Sicherung einspielen“ mit Datensicherung (Ordner, teilen, einspielen), Quellen und Regeln mit eigenen Quellen, gemeinsame UI-Bausteine (Auswahlkarten, Chips, Abschnitte, Symbole, Sportfarben), `TimeText` in `coach_core`, Start des App-Zustands und Abzeichen für Freundschaftsanfragen | erledigt |
| Einstellungen Teil 1 (Phase 3c-1): Einstellungsseite mit Profil (Saisonplan → persönliches Profil, Bearbeiten über den Assistenten, Ziele & Prioritäten, Eingabeprüfung) und Bereichen; Allgemein (Darstellung, Erinnerungen mit Uhrzeiten und Mitteilungs-Status, Datenschutz, Quellen), Training (Urlaub/Pause, Saison & Rennen, Garmin-Konto mit Bestätigungscode), Health (Import), KI (Datensicherung, eigene Quellen), Technik (KI-Worker mit Test, SideStore-Quelle, Android-Link; Garmin-Key mit Ablaufwarnung); `SettingsController` (Port von `SettingsViewModel`). Noch offen in Teil 2: Konto, Begleiter & Rangliste, Disziplinen, Schlaf, Ernährungseinstellungen, Datenquellen, KI-Stufe, Export/Import, Diagnose | erledigt |
| Einstellungen Teil 2 (Phase 3c-2): Datenquellen und Vorrang (Anbieter mit Status, primäres Gerät, Quelle je Datenart mit sofortigem Neuzusammenführen, Herkunft der Werte von heute, Integrationsmatrix), KI-Stufe und Anbieter mit Nutzungsprotokoll (Worker-Anbieter aus `/v1/health`, Zeitraum, je Modell/Aufgabe, letzte Fehler), Ernährungseinstellungen (Ziel bzw. Tempo, Ernährungsweise, Körperwerte mit Garmin-Platzhaltern, Aktivitätsfaktor, Mahlzeiten-Erinnerungen, Tag auswerten, Sperrbildschirm-Schalter, Nährwertquellen); Fehlerbehebung: Controller der Einstellungsseite wird beim Öffnen angelegt. Noch offen (mit ihren Bereichen): Konto, Begleiter & Rangliste, Disziplinen, Schlaf, Rezept-Vorlieben, Export/Import, Diagnose | erledigt |
| Ernährung Teil 1 (Phase 3d-1): `NutritionController` 1:1 (Port von `NutritionViewModel`: Tagesziele für Saisonplan und eigenen Wochenplan inkl. Krankheit, Summen, Was jetzt?, Warteschlange ohne Netz, Kopieren/Verschieben, manuell, unbekannter Barcode, Etikett lesen, bekanntes Lebensmittel, Zeitpunkt am gewählten Tag, Schnell-Eintrag mit Rückgängig, Bearbeiten, KI-Analyse und Ergänzen, Barcode mit Zwischenspeicher, Speichern mit Merken, Tagesauswertung). Swift-Tests aus `NutritionViewModelTests` portiert. Ansichten folgen in 3d-2 | erledigt |
| Ernährung Teil 2a (Phase 3d-2): Hauptansicht (Tagesstreifen mit Wochen, Dashboard-Karten Budget/Übersicht/Wasser/Ideen/Schnell/Mahlzeiten/Nährstoffe in eigener Reihenfolge, Kontextmenü der Mahlzeiten, Suche über eigene Lebensmittel, frühere Mahlzeiten und BLS, Warteschlange, Wochen-Check-in, KI-Auswertung, „+“ mit Rückgängig, „Nur Kalorien“, Übersicht anpassen), Mahlzeit-Editor (Positionen, Detail mit BLS und Portionen, gegessene Menge, Ergänzen per KI), BLS-Auswahl. Erfassen per Text/Foto/Barcode, Schnellzugriffe, Rezepte, Woche, Gewicht und Teilen folgen in 3d-3 | erledigt |
| Ernährung Teil 2b (Phase 3d-3): Erfassen-Bildschirm (Kamera, Mediathek, Text mit Diktat, Barcode, manuell, „Nur kcal“), Schnellzugriffe (Zuletzt, Häufig, Rezepte, Favoriten; „+“ trägt ein, Antippen öffnet), Barcode-Scanner (`mobile_scanner`, EAN-13/EAN-8/UPC-E) mit Eingabe von Hand, „Produkt unbekannt“ (Tabelle fotografieren oder selbst eintragen), `MealPhoto` (1280 px, JPEG 0,7, ohne EXIF/GPS). Eigene Rezepte, Woche, Gewicht und Teilen folgen | erledigt |
| Ernährung Teil 2c (Phase 3d-4): „Was jetzt?“ (übrige Makros, Vorrat, Ideen holen, Übernehmen und prüfen), eigene Rezepte mit Meal-Prep (Portionen, gekochtes Gewicht, Vorrat, vom Topf eintragen), Woche (kcal je Tag mit Ziel und Trainingstagen, Schnitt, Protein, Gewichtstrend mit Hinweisen aus den Schutzgrenzen, KI-Auswertung), Gewichtsverlauf (Wägung, Trend 28 Tage, Prognose, gemessener Verbrauch mit Vorschlag, Anpassung, Verlauf), Mahlzeit teilen und empfangen über den Worker (`MealShareService`), Check-in-Link, Rezept speichern mit Rückfrage. Offen: „Im Feed mit Freunden teilen“ (Social-Phase), „Rezeptideen für die kommende Woche“ (Rezepte-Phase) | erledigt |
| Gym Teil 1 (Phase 3e-1): `GymController` 1:1 (Port von `GymViewModel`: Wochenplan und Einheit für heute, Progression, Vorbefüllen, Routinen mit Supersätzen, Übung hinzufügen/ersetzen/überspringen/verschieben, Aufwärmen, Satzart, RIR mit Pausenverlängerung, Abhaken mit Fokus und Pause, Halteübungen mit Stoppuhr, Pause ±15 s und merken, Rückgängig, KI-Hinweise mit Regel-Ersatz, Beenden mit Health und Garmin, laufende Einheit übersteht den Neustart). `RestAlarm` (sekundengenaue Mitteilung „Pause vorbei“ mit eigenem Ton) und Pausenton (`audioplayers`, ambient). Mitteilungszentrale des Geräts in `main` eingerichtet (fehlte bisher), iOS-Delegate. Swift-Tests aus `GymViewModelTests` portiert. Ansichten folgen in 3e-2 | erledigt |
| Gym Teil 2 (Phase 3e-2): Gym-Reiter (laufende Einheit fortsetzen mit Hinweis auf nicht beendete/nicht gestartete, „Nächste Einheit“ nach Rotation mit Warnungen und Leiste der Routinen, Saisonplan „Heute“ mit Wochenplan und anderer Einheit, Meldung, Letzte Einheiten), Verlauf mit Löschen nach Rückfrage, Einheit im Detail (Dauer, Last, Health nachtragen, Garmin: Status, abgleichen, hochladen, erneut übertragen, wiederherstellen, Sätze), Auswertung (Kalender 8 Wochen mit Serie, Tipps mit KI/Regeln, Muskel-Übersicht 7 Tage/Ø 4 Wochen/Erholung mit Körperkarte, Gewichts-Progression, Sätze je Muskel), `BodyMap`/`MuscleHeatmapSection`, Einstieg im Reiter Training. Laufende Einheit vorerst als einfache Liste (3e-3), Trainingspläne/Übungen/KI-Plan folgen in 3e-4 | erledigt |
| Gym Teil 3 (Phase 3e-3): laufende Einheit 1:1 (Fokus-Karte mit Übungsleiste, Supersatz, Satzart, Überspringen/Wieder aufnehmen, großer Eingabe mit −/+ und Ziffernblock samt Schnelltasten, „wie Satz n“, Unterstützung, Rückfrage bei unplausiblen Werten, „Satz nach Eingabe abhaken“, letzte Leistungen, Notizen/Progression/Aufwärmen/Scheiben, nächster Satz und nächste Übung; Liste mit Sätzen, Wischen zum Löschen, Satzart und RIR per langem Druck, Beschwerde-Hinweis; „Satz erledigt“, Stoppuhr für Halteübungen mit Korrektur; Pause groß/klein mit ±15 s und RIR-Frage, 10-s-Vorwarnung und Signal; Rückgängig; Menü je Übung: später, überspringen, ersetzen, Reihenfolge, Supersatz, Satz, Pause, Notiz, Stange, entfernen; „Plan geschafft“; Beenden mit offenen Sätzen; Abschluss mit Bestleistungen, Volumenvergleich, Muskelkarte, Nächstes Mal, Hinweisen). Übungsauswahl mit Suche, Muskelfilter und eigener Übung. Offen: „Anleitung und Verlauf“ (3e-4), „Mit Freunden teilen“ (Social) | erledigt |
| Gym Teil 4 (Phase 3e-4): Übungsbibliothek (Suche, Muskelfilter, „Nur mit meiner Ausstattung“, eigene Übung), Übung im Detail (nächste Einheit, Beschwerden, Muskelkarte, Muskel/Geräte/Bereich, Ausführung, Bestwerte, Verlauf mit Zeitraum, Zoom und Verschieben, Einheiten), Ausstattung mit Schnellauswahl, Stange und Scheiben, Trainingspläne (KI-Plan, eigene Pläne mit Starten, Bearbeiten, Duplizieren, Löschen, Sortieren; Vorschläge übernehmen), Plan-Editor (Sätze, Bereich, Pause, Supersatz, Startgewicht, Reihenfolge, Muskelkarte), KI-Trainingsplan (Fragebogen, Prüfung durch die Regeln, Regel-Vorschlag ohne Worker, Übernehmen oder Ersetzen), „Anleitung und Verlauf“ im Übungsmenü. GymBook-Import und Gym-Einstellungen folgen mit den Einstellungen › Disziplinen | erledigt |
| Heute Teil 1 (Phase 3f-1): `TodayController` 1:1 (Port von `TodayViewModel`: Tagesampel aus Tageswerten und Form, Werte von gestern als Ersatz, Saisonplan-Stand, Wochenvolumen, Tagesplan aus dem Saisonplan, Soll/Ist der Woche mit Laufplan, Empfehlung aus dem eigenen Wochenplan mit Krankheitsdeckel, „Jetzt dran“ für beide Modi, Belastung der Woche; KI-Notiz `daily_note`/`personal_note` einmal je Tag und Ampelstufe unter `coach.note`, Regel-Notiz ohne Worker). Swift-Tests aus `TodayViewModelTests` portiert. Ansichten folgen in 3f-2 | erledigt |
| Heute Teil 2 (Phase 3f-2): Reiter „Heute“ (Abrufstatus, Hinweis ohne Quelle, „Jetzt dran“ mit Ampel, Warum, Konflikt, Werten von gestern, Phase/Countdown, Pause, Einheiten mit Status und Ablauf, Wochenfokus, Verschieben/Auslassen/Rückgängig; Coach-Notiz bzw. „Warum?“ mit „Neu formulieren“ und Quellen; Vorschläge mit Änderungen je Tag, Regelprüfung, Übernehmen mit Rückgängig, Verwerfen; offene und ausfallende Einheiten des Saisonplans; Wochenrückblick sonntags mit Vorschlag für nächste Woche; heute erledigt; Hinweise Schlaf/Laufumfang/Belastung; Woche mit Fortschritt und letztem Abruf), Wochenübersicht (Rest der Woche, Wochenziele des Saisonplans, Wochenstreifen und eigene Ziele, Import-Hinweise), „Einheit anpassen“ aus Mitteilungen. Offen: Morning Report (Health), verpasste Einheiten (Plan), nach dem Training (Training), Motivation/Rangliste, KI-Empfehlungen und Chat (AI), An die Uhr senden, Mobility, „Anpassen“ eines Vorschlags (Plan) | erledigt |
| Training/Plan Teil 1 (Phase 3g-1): `TrainingController` 1:1 (Port von `TrainingViewModel`: Erholungsverläufe über 28 Tage, Kacheln mit Readiness, Trainingsstatus, Body Battery, HRV, SpO2, VO2max u. a., Schlafphasen, VO2max-Verlauf 180 Tage, Wochenumfang 12 Wochen, Pulszonen-Bericht, Pace-Check, aerobe Kopplung) und `PlanController` 1:1 (Port von `PlanViewModel`: aktuelle Woche, Blättern, ISO-Kalenderwoche, Zeitraum, Einheiten mit Testwerten und Erledigt-Status). Swift-Tests aus `TrainingViewModelTests` und `PlanViewModelTests` portiert. Ansichten folgen | erledigt |
| Training Teil 2 (Phase 3g-2): Reiter Training (Gym mit „läuft“, Erholung, Herzfrequenz, Trends, Schlaf-Coach, Fitness & Form, Wochenbericht mit Kernwert), Erholung (Verläufe 28 Tage mit Schnitt und Veränderung, Kacheln, Schlafphasen), Herzfrequenz (HFmax, Coach-Zonen Laufen/Rad, Intensität gesamt und je Woche, Uhr-Zonen, Hinweise), Trends (Minuten je Woche gestapelt nach Sportart, Form mit heute, aerobe Effizienz; zoombar), Fitness & Form (Einordnung, Kurven 90 Tage), Wochenbericht (Hinweise, Zahlen und Erholung mit Vorwoche), Schlaf-Coach (Schlafenszeit, Schnitt, Defizit, Schwankung, Hinweise, 14 Nächte, Einstellungen, tägliche Erinnerung 30 min vorher). Offen: Plan, Gesundheit, Disziplinen/Ziele und eigene Sportarten (3g-3/3g-4), Wecker (nativ), „Eigene Werte eintragen“ (Einstellungen) | erledigt |
| Training Teil 3 (Phase 3g-3): Übersicht mit Disziplinen (Schwimmen CSS, Rad FTP, Laufen Schwelle) und Zielen (Almere-Zielzeit, Marathon-Countdown) im Saisonplan bzw. „Meine Sportarten“ (Kilometer diese Woche) im persönlichen Modus; Seiten Schwimmen (Kilometer, CSS-Verlauf, Paces, Technik, CSS-Test), Rad (FTP-Verlauf, VO2max, Zonen, Pw:HR-Kopplung, Zwift-Workouts, FTP und Rad-Schnitt), Laufen (Schwellenverlauf, VO2max, Prognose der Uhr, Paces, 30-min-Test, Renn-Laufpace, Pace-Check mit Übernahme, Pa:HR-Kopplung mit nicht gewerteten), Almere (Schätzung, Abschnitte, Aktualität, Hebel), Marathon (Countdown, Zielpace, HM-Test, Longrun-Leiter, Rennen & Verpflegung), eigene Sportart (Kilometer, VO2max, Kopplung ohne Saisonwerte). Offen: Plan (3g-4), Aktivitäten (3g-5) | erledigt |
| Training Teil 4 (Phase 3g-4): Plan im Reiter Training – Saisonplan (Woche mit KW, Phase, Erledigt-Fortschritt, Einheiten mit Haken bzw. offener Entscheidung, Musterwoche, Saisonübersicht nach Phasen), Einheit im Detail (Schwimmablauf mit Ausrüstung, Kraftübungen, Zwift, Wettkampf-Entscheidung, An die Uhr senden, Anleitung, Grundlage), Meine Woche (Ziel, Tage mit Laufminuten, Soll/Ist-Status, Verschieben/Auslassen per Menü und Wischen, Soll/Ist je Sportart, Außerplanmäßiges mit Löschen, Plan-Check), Wochenplan bearbeiten, Training nachtragen, Nächste Woche planen (auch aus Sonntags-Mitteilung, Vorschlag „Anpassen“, Wochenrückblick), Verpasst (nachholen, nachtragen, streichen, krank) in Heute, An die Uhr in „Jetzt“, Verschieben aus Mitteilung. Offen: Aktivitäten (3g-5) | erledigt |
| Aktivitäten (Phase 3g-5): Reiter Aktivitäten mit Alle/Meine/Freunde – eigener Verlauf (Garmin, Health, Nachgetragenes, Gym; Doppelte einmal) mit Zeitraum, Suche, Filter (Sportart, Plan-Einheiten mit Status, harte Einheiten), nach Monaten; Zeitleiste mit Beiträgen der Freunde (Kopf, Kennzahlen, Reaktionszahl) und Nachladen; Detailseite (Übersicht, Quelle/Intensität/Anstrengung, Zonenbalken, verknüpfte Gym-Sätze, Auswertung der Regeln, Karte mit OpenStreetMap, Verlauf HF/Pace/Höhe/Kadenz/Leistung, Runden, Abschnitte, alle Kennzahlen, fehlende Daten; Laden von Details und FIT-Datei bzw. Health-Aufzeichnung, Bericht speichern); „Nach dem Training“ auf Heute (Anstrengung 1–10, Auswertung gegen den Plan, morgen locker mit Übernehmen/Anpassen/Verwerfen/Rückgängig); „Heute erledigt“ und „Letzte Aktivitäten“ mit Detailseiten. Offen: Reaktionen, Kommentare, Teilen, Freunde, automatisches Teilen (Social-Phase) | erledigt |
| Health Teil 1 (Phase 3h-1): Gesundheitsbereich im Reiter Training (Zeile mit aktueller Body Battery) – Morning-Report-Kopf, konfigurierbare Widgets (Wert, Einordnung gegen den eigenen 30-Tage-Bereich, Mini-Verlauf je Darstellung, Ersatzquellen Gewicht und Belastung), Hinweis auf Widgets ohne Daten, Verlauf je Wert (30/90 Tage, eigener Bereich, Werte, Quelle), Schlaf öffnet den Schlaf-Coach, Editor (sortieren, ein-/ausblenden, Darstellung, entfernen, hinzufügen nach Kategorie, Standard); Morning Report (Kopf, Auffälligkeiten, Empfehlung, Werte der Nacht, heute geplant, Schlafempfehlung, fehlt heute) und Karte auf Heute bis 12 Uhr. Offen: Body Battery, Mobility, Wecker (3h-2) | erledigt |
| Health Teil 2 (Phase 3h-2): Body Battery (Ring mit Stand und Einordnung, Aufwachwert gegen den eigenen Bereich, Laden/Verbrauch, Tagesverlauf, 30 Tage mit Spanne und Aufwachwert, Schlaf und Stress), Mobility (Einheit nach Belastung, Tests und Beschwerden mit Anlass und Dauer, Schwerpunkte, Ablauf mit Schritten, als erledigt eintragen, Selbsttests mit Einstufung und Verlauf, Beschwerden, Grundlage; Karte im Gesundheitsbereich, Vorschlag in „Jetzt dran“), Wecker im Morning Report (Weckzeit aus dem Schlaf-Coach, „jetzt ins Bett“, Wiederholung, löschen, Abgleich mit dem Schlaf-Coach) über `WakeAlarmService` mit Plattformbrücke `aironludi/alarm` und Ersatzhinweis. Offen: native Gegenseite der Wecker-Brücke (AlarmKit, AlarmManager) mit den nativen Teilen | erledigt |
| KI Teil 1 (Phase 3i-1): Bereich „AI“ über Heute (Zeile mit Zahl neuer Empfehlungen) – Empfehlungen aus Regeln und KI nach Bereichen (Chips mit Zähler), Neu/Aktuell/Nicht mehr aktuell/Umgesetzt und verworfen, lesen per Tipp, umsetzen/verwerfen per Wischen und Menü, wieder öffnen, „Worauf beruht das?“ (Grundlage, Herkunft, Modell, Gültigkeit); Regeln neu auswerten (`AIController` = `AIViewModel`: Tagesampel, Schlaf, Gym-Beobachtungen, Ernährungslücken, Planvorschläge); KI-Analyse auf Anfrage je Bereich mit fehlenden Daten; Chat „Coach fragen“ (in Heute und AI) mit Vorschlägen, Belegen und Fehlertext; `CoachFacts` (Chat- und Analysefakten, fehlende Daten, Ernährungslücken); weitere Funktionen: KI-Trainingsplan, KI-Einstellungen. Offen: Prompt-Bibliothek, Export/Import für externe KI (3i-2), Rezeptideen (Rezepte-Phase) | erledigt |
| KI Teil 2 (Phase 3i-2): Prompt-Bibliothek (Vorlagen und eigene Prompts, Vorschau mit Platzhaltern, Zeitraum, angehängte Daten mit Zählern, Markdown/JSON, kopieren, als Datei teilen, als eigenen Prompt speichern, bearbeiten, löschen), Datenexport für externe KI (Zeitraum mit Vorgaben oder eigenen Daten, Bereiche mit Zählern, Markdown/JSON/CSV, Antwortformat beilegen, teilen, kopieren) und Import der KI-Antwort (einfügen, prüfen durch die Regeln, Trainingspläne einzeln ersetzen/hinzufügen/weglassen oder alle ersetzen, Wochenplan dauerhaft oder nur nächste Woche mit Tagesauswahl, Hinweise, Korrekturen der Regeln, übernehmen); Einstiege im Bereich AI und in Einstellungen › KI und Automatisierung. Offen: Rezeptideen (Rezepte-Phase) | erledigt |
| Konto (Phase 3j-1): Abschnitt „Konto“ oben in den Einstellungen (angemeldet mit Namen, sonst Hinweis, Anmelden, Konto erstellen), Anmeldefenster (Anmelden/Registrieren/Vergessen, Server nur bei Bedarf, Prüfung von Benutzername, Passwort, Anzeigename, Einladungs- und Wiederherstellungscode), Wiederherstellungscode einmalig mit Bestätigung, Konto verwalten (Anzeigename, Einladungen erstellen/teilen/löschen, angemeldete Geräte, überall abmelden, Passwort ändern, abmelden, Konto löschen mit Passwort), Einladungslink `coach://account` (Registrierung mit Code bzw. „Schon angemeldet“) über `incomingLinkProvider`. Offen: Freunde, Beiträge, automatisches Teilen (3j-2), Spiel (3j-3) | erledigt |
| Freunde (Phase 3j-2): Freunde (Feed, Freundesliste; ohne Konto Hinweis mit Anmelden) über das Personen-Symbol im Reiter Aktivitäten (mit Zahl der Anfragen), Beiträge (Kopf mit Avatar, Inhalt, Übungen, Rekorde, Notiz, eigene löschen, Mahlzeit ins Tagebuch übernehmen), Reaktionen und Kommentare (schreiben, löschen), Suche nach Benutzernamen mit passender Aktion, Anfragen annehmen/ablehnen/zurückziehen, Profil mit Beiträgen, Freundschaft beenden, sperren/entsperren, „Jemanden ohne Konto einladen“; „Mit Freunden teilen“ (Vorschau ohne Körperwerte, Notiz) aus Aktivitätsdetail, Gym-Abschluss und Mahlzeit teilen; automatisches Teilen (`SocialAutoShare`: Schalter in Aktivitäten und Konto, nur Trainings ab dem Einschalten, nach dem Start und beim Öffnen des Reiters). Offen: Wettkampf/Spiel (3j-3) | erledigt |
| Spiel (Phase 3j-3): Abschnitt „Fortschritt“ auf Heute (Tages-Serie mit Joker, Stufe mit Fortschritt, nächstes Abzeichen; meldet Stand und Challenge-Werte an den Worker) über `MotivationSections`, Seite „Wettkampf“ in Freunde (Serie, Stufe, Wochenpunkte, Einladungen annehmen/ablehnen, Rangliste der Woche mit Medaillen, Challenges mit Fortschritt je Person, verlassen/löschen, Abzeichen mit Fortschritt), neue Challenge (Art, Woche, Name, Freunde einladen). Offen: Begleiter (Daisy) und Liga (3j-4) | erledigt |
| Begleiter und Liga (Phase 3j-4): Daisy gezeichnet und animiert (`CustomPainter` auf `DaisyGeometry`, Zubehör und „Zzz“/Funkeln je Stimmung, steht bei „Bewegung reduzieren“ still), Begleiter auf Heute (Avatar mit Stimmung, Nachricht aus `CompanionVoice`), Rangliste der Liga in der Wochenübersicht (Plätze, Symbol, Einheiten, Serie, Punkte, Abgleich mit dem Worker), Einstellungen › Allgemein › Begleiter & Rangliste (Begleiter an/aus, Name, Art, Daisy-Stimmungen, eigenes Foto bis 600 px nur auf dem Gerät; Liga-Name, erstellen, per Code beitreten, Einladungslink erstellen/teilen, verlassen), Liga-Einladungslink `coach://join` | erledigt |
| Rezepte Teil 1 (Phase 3k-1): Rezeptideen über Ernährung und AI (`RecipeController` = `RecipeViewModel`, Teil Wochen-Rezepte: Zeitraum 1–14 Tage ab gewähltem Tag, gleiche Tagesziele aus dem Wochenschnitt, Lücken der letzten 14 Tage, Erstellen in Teilen zu höchstens 2 Tagen nebeneinander mit einem zweiten Versuch bei vorübergehendem Ausfall, fehlende Tage einmal nachfordern bzw. „Fehlende Tage erstellen“, Prüfhinweise, Speichern als `recipes.json`), Tage mit Rezepten und Summen, Rezept im Detail (Nährwerte, Zutaten, Schritte, „Als Mahlzeit eintragen …“ über den Entwurf), Einkaufsliste (Zeitraum, nach Abteilungen, abhaken, Vorrat, teilen), Wünsche und Allergene. Offen: Gemeinsam kochen und vorkochen (3k-2) | erledigt |
| Rezepte Teil 2 (Phase 3k-2): „Kochen planen“ oben in den Rezeptideen (`CookPlanController` = `RecipeViewModel`, Teil Kochpläne: für mich, eine verbundene Person oder beide, Mahlzeit, Menge in Portionen oder Tagen bzw. eigener Anzahl mit Satz zur Menge, Freigabe vor jedem Vorschlag neu abrufen, abgelaufene Freigabe löschen, Prüfhinweise, Vorschläge löschen, Speichern als `cook-plans.json`), Kochplan im Detail (Teller und Grammzahl je Person, Anteil, Nährwerte und Ziel, Hinweise, ganzes Gericht und Kompromiss, Zutaten insgesamt bzw. Basisportion bearbeiten, Lagerung je Tag, Zubereitung, „Meine Portion eintragen …“), Gemeinsam kochen (`CookShareService`: Freigabe abrufen und verbinden, lösen, eigene Freigabe mit Feldauswahl und Vorschau anlegen/aktualisieren/zurückziehen, Link senden, Person einladen), Links `coach://cook/<code>`, `coach://open/cookShare` und `coach://meal/<code>` über `RootShell` | erledigt |
| Einstellungen Teil 2 (Phase 3l-1): Disziplinen in „Training und Fitness“ (Gym bei Krafttraining bzw. im Saisonplan, Laufen/Rad/Schwimmen je nach Profil); Gym (Satzpausen für Grund-, Isolations- und Aufwärmsätze, sofort starten, Ton am Pausenende mit Probehören, Vibration, Satz abhaken nach dem Eintippen, GymBook-Import, Aufwärmsätze, Ausstattung, RIR, Bildschirm anlassen, Sperrbildschirm, Garmin-Abgleich mit Ersatz-Upload); Pausen, Notizen und Stange je Übung (eigene Übungen und Suche); Ausdauer (Testwerte Schwellen-, Marathon- und Renn-Laufpace, FTP, CSS nur im Saisonplan; HFmax und Schwellen mit „Auto“; Schwimm-Erinnerung); Schlaf in „Health und Erholung“; Diagnose in „Technik“ (Garmin: letzter Abruf, befüllte Werte, Rohantworten mit Feldnamen zum Teilen; Health-Prüfung mit Version) | erledigt |
| Widgets Teil 1 (Phase 3m-1): `WidgetPublisher` (Stand für die Homescreen-Widgets wie in Swift: Heute mit Ampel, Einheiten und Woche, Ernährung mit Zielen, Wasser, letzter Mahlzeit und Mahlzeiten-Anteilen, Gym mit nächster Routine, laufender Einheit, letzter Einheit und Wochenstand, Health aus dem Morning Report mit Body Battery, Serien) und Wasser aus dem Widget übernehmen (heute bis 7 Tage zurück, verfallene entfernen); `WidgetStore` mit gleichem Dateiformat (`widget-snapshot.json`, `widget-actions.json`); Plattformbrücke `aironludi/widgets` im `AppDelegate` (Profil lesen, App-Group-Ordner, Warteschlange unter Dateikoordination ändern, WidgetKit neu laden), Android: Datenordner der App; Übernehmen und Schreiben beim Öffnen und Zurückkehren, Schreiben beim Verlassen, dazu Abruf und Erinnerungen beim Zurückkehren (wie `scenePhase`). Offen: Widget-Erweiterung und Live-Aktivitäten (3m-2), Glance-Widgets und laufende Mitteilung (3m-3), Wecker-Brücke | erledigt |
| Widgets Teil 2 (Phase 3m-2): Widget-Erweiterung `CoachWidgets` (SwiftUI, aus der Swift-App übernommen): Homescreen- und Sperrbildschirm-Widgets Heute, Ernährung (mit Wasser-Knopf), Mahlzeiten (mit „+“ je Mahlzeit), Health, Gym, jeweils konfigurierbar; Oberflächen der Live-Aktivitäten Gym und Mahlzeiten. `WidgetCore.swift` enthält nur die nötigen Typen aus CoachCore (Datenformat wie `widget_snapshot.dart`), `Shared/` (Attribute und Knöpfe der Live-Aktivitäten) gehört zu App und Erweiterung. Ziel per `ios/scripts/add_widget_extension.rb` (Gem `xcodeproj`) ins Runner-Projekt eingefügt und vor „Thin Binary“ eingebettet. Offen: Live-Aktivitäten aus der App starten und die Knöpfe an die Gym-Einheit binden (3m-3) | erledigt |
| Widgets Teil 3 (Phase 3m-3): Live-Aktivitäten aus der App über den Kanal `aironludi/activities` (Port von `WorkoutActivityController` und `MealsActivityController` im `AppDelegate`): laufende Einheit ab dem ersten Satz (Übung, Satz x von y, Pause, Gewicht/Wdh. mit Schrittweite, „Danach“; `GymController.liveState`, Schalter in Gym-Einstellungen), Knöpfe „Satz erledigt“, Gewicht ±, Wdh. ±, „Pause überspringen“ an die Einheit in Dart (`GymController.perform`); „Mahlzeiten heute“ aus dem Widget-Stand (Schalter in Ernährung, sofort gestartet bzw. beendet; Neustart nach 2 Stunden, veraltet ab Mitternacht, im Hintergrund nur aktualisieren) | erledigt |
| Widgets Teil 4 (Phase 3m-4): Android – laufende Gym-Einheit als dauerhafte Mitteilung (`WorkoutNotification.kt`, Kanal `aironludi/activities` wie unter iOS): Übung, Satz, Gewicht × Wdh., „Danach“, Pause als Countdown; Knöpfe „Satz erledigt“ und „Pause überspringen“ bzw. Gewicht ± (Android zeigt höchstens drei), Antippen öffnet Gym; Knöpfe ohne laufende App werden gemerkt und beim Öffnen ausgeführt | erledigt |
| Widgets Teil 5 (Phase 3m-5): Android-Homescreen-Widgets (`HomeWidgets.kt`, RemoteViews): Heute (Ampel, Einheiten mit Haken, Woche, Serie), Ernährung (kcal, Protein, Wasser mit Ziel, letzte Mahlzeit, Knopf „+ 250 ml Wasser“), Mahlzeiten (Rest-kcal, je Mahlzeit kcal/Ziel, „+“ öffnet das Erfassen der Mahlzeit), Health (Werte mit Einordnung, „von gestern“), Gym (nächste bzw. laufende Einheit, letzte Einheit, Woche); lesen `widget-snapshot.json` aus dem Datenordner, Tageswechsel wie `display(on:)`, Wasser über `widget-actions.json` (Format wie iOS), Neuzeichnen über `aironludi/widgets` `reload`; helles und dunkles Design | erledigt |
| Wecker-Brücke (Phase 3m-6): Gegenseite von `aironludi/alarm` – iOS: AlarmKit ab iOS 26 im `AppDelegate` (Erlaubnis beim ersten Stellen, Wiederholung je Wochentag, „Aus“, Liste der gestellten Wecker; unter iOS 18–25 `unsupported` mit Hinweis auf die Uhr-App), Android: `WakeAlarm.kt` mit `AlarmManager.setAlarmClock` (Vollbild-Mitteilung mit Weckton bis „Aus“, Wiederholungen und nach Neustart neu gestellt) | erledigt |
| Feinschliff Teil 1 (Phase 3n-1): Abgleich mit der Swift-App – Speicherwarnung oben, wenn die Datenbank nicht geöffnet werden konnte (`AppStorage.isTemporary`); beim Verlassen höchstens einmal täglich in den gewählten Ordner sichern, Widgets versorgen, Schnellaktionen am App-Icon anpassen (`quick_actions`: Training starten nur mit Krafttraining, Mahlzeit erfassen, Health, KI-Analyse nur mit erlaubter KI; Antippen wie `coach://open/<route>`); Bildschirm an während einer Einheit (`wakelock_plus`, Schalter „Bildschirm anlassen“); Hintergrundabruf alle ≥ 2 Stunden mit Netz (`workmanager`, Kennung `io.github.hkrb7p794w.coach.refresh` wie in Swift, gemeinsamer Start `createAppContainer`, danach Widgets versorgen; iOS mit Plugins und Widget-Brücke in der Hintergrund-Engine); neuer Kalendertag (Mitternacht, Rückkehr in die App) lädt Heute, Ernährung und Gym neu (`currentDayProvider`, wie `onDayChange`); Stand im Migrationsplan nachgeführt | erledigt |
| Design wie die Swift-App: iOS-Theme (`AppTheme`, `IOSColors`: Akzent `systemBlue`, gruppierter Hintergrund, weiße bzw. dunkelgraue Gruppen mit Trennlinien bis zum Text, iOS-Schriftgrößen, keine Material-Wellen, Cupertino-Übergänge, Knöpfe und Segmente wie SwiftUI), Tab-Leiste wie `TabView` (`CupertinoTabBar`), große Überschriften der vier Hauptseiten mit kleinem Titel nach dem Rollen (`LargeTitleScope`), grauer Pfeil `DisclosureChevron`, Schalter adaptiv (iOS-Schalter auf dem iPhone) | erledigt |
| coach_core Berichte und Sicherung (Phase 2v): `AppBackup` (Format der Swift-App: sortierte Schlüssel, ISO-Datum, `Data` als Base64; Umzug in beide Richtungen), `CoachExport` (Markdown für den manuellen KI-Coach), `DataExport` (Markdown, JSON wie `JSONEncoder` mit `.prettyPrinted`/`.sortedKeys`, CSV), `CoachImport` (Block ```ironludi```, Prüfung über `GymCoach.validatePlan`, Auswahl je Routine/Tag/Hinweis), `PromptLibrary`, `PersonaReport` (alle Schutzregeln für sechs Musterpersonen). Dazu die letzten offenen Teile: `Personalization.healthWidgets`/`insightTopics`, `ReminderPlanner.season`/`swimEquipment`, `TrainingLog.seasonPlan`. Tests: `AppBackupTests`, `CoachExportImportTests`, `CoachImportSelectionTests`, `DataExportTests`, `PersonaTests`, `prioritiesOrderDashboardAndInsights`, `seasonRemindersUseFixedDays`, Saisonplan-Fälle aus `ReminderExtrasTests`/`ReminderDoneTests`. Damit hat jede öffentliche Struktur aus `CoachCore` ein Dart-Gegenstück | erledigt |
| coach_core Mobilität, Spiel, Social und Widgets (Phase 2u): `MobilityArea`/`ComplaintArea`/`MobilityContext`, `MobilityLibrary` (20 Übungen), `MobilityTest` (4 Selbsttests), `MobilitySettings`, `MobilityPlanner` (Schwerpunkte, Einheit im Zeitbudget, Vorschlag); `DailyStreak` (Joker je Woche), `GameStats`, `BadgeRules`, `GameLevel`, `ChallengeMetric`, `LeaderboardEntry`, `Challenge`; `SocialPerson`/`SocialFriends`/`SocialReaction`/`SocialPost`/`SocialComment`, `WorkoutShare` (ohne Körperwerte), `MealPostShare`, `SocialFormat`, `SocialTimeline`; `WidgetSnapshot` mit Anzeige am Folgetag, `WidgetActionQueue`, `HealthMetric`, `AppGroupProfile`, `MealHeadline`. Tests: `MobilityTests`, `GameTests`, `SocialTests`, `SocialTimelineTests`, `WidgetSnapshotTests`, `MealHeadlineTests`. Widget-Dateien schreiben Zeitpunkte wie der Standard-`JSONEncoder` (Sekunden seit 2001), damit die nativen Widgets sie lesen; `AppGroupProfile.groups` liest das Profil ohne Plist-Parser; Zeiten in Gerätezeit (Tests in vier Zeitzonen geprüft) | erledigt |
| coach_core Integration, Konto und Motivation (Phase 2t): `SourcePreferences` (Reihenfolge je Datenart, tolerant gelesen), `MetricsMerge` (je Datenart eine Quelle als ganze Gruppe), `ActivityMerge` (Doppelte über Anbieter, `localID` FNV-1a wie Swift, in Python nachgerechnet), `SyncLedger`/`SourceEntry` (neu, geändert, gelöscht, ersetzt; Prüfsumme über JSON mit sortierten Schlüsseln wie `JSONEncoder`), `ProviderSyncState` (Wartezeiten, Nachholzeitraum); `AccountRules`/`AccountInvite`; `WeekAdherence`, `ScoreRules`, `MotivationSummary`, `LeagueEntry`, `LeagueInvite` (Token-Schutz bei fremdem Server), `GuestToken`, `AndroidLink`, `LeagueCode`, `CompanionSettings`/`CompanionVoice`, `DaisyGeometry`. Tests: `DataSourceTests`, `AccountRulesTests`, `MotivationTests`. Links: Query-Werte wie `URLComponents` (`+` bleibt Plus) | erledigt |
| coach_core Ernährung Teil 3 (Phase 2s): `MealNow`, `OwnRecipe`, `NutritionWeek`, `ShoppingAisle`, Abend-Erinnerung; `RecipePlan` (`Allergen`, `RecipePreferences`, `RecipeDayTarget`, `Recipe`, `RecipeDay`, `WeeklyRecipePlan`, `RecipePlanner` mit Ernährungsweise, versteckten Allergenen, Plausibilität, Lücken, Einkaufsliste, Zeiträumen); `CookPlan` (`CookShare`/`CookShareFields`/`CookPartner`/`CookRelease`, `CookLink`, `CookAmount` mit JSON wie Swift `{"portions":{"_0":3}}`, `CookPerson`, `CookPlan`, `CookPlanner`), Abfragen in Teilen, `AIErrorText`. Tests: `MealPlanningTests`, `RecipeTests`, `StricterRecipeTests`, `CookPlanTests`, Rezept-Fall aus `MealLibraryTests`. Einkaufsliste sortiert wie `localizedCompare` (Umlaute wie Grundbuchstabe) | erledigt |
| coach_core Ernährung Teil 2 (Phase 2r): `QuickLog` (`MealEntry`, `MealSuggestions`, `FoodSearch.rank`, `NutritionBudget`, Schnell-Eintrag), `MealLibrary` (`FavoriteMeal`, `MealShortcuts`, `MealPortion`), `MealShare` (`SharedMeal`, Codes aus Links), `NutritionCheckIn`, `Expenditure`, `WeightForecast`, `MealReminderSettings` mit Erinnerungen, `NutritionDashboard`/`NutritionDaySummary`. Tests: `QuickLogTests`, `MealLibraryTests` (Rezept-Fall in Phase 2s), `MealShareTests`, `NutritionCheckInTests`, `ExpenditureTests`, `WeightForecastTests`, `MealReminderTests`, `NutritionDashboardTests`, Verbrauchs-Test aus `GoalGuardTests`. | erledigt |
| coach_core Coach-Rest und KI (Phase 2q): `ActivityReport` (Runden, Splits, Hälften, Standzeit, Kadenz; JSON wie Swift mit Rundenintensität als Zahl), `ActivityReportBuilder`, `ActivityFindings` (Tempo-Einteilung, Puls-Drift, Intervalle, Standzeit, Zonen; ohne Pulswerte im Modus „reduziert“), `ActivityReportPlanner`; `ChatContext`/`ChatRouter` (Themen, Fakten je Frage mit Herkunft, Schutzgrenzen), `PersonalNote`, `WeeklyReport`, `WeeklyReview`, `TrainingTrends`; KI: `AIMode`/`AIPolicy`/`AIProviderChoice`/`AISettings`, `AIUsageLog`, `Insight`/`InsightInbox`/`InsightRules`/`InsightAnalysis`; Rest von `WeightTrend` (Trendlinie, Vorschlag mit Schutzstufen, Garmin-Wägungen). Tests: `ActivityReportTests`, die zwei offenen Fälle aus `HealthRecordingTests`, `InsightsTests`, `AIPolicyTests`, `ChatRouterTests`, `ChatContextTests`, `PersonalNoteTests`, `WeeklyReportTests`, `WeightTrendTests`, Vorschlags-Test aus `GoalGuardTests`. `WeeklyReview`/`TrainingTrends` rechnen in der Gerätezeitzone (wie `WeekLoad`) | erledigt |
| coach_core Health und Schlaf: `PersonalNorm`, `BodyBatteryAnalysis` (Aufwachwert, Verlauf, Zusammenhänge mit Schlaf und Stress), `GermanState`/`GermanHolidays`, `WakePlan`, `HealthAccessDiagnosis`, `HealthRecording` (Workout-Verlauf als FIT-Aufzeichnung), `HealthImport` (Tageswerte, Nächte mit Phasen, Workouts ohne Doppel, Wägungen; Uhrzeiten in Ortszeit oder mit festem UTC-Abstand), `HealthDashboard`, `MorningReport` mit Mitteilung, `SleepCoach`/`SleepSettings`/`SleepAlarm`. Tests: `SleepCoachTests`, `HealthAccessDiagnosisTests`, `BodyBatteryTests`, `HealthImportTests`, `HealthRecordingTests`, `HealthDashboardTests`, `WakePlanTests`, `MorningReportTests` | erledigt |
| coach_core Garmin und FIT-Export: `GarminEndpoint` (Personal API mit Bereichsgrenzen), `GarminBearerToken`, `GarminAPIError`, `SyncPlan`, `GarminConnect` (mobile Anmeldung mit Bestätigungscode, DI-OAuth2-Token, Abrufe, Upload), `ConnectEndpoint`, `GarminConnectMetrics` (Readiness, Trainingsstatus, Endurance Score), `GarminWorkout` (Workouts aus dem Plantext und Schwimmschritten, Garmin-JSON), `SentWorkouts`, `GarminStrengthSync` (Sätze füllen oder ersetzen, Zuordnung zur Uhr-Aufzeichnung, Warte-/Upload-Logik), `FitEncoder`, `StrengthFitExport`, `GarminExerciseMapping`, `GymItem.fromSession`. Tests: `GarminEndpointTests`, `SyncPlanTests`, `GarminConnectTests`, `GarminWorkoutTests`, `GarminStrengthSyncTests`, FIT-Fälle aus `GymBookTests`, Endpunkt-Pfade aus `MetricsAndZonesTests`, Readiness aus `BodyBatteryTests` | erledigt |
| coach_core Profil vollständig: `SchedulePlanner` (Einheiten nach Ziel, Wettkampf und Erfahrung, Kürzen nach Priorität, beste Verteilung auf die freien Tage), `RunPlanner` (Laufwoche mit 10-%-Grenze, Entlastung, Tapering, Grenze am längsten Lauf), `InputCheck` (Körperwerte, Gewichtsziele, Zielzeit gegen die Prognose der Uhr), `RacePredictions`, `PostWorkout` (Auswertung und morgen entschärfen), `PlanSuggestion` (Diff mit Regelkonflikten aus Tagesform, Belastung, Nach-dem-Training und Wochenrückblick). Tests: `SchedulePlannerTests`, `ProfileEvidenceTests`, `RunPlanTests`, `InputCheckTests`, `PostWorkoutTests`, Planvorschläge aus `TrainingTodayTests`, Planer-Fälle aus `AuditR4APlanTests` und `Phase78Tests` | erledigt |
| coach_core Plan-Modul: `SeasonSchedule` (48 Wochen aus `assets/season-plan.json`, Schwimmschritte, Zwift-Workouts, Phasen), `PlanTokens` (Platzhalter §T§, §I§, §E§, §S±n§, §Wnn§, §MP§, §R§), `PlannedUnit` mit Wettkampf-Entscheidungen, `PlanProgress`, `SwimStepText`, `TestRecord`/`TestHistory`, `SwimPaces`/`BikeZones`/`RunPaces`, `RaceEstimate`, `MarathonOutlook`, `WeekFrame`/`TodayPlan`/`FilledWeek`, `TodayFocus` (beide Modi), `UnitGuides` (Saisonplan und eigener Wochenplan). Tests: `DisciplineTests`, `PlanScheduleTests`, `TodayPlanTests` (alle über 2000 Vergleichsfälle mit den Original-Templates), `UnitGuideTests`, `ScheduleAdvisorTests`, „Jetzt dran“-Fälle aus `TrainingTodayTests` und `AuditR4APlanTests` | erledigt |
| coach_core Gym vollständig und Belege: `WorkoutFlow` (Fokus-Satz, Supersätze mit Kürzeln, Vorschau, Zusammenfassung), `NumberPad`, `ActiveSessionState`, `WorkoutEdits` (später, verschieben, Supersatz, ersetzen, Alternativen, Aufwärmsätze, Satzgewicht, überspringen), `SetCheck`, `RestAdvisor`, `ExerciseUnits`, `PlateCalculator`, `WarmUp`, `RestText`, `HoldTimer`, `Routine`/`RoutineItem`/`RoutineTemplates` (GymBook-Pläne, Vorlagen nach Krafttagen), `GymSettings` (alle Felder, nachsichtiger Decoder), `CompleteOnEdit`, `RestSound`, `GymTarget`, `RoutineRotation`, `SessionComparison`, `GymCalendar`, `MuscleMap`/`MuscleLoad` (Heatmap, Erholung), `GymCoach` (Beobachtungen, KI-Plan mit Fragebogen und Prüfung), `GymHints`, `GymBookImport` (stabile IDs wie Swift, in Python nachgerechnet); `Evidence` (75 Studien, 47 Regeln), `UserSources`, `CoachingNote` mit `PrivacyMode`. KI-Eingaben sind `Map<String, Object?>`. Tests aus allen Gym-Testdateien außer FIT-Rundreise und Garmin-Übungscodes (folgen mit `FitEncoder`/`GarminExerciseMapping`), dazu `UserSourcesTests` und `everyEvidenceIDExists` | erledigt |
| coach_core Gym-Grundlagen: `ExerciseCatalog` (47 Garmin-Regeln, Reihenfolge wie im Altbestand), `ExerciseLibrary` (59 Übungen mit Anleitung), `ExerciseInfo` (eigene Übungen), `GymPlan` (Standardplan, flexible Beintage, Zielbereiche), `GymSession`/`LoggedExercise`/`LoggedSet`/`GarminLink` mit JSON wie die Swift-Sicherung (ISO-8601, nachsichtige Decoder), `ExerciseAliases`, `MuscleVolume`, `GymProgression` (Doppelprogression A–D, Wiedereinstieg, Warnsignal), `GymStats` (Epley, Verlauf, Bestwerte, letzte Leistungen); Tests aus `GymTests` und `GymLibraryTests` (ohne Routinen/Einstellungen/Hinweise, folgen in 2l). Die Pace-Check-Zeile heißt jetzt `PaceCheckRow`, damit `PaceRow` frei für die Tempotabellen ist | erledigt |
| coach_core Pulszonen und Verläufe: `HeartRateZoneCalculator` (Friel-Zonen, Zonen der Uhr, bestätigter Höchstpuls, eigene Werte vor Garmin, Schätzung, Verteilung locker/mittel/hart je Woche, Hinweise), `HeartRateOverrides`, `MetricTrend`, `WeekVolume`, `VO2MaxHistory`; Tests aus `MetricsAndZonesTests` (ohne Endpunkt-Pfade, folgen mit dem Garmin-Client) | erledigt |
| Offen aus bisherigen Dateien: alle nachgezogen (zuletzt in Phase 2v) | erledigt |
| Native Registrierung im `AppDelegate` (Mitteilungs-Delegate, Widget-, Live-Aktivitäts- und Wecker-Brücke), Widget-Erweiterung | erledigt (3m-1 bis 3m-6), geprüft per iOS-Build |
| Hintergrundabruf (`BGAppRefreshTask` bzw. WorkManager, `workmanager`) | erledigt (3n-1) |
| Alle Teilphasen aus Abschnitt 6 | erledigt (Stand 14.11.2026) |
| WHOOP-Anbindung (offizielle API v2, OAuth über den Worker): Recovery, HRV, Ruhepuls, Schlaf, Kalorien, Schritte, Trainings; Einstellungen › Training und Fitness › WHOOP | erledigt |
| Erweiterungen nach der Migration (15.11.2026): Vorrang der Gym-Live-Aktivität vor „Mahlzeiten heute“ (keine doppelten Karten mehr), Einstellungen › Sperrbildschirm (Bereiche Gym/Ernährung, Ansicht der Gym-Karte: nur Pause, nur Übung, beides), Einheit und Trainingsplan teilen (Text plus `coach://routine/…` zum Übernehmen), Rezepte aus dem Kühlschrank-Foto mit Rückfragen, Erinnerung an Mahlzeiten auf dem Sperrbildschirm statt als Mitteilung, „Mahlzeiten heute“ unter Android als lautlose Mitteilung | erledigt (#73) |
| Mehrere Benutzer je Gerät, strikt getrennt (eigene Datenbankdatei, Schlüssel und Ordner je Benutzer; Wechsel verwirft den kompletten Zustand), Einstellungen › Benutzer | erledigt (#73) |
| Worker nach AIronLudi übernommen (`worker/`, Workflows `worker.yml`, `worker-smoke.yml`), Aufgabe `pantry_recipes` (Kühlschrank-Foto) mit Tests; Einrichtung `docs/einrichtung.md`, Anleitungen `docs/anleitung.md` | erledigt |
| Secrets des Workers in AIronLudi anlegen und Worker von hier bereitstellen; Git-Anbindung bei Cloudflare an Coach-App trennen | erledigt (Secrets in AIronLudi gesetzt, Stand 25.11.2026); ob die alte Git-Anbindung bei Cloudflare getrennt ist, lässt sich von hier nicht prüfen |
| Sicherung der Kotlin-App „IronLudi“ (`IronLudi-Gym-Sicherung-*.json`) einlesen (`KotlinBackup`, `BackupService.restoreKotlin`, Erkennung beim Einspielen) – Voraussetzung für den Umstieg unter Android | erledigt (#76) |
| Android-Download über ein privates Release-Repo (APK über 100 MB, KV-Grenze 25 MiB), `ironludi://connect` in der App | erledigt |
| Adaptiver Ausdauerplan (Laufen, Rad/Zwift, Schwimmen): Ziel- oder Zeitraum-Plan mit Periodisierung, tägliche Anpassung an Training (disziplinübergreifend, TSS), Ausfälle und Erholung (HRV, Ruhepuls, Schlaf, Body Battery, Readiness); Export als FIT-Workout, Zwift `.zwo`, „An Uhr senden“ und automatischer Garmin-Kalender-Abgleich; strikt je Benutzer (`TrainingPlanEngine`, `WorkoutExporterService`, Reiter Training › Ausdauerplan) | erledigt |
| KI-Empfehlungen extern prüfen lassen: Export mit Prüfauftrag für alle offenen Empfehlungen, Import von `empfehlungen`/`verwerfen` mit Auswahl je Empfehlung (Regeln nur ausdrücklich), Hinweis im Bereich „AI“ | erledigt |
| Rückmeldung 17.11.2026: „Entfernen“ im Wochenplan, veraltete Trainingstage, Fettabbau ohne Überschuss; Texte geräteunabhängig (Health Connect unter Android); Tagesanpassungen und Makros in der Ernährung, realistische Hochrechnung; „Meine Belastung heute“; Training als Kacheln mit Wochendiagramm | erledigt |
| Import von KI-Antworten nachsichtig (Namen statt IDs, englische Schlüssel, reparierbares JSON, Datei laden, fester Übernehmen-Knopf, Wege zum Plan) | erledigt |
| Import von Wochenplänen als Markdown-Tabelle (.md-Datei), „Diese Woche“ nur für die laufende Woche | erledigt |
| Routenplaner auf OpenStreetMap (Laufen, Rennrad, Gravel): Rundweg, zum Ziel mit Umweg, Richtung; Distanz ±7 % und Höhenmeter; drei Varianten mit „Neu würfeln“, Karte, Höhenprofil, Dauer; Übernahme in eine Einheit (Heute › Route für heute), GPX und FIT-Kurs; Valhalla (FOSSGIS) mit BRouter als Ausweich und Rate-Limit; optionale Gebiete und Erkundungskarte; strikt je Benutzer (Training › Routen) | erledigt (#95) |
| Routenplaner Teil 2: Ansichtsmodus (Antippen verschiebt nichts mehr, langes Drücken / „Startpunkt ändern“), Umgebung Wald/Wasser/Asphalt/Mix (Router-Gewichtung und Overpass-Wegpunkte), Distanz ±2,5 % (Sekantenverfahren, offene Ziele exakt gekürzt), Richtungspfeile, Modus „Frei planen“ (Punkte oder Zeichnen mit Snapping, Live-Werte, Rückgängig, Rundweg schließen) | erledigt (#96) |
| Routenplaner: Start und Ziel per Adresszeile (Photon mit Vorschlägen beim Tippen, Nominatim bei ausdrücklicher Suche, Koordinaten), Adresssuche auch beim freien Planen | erledigt (#97) |
| Routenplaner: Karte im Vollbild (Antippen; langes Drücken setzt Punkte), Favoriten-Orte je Benutzer (Stern, Liste in der Adresszeile, Verwaltung), „Gravel“, Disziplin Spazieren (Gassi) | erledigt (#98) |
| Routenplaner: Archiv abgeschlossener Routen (automatisch über passende Aktivität oder von Hand), Kilometermarken auf allen Routen, „An Uhr senden“ mit Anleitung je Hersteller | erledigt (#99) |
| Routenplaner: Knopf „Mein Standort“ auf allen Karten (blauer Punkt, zentrieren) | erledigt (#100) |
| Routenplaner: Echttest gegen die öffentlichen Dienste (`tool/live_check.dart`), BRouter-Profile korrigiert, Höhen geglättet, Overpass-Spiegel, zweiter Versuch bei Verbindungsabbruch | erledigt (#101) |
| Routenplaner: Controller (Stand bleibt beim Verlassen), Vorschläge einzeln, Route aus einer Einheit des Ausdauerplans, Hinweis bei nicht berücksichtigter Wegart, frei geplante Routen bearbeiten (verschieben, löschen, einfügen) | erledigt (#102) |
| Routenplaner: Gassi-Extras (Hundewiese als Wegpunkt, Trinkbrunnen/Hundewiesen/Kotbeutel unterwegs, Vorlagen) und „Route folgen“ (Standort live, Restdistanz, Warnung abseits) | erledigt (#103) |
| Routenplaner: Kurs direkt an Garmin Connect senden (ersetzt beim erneuten Senden, sonst FIT teilen) | erledigt (#104) |
| Routenplaner: Kartendienste mit Schlüssel über den Worker (openrouteservice-Rundwege als Ausweich, MapTiler-Kacheln mit Dunkelmodus, Cache, Tageslimit) | erledigt |
| Routenplaner: Wetter und Wind für den geplanten Tag (Open-Meteo, Wind je Hälfte, Richtung umkehren) | erledigt |
| Routen in eigener Tabelle `RouteRecords` (Schema 2, Übernahme aus `coach.routes`, Sicherung im bisherigen Format) | erledigt |
| Gebiete ohne vorheriges Öffnen (still nach jedem Abruf, „Letzte 12 Wochen laden“ begrenzt mit Pausen) | erledigt |
| Fuel Planner (neu, Research-First, `docs/FUEL_PLANNER_SCIENCE.md`): Kohlenhydrate/Flüssigkeit/Natrium/Koffein vorher, unterwegs und danach nach Dauer, Intensität, Disziplin, Verträglichkeit (Gut-Training) und Wetter; Glukose-Fruktose-Verhältnis, Carboloading, Doppeltag-Auffüllen; Zeitstrahl im 15/20/30-min-Takt mit eigenen Produkten und DIY-Mischungen, Packliste; aus jeder Einheit des Ausdauerplans oder frei; Übernahme ins Ernährungstagebuch; strikt je Benutzer (`coach.fuelPlanner`) | erledigt (#106) |
| Fuel Planner, zweite Runde: Koffein-Budget, gleitende Werte, Triathlon-Abschnitte, Trinken mit Saldo, mehrere Getränke, Tagebuch ohne Doppelzählung (Platzhalter), veraltete Pläne, Wetter aus der Vorhersage, Einstieg aus dem Wochenplan (auch Kraft), Editor mit Vorlagen, ehrliche Kennzeichnung geschätzter Zahlen | erledigt (#107) |
| Fuel Planner: wie man es zu sich nimmt (Vorschläge mit BLS-Lebensmitteln vorher/danach, „So nimmst du es“, feste Kost zuerst), Alltag unterwegs statt Sportnahrung, „nur was ich zu Hause habe“ (annähernd mit Prozent), Vorrat mit Mindesthaltbarkeit (zuerst aufbrauchen, Packliste Vorrat/kaufen, Abbuchen beim Tagebuch) | erledigt |
| Heute entschlackt: Ringe für Schlaf, Erholung und Strain (0–21) mit Ampelfarben, Training heute mit Strain je Einheit, Bereiche ein-/ausblendbar (auch AI); weitere Sportarten (Bouldern, Klettern, Yoga, HIIT …); „Wochenplan importieren“ unter Training › Plan; eigene Makroziele (Gramm/Prozent, Ruhetage); Produktsuche (eigene, BLS, Open Food Facts) | erledigt |
| Erfassen mit Suche zuerst: Vorschläge zur Mahlzeit, „+“ in den Korb, mehrere Lebensmittel auf einmal eintragen, andere Wege als Reiter | erledigt |
| UI-Redesign „Clean Liquid Design“ (`lib/ui/liquid.dart`, `AppTheme`): Glasflächen mit Lichtkante über Lichtflecken-Hintergrund, große Radien, Pillen-Knöpfe, schwebende Tab-Leiste, Verlaufs-Ringe und -Balken mit Federanimation, taktile Rückmeldung, Vorschau der Live-Aktivität (`docs/decisions.md`, 18.11.2026) | erledigt |
| Daily Strain aktualisiert über den Tag (Neuladen bei jeder Änderung von Aktivitäten, Tageswerten und Gym-Einheiten, Abruf alle 15 min im Vordergrund); Schnellsuche Ernährung mit Markenprodukten aus Open Food Facts (Volltextsuche, Ausweich-Suche, Fehler statt stiller Leere) | erledigt |
| Strain wie bei WHOOP: WHOOP-Tageswert, sonst aus dem Puls über den ganzen Tag (Garmin `dailyHeartRate`, Apple Health / Health Connect), Zonen der Herzfrequenzreserve, Skala 0–21; neue Datenart „Strain“ | erledigt |
| Prüfung der Ernährungsrechnung: Training netto ohne Doppelzählung mit dem PAL, Überschuss beim Aufbauen an jedem Tag, Untergrenze nie unter dem Grundumsatz, Defizit am Ruhetag auch bei kleinen Personen, kcal = Summe der Makros, Lücken bei Mikros statt 0 (`FoodAggregation`), Plausibilität fremder Nährwerte (`NutrientPlausibility`), Natrium aus Salz | erledigt |
| Ernährungsrechnung, zweite Runde: Formel-Bedarf ohne eigene Makros für den Verbrauchsabgleich, keine vorgetäuschten Lücken an KI, Rezept-Lückenliste und Budget-Karte, Fett ≥ 0,7 g/kg, Eisen ab 51, Natrium als Richtwert mit Schweißverlust | erledigt |
| Test auf echten Geräten: Widgets, Live-Aktivitäten, laufende Mitteilung, Wecker, Hintergrundabruf, Schnellaktionen (nur dort prüfbar, CI baut sie) | teilweise automatisch (`device-test.yml`: Brücken, Live-Einheit); Rest durch den Nutzer (Geräte-Checkliste im Roast-Bericht) |
| Umstellung: `vars.DEPLOY_SIDESTORE` bzw. `vars.DEPLOY_ANDROID` auf `true`, dann ersetzt die Flutter-App die Swift- bzw. Kotlin-App (gleiche Bundle-/Application-ID) | erledigt (beide Variablen seit 16.11.2026 auf `true`) |
| Android-Widgets mit Ringen und Einstellung je Widget, Wiederholungen ± in der Android-Mitteilung (ohne Glance, Bilder in RemoteViews) | erledigt |
| Update-Hinweis Android (neu, `docs/decisions.md`): Worker `GET /v1/app/android` (neueste Version, Link zur Download-Seite, nur mit Anmeldung), `AppUpdateService` (Prüfung beim Start/Zurückkehren höchstens alle 6 h, Vergleich `versionCode`, „Später“ je Version), Hinweis oben in der App mit „Jetzt laden“ | erledigt |
| Roast 24.11.2026 (`docs/roast/`), Stufe 1 / PR 1: WHOOP-Anmeldefehler verständlich (`WhoopAuthErrors`, Rücksprung-Seite nennt fehlende Scopes), Anleitung mit Scope `offline` | erledigt |
| Roast Stufe 1 / PR 2: Überläufe bei großer Schrift und auf kleinem Android behoben (Makro-Zeilen, Wochenstreifen in Ernährung, „Sicherung einspielen“ der Einrichtung), Regressionstest `layout_overflow_test.dart` | erledigt |
| Roast Stufe 1 / PR 3: „Heute“ – Hinweis „Datenquelle verbinden“ mit Knopf und nur ohne Werte der letzten Woche (`showsConnectSourceHint`), Strain-Wert neutral, solange nichts trainiert ist (`Kpi.valueStatus`) | erledigt |
| Roast Stufe 1 / PR 4: WHOOP-Recovery mit eigener Skala in der Tagesampel (`WhoopRecoveryLevel`, rot < 34 → Pause), Garmin unverändert | erledigt |
| Roast Stufe 1 / PR 5: `.gitattributes` (LF), Tests laufen unter Windows (Pfade, Temp-Ordner, unbeschreibbarer Pfad), Abschnitt 8 ohne veraltetes „in PR“, `CLAUDE.md` mit `ironludi://` und Prüfstand | erledigt |
| Agenten-Anweisungen: `AGENTS.md` als gemeinsame Quelle für alle KI-Werkzeuge (Funktionsübersicht, Architektur, UI-Regeln, Doku-Pflege), `CLAUDE.md` bindet sie ein, `worker/AGENTS.md` für den Worker; doppelte Zeilen in Abschnitt 8 entfernt | erledigt |
| Roast Stufe 1 / PR 7: Export-Ordner (KI, Routen) beim Benutzerwechsel geleert (`ExportFolders`, `clearSharedExports`); PR 6 (Ladefenster „Heute“) nach Prüfung verworfen | erledigt |
| Roast Stufe 2 / PR 8: Designsystem-Tokens (`lib/ui/tokens.dart`) und Sperrklinken-Test gegen neue Rohfarben/Schriftgrößen in `lib/features` | erledigt |
| Roast Stufe 3 / PR 16: HRV-Trend für WHOOP und Health in der Tagesampel (`HrvTrend`, 7-Tage-Schnitt gegen eigene Basis) | erledigt |
| Roast Stufe 2 / PR 9: Heute und Ernährung auf Tokens (`AppColors`, `AppText`): keine festen Schriftgrößen mehr, Ampelfarben semantisch, nichts unter 12 pt | erledigt |
| Roast Stufe 2 / PR 10a: übrige Bereiche auf Tokens – Ampelfarben semantisch, häufige Schriftgrößen als Textrollen; Bestand 166 Farben, 61 Schriftgrößen (Rest in PR 10b) | erledigt |
| Roast Stufe 2 / PR 12: Barrierefreiheits-Tests der vier Reiter (iOS-Tap-Flächen 44 pt, Beschriftungen, Kontrast 4,5 : 1); Nebentexte, Akzent und Tab-Leiste kontrastreicher, Tab-Beschriftung 12 pt, Segmente 44 pt, ein Symbolsatz in der Tab-Leiste | erledigt |
| Roast Stufe 2 / PR 11b: gemeinsame Diagramm-Achsen (`lib/ui/chart_axes.dart`: deutsches Zahlenformat, keine krummen Randwerte, kein Umbruch, skalierende Schrift) in allen fl_chart-Diagrammen | erledigt |
| Roast Stufe 3 / PR 13: Einheiten des adaptiven Ausdauerplans unter „Jetzt dran“ (`TodayFocus.withEndurance`, ersetzt gleiche Sportart des Wochenplans, Ampel warnt), Antippen öffnet den Ausdauerplan | erledigt |
| Fehler aus Stufe-4-Vorbereitung: Schnellaktionen, Widgets und `coach://open/…` führen ihre Aktion aus (`PendingRouteHandler`: Erfassen mit Mahlzeit, Gesundheit, Gym, Einheit starten, KI, KI-Analyse); vorher nur Reiterwechsel | erledigt |
| Roast Stufe 3 / PR 14: Modul „Ernährung heute“ auf „Heute“ (übrige kcal und Protein mit denselben Tageszielen, „Mahlzeit erfassen“; standardmäßig sichtbar, alte Einstellungen kompatibel) | erledigt |
| Roast Stufe 3 / PR 15: „Route dazu planen“ auch für Lauf- und Radeinheiten des Wochenplans (`RouteForSessionSection`, gemeinsamer Baustein `RouteForUnitSection`) | erledigt |
| Roast Stufe 3 / PR 16b: ein Titel je Tagesbewertung (`RecoveryLevel.headline`) auf „Heute“ und im Morning Report; Einheitennamen im Satz in Anführungszeichen | erledigt |
| Roast Stufe 4 / PR 18–21 (Grundumbau): fünf Reiter Heute · Plan · Verlauf · Ernährung · Ich; Training aufgeteilt in Plan und Auswertungen, Einstellungen als Reiter Ich mit Freunde & Liga und KI | erledigt |
| Roast Stufe 4 (F-6): „KI“ statt „AI“ in allen Texten (Schnellaktion, Bereich, Heute-Modul, Export-Anleitung) | erledigt |
| Roast Stufe 4 / PR 23: Ernährung geordnet – Wochen-Check-in unter dem Tag, Navigationszeilen in „Planen“ und „Verlauf“, „Fuel Planner“ heißt „Verpflegung“ (Glossar) | erledigt |
| Roast Stufe 3 / PR 17 (F-1): Demo-Modus – Ich › Technik › Demo ansehen legt Benutzer „Demo“ mit Demo-Daten an (`coach.demo`), kein Abruf/Sicherung/Teilen | erledigt |
| Roast Stufe 4 / PR 21: Verlauf nach Wochen (KW, Zeitraum, Anzahl, Dauer; `FeedWeek`), Hinweis auf Freunde nur im Filter „Freunde“ | erledigt |
| Anatomische Körperkarte für die Muskel-Heatmap: eigene Vektorzeichnung mit Schattierung und Fasern, Vorder-/Rückseite zum Blättern, Seite mit mehr Last zuerst (`BodyMap`, `tool/body_map_art.py`) | erledigt |
| Körperkarte: Umschalter Kraft/Kardio/Dehnen in der Gym-Auswertung (`CardioLoad`, `StretchLoad` in coach_core; Ausdauerminuten und Mobility-Protokoll je Muskel) | erledigt |
| Routenplaner: Luftlinie-Abschnitte in „Frei planen“ (z. B. Brücke nach Baustelle), lauffreundliche Wege beim Laufen, „Zum Ziel“ ohne Wunschdistanz | erledigt |
| Roast Stufe 4 (F-3): Karten nahezu deckend, Unschärfe nur für deckendes Glas (Tab-Leiste, Leisten, Sheets); Prüfstand auf fünf Reiter; Anleitung mit neuen Wegen und Übersicht der Reiter | erledigt |
| Roast Stufe 4 / PR 22 (Teil 1): zehn große Dateien in `part`-Dateien geteilt (Klassen nur verschoben); keine Datei mehr über 1000 Zeilen | erledigt |
| Roast Stufe 4 / PR 24: Prüfstand nach Stufe 1–4 neu gerendert (239 Bilder, fünf Reiter, keine Layoutfehler) | erledigt |
| Roast Stufe 2 / PR 10b: letzte Rohwerte abgebaut (`AppPalette` für Kategorie-, Karten- und Diagrammfarben; Kennzahlen über `LiquidText.kpi`); Designsystem-Test ohne Bestandsliste | erledigt |
| Roast Stufe 4 / PR 22 (Teil 2): letzte acht Dateien über 800 Zeilen geteilt (Klassen in `part`-Dateien; Abschnitte der Ernährungsseite und reine Abfragen des Gym-Controllers als Erweiterungen, Verhalten unverändert); keine Datei in `lib/features` mehr über 800 Zeilen | erledigt |
| Roast Glossar: Ring und Texte auf „Heute“ sagen „Belastung“ statt „Strain“ (Ring, Dashboard-Editor, Aktivitätszeile, Belastungskarte, Datenquellen, Garmin-Diagnose); „WHOOP-Strain“ bleibt als Name des WHOOP-Werts | erledigt |
| Roast-Nacharbeit: kein Abschneiden bei großer Schrift (Prüfstand meldet abgeschnittene Texte; Tab-Leiste, Ringe, Kacheln, Erfassen), Knopfschrift im Theme, nichts unter 12 pt in ganz `lib/` | erledigt |
| Roast-Nacharbeit: deutsche Begriffe (Morgenbericht, Verpflegung, Trainingsbereitschaft, Normalbereich, Erholung, Einheit/Aktivität), Health-Meldungen ohne interne Namen; reduzierter Datenschutzmodus ohne WHOOP-Zahl | erledigt |
| Roast-Nacharbeit: Verlauf, Ernährung, Plan, Woche und Gesundheit laden bei neuen Trainingsdaten neu (vorher nur beim Garmin-Abruf) | erledigt |
| Durchläufe Ernährung (`test/walkthrough/`): Tagebuch, Erfassen, Gewicht, Verpflegungsprodukte; behoben: BLS-Suche mit Schreibweisen, Früheres in „Erfassen“ suchbar, Wasser 0,25 l, einheitlich „Sichern“ | erledigt |
| Durchläufe Plan und Verlauf, beide Geräte (iPhone, kleines Android mit großer Schrift); behoben: Überlauf im Mahlzeiten-Editor, „Abbrechen“ ohne Umbruch (`BarTextButton`) | erledigt |
| Durchlauf „Ich“ (alle Bereiche, Sicherung, Datenquellen, Benutzer, Konto); Datensicherung unter Allgemein, Sicherungsdatei im Export-Ordner je Benutzer | erledigt |
| Durchlauf Einrichtung und Heute (beide Geräte); Einrichtung: „Weiter“ schlägt den Wochenplan aus den gewählten Tagen vor | erledigt |
| Ernährung: Makrobalken (Protein/KH/Fett) über die volle Breite, Name links und Rest rechts, 8 pt hoch; Balkenspur (`LiquidTheme.track`) kräftiger, damit der Fortschritt auf weißen Karten erkennbar ist | erledigt |
| Routenvorschläge zu geplanten Läufen: passend zum Training, annehmen/ablehnen, Gelände und Start in den Einstellungen, Abwechslung über vier Wochen | erledigt |
| Durchläufe Konto, Freunde & Liga, automatisch teilen, Quellen gegen nachgebauten Worker; behoben: Fehler beim Öffnen von Freunde/Verlauf mit Konto | erledigt |
| Gerätetests auf Android-Emulator und iOS-Simulator (`device-test.yml`); behoben: „Verpasst“ direkt nach der Einrichtung | erledigt |
| Durchläufe Rezepte, Garmin-Konto und WHOOP gegen nachgebaute Server; „Eigene Rezepte“ mit Knopf im leeren Zustand | erledigt |
| Wünsche vom 25.11.2026: Plan-Kacheln gleich groß, Krafteinheiten heißen überall Push, Pull, Lower, Pull & Push, Musterwoche und Quellen/Grundlagen nicht mehr angezeigt, Wasser-Karte kompakt, lange Einheit nur an Trainingstagen, Zeitrechner mit Reglern (Almere, Marathon), KI-Auswahl im Menüstil | erledigt |
| Fotos beim Erfassen: bis zur erfolgreichen Auswertung gesichert, nach Fehlschlag „Erneut versuchen“, „Später automatisch eintragen“ (auch im Hintergrund, mit Uhrzeit der Aufnahme, Mitteilung) oder „Verwerfen“; Warteschlange als Dateien mit Sperre; gewähltes Foto als Karte | erledigt |
| WHOOP: Bouldern und Klettern erkannt (auch über die Sport-ID); Wochenplan: „Anderes“ mit gewählter Art (z. B. Bouldern), Abgleich nach Art | erledigt |
| Routenplaner: „Route folgen“ auch bei gesperrtem Bildschirm (iOS Hintergrund-Ortung, Android Vordergrunddienst, Warnung als Mitteilung) | erledigt |
| Karte auf der Garmin-Uhr, Schritt 1: Uhr-Paket `AIW1` (Wegenetz, Varianten, Abbiegungen), Worker-Ablage und Kopplung, „Karte auf die Uhr“ in der App, Datenfeld-Grundgerüst `garmin/` mit CI | erledigt |
| Garmin-Build: Testversion ohne Garmin-Zugang als Artefakt, Lizenz-Hash in der Zusammenfassung, Werkzeug fest auf v0.8.4, Anleitung in Stufen | erledigt |
