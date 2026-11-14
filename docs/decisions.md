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

## 2026-11-13 – App-Einstellungen (Phase 2h)

- **`CoachSettings` speichert beim Zuweisen** (wie `didSet`). Swift-Strukturen sind Werttypen: Dort speichert
  schon eine geänderte Eigenschaft (`settings.league.code = …`). In Dart sind es Objekte, deshalb wird nach einer
  Änderung neu zugewiesen (`settings.league = settings.league..code = …`) oder eine Kopie gesetzt. Die Schlüssel und das JSON-Format
  bleiben gleich wie in Swift.
- **Optionale Werte** (`coach.illnessDay`, `coach.importedNotes`) werden beim Leeren entfernt, nicht als JSON
  `null` gespeichert. Beides liest sich als „nicht gesetzt“.
- `ReminderSettings`, `LeagueSettings` und `ImportedNotes` lagen in Swift in der App. Sie sind reine Datentypen
  und stehen deshalb in `coach_core` (`settings/app_settings.dart`).

## 2026-11-13 – Erinnerungen (Phase 2j)

- **Mitteilungen über `flutter_local_notifications`** hinter der Brücke `NotificationCenterBridge`. Das Plugin
  arbeitet mit Zahlen als Kennung. Die Text-Kennungen der Swift-App (`coach.reminder.…`) liegen deshalb in der
  Nutzlast, die Zahl ist ein stabiler 31-Bit-FNV-Hash davon.
- **Erlaubnis:** Das Plugin unterscheidet nicht zwischen „noch nicht gefragt“ und „abgelehnt“. Die App fragt deshalb,
  wenn eine Erinnerung gewünscht ist und keine Erlaubnis vorliegt. Bleibt sie aus, gilt der Stand als „abgelehnt“
  (iOS zeigt die Abfrage ohnehin nur einmal).
- **Mitteilungen in der Vergangenheit** werden nicht eingetragen, bei iOS würden sie nie auslösen.
- **Ausgelieferte Mitteilungen entfernen** heißt beim Plugin: die Kennung zurückziehen, geplant und ausgeliefert.
  Nach „Auslassen“ ist beides gewollt.

## 2026-11-13 – Health (Phase 2k)

- **Paket `health`** (HealthKit auf iOS, Health Connect auf Android) hinter der Schnittstelle `HealthSource`. Das
  Paket liefert Rohproben, keine HealthKit-Statistikabfragen. Deshalb rechnet die App die Tageswerte selbst
  aus, je Tag in der Zeitzone des Geräts:
  - **Summen** (Schritte, Energie): HealthKit führt Uhr und iPhone ohne Doppelzählung zusammen. Hier zählt
    stattdessen je Tag die Quelle mit der größten Summe.
  - **Mittel und Minimum** (Ruhepuls, HRV, Atemfrequenz, SpO₂) werden über alle Proben des Tages gebildet.
- **Was das Paket nicht liefert** (gegenüber Swift fehlt es):
  - VO2max, Lauf- und Radleistung.
  - Strecke (GPS) eines Workouts, Runden und Pausen, Höhenmeter.
  - Zuordnung von Proben zu einem Workout. Puls und Distanz für den Verlauf kommen deshalb aus dem Zeitraum des
    Workouts; bei mehreren Distanzquellen zählt die mit der größten Strecke.
  - Das nachzurüsten braucht eine eigene native Brücke (Migrationsplan 4.2).
- **Workout-Kennungen**, die keine UUID sind (manche Health-Connect-Quellen), werden stabil in UUID-Form gebracht,
  damit die Aktivitäts-ID wie in Swift entsteht (`HealthImport.activityID`).
- **Krafteinheit schreiben** (`writeWorkoutData`) ohne `HKMetadataKeyExternalUUID`; das Paket bietet keine Metadaten.
  Die Einheit trägt Titel, Start und Ende.
- **Wecker zur Aufstehzeit** (AlarmKit, iOS 26) bleibt eine native Funktion und folgt mit den Plattformbrücken.

## 2026-11-13 – GymBook und Diktat (Phase 2l)

- **GymBook-Backup** wird über das Paket `sqlite3` gelesen (ist schon über drift im Projekt), nur lesend und aus
  einer Kopie im Temp-Ordner, wie in Swift.
- **Diktat über `speech_to_text`.** Das Plugin sagt nicht, ob die Erkennung auf dem Gerät möglich ist. Deshalb wird
  keine Erkennung auf dem Gerät erzwungen, sondern wie beim Diktieren der Tastatur gearbeitet; `isOnDevice` bleibt
  `false`. Swift erzwingt sie, wenn das Gerät sie unterstützt. Das ließe sich mit einer nativen Brücke nachrüsten.

## 2026-11-13 – Ernährung (Phase 3d)

- **Swift-Test `PersonalizationAppTests.nutritionUsesTheOwnWeekPlan`:** Er erwartet für einen geplanten harten Lauf
  den Tagestyp `.hard`. `SessionSlot.plannedDayType` liefert für `.hard` aber `.moderate`, nur `.long` ergibt `.hard`.
  Swift und Dart sind dabei Zeile für Zeile gleich. Der Dart-Test erwartet deshalb `.moderate`; die Regel bleibt
  unverändert.
- **Fotos für die KI** werden vor dem Controller verkleinert und neu kodiert (ohne EXIF/GPS, wie `MealPhoto`). Der
  Controller bekommt fertige JPEG-Daten.

## 2026-11-14 – Erfassen (Phase 3d-3)

- **Fotos:** `image_picker` mit `requestFullMetadata: false`, danach `MealPhoto` mit dem Paket `image` (rein Dart, im
  Isolate): Ausrichtung übernehmen, längste Seite 1280 px, JPEG-Qualität 70, EXIF/ICC/Text verworfen. So verlässt wie
  in Swift (`UIGraphicsImageRenderer` + `jpegData(0.7)`) kein Standort das Gerät; `image_picker` allein garantiert das
  auf iOS nicht.
- **Barcode:** `mobile_scanner` statt VisionKit, gleiche Formate (EAN-13, EAN-8, UPC-E) und Eingabe von Hand mit
  Prüfziffer. Ohne Kamera zeigt die Ansicht wie Swift „Kamera-Scan nicht verfügbar“.
- **Diktat-Hinweis:** Swift unterscheidet „läuft auf dem iPhone“ und „Apple wandelt um“. `speech_to_text` meldet das
  nicht (siehe Phase 2l); der Hinweis lautet neutral „Die Spracherkennung des Geräts wandelt die Sprache in Text um“.
- **Abfolge der Bildschirme:** Swift wartet 450 ms zwischen zwei Sheets. In Flutter liefert der Erfassen-Bildschirm
  ein Ergebnis (`CaptureResult`), danach öffnet die Ernährungsansicht den nächsten Bildschirm – ohne Wartezeit.

## 2026-11-14 – Ernährungsplan, Gewicht und Teilen (Phase 3d-4)

- **Diagramme:** `fl_chart` statt Swift Charts. Im Wochendiagramm kennt `fl_chart` keine Punkte über Balken; das
  Tagesziel steht deshalb als „◆ kcal“ unter dem jeweiligen Balken statt als Raute im Diagramm. Inhalt und
  Bedienungshilfe-Text („Raute = Ziel, orange = Trainingstag“) bleiben gleich.
- **Wochen-Check-in beim Öffnen des Gewichtsverlaufs:** Swift setzt `lastCheckInDay` in `onAppear`. In Flutter darf
  ein Provider nicht während des Aufbaus geändert werden; die App setzt den Tag nach dem ersten Bild
  (`addPostFrameCallback`). Für die Person gleich.
- **„Im Feed mit Freunden teilen“** im Teilen-Bildschirm folgt mit der Social-Phase (`ShareWithFriendsSheet`), der
  Link „Rezeptideen für die kommende Woche“ mit der Rezepte-Phase. Teilen per Code und Link funktioniert bereits.

## 2026-11-14 – Gym-Logik der App (Phase 3e-1)

- **`GymViewModelTests.finishSavesDoneSetsAndWritesHealth`** erwartet nach `setWeight(50, set: 0)` noch
  `[50, 50, 50]`. `WorkoutEdits.setWeight` ändert in Swift aber seit dem Gerätetest bewusst nur den einen Satz
  (Kommentar dort: „das frühere Mitziehen der Folgesätze überschrieb gewollte Werte“). Die App-Tests laufen nur im
  Simulator und wurden nicht nachgezogen. Der Dart-Test erwartet das heutige Verhalten `[50, 0, 0]`.
- **Laufende Einheit** liegt wie in Swift unter `gym.activeSession` (jetzt im Einstellungsspeicher statt in den
  UserDefaults); `AppBackup` und Umzug bleiben kompatibel.
- **Pause vorbei:** `LocalNotification` kennt jetzt Sekunden, „exakt“ (Android `exactAllowWhileIdle`), „ohne Ton“ und
  einen eigenen Ton. iOS spielt eigene Töne nur aus dem Bundle oder `Library/Sounds`; die App kopiert die drei Töne
  beim Start dorthin. Android nutzt den Ton des Mitteilungskanals (eigene Töne je Mitteilung erlaubt Android 8+
  nicht); in der geöffneten App spielt `audioplayers` den gewählten Ton mit `ambient` wie in Swift.
- **Mitteilungszentrale:** `notificationCenterProvider` war bisher nirgends gesetzt – Erinnerungen wären auf dem Gerät
  nie geplant worden. `main` richtet jetzt `DeviceNotificationCenter` ein und reicht Antworten an `ReminderService`
  weiter (auch solche, die vor dem Start eintreffen). Dazu setzt der iOS-`AppDelegate` den Delegate der
  Mitteilungszentrale, wie es `flutter_local_notifications` verlangt.

## 2026-11-14 – Laufende Einheit (Phase 3e-3)

- **„Pause starten“:** Ist die automatische Pause aus, merkt sich `GymViewModel` die Pause (`pendingRest`) und die
  Einstellung verspricht „erscheint nach dem Satz ‚Pause starten‘“ – die Swift-Ansicht zeigt den Knopf aber nirgends.
  Flutter zeigt ihn an der Stelle des Pausenfelds.
- **Zeiten:** Swift nutzt `Text(timerInterval:)` und `TimelineView`; Flutter aktualisiert Uhr der Einheit,
  Pausen-Countdown und Stoppuhr mit einem Sekundentakt. Vorwarnung 10 s vor Pausenende und Signal am Ende wie in Swift
  (`HapticFeedback` statt `sensoryFeedback`).
- **Gym-Eintrag im Reiter Training:** Status („Einheit starten“ bzw. „läuft“) steht als Untertitel statt rechts neben
  dem Titel – auf iPhone-Breite passte beides nicht in eine Zeile (im Widget-Test gefunden).
- **Menü „Anleitung und Verlauf“** folgt mit der Übungsbibliothek (3e-4), **„Mit Freunden teilen“** im Abschluss mit
  der Social-Phase.

## 2026-11-14 – Gym-Bibliothek (Phase 3e-4)

- **Verlaufsdiagramme:** Swift Charts scrollt die X-Achse nativ; mit `fl_chart` verschiebt ein Wisch- bzw.
  Zwei-Finger-Gestenerkenner den sichtbaren Ausschnitt (Zeitraum, Zoom um die Mitte und Y-Achse aus `ChartZoom` wie in
  Swift). Das Balkendiagramm der bewegten Last zeigt die Einheiten des Ausschnitts gleichmäßig verteilt statt auf
  einer Zeitachse.
- **Auswahl im KI-Plan:** „Ziel“ und „Erfahrung“ stehen als Auswahl über die volle Breite statt rechts neben dem
  Titel – auf iPhone-Breite passten die langen Bezeichnungen nicht (im Widget-Test gefunden).
- **Trainingspläne sortieren:** Swift nutzt „Bearbeiten“ mit Ziehen; Flutter zeigt einen Griff je Plan. Duplizieren
  per langem Druck statt Kontextmenü.
- **GymBook-Import** und **Gym-Einstellungen** (Link in der Bibliothek) gehören in Swift zu Einstellungen ›
  Disziplinen und folgen dort.

## 2026-11-14 – Reiter „Heute“ (Phase 3f-2)

- **Bereiche aus anderen Phasen** (Morning Report, verpasste Einheiten, „Nach dem Training“, Motivation und
  Rangliste, KI-Empfehlungen, Chat, „An die Uhr senden“, Mobility, „Anpassen“ eines Vorschlags und „Nächste Woche
  planen“) hängen in Swift an Ansichten der Bereiche Health, Plan, Training, Motivation und AI. Sie kommen mit diesen
  Bereichen dazu; „Heute“ zeigt bis dahin alles Übrige.
- **„Heute erledigt“** zeigt die Einträge des gemeinsamen Verlaufs noch ohne Link zur Aktivität; der Link folgt mit
  dem Reiter „Aktivitäten“.
- **Verschieben/Auslassen** als Chips, die bei wenig Platz umbrechen (statt `ViewThatFits`).

## 2026-11-14 – Reiter Training (Phase 3g-2)

- **Tägliche Erinnerung:** `LocalNotification.repeatsDaily` plant wie `UNCalendarNotificationTrigger` mit
  `repeats: true` jeden Tag zur selben Uhrzeit (`matchDateTimeComponents: time`). Liegt die Uhrzeit heute schon hinter
  uns, beginnt die Wiederholung morgen. Genutzt von der Schlafenszeit-Erinnerung des Schlaf-Coachs.
- **Diagramme:** `fl_chart`; Balken auf einer Zeitachse (Form, Fitness & Form) als senkrechte Linien je Tag, weil
  `BarChart` keine Datumsachse kennt. Gestapelte Minuten je Sportart mit `rodStackItems`, Legende darunter.
- **Übersicht:** Wert und Erklärung stehen rechts, kürzen aber bei Platzmangel (statt umzubrechen wie bei sehr großer
  Schrift in Swift).


## 2026-11-14 – Disziplinseiten (Phase 3g-3)

- Swift-Charts der Testverläufe, Kilometer, VO2max und Kopplung sind `fl_chart`-Diagramme; bei Paces (kleiner ist
  besser) wird die Achse wie in Swift umgedreht, indem die Werte negiert und die Beschriftung zurückgerechnet wird.
- Die Testeingaben (`TestEntrySection`) sind Textfelder mit Ziffern, Doppelpunkt und Komma; die Auswertung liegt je
  Seite in einem `evaluate`-Rückruf, gespeichert wird wie in Swift über `settings.record(TestKind, Wert)`.
  `TimeText` kommt aus `coach_core`.
- Die Übernahme im Pace-Check gibt eine Haptik (`HapticFeedback.mediumImpact`) statt `sensoryFeedback(.success)`.
- `DisclosureGroup` wird zu `ExpansionTile`; der Evidenz-Hinweis steht in der Sektion statt im Footer.

## 2026-11-14 – Plan (Phase 3g-4)

- Sheets der Swift-App (`NextWeekPlanSheet`, `ManualActivitySheet`, `ScheduleEditorSheet`, `SendToWatchSheet`) sind
  Vollbild-Dialoge (`fullscreenDialog`); die Saisonübersicht ist ein ziehbares Bottom-Sheet.
- `swipeActions` in „Meine Woche“ werden zu `Dismissible`: nach links auslassen, nach rechts auf den besten Tag
  verschieben; die Zeile bleibt stehen (`confirmDismiss` gibt `false` zurück), die Änderung kommt über die Einstellungen.
  Dieselben Aktionen bietet das Menü je Tag.
- Außerplanmäßige und nachgetragene Einheiten zeigen vorerst eine einfache Zeile ohne Detailseite; die Aktivitätsdetails
  folgen mit Phase 3g-5. Nachgetragene lassen sich über ein Löschen-Symbol statt Wischen entfernen.
- `FitnessGoal.symbol` fehlte im Kern-Port und ist ergänzt (wie `UserProfile.swift`).
- Aus Mitteilungen geöffnete Sheets (`AdjustDaySheet`, „Nächste Woche planen“) zeigt `RootShell`, sobald der
  `ReminderService` sie meldet – auch wenn die Antwort vor dem ersten Bild kam.

## 2026-11-14 – Aktivitäten (Phase 3g-5)

- Die Karte der Strecke nutzt `flutter_map` mit OpenStreetMap-Kacheln (eigener User-Agent, Quellenangabe
  „© OpenStreetMap-Mitwirkende“), Start- und Zielmarke wie bei MapKit. Gezeigt wird nur die aufgezeichnete Strecke.
- Diagramme des Verlaufs: `fl_chart` statt Swift Charts; Pace mit umgedrehter Achse über negierte Werte. Die Runden
  sind eine horizontal scrollbare `DataTable` statt `Grid`.
- Suche im Verlauf über ein Suchfeld in der App-Leiste (statt `.searchable`); Filter als Menü wie in Swift.
- Beiträge der Freunde stehen in der Zeitleiste vorerst als einfache Karte (Name, Zeit, Überschrift, Kennzahlen,
  Anzahl der Reaktionen und Kommentare). Reagieren, Kommentieren, Mahlzeit übernehmen, Beitrag löschen, Freunde und
  automatisches Teilen kommen mit der Social-Phase.
- Der leere Platzhalter (`PlaceholderView`) ist entfernt; alle vier Reiter haben Inhalt.

## 2026-11-14 – Gesundheitsbereich (Phase 3h-1)

- Widget-Raster: zwei Spalten über `Wrap` mit halber Breite statt `LazyVGrid`; Mini-Verläufe und Verlauf je Wert mit
  `fl_chart`, der eigene Bereich als graues Band (`HorizontalRangeAnnotation`).
- Editor: `ReorderableListView` mit Ziehgriff; Entfernen über ein Papierkorb-Symbol statt Wischen (wie in den anderen
  Listen der Flutter-App).
- Body Battery öffnet bis Phase 3h-2 den Verlauf des Werts; die eigene Seite, Mobility und der Wecker folgen dort.
- Der Morning Report im Gesundheitsbereich rechnet „heute geplant“ wie in Swift über den `TodayController`, wenn er
  nicht aus „Heute“ geöffnet wird.

## 2026-11-14 – Body Battery, Mobility, Wecker (Phase 3h-2)

- `Gauge(.accessoryCircular)` wird zu einem Ring (`CircularProgressIndicator`) mit Farbstufen nach
  `BodyBatteryAnalysis.band`. Im 30-Tage-Diagramm ist der Aufwachwert eine kurze dunkle Marke im Tagesbalken
  (`fl_chart` kennt keine Punkte im Balkendiagramm).
- Wecker: `WakeAlarmService` (Dart) entspricht der Swift-Klasse (höchstens ein Wecker, gleicher Schlüssel
  `coach.wakeAlarm`, gleiches JSON, Abgleich mit dem Schlaf-Coach). Der Systemwecker läuft über den `MethodChannel`
  `aironludi/alarm` (`state`, `alarms`, `schedule`, `cancel`). Die native Gegenseite (AlarmKit ab iOS 26,
  `AlarmManager.setAlarmClock` auf Android) kommt mit den nativen Teilen (Widgets, Live-Aktivitäten); bis dahin meldet
  die Brücke „nicht unterstützt“ und die App zeigt wie in Swift unter iOS 18–25 den Hinweis auf die Uhr-App.
- Der Selbsttest „Stufen“ nutzt `RadioGroup` statt eines Inline-Pickers.

## 2026-11-14 – KI-Empfehlungen und Chat (Phase 3i-1)

- `swipeActions` und `contextMenu` der Empfehlungen werden zu `Dismissible` (rechts umgesetzt, links verwerfen; die
  Zeile bleibt, der Status kommt aus den Einstellungen) und einem Aktionsmenü per langem Druck.
- Der Chat-Verlauf bleibt wie in Swift nur im Speicher, solange der Chat offen ist. Lange auf eine Nachricht drücken
  kopiert sie (statt `textSelection`; der Text ist zusätzlich markierbar).
- `RecipeViewModel.gaps` ist als `nutritionGaps` in `lib/features/ai/coach_facts.dart` portiert, weil Regeln und
  Analyse es vor der Rezepte-Phase brauchen.
- Die Links „Rezeptideen“, „Prompt-Bibliothek“, „Export“ und „Import“ in „Weitere KI-Funktionen“ kommen mit den
  jeweiligen Phasen dazu.

## 2026-11-14 – Externe KI: Prompts, Export, Import (Phase 3i-2)

- Dateien für Export und Prompts entstehen in einem eigenen temporären Ordner (`ki-export`, alte werden ersetzt) und
  werden über `share_plus` geteilt (statt `ShareLink`); Kopieren über die Zwischenablage.
- Wasser-Einträge (Glas-Knopf) gehen wie in der Mahlzeitenliste nicht in den Export.
- Pickers mit Menü werden zu `DropdownButtonFormField`, Stepper zu Plus/Minus-Knöpfen.

## 2026-11-14 – Konto (Phase 3j-1)

- Links von außen, die keine Reiter-Route sind, landen in `incomingLinkProvider`; `RootShell` übernimmt
  Konto-Einladungen. Liga-Einladungen, geteilte Mahlzeiten und Kochpartner-Links folgen mit ihren Bereichen.
- Bestätigungsdialog und Lösch-Abfrage mit Passwortfeld sind `AlertDialog`s; der Wiederherstellungscode lässt sich
  wie in Swift erst nach Bestätigung schließen (`PopScope`).
- Der Schalter „Trainings automatisch teilen“ in „Konto verwalten“ kommt mit dem Port von `SocialAutoShare` (3j-2).

## 2026-11-14 – Freunde und Teilen (Phase 3j-2)

- `SocialAutoShare` ist ein Dienst (`socialAutoShareProvider`) statt eines statischen Typs; Schlüssel wie in Swift
  (`social.autoShare`, `social.autoShareSince` in Sekunden seit 1970).
- Freunde öffnen sich über das Personen-Symbol links in der App-Leiste des Reiters Aktivitäten (wie die Schaltfläche
  oben links in Swift), mit Zahl der Anfragen. Die Seite „Wettkampf“ folgt mit dem Spiel (3j-3).
- Wischaktionen (Freund entfernen, Kommentar löschen) werden zu Symbolen bzw. zur Profilseite; Bestätigungen sind
  `AlertDialog`s.

## 2026-11-14 – Spiel (Phase 3j-3)

- `MotivationSections` zeigt vorerst nur den Fortschritt (Serie, Stufe, Abzeichen); Begleiter und Liga folgen in 3j-4.
- Der Stand wird wie in Swift (`.task(id:)`) nur gemeldet, wenn sich Punkte, Serie, Mahlzeit- oder Trainingstage
  ändern (Schlüssel im Zustand des Abschnitts, Meldung nach dem Aufbau des Bilds).
- Abzeichen als `Wrap` statt `LazyVGrid`; Wischen zum Verlassen einer Challenge wird zu einem Symbol mit Bestätigung.

## 2026-11-14 – Begleiter und Liga (Phase 3j-4)

- Daisy wird mit `CustomPainter` gezeichnet (statt `Canvas` in `TimelineView`); ein `Ticker` liefert die Zeit für
  `DaisyGeometry.pose`, bei `MediaQuery.disableAnimations` steht sie still. Farben und Pfade sind 1:1 übernommen.
- Das Begleiter-Foto liegt wie in Swift als `companion.jpg` im App-Support-Ordner (höchstens 600 px, JPEG 0,8) und
  wird über `image_picker` aus der Mediathek gewählt.
- Liga-Einladungen (`coach://join`) öffnet `RootShell` über `incomingLinkProvider`, wie die Konto-Einladungen.

## 2026-11-14 – Rezeptideen (Phase 3k-1)

- Der Plan liegt wie in Swift als `recipes.json` im App-Support-Ordner (gleiches JSON); Zeitraum und abgehakte
  Einträge unter den bisherigen Schlüsseln (`recipes.periodStart`, `recipes.periodDays`, `recipes.checked`).
- Die Teilabfragen laufen mit `Future.wait` nebeneinander (statt `Task`s), der zweite Versuch bei 502/503/504 nach zwei
  Sekunden wie in Swift.
- „Als Mahlzeit eintragen …“ öffnet den Mahlzeiten-Entwurf mit einem eigenen `NutritionController` (wie das eigene
  `NutritionViewModel` in Swift); nichts landet ungefragt im Tagebuch.
- Wischen zu „Habe ich da“ wird zu einem Kisten-Symbol in der Zeile.

## 2026-11-14 – Gemeinsam kochen (Phase 3k-2)

- Die Kochpläne stehen in einem eigenen `CookPlanController` statt im Rezept-Controller; die eigenen Tagesziele kommen
  weiterhin aus den Rezeptideen (`RecipeController.targets`), die Datei bleibt `cook-plans.json` im gleichen JSON.
- Verbindungen und eigene Freigabe liegen unter den bisherigen Schlüsseln `coach.cookPartners` und `coach.cookRelease`.
- Picker werden zu Auswahlfeldern, der Stepper der Anzahl und der Zutatenmengen (5-g-Schritte, 5–1.000 g) zu
  Minus/Plus-Knöpfen, „Lösen“ per Wischen zu einem Knopf in der Zeile.
- Links: `coach://cook/<code>` öffnet „Gemeinsam kochen“ mit abgerufener Freigabe, `coach://open/cookShare` die eigene
  Freigabe (wird vor den Reiter-Zielen geprüft wie in `RootView`), `coach://meal/<code>` die empfangene Mahlzeit.
- Der Mahlzeiten-Controller im Rezeptdetail wird erst beim Eintragen angelegt (in `dispose` ist `ref` nicht nutzbar).

## 2026-11-14 – Einstellungen nach Disziplin und Diagnose (Phase 3l-1)

- Picker werden zu Auswahlfeldern, Stepper zu Minus/Plus-Knöpfen (`StepperRow`, `HeartRateRow`); „automatisch“ steht
  beim Pulswert als Untertitel, der Knopf heißt „eigenen Wert setzen“ (passt so in die Zeile).
- Der Ton am Pausenende wird beim Wählen probeweise abgespielt; dafür gibt es `restSoundPlayerProvider`, den auch die
  Gym-Einheit nutzt.
- Die Diagnose-Seite heißt wie in Swift „HealthKit“ und nutzt `HealthProbe` (Apple Health bzw. Health Connect); die
  Version kommt aus `package_info_plus`. Der Status steht unter der Beschriftung statt rechts daneben.
- GymBook-Import über `file_picker` (beliebige Datei, wie `.item` in Swift).

## 2026-11-14 – Widget-Stand und App Group (Phase 3m-1)

- Die App Group ermittelt Dart wie Swift aus `embedded.mobileprovision` (`AppGroupProfile`); der `AppDelegate` liefert
  nur das Profil und den Ordner je Kandidat. Dateien schreibt Dart selbst (temporär schreiben, dann umbenennen statt
  `.atomic`); nur das Entfernen aus der Warteschlange läuft nativ unter `NSFileCoordinator`, weil das Widget
  gleichzeitig schreiben kann.
- Die Brücke steht im `AppDelegate.swift`, damit das Xcode-Projekt nicht für eine neue Datei geändert werden muss.
- Android schreibt in den Datenordner der App; die Glance-Widgets (3m-3) lesen ihn im selben Prozess.
- Statt `scenePhase` lauscht `RootShell` mit `AppLifecycleListener`: beim Zurückkehren Wasser übernehmen, schreiben,
  abrufen, Erinnerungen planen, erneut schreiben; beim Verlassen schreiben. Die Live-Aktivität „Mahlzeiten heute“
  folgt mit der Widget-Erweiterung (3m-2).

## 2026-11-14 – Widget-Erweiterung (Phase 3m-2)

- Die Widgets bleiben SwiftUI (Migrationsplan 4.2). Statt das ganze Swift-Paket CoachCore (≈ 25 700 Zeilen) ins Repo zu
  holen, enthält `ios/CoachWidgets/WidgetCore.swift` nur die Typen, die die Widgets lesen (`WidgetSnapshot`,
  `WidgetActionQueue`, `AppGroupProfile`, `MealHeadline`, `CalendarDay`, `MealCategory`, `MealSplit`,
  `RecoveryLevel`, `GermanFormat`, `AppRoute`, Einordnung des Morning Reports). Die Rechnung macht die Flutter-App.
- `WidgetStore.swift` liegt nur in der Erweiterung (die App schreibt über `aironludi/widgets` aus Dart);
  `Shared/` mit den Live-Aktivitäts-Attributen und Intents gehört zu App und Erweiterung, weil `LiveActivityIntent`
  im Prozess der App läuft.
- Ohne Mac fügt `ios/scripts/add_widget_extension.rb` das Ziel mit dem Gem `xcodeproj` ein (einmalig, Ergebnis
  eingecheckt). Die Erweiterung erbt nur `Flutter/Generated.xcconfig` (Versionsnummern), nicht die Pod-Einstellungen.

## 2026-11-14 – Live-Aktivitäten aus der App (Phase 3m-3)

- Statt des Pakets `live_activities` eine eigene kleine Brücke im `AppDelegate` (`ActivityBridge`): Die Attribute und
  Intents aus `ios/Shared/` bleiben unverändert, nur die Inhalte rechnet Dart (`WorkoutLiveState`, `MealsLiveState`)
  und schickt sie als Wörterbuch. So passen App und Erweiterung ohne doppelte Typen zusammen.
- Die Knöpfe laufen weiter als `LiveActivityIntent` im Prozess der App; `WorkoutActions.handler` meldet sie als
  `workoutAction` an Dart, `GymController.perform` führt sie aus, der neue Stand geht über `RootShell` zurück.
- Der Schalter „Mahlzeiten auf dem Sperrbildschirm“ schreibt sofort neu (wie `onChange` in Swift).

## 2026-11-14 – Laufende Mitteilung der Gym-Einheit unter Android (Phase 3m-4)

- Kein Foreground-Service: Die Einheit läuft in der App, die Mitteilung zeigt nur ihren Stand (Kanal „Laufende
  Einheit“, leise, dauerhaft). Gebaut mit `android.app.Notification` (minSdk 26), ohne zusätzliche Abhängigkeit.
- Android zeigt höchstens drei Knöpfe: „Satz erledigt“ und in der Pause „Pause überspringen“, sonst Gewicht − und +.
  Wiederholungen ± bleiben der App vorbehalten.
- Die Knöpfe gehen per `BroadcastReceiver` an Dart; läuft keine Flutter-Engine, merkt sich die App sie
  (`SharedPreferences`) und führt sie beim nächsten Öffnen aus.
- „Mahlzeiten heute“ gibt es unter Android nicht als laufende Mitteilung; die Mahlzeiten zeigt das Widget (3m-5).

## 2026-11-14 – Android-Widgets (Phase 3m-5)

- RemoteViews statt Jetpack Glance: kein Compose-Compiler und keine neue Abhängigkeit im Gradle-Build, dieselben
  fünf Widgets mit Texten statt Ringen und Balken. Glance bleibt eine spätere Verbesserung.
- Die Widgets lesen dieselbe Datei wie unter iOS (`widget-snapshot.json`, hier im Datenordner der App) und rechnen nur
  den Tageswechsel ein (wie `WidgetSnapshot.display(on:)`). Wasser merken sie in `widget-actions.json` vor
  (Zeitpunkt in Sekunden seit 2001, ID als UUID), die App übernimmt es beim Öffnen wie unter iOS.
- Konfiguration je Widget (iOS: Widget bearbeiten) entfällt unter Android vorerst; die Widgets zeigen die Standard-
  Auswahl der iOS-Widgets.

