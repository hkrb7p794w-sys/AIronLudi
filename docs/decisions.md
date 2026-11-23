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

## 2026-11-14 – Wecker-Brücke (Phase 3m-6)

- iOS: AlarmKit wie in Swift (`IronLudiAlarm`), im `AppDelegate` hinter `#if canImport(AlarmKit)` und
  `#available(iOS 26.0, *)`. Die Wecker-ID kommt aus Dart (`coach.wakeAlarm`, UUID in Großbuchstaben wie
  `uuidString`).
- Android: `AlarmManager.setAlarmClock` (erscheint als nächster Wecker, klingelt im Ruhemodus) statt eines Wecker-Pakets.
  Beim Klingeln eine Vollbild-Mitteilung im Kanal „Wecker“ (Weckton, `FLAG_INSISTENT` bis „Aus“). Wiederholungen
  stellt der Empfänger auf den nächsten passenden Tag, nach Neustart und Update ebenso. Ohne Erlaubnis für genaue
  Wecker (Android 12+) meldet der Kanal `denied`.

## 2026-11-14 – Feinschliff Teil 1 (Phase 3n-1)

- Schnellaktionen über `quick_actions` ohne eigene Symbole (das Paket erwartet Bild-Assets statt SF Symbols); Titel
  und Untertitel wie in Swift. Antippen läuft über denselben Weg wie `coach://open/<route>` (`openRoute`).
- „Bildschirm anlassen“ über `wakelock_plus`, an- und abgeschaltet aus `RootShell` wie `isIdleTimerDisabled` in
  `RootView`.
- Beim Verlassen der App (`AppLifecycleListener.onHide`) wie `.background` in `CoachApp`: Ordner-Sicherung, Widgets,
  Schnellaktionen, dazu den Hintergrundabruf planen.
- Hintergrundabruf über `workmanager` (iOS: `BGAppRefreshTask` mit der Kennung der Swift-App; Android: WorkManager,
  periodisch alle 2 Stunden, nur mit Netz). Der Durchlauf startet den Container wie `main` (`createAppContainer`, ohne
  Mitteilungszentrale), ruft ab, wenn fällig, und versorgt die Widgets. Unter Android zeichnen sich die Widgets nach
  einem Abruf im Hintergrund erst mit dem nächsten Aktualisierungsintervall (30 Minuten) bzw. beim Öffnen neu, weil
  die Kanäle der `MainActivity` in der Hintergrund-Engine fehlen.

## 2026-11-14 – WHOOP (offizielle API v2)

- **Wie Garmin:** Die App ruft die Daten selbst bei `api.prod.whoop.com/developer/v2` ab; nur die Anmeldung (OAuth
  2.0, Authorization Code) läuft über den Worker, weil WHOOP das Client-Secret verlangt und kein PKCE anbietet
  (`hkrb7p794w-sys/Coach-App`, `worker/src/whoop.ts`, Einrichtung in `docs/whoop.md`). Rücksprung über
  `https://<worker>/w/whoop` → `coach://whoop?code&state`; die App prüft den `state`.
- **Tokens** (`WhoopToken`) nur im sicheren Speicher (`SecretKey.whoopToken`). WHOOP rotiert das Refresh-Token bei
  jedem Refresh: Die App erneuert genau einmal gleichzeitig (gemeinsamer Future) und speichert das neue sofort. Ein
  abgelehntes Refresh-Token oder ein zweites 401 trennt lokal mit „Bitte neu verbinden“.
- **Abbildung** (`WhoopImport` in coach_core, Felder laut OpenAPI): Recovery → Ruhepuls, HRV (RMSSD wie Garmin),
  Trainingsbereitschaft (Recovery-Score, Stufe ab 67/34 %), SpO2; Hauptschlaf (ohne Nickerchen, längster der Nacht)
  → Dauer, Phasen, Wachzeit, Schlaf-Score (Schlafleistung), Atemfrequenz, Zeiten; Zyklus → Gesamtkalorien
  (kJ ÷ 4,184), Schritte, Max-HF. Zugeordnet zum Aufwachtag (Ende plus sechs Stunden wie beim Health-Import).
  Trainings → Aktivitäten mit Herkunft WHOOP (stabile negative ID aus der UUID, Sportart auf Garmin-Typen, Zonen 1–5,
  Strain als „WHOOP-Strain x,y“). Day-Strain hat kein Gegenstück in den Tageswerten und entfällt.
- **Zusammenführen** wie bei Apple Health über das Herkunftsverzeichnis (`SourceStore.ingestDays`,
  `recordActivities`): Welche Quelle je Datenart zählt, regeln die Quellen-Einstellungen (WHOOP-Stärken: Schlaf,
  HRV, Ruhepuls, Recovery); doppelte Trainings mit Garmin oder Health entfernt `deduplicateActivities`.
- **Abruf:** nach Garmin, vor Health; erster Abruf 90 Tage, danach ab dem letzten mit zwei Tagen Überlappung (WHOOP
  bewertet nachträglich). Seiten zu 25 Einträgen, höchstens so viele Seiten wie für den Zeitraum nötig (Limit 100
  Anfragen je Minute). Auch im Hintergrundabruf.
- **Trennen** widerruft bei WHOOP (`DELETE /v2/user/access`) und löscht Tokens und Profil; übernommene Werte bleiben.
- Körperwerte (Größe, Gewicht, Max-HF) werden angezeigt, aber nicht in Profil oder Gewichtsverlauf übernommen (keine
  Datierung, die eigenen Angaben haben Vorrang).


## 2026-11-15 – Sperrbildschirm, Teilen, Kühlschrank-Rezepte (Erweiterungen ohne Swift-Gegenstück)

Neue Funktionen auf Wunsch des Nutzers; die Swift-App hat sie nicht. Datenformate bleiben kompatibel (neue Felder sind
optional, alte Stände lesen sich wie bisher). Tests: `packages/coach_core/test/lock_screen_share_pantry_test.dart`,
`test/features/pantry_controller_test.dart`, Ergänzungen in `live_activities_test.dart` und
`reminder_service_test.dart`.

- **Vorrang der Gym-Einheit** (`LockScreenActivities`): Sobald die Live-Aktivität der Einheit läuft (eingeschaltet,
  erster Satz gemacht), endet „Mahlzeiten heute“; nach der Einheit startet sie mit dem nächsten Stand wieder. Dart
  entscheidet (`WidgetPublisher.showsMealsActivity`), `RootShell` stößt beim Wechsel neu an – erst Mahlzeiten beenden,
  dann die Einheit starten. Als Sicherheitsnetz beendet auch der `AppDelegate` Mahlzeiten-Aktivitäten, solange eine
  Einheit läuft, und Android nimmt die Mahlzeiten-Mitteilung beim Start der Einheits-Mitteilung weg.
- **Doppelte „Mahlzeiten heute“**: Ursache war das asynchrone `end` – bis es durch war, stand die alte Aktivität noch in
  `Activity.activities`; der nächste Aufruf (beim Öffnen kommen zwei `publish` kurz hintereinander) hielt sie für die
  laufende, fand sie zu alt und startete eine weitere. Jetzt merkt sich die Brücke angestoßene Enden (`ending`), zählt
  nur aktive/veraltete, behält die neueste und beendet alle übrigen. Gleiches für die Einheit.
- **Einstellungen › Sperrbildschirm**: Schalter je Bereich (Gym = `GymSettings.liveActivity`, Ernährung =
  `mealsLiveActivity`), Ansicht der Gym-Karte (`GymSettings.liveActivityLayout`: `timer`, `exercise`, `combined`;
  Standard `combined` wie bisher) und „Erinnerung an Mahlzeiten auf dem Sperrbildschirm statt als Mitteilung“
  (`mealsLiveReminders`). Die bisherigen Schalter unter Gym und Ernährung verweisen dorthin. Die Ansicht geht als
  `layout` an die Live-Aktivität (fehlt = beides) und an die Android-Mitteilung.
- **Erinnerung auf dem Sperrbildschirm** (`MealLiveReminder`): nächste offene Mahlzeit nach den eingeschalteten
  Essenszeiten, ohne eingeschaltete die gewohnten Hauptmahlzeiten (8:00, 12:30, 19:00); eine offene Mahlzeit bleibt
  drei Stunden „fällig“, dann rückt die nächste nach. Live-Aktivitäten können sich nicht selbst zeitgesteuert ändern:
  Der Stand gilt deshalb ab der Essenszeit als veraltet (`staleDate`), iOS zeichnet die Karte neu und sie zeigt „Zeit
  fürs Mittagessen – jetzt eintragen?“. „Neuer Tag“ gilt erst ab `dayEndsAt` (Mitternacht), nicht mehr bei jedem
  Veralten. Mit dem Schalter plant `ReminderService` keine Mitteilungen für Mahlzeiten mehr. Grenze: Öffnet man die
  App länger nicht, beendet iOS die Karte nach etwa acht Stunden – dann gibt es auch keine Erinnerung (im Fußtext
  genannt). Unter Android aktualisiert sich die Mitteilung nur beim Öffnen bzw. mit dem nächsten Stand der App.
- **„Mahlzeiten heute“ unter Android**: bisher nicht vorhanden (Abschnitt 4.2), jetzt als dauerhafte, lautlose
  Mitteilung (Kanal `meals`, `IMPORTANCE_LOW`) mit Kopfzeile, kcal je Mahlzeit und einem Knopf „… eintragen“.
- **Einheit teilen** (`GymShareText`, `RoutineLink`): über das Teilen-Menü des Systems als Text, ohne Körperwerte und
  RIR. Abgeschlossene Einheit (Abschluss-Bildschirm „Teilen …“, Verlauf) und Trainingsplan (Liste der Pläne). Dazu ein
  Link `coach://routine/<base64url(JSON)>` mit kurzem JSON (`n`, `i` als Listen), ohne Server; `RootShell` zeigt ihn
  als „Geteilter Trainingsplan“ zum Übernehmen (neue Kennungen, Werte begrenzt, höchstens 20 Übungen). Aus einer
  Einheit wird die Routine aus den erledigten Sätzen gebildet (Sätze, Wiederholungsbereich, schwerster Satz).
- **Rezepte aus dem Kühlschrank-Foto** (`PantryRecipes`, Worker-Aufgabe `pantry_recipes`, Art „planning“): Foto plus
  Ernährungsweise, Allergene, Abneigungen, Vorrat aus der Einkaufsliste; bei „Neu vorschlagen“ die korrigierte Liste
  und die Antworten (`erkannt`, `bestaetigt`, `nicht_da`). Die KI nennt je Gericht unter `fehlt` höchstens zwei kleine
  Standardzutaten; die App fragt „Ist noch Butter da?“ (häufigste zuerst, höchstens vier Fragen). Antworten wirken
  sofort und ohne neue Anfrage (bereit / wartet / geht nicht). Regeln wie bei allen Rezepten (Ernährungsweise,
  Allergene, unplausible Nährwerte); mehr als zwei fehlende Zutaten verwirft die App, Zutaten aus Vorrat, Foto oder
  bestätigten Antworten gelten nicht als fehlend. Die Aufgabe muss im Worker (Coach-App) ergänzt werden; Vertrag in
  `docs/worker-pantry-recipes.md`. Bis dahin meldet die App den Fehler des Workers.

## 2026-11-15 – Mehrere Benutzer auf einem Gerät, strikt getrennt

Auf Wunsch des Nutzers; die Swift-App kennt nur einen Benutzer. Tests: `packages/coach_core/test/user_directory_test.dart`,
`test/app/user_session_test.dart`.

- **Trennung über den Speicherort statt über eine `username`-Spalte.** Jeder Benutzer hat eine eigene Datenbankdatei
  (`coach-<id>.sqlite`), eigene Schlüssel im Schlüsselbund (`u.<id>.<name>`) und eigene Ordner (`users/<id>/` in
  App-Support und Cache: Rezepte, Kochplan, Begleiter-Foto, Auswertungen, FIT-Dateien, wartende Fotos). Eine Spalte
  in allen Tabellen hätte bei jeder einzelnen Abfrage einen Filter verlangt – eine vergessene Bedingung, und Daten
  wären übergreifend sichtbar. Mit getrennten Dateien kann keine Abfrage die Daten eines anderen erreichen; die
  Tabellen, das Sicherungsformat (`AppBackup`) und alle Repositories bleiben unverändert. Skaliert ohne Kosten: Offen
  ist immer nur der Speicher des aktiven Benutzers (höchstens 20 Benutzer je Gerät).
- **Benutzer ↔ Speicher über eine feste Kennung (UUID)**, nicht über den Namen. Der Benutzername ist eindeutig auf dem
  Gerät, folgt den Regeln der Konten (`AccountRules`, passt also zu einem Konto am Worker) und ändert sich nie; der
  Anzeigename schon. Verzeichnis in `users.json` (`UserDirectory`) – nur Kennung, Benutzer- und Anzeigename.
- **Bestehende Installationen:** Ohne `users.json` gehört der vorhandene Speicher dem ursprünglichen Benutzer
  (`legacyID`, Name „ich“) an den bisherigen Stellen (Datenbank `coach`, Schlüssel ohne Präfix, Ordner direkt im
  App-Support). Nichts wird verschoben, nichts geht verloren. Dieser Benutzer lässt sich nicht löschen (sein Speicher
  liegt zwischen den Verzeichnissen der anderen und ließe sich nur unsicher entfernen); umbenennen geht.
- **Ein Provider-Container je Benutzer** (`createAppContainer(user:)`, `UserSession`): Alle Controller, Zwischenspeicher
  und die im Arbeitsspeicher gehaltenen Geheimnisse hängen am Container. Wechsel: aufräumen (Wasser aus dem Widget
  noch dem bisherigen Benutzer gutschreiben, Live-Aktivitäten beenden, alle geplanten Mitteilungen entfernen,
  Widget-Stand löschen), Einstellungen schließen (späte Schreibvorgänge werden ignoriert), Container verwerfen,
  Datenbank schließen, Bild-Zwischenspeicher leeren; dann neuer Container und die Oberfläche mit neuem Schlüssel
  (`UserScope`) – jeder Bildschirm entsteht neu. Spät eintreffende Antworten (KI, Garmin, WHOOP) des alten Containers
  schreiben in eine geschlossene Datenbank und landen nirgends. Mitteilungs-Antworten gehen immer an den aktiven
  Container. Hintergrundabruf und Widgets arbeiten mit dem aktiven Benutzer.
- **Kein Benutzername an die KI.** Die Anfrage war, KI-Aufrufen den Benutzernamen mitzugeben, damit Ergebnisse in der
  richtigen Historie landen. Das ist bereits durch den Aufbau gesichert: Jeder Container hat sein eigenes App-Token,
  seine eigene Konto-Sitzung und schreibt Ergebnisse (Rezepte, Empfehlungen, Verlauf) nur in den eigenen Speicher.
  Den Namen zusätzlich an Worker und KI-Anbieter zu schicken, brächte keine Trennung, widerspräche aber dem
  Datenschutzmodus „reduziert“ (CLAUDE.md) – deshalb nicht.
- **Ordner-Sicherung:** Weitere Benutzer sichern als `IronLudi-Sicherung-<benutzername>.json`, damit zwei Benutzer im
  selben Ordner sich nicht überschreiben; der ursprüngliche behält den Namen der Swift-App.
- **Bewusst gerätebezogen** (keine Nutzerdaten): Darstellung (hell/dunkel), mitgelieferte Tabellen (BLS, Saisonplan),
  das Verzeichnis selbst. Homescreen-Widgets und Live-Aktivitäten zeigen den aktiven Benutzer. Ein mit AlarmKit
  gestellter Wecker ist ein System-Wecker und bleibt beim Wechsel bestehen. Apple Health / Health Connect sind Daten
  des Geräts: Ein neuer Benutzer startet mit ausgeschaltetem Import und sollte ihn nur einschalten, wenn es seine
  Daten sind.

## 2026-11-16 – Worker zieht nach AIronLudi

- Auf Wunsch des Nutzers erfolgen **alle Änderungen nur noch in AIronLudi**. Der Worker wurde dafür unverändert aus
  Coach-App (`d29c61f`) übernommen (`worker/`, `.github/workflows/worker.yml`, `worker-smoke.yml`,
  `.github/scripts/worker-smoke.mjs`). Name (`coach-ai`), Bindungen (KV, D1, Workers AI) und Secrets bleiben, damit
  Adresse, Konten, Ranglisten, Gastzugänge und die SideStore-Quelle weiter gelten. Coach-App bleibt als Altbestand
  zum Lesen; ihr Worker-Workflow läuft nur bei Änderungen an ihrem `worker/` und darf deshalb nicht mehr angefasst
  werden. Eine Git-Anbindung bei Cloudflare („Workers Builds“) muss der Nutzer trennen (`docs/einrichtung.md`).
- Neue Aufgabe `pantry_recipes` (Kühlschrank-Foto, `docs/worker-pantry-recipes.md`): Bildmodelle zuerst (Gemini,
  GitHub Models, Mistral, Groq-Vision, Workers AI), Cerebras ausgelassen (keine Fotos). Der Worker prüft nur die Form
  (Liste, höchstens vier Gerichte); Ernährungsweise, Allergene und die Zahl fehlender Zutaten prüft die App.
- **WHOOP zentral:** eine Developer-App der Betreiberin bzw. des Betreibers im Worker; jede Person verbindet nur ihr
  eigenes WHOOP-Konto (eigene Tokens). So wie die Swift-App es vorsah.
- **Lücke festgehalten:** Die Flutter-App liest die Sicherung der Kotlin-App „IronLudi“ noch nicht. Bis das
  nachgerüstet ist, sollen Android-Nutzer:innen nicht umsteigen (`docs/anleitung.md`, B2).

## 2026-11-16 – Neuer Android-Signaturschlüssel

- Für AIronLudi wurde ein neuer Keystore angelegt (Alias `aironludi`, Commit `e1fce6a` aus einer anderen Sitzung);
  der Schlüssel der Kotlin-App (Alias `ironludi`) wird nicht verwendet. Folge: Android installiert die neue App
  nicht als Update über die Kotlin-App „IronLudi“ (gleiche Application-ID, andere Signatur). Umstieg also: in der
  alten App sichern, alte App deinstallieren, neue App installieren, Sicherung einspielen – Letzteres erst, wenn die
  Flutter-App die Kotlin-Sicherung lesen kann (offen, `docs/anleitung.md` B2). Ab jetzt darf der Schlüssel nicht mehr
  wechseln.

## 2026-11-16 – Sicherung der Android-App einlesen

- `KotlinBackup` (coach_core) liest `AppData` der Kotlin-App (Coach-App `android/core/.../Model.kt`, kotlinx mit
  `encodeDefaults`). Mahlzeit-Positionen, eigene Rezepte und Lebensmittel haben dasselbe JSON wie hier und werden
  direkt gelesen; Trainings, Pläne und eigene Übungen werden umgesetzt (Satz `warmup` → `SetKind.warmup`, Gruppe =
  deutscher Name wie `MuscleGroup.rawValue`, Routine-Kennung als `workoutKey` `routine-<id>`, Pause aus
  `settings.restSeconds`). Kennungen werden wie in der App großgeschrieben (Kotlin schreibt UUIDs klein), damit
  erneutes Einspielen nichts doppelt anlegt.
- **Zusammenführend** wie `restore`: Vorhandenes bleibt. Einstellungen nur, wo noch nichts eingerichtet ist
  (Körperwerte ohne Gewicht, Rezept-Wünsche im Standard, keine Mahlzeiten-Erinnerung an). **Ziel und Tempo werden
  nicht übernommen** – sie laufen über die Einrichtung und damit über die Schutzgrenzen (`GoalRules`).
- Nicht übernommen (Hinweis nach dem Einspielen): laufendes Training, Tagestypen (gibt es hier nicht), Rezeptideen der
  Woche, wartende KI-Auswertungen.
- Die Testdatei ist von Hand nach den Datenklassen gebaut (Gradle-Lauf der Kotlin-App in der Sitzung nicht möglich);
  ein Abgleich mit einer echten Sicherung steht beim Gerätetest an.

## 2026-11-16 – Android-APK über ein privates Release-Repo

- Die universelle APK (alle Prozessortypen, auf Wunsch des Nutzers keine Beschränkung auf arm64) ist rund 109 MB groß,
  Workers KV nimmt höchstens 25 MiB je Wert. Statt R2 (verlangt vermutlich ein Zahlungsmittel) oder öffentlichen
  GitHub-Releases (APK auffindbar) liegt sie als Release in einem privaten Repo (`aironludi-releases`, Variable
  `RELEASES_REPO`). AIronLudi bleibt öffentlich, damit die macOS-Minuten kostenlos bleiben.
- `android.json` in KV bekommt `asset` (`repo`, `id`); der Worker holt die Datei mit `RELEASES_READ_TOKEN` über die
  GitHub-API und folgt der Weiterleitung auf die signierte Adresse **ohne** Token. Stände ohne `asset` kommen wie
  bisher aus KV. Die letzten drei Releases bleiben (Rückweg). Neuer Dateiname `AIronLudi.apk`, der alte Pfad
  `IronLudi-Gym.apk` funktioniert weiter. Die IPA (rund 16 MB) bleibt in KV.
- `ironludi://connect?worker=…&token=…` (Knopf „In der App verbinden“ der Download-Seite) wertet jetzt auch die
  Flutter-App aus (`AndroidConnectLink`, gleiche Regeln wie Einladungen: ein Haupt-Token wird nie durch einen Link
  für einen anderen Server ersetzt). Bisher war das Schema nur im Manifest angemeldet.

## 2026-11-16 – Design wie die Swift-App

- Rückmeldung des Nutzers: Seit der Umstellung sah die App anders aus (Material 3 mit oranger Grundfarbe). Die
  Swift-App nutzt den SwiftUI-Standard ohne eigene Akzentfarbe, also `systemBlue`, gruppierte Listen
  (`systemGroupedBackground`, `secondarySystemGroupedBackground`), iOS-Schriftgrößen und die iOS-Tab-Leiste.
- `AppTheme` bildet das zentral nach (Farben aus den Human Interface Guidelines, „Color“), statt jede Seite einzeln
  umzubauen: `FormSection` zeichnet Trennlinien wie `Form`, `CupertinoTabBar` ersetzt `NavigationBar`, die vier
  Hauptseiten zeigen große Überschriften (`LargeTitleScope`), Pfeile am Zeilenende sind grau (`DisclosureChevron`).
- Gilt auf beiden Plattformen gleich, damit die App überall gleich aussieht; nur die Schalter sind adaptiv
  (`SwitchListTile.adaptive`: iOS-Schalter auf dem iPhone, Material-Schalter unter Android). Schrift ist die des
  Systems (SF Pro auf dem iPhone, Roboto unter Android).

## 2026-11-16 – Update-Hinweis der Android-App (neu, kein Swift-Vorbild)

- Die Android-App kommt nicht aus dem Play Store und aktualisiert sich nicht selbst; still installieren erlaubt
  Android außerhalb des Play Stores nicht. Deshalb ein Hinweis: `AppUpdateService` fragt beim Start und beim
  Zurückkehren (höchstens alle sechs Stunden) `GET /v1/app/android` und zeigt oben „Neue Version … verfügbar“ mit
  „Jetzt laden“ (Download-Seite im Browser) und „Später“ (diese Version ausblenden, eine neuere erscheint wieder).
- Der Endpunkt verlangt eine Anmeldung (Haupt-, Gast- oder Sitzungs-Token) und gibt den geheimen Pfad der
  Download-Seite heraus. Das ist vertretbar: Gäste haben den Android-Link ohnehin bekommen, Konten entstehen nur mit
  Einladung. Ohne Anmeldung bleibt der Pfad geheim.
- Verglichen wird `versionCode` (CI: 10000 + Laufnummer) mit `PackageInfo.buildNumber`. Prüfzeitpunkt und ausgeblendete
  Version (`update.lastCheck`, `update.dismissedVersion`) sind Gerätestand und gehören nicht zur Sicherung.
- iPhone: nichts Neues, Updates meldet weiterhin SideStore. Fehler (kein Netz, alter Worker, keine Version) bleiben still.


## 2026-11-16 – Adaptiver Ausdauerplan (Laufen, Rad/Zwift, Schwimmen)

- **Neue Funktion ohne Swift-Gegenstück** (Auftrag des Nutzers): Trainingsplan auf ein Ziel (5 km bis Langdistanz,
  Radrennen, Schwimmwettkampf; Datum, optionale Zielzeit) oder für einen Zeitraum (4/8/12 Wochen, Grundlage oder
  Formsteigerung). Bestehende Funktionen (Saisonplan, eigener Wochenplan) bleiben unverändert; der Plan ist ein
  zusätzlicher Eintrag „Ausdauerplan“ im Reiter Training.
- **Regeln entscheiden** (`TrainingPlanEngine` in `coach_core`, deterministisch, Tests in `endurance_test.dart`):
  - Periodisierung: Grundlage → Aufbau → Spitze → Tapering → Wettkampfwoche, 3:1 mit Entlastungswoche; Tapering je
    Distanz 1–3 Wochen (Mujika & Padilla 2003, Bosquet et al. 2007: 40–60 % weniger Umfang bei gleicher
    Intensität). Umfang steigt höchstens 5 Prozentpunkte je Woche (unter der üblichen 10-%-Grenze).
  - Intensität nach Zonen relativ zur Schwelle: Rad % FTP (Coggan), Laufen/Schwimmen % der Schwellen- bzw.
    CSS-Geschwindigkeit, ersatzweise % Schwellenpuls (Friel). Ohne Werte nur Zonen als Notiz.
  - Belastung als Training Stress Score (TSS, rTSS, sTSS, hrTSS), Fitness/Ermüdung/Form nach dem
    Impulse-Response-Modell (CTL 42, ATL 7 Tage). Ohne Messwerte eine Schätzung je Stunde und Sportart.
  - Anpassung jeden Tag vom ursprünglichen Plan aus (entfällt der Grund, gilt wieder der Plan): ausgefallene
    Schlüsseleinheit einmal je Woche nachholen, ohne harte Tage zu stapeln (ausgefallener Grundlagenumfang wird
    bewusst nicht nachgeholt); deutlich mehr Belastung als geplant (> 25 TSS bzw. 30 %) entschärft die nächste
    Einheit, **gleich welcher Disziplin**; Form unter −30 nimmt Intensität heraus; Erholung heute über
    `RecoveryEvaluator` (gleiche Ampel wie „Heute“) plus Body Battery beim Aufwachen (< 25 Ruhetag, < 40 locker).
    Wettkämpfe ändert die App nie selbst. Jede Änderung steht mit Grund im Anpassungsverlauf.
  - Health ist optional: Die Tageswerte kommen zusammengeführt aus Garmin, Health und WHOOP; ohne Werte entfällt
    nur die Erholungsregel.
- **Export und Synchronisation** (`WorkoutExport`, `WorkoutExporterService`):
  - Garmin: über den Garmin-Connect-Kalender wie schon `GarminWorkoutService` (inoffizielle `workout-service`-
    Schnittstelle), jetzt mit Zielen je Schritt (`pace.zone`, `power.zone`, `heart.rate.zone`). Die offizielle
    „Garmin Training API“ setzt eine Partner-Freigabe durch Garmin voraus und kommt daher nicht in Frage.
    Automatischer Abgleich (abschaltbar, Standard aus) hält die nächsten 14 Tage aktuell: Fingerabdruck je
    Einheit, geänderte werden ersetzt, zu Ruhetagen gewordene gelöscht.
  - FIT-Workout-Datei (`file_id` Typ 5, `workout`, `workout_step` mit Wiederholungen und Zielen) zum Teilen;
    `FitEncoder` kann dafür jetzt Textfelder.
  - Zwift: `.zwo` (Leistung als Anteil der FTP, `IntervalsT` für Intervalle) zum Teilen. Zwift bietet keine
    öffentliche Schnittstelle zum Hochladen; die Datei kommt in `Dokumente/Zwift/Workouts/<Zwift-ID>/`.
- **Mehrbenutzer-Trennung:** Der Plan liegt unter `coach.endurancePlan` in der Datenbank des Benutzers und trägt den
  `username`; `EndurancePlan.fromJson` und `EndurancePlanStore` weisen fremde Pläne ab, `WorkoutExporterService`
  arbeitet nur mit Plänen seines Benutzers und mit dessen Garmin-Anmeldung (Schlüssel im sicheren Speicher je
  Benutzer). Kennungen der übertragenen Workouts und der Anpassungsverlauf gehören zum Plan. Folge: Eine Sicherung
  bringt den Plan nur beim gleichen Benutzernamen zurück – sonst wird neu geplant.
- **Vorschläge für Schwellen** nur im Modus Saisonplan aus `SeasonConfig` (keine Saisonwerte für andere Personen).

## 2026-11-17 – KI-Empfehlungen von einem stärkeren Modell prüfen lassen

- Auftrag des Nutzers: Die Empfehlungen im Bereich „AI“ (heute von frei verfügbaren Modellen über den Worker) sollen
  beim manuellen Export an eine externe KI (Claude, ChatGPT …) mit dem Auftrag gehen, sie zu prüfen; beim Import
  entscheidet die Person, was überschrieben wird.
- **Export:** Mit Antwortformat enthält die Datei den Abschnitt „Empfehlungen der App (bitte prüfen)“: alle offenen,
  noch gültigen Empfehlungen (höchstens 30, wichtigste zuerst) mit ID (`thema.betreff`), Herkunft (Regeln bzw. KI mit
  Modell), Priorität, Richtung und Belegen. Neue Felder im Block: `empfehlungen` (mit `id` = ersetzt diese
  Empfehlung, ohne = neu), `verwerfen` (IDs), `modell`. Gilt automatisch für alle künftigen Empfehlungen.
- **Import:** Empfehlungen werden als `origin: ki` mit dem Modellnamen aus der Antwort gespeichert (kein neuer
  Rohwert für `InsightOrigin`, damit Sicherungen mit der Swift-App lesbar bleiben); die Begründung der KI ist der
  Beleg. Vorschau je Empfehlung mit „Überschreibt: …“ bzw. „Neu“ zum Abhaken, dazu die zu verwerfenden.
- **Regeln entscheiden:** Empfehlungen der Regeln sind weder zum Überschreiben noch zum Verwerfen vorausgewählt;
  ausdrücklich angehakt werden sie trotzdem ersetzt (die Person entscheidet). Übernommene Empfehlungen ersetzen
  widersprechende KI-Empfehlungen, nie Regel-Empfehlungen ohne Haken.

## 2026-11-17 – Ausdauerplan nach den Zielen der App

- Rückmeldung des Nutzers: Beim Erstellen fehlten die Ziele und Wettkämpfe, die in der App schon gepflegt sind.
- `EnduranceGoals` (coach_core) leitet die Vorgaben ab: Wettkampf aus der Einrichtung (`UserProfile.event`, Art aus
  `EventKind`, beim Triathlon aus dem Namen), im Modus Saisonplan zusätzlich Marathon und Hauptrennen aus
  `SeasonConfig` (sonst nie – keine Saisonwerte für andere Personen); Ausdauersportarten aus dem Profil, Tage, langer
  Tag und Zeit je Woche aus dem Wochenplan; ohne Wettkampf ein Zeitraum-Plan, Schwerpunkt nach dem Hauptziel.
- Bekannte Wettkämpfe stehen beim Erstellen oben zur Auswahl (vorausgewählt der nächste), „Anderes Ziel“ bleibt.
  Der Name des Wettkampfs wird im Plan gespeichert (`eventName`). Ändert sich das Ziel in der App, zeigt die
  Übersicht „Neues Ziel …“ mit dem Weg zu einem neuen Plan; ersetzt wird nichts automatisch.

## 2026-11-17 – Rückmeldung: Fehler, geräteunabhängige Texte, Ernährung, Belastung und Übersichten

- **Fehler „Entfernen“ im Wochenplan:** Der Menüeintrag hatte den Wert `null`; Flutter wertet `null` als Abbruch
  (`onSelected` wird nicht aufgerufen). Jetzt eigene Aktionswerte; gleicher Fehler bei „Freies Training“ im Gym.
- **Veraltete Trainingstage:** Folge des obigen Fehlers (der Tag wurde nie entfernt). Zusätzlich verwirft ein neuer
  dauerhafter Wochenplan Wochenpläne und Ausnahmen ab der laufenden Woche (`PlanAdjustments.dropFrom`), weil sie sich
  auf den alten Stand bezogen – Abweichung von Swift, dort blieben sie stehen.
- **Fettabbau ohne Überschuss:** `Personalization.fitnessGoal` bildete „Muskelaufbau + Nebenziel Fettabbau“ auf
  Überschuss ab; jetzt Rekomposition wie schon bei „Kraftsteigerung + Fettabbau“. Gespeicherte Profile werden beim
  Laden korrigiert (Ernährungsziel neu berechnet).
- **Geräteunabhängige Texte:** Werte kommen aus Garmin, WHOOP oder den Gesundheitsdaten des Telefons; Texte sprechen
  von Uhr, Datenquellen bzw. Gesundheitsdaten. „Garmin“ bleibt, wo das Garmin-Konto ausdrücklich genutzt wird
  (Anmeldung, Personal API, Diagnose, Garmin-Kalender, Krafteinheiten-Abgleich, Herkunft einzelner Werte). Der
  Gesundheitsspeicher heißt unter Android „Health Connect“ (`healthStoreName`).
- **Ernährung:** Anpassungen für einzelne Tage (Refeed: kein Defizit, Plus als Kohlenhydrate; Ruhetag; ±500 kcal) und
  eigene Makros (Protein 1,2–2,4 g/kg, Fettanteil 20–35 %, ACSM 2016) – die Schutzgrenzen in `NutritionPlanner`
  (höchstens 25 % Defizit, Energieverfügbarkeit ≥ 30 kcal/kg FFM) bleiben vorrangig.
- **Realistische Hochrechnung** (`IntakeForecast`): Schnitt der letzten 14 erfassten Tage, Ausreißer auf ±40 % des
  Medians begrenzt, höchstens 1 % Abnahme bzw. 0,5 % Zunahme des Körpergewichts pro Woche (`GoalRules`), nicht über 4
  Wochen, mit Hinweis auf Wasser/Glykogen (Hall et al. 2011). Die KI darf keine eigenen Gewichtsprognosen mehr nennen
  (Worker: `GROUNDING_SYSTEM`, Chat); die Ernährungs-Auswertung setzt keinen Triathleten mehr voraus.
- **„Meine Belastung heute“** (`DailyStrainRules`): erledigte Punkte (TSS wie im Ausdauerplan) plus geplante (Ausdauerplan,
  sonst Schätzung je Sportart und Intensität des Wochenplans) gegen den üblichen Tag (CTL, mindestens 25); ohne Verlauf
  feste Stufen 40/80/120. Ampel aus derselben Erholungsbewertung wie „Jetzt dran“; „Pause“ streicht Geplantes. Auf
  „Heute“ und im Reiter Training.
- **Weniger Text im Reiter Training:** Kacheln statt Listenzeilen mit Erklärtext, Trainingszeit der letzten 8 Wochen als
  gestapeltes Balkendiagramm; Details erst beim Antippen.

## 2026-11-18 – Import von KI-Antworten nachsichtig lesen

- Rückmeldung: Ein Trainingsplan aus Claude kam nicht an. Nachgestellt mit typischen Antworten: Übungsnamen statt IDs
  („Bankdrücken (Langhantel)“, „Kniebeugen“, „Klimmzüge“) wurden entfernt und die Routine **still** verworfen; JSON mit
  Kommentaren, Kommas vor Klammern oder „“ war „ungültig“; englische Schlüssel, JSON ohne Codeblock oder ein Block auf
  einer Zeile wurden nicht gefunden; „Übernehmen“ stand unter einer langen Vorschau außer Sicht.
- `ImportJson`: Codeblöcke mit ```/~~~ (mit oder ohne Sprache), sonst ganzer Text bzw. größtes `{…}`; Kommentare,
  überzählige Kommas und typografische Anführungszeichen werden repariert; Schlüssel-Synonyme Deutsch/Englisch
  (`routines`, `exercises`, `sets`, `reps: "6-8"`, `weekly_plan`, `monday` …), Übungen als Text, Tage als Text.
- `CoachImport.resolve`: genaue ID, gleicher Name, englische Namen (Bench Press …), ohne Klammerzusatz, Wortstämme
  (Plural, Umlaut), sonst die Übung, deren Namenswörter alle vorkommen. Jede Zuordnung steht in der Vorschau
  („„Kniebeugen“ als Kniebeuge übernommen“); eine Routine ohne bekannte Übung wird gemeldet.
- Die Regeln bleiben unverändert: nur Übungen der eigenen Ausstattung, Grenzen für Sätze/Wiederholungen/Pausen, im
  Saisonplan kein Wochenplan (mit Hinweis). Neu in der App: „Aus Datei laden“, fester Knopf „Auswahl übernehmen“ und
  nach dem Übernehmen Wege zu Trainingsplänen und Wochenplan.
- Nachtrag: Pläne kommen auch als Markdown-Tabelle (.md-Datei aus Claude, ohne JSON). `MarkdownPlan` liest Tabellen
  mit Wochentagen in der ersten Spalte. Die Überschrift darüber entscheidet: „Diese Woche“ gilt nur für die laufende
  Woche (neues Feld `diese_woche`, auch im JSON). „Nächste Woche“ gilt für die nächste Woche, sonst dauerhaft.
  Fließtext und die Spalte „Hinweis“ werden zu Hinweisen. Tabellen ohne Wochentage (z. B. Verlauf je Woche) werden
  übergangen. Einheiten werden wie beim JSON erkannt, auch mehrere je Tag („Schwimmen + Kraft“). Ruhetage („Frei“,
  „Regeneration“) bleiben frei. „Krafttraining“ ohne Zusatz ist die normale Krafteinheit, nicht „Kraft leicht“.
  Ein JSON-Block hat weiter Vorrang.
- Eine Tabelle ist der ganze Plan und überschreibt den bisherigen Wochenplan: Tage, die sie nicht nennt, werden frei
  (bei „Diese Woche“ ab heute; vergangene Tage bleiben). Ein JSON-Block ändert weiterhin nur die genannten Tage, wie
  es die Export-Anleitung beschreibt; mit `"vollstaendig": true` ersetzt auch er alle Tage. Wochenpläne und Ausnahmen
  ab dieser Woche fallen wie bei jeder Änderung des dauerhaften Plans weg.

## 2026-11-18 – „Heute“ entschlackt, Sportarten, Makroziele, Produktsuche

- **Kennzahlen oben (`TodayKpis`):**
  - **Schlaf:** Schlafwert der Uhr bzw. WHOOP (grün ab 80, gelb ab 60), sonst die Dauer gegen das Schlafziel.
  - **Erholung:** WHOOP-Recovery bzw. Training Readiness (grün ab 67, gelb ab 34, wie bei WHOOP), sonst Body
    Battery beim Aufwachen, sonst nur die Tagesampel. Die Farbe ist nie besser als die Tagesampel der App
    (Regeln entscheiden).
  - **Strain 0–21:** `21 × (1 − e^(−Punkte/91))` auf den Trainings-Stress-Punkten von „Meine Belastung heute“,
    logarithmisch wie bei WHOOP. 100 Punkte (eine Stunde an der Schwelle) ≈ 14. WHOOP liefert den Tages-Strain zwar,
    er gilt aber nur für WHOOP-Daten; die eigene Skala gilt für alle Quellen gleich und auch für einzelne Einheiten.
    Farbe aus der Einordnung gegen den üblichen Tag; „hoch“ bei eingeschränkter Erholung ist rot.
- **Bereiche (`TodayDashboard`, Schlüssel `coach.todayDashboard`):**
  - Gespeichert werden die ausgeblendeten Bereiche; die Reihenfolge ist fest (Kennzahlen, Training, AI, Vorschläge …).
  - Standardmäßig aus: Morning Report, Belastungs-Detailkarte, Nach dem Training, Motivation, Hinweise.
  - Die AI-Empfehlungen lassen sich ganz ausblenden; Export und Import für externe KI bleiben in den Einstellungen.
  - Der Morning Report bleibt unter Training › Gesundheit.
- **Sportarten (`ActivityKind`):** feinere Einordnung aus Typ und Name, ohne das gespeicherte `ActivitySport` zu
  ändern (Datenformat). Bouldern, Klettern, Yoga, HIIT, Rudern, Wandern & Co. zählen als Training, auch ohne Eintrag
  im Plan; Gehen und Unbekanntes wie bisher nur, wenn geplant. Health: Klettern, Paddeln, Tanzen, Kampfsport und
  Treppensteigen haben eigene Typen. Namen werden nur am Wortanfang erkannt („Abendrunde“ ist kein Lauf).
- **Eigene Makroziele:** in Gramm oder Prozent, auf Wunsch eigene Werte für Ruhetage. Die Schutzgrenzen bleiben:
  - nicht unter dem größten erlaubten Defizit bzw. der Energieverfügbarkeit (sonst Kohlenhydrate und Fett anteilig
    angehoben);
  - ohne Gewichtsziel kein Defizit;
  - mindestens 20 % Fett;
  - ohne Gewichtsziele (Schutzeinstellung) gilt die automatische Rechnung.
  Jede Anpassung steht als Hinweis im Reiter Ernährung.
- **Produktsuche:** eigene Lebensmittel und BLS sofort beim Tippen, Open Food Facts (`de.openfoodfacts.org`,
  `cgi/search.pl`) erst nach 0,7 s Pause und ab drei Zeichen, je Suchbegriff gemerkt. Grund: Open Food Facts erlaubt
  nur wenige Suchen je Minute. Filter nach Herkunft, „Viel Protein“ (≥ 15 g/100 g) und „Kalorienarm“
  (≤ 100 kcal/100 g); Nährwerte je 100 g und je Portion. Übernommene Markenprodukte merkt sich die App wie nach einem
  Scan.

## 2026-11-18 – Erfassen mit Suche zuerst

- Rückmeldung mit Screenshot einer anderen App: Die Lebensmittelsuche soll die Startansicht beim Erfassen sein.
  Umgesetzt als eigene Gestaltung, keine Nachbildung:
  - „+“ im Reiter Ernährung öffnet die Suche; Scannen, KI (Foto/Text), Nur kcal und Manuell sind Reiter darüber.
  - Ohne Suchbegriff: „Vorschläge · Mahlzeit“ (`ProductSearch.picks`) und „Zuletzt verwendet“.
  - Jede Zeile hat eine Kurzzeile mit kcal, P, K, F und der Menge.
  - „+“ legt mit der üblichen Menge in den Korb; Antippen öffnet die Mengenwahl.
  - Unten Korb mit Summe, Suchfeld und „Eintragen (n)“; oben Mahlzeit und Tageskalorien einschließlich Korb.
- **Vorschläge:** einzelne Lebensmittel, die zur gewählten Mahlzeit in den letzten 60 Tagen am häufigsten gegessen
  wurden, mit der zuletzt gegessenen Menge; aufgefüllt mit dem Häufigsten der anderen Mahlzeiten. Wasser zählt nicht.
- **Übliche Menge für „+“:** bei eigenen Lebensmitteln die zuletzt gegessene Menge, bei Markenprodukten die
  Packungsportion, sonst 100 g.
- **Eintragen:** direkt als Mahlzeit, mit „Rückgängig“ wie bei der Schnell-Leiste, ohne den Editor.
- **Symbole:** nach Art statt Emojis (Getränk, eiweißreich, fettreich, leicht, kohlenhydratreich). Die
  KI-Erfassung bleibt unverändert erreichbar.

## 2026-11-18 – „Clean Liquid Design“ (löst „Design wie die Swift-App“ ab)

- Auftrag des Nutzers: die ganze App durchgängig in einem cleanen Liquid Design (Glasflächen wie iOS/visionOS,
  weiche Radien, fließende Bewegung). Das ersetzt die Entscheidung vom 16.11.2026, das SwiftUI-Standardaussehen
  nachzubilden. Funktionen, Texte, Abläufe und Datenformate bleiben unverändert – es ändert sich nur die Darstellung.
- Zentral in `lib/ui/liquid.dart` (Werte und Bausteine) und `AppTheme` (Material-Theme mit `LiquidTheme` als
  Theme-Erweiterung), damit alle Seiten über die gemeinsamen Bausteine umgestellt werden statt einzeln:
  - Hintergrund: ruhiger Verlauf mit vier weichen Lichtflecken (`LiquidBackground`), hell und dunkel. Seiten sind
    durchsichtig; den Hintergrund malt der Seitenübergang (`LiquidPageTransitionsBuilder`, sonst der native von iOS)
    und als Grundschicht `MaterialApp.builder`.
  - Glas: `LiquidSurface`/`LiquidCard` – transluzente Füllung, Hintergrund-Unschärfe (`BackdropFilter.grouped` in
    einer `BackdropGroup` je Seite, damit lange Listen nicht für jede Karte neu lesen), 1-px-Lichtkante als Verlauf,
    sehr weicher Umgebungsschatten. „Kontrast erhöhen“ macht das Glas deckend. `FormSection` (über 500 Abschnitte)
    und das Karten-Theme nutzen es, so wirkt jede Seite gleich.
  - Radien 24 (Karten), 14 (innere Flächen), 28 (Sheets, Dialoge), Pillen für Knöpfe, Marken, Segmente und die
    Tab-Auswahl.
  - Status bleibt deterministisch und gleich eingeordnet (Ampel, Strain-Stufen, Makros); die Farben erscheinen als
    leuchtende Verläufe in Ringen (`ProgressRing`, Bogenverlauf mit Glühen), Balken (`StrainBar`,
    `LiquidProgressBar`) und Symbolen.
  - Bewegung: Federkurve aus einer echten Federsimulation (`LiquidSpringCurve`); Ringe und Balken füllen sich, Module
    unter „Heute“ erscheinen nacheinander, die Auswahl der Tab-Leiste gleitet. Bei „Bewegung reduzieren“ entfällt
    alles (`LiquidMotion.of`). Keine endlos laufenden Animationen (Akku, Tests mit `pumpAndSettle`).
  - Berührung: Karten, Ringe und Reiter sinken leicht ein und federn zurück (`LiquidPressable`, fängt keine Gesten
    ab), Knöpfe leuchten beim Drücken auf, gefüllte Knöpfe haben einen Glanz.
  - Tab-Leiste: schwebende Glas-Kapsel (`LiquidTabBar`) statt `CupertinoTabBar`, gleiche vier Reiter und Abzeichen.
- Schrift bleibt die des Systems (SF Pro auf dem iPhone, Roboto unter Android); keine gebündelte Schrift (Größe,
  Lizenzpflege). Kennzahlen mit gleich breiten Ziffern und engerer Laufweite (`LiquidText.kpi`), Labels dezent.
- Neu: Vorschau der Live-Aktivität unter Einstellungen › Sperrbildschirm (`LiveActivityPreview`, Beispielwerte je
  gewählter Ansicht). Die echten Widgets und Live-Aktivitäten bleiben nativ (Migrationsplan 4.2) und sind nicht Teil
  dieser Umstellung.

## 2026-11-19 – Daily Strain läuft über den Tag mit; Markenprodukte in der Schnellsuche

**Daily Strain (Ring „Strain“ unter „Heute“, „Meine Belastung heute“ unter „Heute“ und „Training“)**

- Ursache: Beide Seiten luden ihre Daten nur beim Öffnen, um Mitternacht und wenn sich `AppModel.lastSync` änderte.
  `lastSync` ist der Zeitpunkt des letzten **Garmin**-Abrufs. Abrufe nur von WHOOP oder Apple Health / Health
  Connect, nachgetragene Aktivitäten und gesicherte Gym-Einheiten änderten ihn nicht – der Wert blieb auf dem Stand
  vom Morgen. Blieb die App offen, wurde außerdem nicht weiter abgerufen.
- Jetzt: `trainingDataChangesProvider` meldet jede Änderung der Tabellen für Tageswerte, Aktivitäten und
  Gym-Einheiten (drift `tableUpdates`), gleich welche Quelle schreibt. „Heute“ und „Training“ laden dann neu
  (`TrainingDataReload`, 0,6 s nach der letzten Änderung, damit ein Abruf mit vielen Zeilen nur einmal neu lädt).
  Gerechnet wird bei jedem Neuladen frisch; es gibt keinen Zwischenspeicher für den Wert.
- Abruf: wie bisher beim Start, beim Zurückkehren in die App und per „Ziehen zum Aktualisieren“; neu zusätzlich alle
  15 min, solange die App im Vordergrund ist (`RootShell`, über `syncIfDue` mit Mindestabstand und Wartezeit nach
  Fehlern). Im Hintergrund bleibt es beim Hintergrundabruf des Systems.
- Datenquellen (unverändert, `DailyStrainRules.compute`): erledigt = Belastungspunkte der heutigen Aktivitäten aus
  allen Quellen (Garmin, WHOOP, Health, nachgetragen; Doppelte einmal) aus Leistung, Tempo bzw. Puls, sonst aus Dauer
  und Sportart (`TrainingLoad`), dazu abgeschlossene Gym-Einheiten der App ohne Uhr-Aufzeichnung (35 Punkte je
  Stunde). Geplant = offene Einheiten aus Ausdauerplan bzw. Wochenplan. Üblicher Tag und Ermüdung aus dem Verlauf
  (42 bzw. 7 Tage); Erholungsampel aus den Tageswerten. Strain 0–21 = `TodayKpis.strainOf` der erledigten Punkte.

**Lebensmittelsuche**

- Ursache: Die Lupe im Reiter Ernährung (Schnellsuche) durchsuchte nur eigene Lebensmittel, frühere Mahlzeiten und
  den BLS – keine Produktdatenbank. „Nutella“ & Co. gab es nur unter „+“ › Suchen.
- Jetzt zeigt die Schnellsuche darunter „Markenprodukte“ aus Open Food Facts (`BrandProductResults`, ab drei
  Zeichen, nach 0,7 s Tipp-Pause) mit kcal, Protein, Kohlenhydraten und Fett je Portion bzw. 100 g und je 100 g.
  „+“ trägt mit der Packungsportion (sonst 100 g) ein, Antippen öffnet den Entwurf. Eingetragene Produkte merkt sich
  die App als eigenes Lebensmittel (stehen beim nächsten Mal oben, ohne Netz).
- Suche robuster (`OpenFoodFactsClient.search`): zuerst die Volltextsuche „Search-a-licious“
  (`search.openfoodfacts.org/search`), bei Fehler oder ohne Treffer die klassische `cgi/search.pl`. Bisher ergab eine
  Fehlerseite (HTML, 5xx) still „Keine Markenprodukte gefunden“ – jetzt eine Meldung mit „Erneut“. Ergebnisse je
  Suchbegriff gemerkt (Sitzung, höchstens 40), Fehler nicht. `brands` als Liste (Search-a-licious) wird gelesen.

## 2026-11-20 – Strain wie bei WHOOP (Puls über den ganzen Tag)

- Wunsch des Nutzers: Strain soll wie bei WHOOP entstehen. Bisher zählten nur Trainings (Belastungspunkte →
  0–21); ohne aufgezeichnetes Training stand der Ring auf 0,0, Alltagsbewegung zählte nie.
- Reihenfolge der Quellen (neue Datenart `DataKind.strain`, einstellbar unter Datenquellen; Standard WHOOP, Garmin,
  Apple Health / Health Connect):
  1. **WHOOP verbunden:** der Tages-Strain des WHOOP-Zyklus (`WhoopCycle.strain` → `DailyMetrics.dayStrain`), also
     genau der Wert der WHOOP-App.
  2. **Pulsverlauf:** Garmin `dailyHeartRate` (alle 2 min, gestern und heute bei jedem Abruf) bzw. Herzfrequenz aus
     Apple Health / Health Connect (in 2-Minuten-Fenster gemittelt) → `DailyMetrics.heartRateCurve`, kompakt als
     `[Minute, Puls, …]` gespeichert. Daraus `HeartRateStrain.compute`.
  3. **Ohne Pulsverlauf:** wie bisher aus den Trainings (`DailyStrainRules`, Belastungspunkte).
- Berechnung (`HeartRateStrain`): Anteil an der Herzfrequenzreserve je Minute, Ruhepuls des Tages (sonst 60),
  HFmax aus den Einstellungen, sonst höchster Lauf-/Radpuls der letzten 12 Monate, sonst 208 − 0,7 × Alter (Garmin-
  Profil), sonst 190 – nie unter dem heute gemessenen Höchstwert. Zonen wie bei WHOOP (50–60 … 90–100 % HRR) mit
  Gewicht 1–5 (Edwards), Alltagsbewegung 30–50 % mit 0,1, darunter 0. Lücken über 10 min zählen nicht (Uhr
  abgelegt). Skala: Strain = 21 × (1 − e^(−gewichtete Minuten / 170)) – wächst anfangs schnell und wird nach oben
  immer schwerer zu steigern.
- WHOOP veröffentlicht seine Formel nicht. Die Skala ist an WHOOPs Einordnung kalibriert (leicht 0–9, mittel 10–13,
  hoch 14–17, all out 18–21) und getestet: ruhiger Tag ≈ 4, dazu 1 h locker ≈ 13, 1 h zügig ≈ 15, 1 h Intervalle
  ≈ 17, Marathon ≥ 20. Abweichungen zur WHOOP-App sind möglich; mit WHOOP gilt dessen Wert.
- Ring „Strain“: gemessener Wert, Beschriftung mit der Quelle („WHOOP“, „Puls ganztags“); noch Geplantes hell
  obendrauf (Belastungspunkte × 2,5 als gewichtete Minuten). Antippen zeigt Ruhepuls, HFmax und Minuten je Zone.
  Ampel, „Meine Belastung heute“ und der übliche Tag rechnen weiter mit den Trainings (Vergleich mit dem Verlauf).

## 2026-11-20 – Prüfung der Ernährungsrechnung (Ziele und Ist-Werte)

Auftrag des Nutzers: Grundumsatz, Bedarf, Ziel-Anpassung, Makros, Mikros und die Summe der Lebensmittel prüfen. Die
Rechnung bleibt in `NutritionPlanner` (Port von Swift, kein neuer „Service“-Name, damit Swift-Tests und Bezeichner
zuordenbar bleiben); die Tagessumme läuft neu über `FoodAggregation`. Abweichungen von Swift:

- **Training doppelt gezählt (Fehler):** Netto-kcal einer Aktivität = Uhr-kcal − Grundumsatz/1440 × Minuten. Der PAL
  enthält für diese Minuten aber schon den Alltag (Grundumsatz × PAL). Jetzt wird Grundumsatz × PAL abgezogen; bei
  geplanten Einheiten MET × kg × h − Grundumsatz × PAL / 24 × h statt (MET − 1) × kg × h. Beispiel 80 kg, PAL 1,4,
  60 min Lauf mit 700 kcal: 596 statt 626 kcal Training.
- **Aufbauen ohne Überschuss an Trainingstagen (Fehler):** Der Tagestyp-Faktor „fuel for the work“ (an harten Tagen
  0) galt auch für Überschüsse – an harten Tagen gab es keinen, an moderaten nur die Hälfte. Er gilt jetzt nur für
  Defizite. Der Überschuss ist ein fester Betrag: 10 % des Bedarfs ohne Sport (80-kg-Mann ≈ 250 kcal, 62-kg-Frau
  ≈ 190 kcal) bzw. aus dem Wochentempo (höchstens 15 % des Bedarfs ohne Sport), an jedem Tag gleich.
- **Untergrenze unter dem Grundumsatz (Fehler):** Die Untergrenze war 30 kcal/kg fettfreie Masse + Training. Bei
  niedrigem PAL und viel Körperfett lag sie unter dem Grundumsatz (Frau 62 kg, 32 % Fett, PAL 1,2: 1265 < 1347 kcal).
  Jetzt gilt das Höhere von beiden, nie über dem Bedarf.
- **Abnehmen ohne Defizit am Ruhetag (Fehler):** Bei kleinen, wenig aktiven Personen fraßen 2,2 g/kg Protein, 3 g/kg
  Kohlenhydrate und 20 % Fett das ganze Defizit (Ziel = Bedarf). Am Ruhetag im Defizit dürfen Kohlenhydrate jetzt auf
  2 g/kg sinken, mindestens 130 g (Glukosebedarf des Gehirns, IOM 2005). An Trainingstagen bleiben die Spannen nach
  Thomas et al. 2016.
- **kcal ≠ Summe der Makros (Ungenauigkeit):** kcal und Gramm wurden getrennt gerundet (bis 8 kcal Abweichung). Jetzt
  sind die kcal genau 4 × P + 4 × KH + 9 × F der angezeigten ganzen Gramm; die Kohlenhydrate nehmen den Rest auf
  (abgerundet, höchstens 4 kcal unter dem Ziel, nie darüber).
- **Fehlende Mikros als 0 (Fehler in der Anzeige):** „Alle Nährstoffe“ zeigte fehlende Werte als 0 – ein Riegel aus
  Open Food Facts ohne Eisenangabe sah wie ein Mangel aus. `FoodAggregation.of` zählt die Lücken je Nährstoff: „–“
  und „Keine Angabe in den Einträgen“, wenn niemand einen Wert hat, „≥ x“ und „n von m Einträgen ohne Angabe“ bei
  Lücken. Flüssigkeit in der Tagessumme wie im Wasser-Ring (Getränke ohne Wasserwert mit ihrer Menge).
- **Einheiten fremder Quellen (Absicherung):** `NutrientPlausibility.per100g` verwirft für Open Food Facts,
  Etikett-Foto und KI-Schätzung, was physikalisch nicht geht: über 900 kcal oder über 100 g eines Stoffs je 100 g
  (typisch: mg ins Gramm-Feld getippt, Faktor 1.000), mehr Zucker als Kohlenhydrate, mehr gesättigte Fette als Fett.
  Open Food Facts: Natrium aus Salz (÷ 2,5), wenn nur Salz angegeben ist.
- **Aktivitätsfaktor:** Hinweis in den Einstellungen, dass er nur Alltag und Beruf meint (1,4 / 1,6 / 1,8) – das
  Training rechnet die App selbst dazu.

Geprüft und unverändert (plausibel): Mifflin-St Jeor in kg/cm/Jahren; Defizit −15 % (Abnehmen) bzw. −5 %
(Umformen), höchstens 25 %; Protein 1,8–2,2 g/kg (ab BMI 30 auf das Referenzgewicht); Fett mindestens 20 % der
Energie (ACSM 2016, bei −15 % etwa 0,6 g/kg); Mikro-Referenzwerte der DGE in den Einheiten von `Nutrient` (mg/µg,
Vitamin D 20 µg = 800 IE); Ballaststoffe fest 30 g (DGE-Richtwert, nicht je 1.000 kcal, damit lange Trainingstage
keine 50 g verlangen); Flüssigkeit 35 ml/kg + 10 ml je Minute Ausdauer; Umrechnung je 100 g → Menge, Portionen,
Packungsportion, Rezepte je 100 g des fertigen Gerichts; Open Food Facts g → mg (× 1.000) bzw. µg (× 1.000.000);
Tagessumme wird bei jeder Änderung aus den gespeicherten Mahlzeiten neu gebildet (Bearbeiten, Löschen).

Beispiel (Mann 80 kg, 180 cm, 30 J., PAL 1,4; Grundumsatz 1780 kcal):

| Tag | Ziel | Bedarf | kcal | Protein | KH | Fett |
|---|---|---|---|---|---|---|
| Ruhetag | Abnehmen | 2492 | 2118 (−374) | 176 | 241 | 50 |
| Ruhetag | Halten | 2492 | 2489 | 144 | 260 | 97 |
| Ruhetag | Aufbauen | 2492 | 2739 (+247) | 160 | 284 | 107 |
| Lauf 60 min (700 kcal) | Abnehmen | 3088 | 2880 (−208) | 176 | 400 | 64 |
| Lauf 60 min (700 kcal) | Halten | 3088 | 3085 | 144 | 472 | 69 |
| Lauf 60 min (700 kcal) | Aufbauen | 3088 | 3334 (+246) | 160 | 480 | 86 |
| Rad 120 min (1500 kcal) | Abnehmen | 3784 | 3784 (kein Defizit am harten Tag) | 176 | 581 | 84 |
| Rad 120 min (1500 kcal) | Aufbauen | 3784 | 4033 (+249, vorher +0) | 160 | 639 | 93 |

Tests: `packages/coach_core/test/nutrition_audit_test.dart` (alle Ziele × Tagestypen × Mann/Frau, Makrosumme,
Untergrenzen, Mikros, Skalierung, Einheiten, Lücken, Tagessumme).

## 2026-11-20 – Ernährungsrechnung, zweite Runde

Auftrag des Nutzers: weiter verbessern, Mikros nachrangig. Ergänzend zur ersten Runde:

- **Verbrauchsabgleich mit falschem Formel-Bedarf (Fehler):** „Gemessener Verbrauch vs. Formel“ verglich mit dem
  kcal-Ziel eines Tages mit Ziel „Halten“. Mit eigenen Makros in Gramm ist das die selbst gewählte Zahl, nicht der
  Bedarf – der Vorschlag zur Anpassung war dann falsch. Neu: `NutritionTargets.maintenanceKilocalories`
  (Grundumsatz × PAL + Training netto, ohne Ziel, Anpassungen und eigene Makros) als Vergleichswert.
- **KI-Tagesauswertung bekam 0 für fehlende Werte (Fehler):** Unbekannte Nährstoffe gehen jetzt als `null`
  („unbekannt“), Summen mit Lücken mit der Zahl der Einträge ohne Angabe („mindestens …“) an den Worker; der Prompt
  sagt, dass beides kein Mangel ist. Kleine Werte mit einer Nachkommastelle (2,4 µg statt 2 µg).
- **Lückenliste für Rezepte (Fehler):** `RecipePlanner.gaps` zählte fehlende Werte als 0 und meldete z. B.
  „Eisen 20 %“, wenn Produkte keine Eisenangabe hatten. Jetzt zählen nur Tage mit bekanntem Wert (mindestens drei),
  und `FoodIntake.completeTotals` lässt Nährstoffe weg, deren Einträge ohne Angabe mehr als 10 % der Energie
  ausmachen. Reines Wasser zählt bei Lücken nicht mit.
- **Budget-Karte:** Mit Einträgen ohne Angabe heißt es „noch höchstens 62 g“ bzw. „mind. 18 g drüber“.
- **Fett mindestens 0,7 g/kg** (Referenzgewicht) zusätzlich zu 20 % der Energie, auch bei eigenen Makros (mit
  Hinweis). Vorher lag Fett bei −15 % am Ruhetag bei 0,58–0,63 g/kg. Die Kohlenhydrate geben dafür nach (am
  Ruhetag im Defizit bis 2 g/kg, mindestens 130 g).
- **Eisen:** Frauen ab 51 Jahren 14 mg (DGE/ÖGE 2024: nach der Menopause), sonst 16 mg; Männer 11 mg.
- **Natrium als Richtwert:** 1500 mg plus Schweißverlust (500 mg je Stunde Ausdauer, 250 mg je Stunde anderes
  Training, auf 50 mg gerundet). Keine Obergrenze mehr (vorher rot ab 1500 mg – irreführend für Ausdauersport),
  in der Anzeige ohne Ampelfarbe, für die KI „(Richtwert)“.

Bewusst nicht geändert: eine Prüfung auf „mögliche, aber unwahrscheinliche“ Mikrowerte je 100 g (z. B. Vitamin D in
mg statt µg). Nahrungsergänzungen haben je 100 g echte Werte in dieser Höhe; eine Grenze würde sie verwerfen.
Wasser- und Natriumzuschlag zählen nur aufgezeichnetes Training, nicht geplantes (wie bisher beim Wasser).

Tests: `nutrition_audit_test.dart` (Gruppen „Auswertungen über Tage“, Natrium, Eisen), Widget-Test „Nur Kalorien:
Makros und Mikros ohne Angabe zeigen keinen Mangel“, Worker `nutrition.test.ts`.

## 2026-11-21 – Routenplaner (OpenStreetMap) und optionale Gebiete

Auftrag des Nutzers: Routenplaner für Laufen und Radfahren auf OSM-Basis mit Rundweg, Strecke zum Ziel bzw. in eine
Richtung, Wunschdistanz und Höhenmetern, 2–3 Vorschlägen, Höhenprofil, Übernahme in eine Einheit, GPX/FIT-Export
und einem abschaltbaren Gebiete-Modul (Prinzip von Territory-Apps). Neu in AIronLudi, keine Swift-Vorlage.

- **Router ohne Schlüssel, direkt aus der App:** Valhalla auf dem Server der FOSSGIS (`valhalla1.openstreetmap.de`,
  `/route` und `/height`), bei Störung BRouter (`brouter.de`, Höhen in der Antwort). Beide sind kostenlos und
  brauchen keinen API-Key; daher kein Umweg über den Worker (die Regel „Keys nur im Worker“ betrifft hier nichts).
  OpenRouteService/GraphHopper bräuchten einen Schlüssel – sollte das nötig werden, gehört der Aufruf in den Worker.
  Rate-Limit: höchstens etwa eine Anfrage je Sekunde je Dienst (`RateGate`), `Retry-After` bei 429, gestörte Router
  werden einige Minuten übersprungen, gleiche Anfragen kommen aus dem Zwischenspeicher. „Kein Weg“ (z. B. Wegpunkt im
  See) führt nicht zum Ausweichen, sondern zu einem gedrehten Wegpunkt.
- **Regeln entscheiden, Router routet:** Wegpunkte (Kreis mit leicht unregelmäßigen Punkten für Rundwege, Ellipse
  für den Umweg zum Ziel, Endpunkt in der Himmelsrichtung) werden deterministisch aus einem Startwert erzeugt
  („Neu würfeln“ = anderer Startwert). Nach jeder Antwort wird die Größe proportional zur Abweichung nachgeführt,
  höchstens drei Anfragen je Variante; Toleranz ±7 %. Bewertung (`RouteScore`): Distanz, Höhenvorgabe (beim
  Höhenmeter-Fokus doppelt) und doppelt gelaufene Abschnitte. Wegbevorzugung über die Valhalla-Kosten
  (`pedestrian` mit `use_tracks`/`walkway_factor`, `bicycle` mit `bicycle_type` Road/Cross/Mountain, `use_roads`,
  `avoid_bad_surfaces`, `use_hills` aus der Höhenvorgabe je km).
- **Dauer:** Laufen mit lockerer Pace (Schwellen-Pace × 1,25, sonst 6:00 /km) und 8 m Flachstrecke je Höhenmeter
  (Naismith/Scarf); Rad 25 km/h (Rennrad) bzw. 19 km/h (Gravel) plus halbe Steigzeit bei 700 bzw. 550 hm/h.
- **Höhen:** Anstieg mit 3 m Hysterese gegen Rauschen; Höhen für höchstens 400 Stützpunkte, dazwischen interpoliert.
- **Speicher strikt je Benutzer:** `coach.routes`, `coach.exploration` und `coach.routePlanner` in der Datenbank des
  Benutzers (wie alle `coach.*`-Schlüssel in der Sicherung). Routen und Erkundung tragen zusätzlich den `username`;
  ein Stand eines anderen Benutzers wird weder angezeigt noch überschrieben (wie `coach.endurancePlan`).
- **Gebiete:** standardmäßig aus. Raster aus OSM-Kacheln der Zoomstufe 17 (in Mitteleuropa etwa 190 × 190 m).
  Eine Runde gilt als geschlossen bei höchstens 150 m (bzw. 3 % der Länge) zwischen Start und Ende, mindestens
  1 km Länge und mindestens 2 ha Fläche (kein „hin und zurück“); eroberte Fläche = Kacheln mit Mittelpunkt im
  Gebiet (Überschneidungen zählen einmal). Quellen sind die zwischengespeicherten FIT-Dateien der Aktivitäten (keine
  zusätzlichen Downloads); jede Aktivität zählt einmal.
- **FIT-Kurs:** Dateityp 6 (`course`) mit Runde, Start/Stopp und Punkten (Halbkreise, Strecke, Höhe); Zeitstempel
  aus der geschätzten Dauer. Dafür neu `FitBaseType.sint32`.
- **Standort:** `geolocator`, nur im Vordergrund und nur auf Antippen; ohne Freigabe bleibt der Pin auf der Karte.
- **Kartenkacheln:** wie die bestehende Streckenkarte `tile.openstreetmap.org` (Tile Usage Policy: geringe Nutzung,
  Quellenangabe). Bei wachsender Nutzung auf einen eigenen bzw. kommerziellen Kachel-Anbieter umstellen.

Tests: `packages/coach_core/test/routes_test.dart` (Geometrie, Wegpunkte, Router-Formate, Planer mit Test-Router,
Export, Gebiete), `test/services/routing_service_test.dart` (Ausweichen, Rate-Limit, Benutzer-Trennung),
`test/features/route_planner_screen_test.dart` (Ablauf vom Reiter Training bis zur Übernahme und Gebieten).

## 2026-11-22 – Routenplaner: Ansichtsmodus, Wegearten, ±2,5 %, Richtungspfeile, frei planen

Auftrag des Nutzers: Fehler „Antippen beim Zoomen löscht die Route“ beheben, Umgebung wählbar (Wald, Wasser,
Straße, Mix), Distanz enger einhalten, Richtungspfeile, Modus „Frei planen / zeichnen“.

- **Ansichts- und Bearbeitungsmodus:** Sobald Vorschläge vorliegen, verschiebt ein einfaches Antippen der Karte keine
  Punkte mehr (auch der erste Tipp eines Doppeltipps zum Zoomen löste bisher `onTap` aus). Punkte setzen dann nur
  **langes Drücken**, **„Startpunkt ändern“** (der nächste Tipp setzt den Punkt) oder **Planer zurücksetzen**.
- **Wegearten (`RoutePreference`):** Mehrfachauswahl Wald & Natur, Am Wasser, Straße & Asphalt; keine Auswahl =
  ausgewogener Mix. Natur und Asphalt schließen sich aus. Umgesetzt in zwei Stufen:
  1. **Router-Gewichtung:** Valhalla `pedestrian` (`use_tracks`, `walkway_factor`, `sidewalk_factor`,
     `use_living_streets`) bzw. `bicycle` (`bicycle_type`, `use_roads`, `avoid_bad_surfaces`); BRouter-Profile
     (`mtb`, `gravel`, `fastbike-lowtraffic`, `trekking-noferries`, `trekking`, `shortest`; ursprünglich `mtb-zossebart`, das es auf brouter.de nicht gibt – siehe Echttest 2026-11-22).
  2. **Wegpunkte auf passende Wege (Overpass):** Valhalla kennt kein „nah am Wasser“. Daher sucht der Planer über die
     Overpass-API (`overpass-api.de`, ohne Schlüssel, höchstens eine Anfrage je 2 s, Ergebnisse zwischengespeichert)
     Wege der Art im Umkreis – Pfade/Tracks/Fuß- und Radwege höchstens 40 m neben `waterway=canal|river` bzw.
     `natural=water`, unbefestigte `highway=path|track|bridleway` und `leisure=park`, beim Rad mit Asphalt
     `highway=cycleway` – und zieht die Zwischenpunkte auf den nächsten solchen Weg (höchstens 45 % des
     Schleifenradius bzw. 12 % der Strecke). Der Anteil der Strecke in 150 m Nähe solcher Wege fließt leicht in die
     Bewertung ein und wird angezeigt („ca. 62 % Am Wasser“). Fällt Overpass aus, routet der Planer nur mit der
     Gewichtung. **„Am Wasser“ heißt entlang, nie durch:** Als Anziehungspunkte dienen Knoten *auf* den Wegen
  (`node(w)`, auf 80 m ausgedünnt), nicht der Mittelpunkt ihres umgebenden Rechtecks – der läge bei einem Uferweg in
  einer Flussbiegung im Wasser. Fähren sind bei Valhalla abgewertet (`use_ferry` 0); meldet die Antwort trotzdem
  `has_ferry` bzw. enthält eine BRouter-Strecke `route=ferry`, wird sie verworfen und mit gedrehtem Wegpunkt neu
  geplant. Brücken bleiben erlaubt. Waldflächen als Polygone (`landuse=forest`, `natural=wood`) werden nicht abgefragt, weil
     `map_to_area` auf dem öffentlichen Server zu langsam ist; Wald- und Forstwege sind fast immer `track`/`path`.
- **Distanz ±2,5 %** (vorher ±7 %): bis zu sechs Anfragen je Variante; nach der ersten Antwort proportional, sobald
  eine zu kurze und eine zu lange Antwort vorliegen, per Sekantenverfahren dazwischen. Offene Ziele (Richtung) werden
  bewusst etwas zu lang geplant und **exakt** auf die Wunschdistanz gekürzt. Strecken zum festen Ziel, deren
  Luftlinie schon länger ist, bleiben unverkürzbar (Hinweis in der Anzeige).
- **Richtungspfeile:** etwa alle 90 Bildpunkte (zoomabhängig, höchstens 80) auf der gewählten Route, gedreht nach der
  Fahrtrichtung des Abschnitts; die Karte dreht sich nicht, daher genügt die Richtung über Grund.
- **Frei planen:** eigener Bildschirm, umschaltbar mit „Automatisch“. Werkzeuge *Punkte* (Antippen, Doppeltipp-Zoom
  aus, damit kein Punkt doppelt entsteht) und *Zeichnen* (Karte steht still; der Strich wird vereinfacht und mit
  höchstens 16 Wegpunkten geroutet). Jeder Abschnitt wird mit Sportart und Wegearten auf OSM-Wege gelegt, Höhen über
  Valhalla `/height`. Rückgängig entfernt den letzten Abschnitt, „Rundweg schließen“ routet zum Start. Gespeichert
  als `RouteShape.drawn` mit `username` wie alle Routen.

Tests: `routes_test.dart` (Gruppen „Wegarten, Pfeile, Zeichnen“ und „Planer mit Wegarten und exakter Distanz“,
u. a. nichtlinearer Test-Router auf ±2,5 %), `routing_service_test.dart` (Wegarten an beide Router, Overpass),
`route_planner_screen_test.dart` (Ansichtsmodus beim Antippen, Wegarten, frei planen bis zum Speichern).

## 2026-11-22 – Routenplaner: Start und Ziel per Adresszeile

Auftrag des Nutzers: Start und Ziel individuell als Adresse eingeben.

- **Dienste ohne Schlüssel:** Photon (`photon.komoot.io`, OSM-Daten) für Vorschläge beim Tippen – erst nach 450 ms
  Pause und ab drei Zeichen, höchstens eine Anfrage je 600 ms, nach Nähe sortiert (Start bzw. Kartenmitte).
  Nominatim (`nominatim.openstreetmap.org`) nur bei ausdrücklicher Suche (Eingabetaste) und nur, wenn Photon nichts
  liefert oder ausfällt: Die Nutzungsregeln der OSM Foundation verbieten Vorschläge beim Tippen und erlauben höchstens
  eine Anfrage je Sekunde. Ergebnisse werden zwischengespeichert; Koordinaten („52.52, 13.40“) gehen ohne Anfrage.
- **Ausdrückliche Eingabe:** Eine gewählte Adresse setzt den Punkt auch über vorhandenen Vorschlägen (wie langes
  Drücken) und verwirft sie; ein Pin oder der Standort leert das Adressfeld wieder.
- **Frei planen:** Lupe in der Leiste – ohne Start wird die Adresse zum Start, sonst wird die Route auf Wegen bis zu
  ihr verlängert.

Tests: `routes_test.dart` (Gruppe „Adresssuche“: Photon, Nominatim, Koordinaten), `routing_service_test.dart`
(Photon zuerst, Nominatim nur ausdrücklich, Zwischenspeicher), `route_planner_screen_test.dart` (Start mit
Vorschlägen, Ziel per Eingabetaste, Planen).

## 2026-11-22 – Routenplaner: Vollbild-Karte, Favoriten, „Gravel“, Spazieren

Auftrag des Nutzers: Karte beim Antippen im Vollbild, Orte als Favoriten, „Gravel“ statt „Gravel/Allround“,
Disziplin „Spazieren“ (Gassi mit dem Hund).

- **Antippen = Vollbild, langes Drücken = Punkt.** Damit ändert sich die Belegung aus #96: Ein Tipp auf die kleine
  Karte setzt keinen Punkt mehr, sondern öffnet `FullscreenRouteMap` (Vorschläge mit Pfeilen, Auswahl unten, langes
  Drücken setzt den Punkt und plant neu). Punkte setzen weiterhin: langes Drücken, Adresszeile, Standort und
  „Startpunkt ändern“ (danach setzt ein Tipp den Punkt). Die Detailseite öffnet ihre Karte ebenso im Vollbild. Beim
  freien Planen bleibt Tippen = Wegpunkt, die Karte füllt dort ohnehin den Bildschirm.
- **Favoriten (`coach.favoritePlaces`)** mit `username` wie Routen; ein fremder Stand wird weder angezeigt noch
  überschrieben. Speichern über den Stern in der Adresszeile (bei gesetztem Start bzw. Ziel, mit Namen), anzeigen beim
  Antippen der Adresszeile (leer: alle, sonst passende), verwalten unter *Routen › Favorisierte Orte*. Ein Favorit
  höchstens 30 m neben einem anderen ersetzt diesen, höchstens 40 Favoriten.
- **Spazieren als eigene Disziplin** statt über „Laufen“: Das Wegenetz ist dasselbe (Fußwege), aber Dauer (4,5 km/h,
  600 hm je Stunde statt Lauf-Pace), Grenzen (30 km, 1000 hm) und Wegwahl unterscheiden sich – ruhige Fußwege, Parks
  und Wohnstraßen, sanfte Steigungen (`use_hills` 0,2, `walkway_factor` 0,7, `use_living_streets` 0,9). Export als
  `walking` (GPX) bzw. Sportart 11 (FIT). Spaziergänge haben keine Einheiten im Ausdauerplan; „In Einheit übernehmen“
  bietet daher nur Tage an.
- **„Gravel“:** nur die Bezeichnung; der gespeicherte Rohwert bleibt `gravel`.

## 2026-11-22 – Routenplaner: Archiv, Kilometermarken, An Uhr senden

Auftrag des Nutzers: abgeschlossene, vorab geplante Routen im Archiv; Kilometermarken auf allen Routen; Frage, ob
sich Routen an die Uhr übertragen lassen.

- **Archiv:** Eine Route mit geplantem Tag gilt als abgeschlossen, sobald an diesem Tag eine Aktivität mit passender
  Sportart (Laufen, Rad, Gehen/Wandern für Spazieren) und 50–150 % der geplanten Distanz vorliegt (ohne Distanz
  genügt die Sportart; je Aktivität höchstens eine Route). Geprüft beim Öffnen von *Routen* und bei jedem Neuladen
  von *Training*. Von Hand: „Als erledigt markieren“ bzw. zurück in die Planung. Abgeschlossene Routen verschwinden
  aus „Route für heute“ und der offenen Liste, stehen im Archiv (`completedAt`, `activityID` in `coach.routes`) und
  zählen getrennt (60 offene, 200 im Archiv).
- **Kilometermarken:** auf der gewählten Route jeder Karte (Planer, Vollbild, Detail, frei planen), mindestens 56 px
  auseinander – sonst alle 2, 5, 10, 20 bzw. 50 km. Keine Marke direkt vor dem Ziel.
- **An Uhr senden:** über das Teilen-Menü an die App des Herstellers, mit kurzer Anleitung je Marke (Garmin als
  FIT-Kurs, alle anderen als GPX). Eine **direkte Übertragung zu Garmin** ginge über den inoffiziellen
  Garmin-Connect-Zugang der App (Kurs anlegen im `course-service`, wie „An Uhr senden“ beim Ausdauerplan); das
  Format dieser Schnittstelle ist nicht dokumentiert und ließ sich hier nicht prüfen. Deshalb vorerst nicht eingebaut.

## 2026-11-22 – Routenplaner: „Mein Standort“ auf jeder Karte

Auftrag des Nutzers: Symbol zum Finden des eigenen Standorts wie bei Google Maps. Knopf ◎ auf allen Routenkarten
(Planer, Vollbild, frei planen, Gebiete): bestimmt den Standort (Freigabe wie beim Start), zentriert die Karte
(mindestens Zoom 15) und zeigt einen blauen Punkt. Er setzt bewusst keinen Start – dafür gibt es „Aktueller
Standort“ bzw. langes Drücken. Der Punkt folgt nicht laufend (keine Ortung im Hintergrund, kein Akkuverbrauch);
erneutes Antippen aktualisiert ihn.

## 2026-11-22 – Echttest des Routenplaners gegen die öffentlichen Dienste

Mit Netzfreigabe für die Dienste lief `packages/coach_core/tool/live_check.dart` (von Hand, nicht in CI) gegen die
echten Server. Ergebnisse und Folgen:

- **Planer auf echten Wegen (Berlin, Valhalla):** Rundweg Laufen 10 km → 9,95 / 9,81 / 9,84 km, Rennrad 40 km →
  40,23 / 40,37 / 40,77 km, Spazieren Richtung 4 km → 3,99 km, Gravel zum Ziel 15 km → 15,01 / 14,69 / 15,15 km. Alle
  Varianten in ±2,5 %; 6–13 Anfragen und 11–25 s je Planung (Rate-Limit). Valhalla `/route` und `/height` für alle
  vier Disziplinen in Ordnung.
- **BRouter:** `mtb-zossebart` gibt es nicht (Status 500) → `mtb` (Gravel + Natur), `gravel` (Gravel), neu
  `trekking-noferries` für „Am Wasser“ beim Rad. Alle übrigen Profile lieferten Strecke mit Höhe.
- **Höhenmeter waren zu hoch:** Das Geländemodell misst auch Bäume, Gebäude und Brücken. Für 9 km durch Berlin
  ergab die Rohsumme 184 hm, die bisherige 3-m-Schwelle 132 hm. Jetzt werden die Höhen vorher über 200 m Strecke
  geglättet (gleitender Mittelwert) – 61 hm, realistisch. Echte Anstiege bleiben erhalten (Test: 100 hm auf 2 km).
- **Overpass** war aus der Cloud-Umgebung nicht erreichbar (overpass-api.de bricht ab, die Spiegel antworten nicht,
  auch nicht auf eine Minimalabfrage) – vom Handy aus erwartet erreichbar, aber hier ungeprüft. Neu: zwei öffentliche
  Spiegel (`overpass.kumi.systems`, `overpass.private.coffee`) als Ausweich; ein gestörter Server wird 3 Minuten
  übersprungen. Antwortet keiner, meldet die Quelle jetzt einen Fehler statt still nichts.
- **Photon** antwortete, aber nicht jedes Mal (Verbindungsabbruch). **Nominatim** antwortete (einmal mit 629, beim
  nächsten Mal korrekt). Neu: bei Verbindungsabbruch ein zweiter Versuch nach 0,6 s für alle Router und die
  Adresssuche (`sendWithRetry`).

## 2026-11-22 – Routenplaner: Controller, Vorschläge einzeln, Einheiten, Hinweise, Bearbeiten

Umsetzung der Verbesserungsliste, Punkte 2–6 und 14:

- **Controller (Punkt 14):** `RoutePlannerController` (Riverpod, im Container des Benutzers) hält Vorgaben, Punkte und
  Vorschläge; der Bildschirm zeigt nur an. Er liest den Routen-Speicher, ohne ihn zu beobachten – sonst entstünde
  er bei jedem Speichern neu und die Vorschläge wären weg.
- **Vorschläge einzeln (Punkt 2):** `RoutePlanner.generate(onRoute:)` meldet jeden fertigen Vorschlag sofort; die
  Planung braucht auf echten Wegen 11–25 s (siehe Echttest), der erste Vorschlag steht nach etwa einem Drittel.
- **Stand bleibt (Punkt 3):** Vorschläge, Start und Vorgaben überdauern das Verlassen des Planers; eine laufende
  Planung rechnet weiter. Geänderte Vorgaben verwerfen eine laufende Planung (Lauf-Zähler), „Zurücksetzen“ leert alles.
- **Aus der Einheit planen (Punkt 4):** In einer Einheit des Ausdauerplans „Route dazu planen“. Distanz: geplante
  Strecke, sonst Dauer × lockeres Tempo (Schwellen-Pace × 1,25, sonst 6:00 /km) bzw. 25 km/h beim Rad
  (`RouteForWorkout`); Laufen auf halbe, Rad auf ganze km gerundet. Gespeicherte Vorschläge tragen Tag, Einheit und
  Titel; zugeordnete Routen stehen in der Einheit.
- **Hinweis bei Wegarten (Punkt 5):** Sind die Wegdaten nicht erreichbar oder gibt es in der Nähe kaum passende Wege,
  meldet der Planer das über den Vorschlägen (`onNotice`), statt still ohne Wegart zu planen.
- **Bearbeiten beim freien Planen (Punkt 6):** `DrawnRoute` kennt Wegpunkte, Zwischenpunkte je Strich und einen
  Verlauf (50 Schritte). Punkt antippen wählt ihn (Fangbereich ≈ 28 px), dann verschieben oder löschen; langes
  Drücken auf die Linie fügt einen Punkt ein. Neu geroutet werden nur die betroffenen Abschnitte (verschieben: beide
  Nachbarn, löschen: die neue Verbindung, einfügen: beide Hälften); misslingt das, wird die Änderung zurückgenommen.
  „Rückgängig“ nimmt jede letzte Aktion zurück, auch „Zurücksetzen“.

## 2026-11-22 – Routenplaner: Gassi-Extras und „Route folgen“

Punkte 7 und 8 der Verbesserungsliste.

- **Hundewiese (nur Spazieren):** Wegart `dogPark`. Overpass sucht `leisure=dog_park`; die nächste Wiese wird fester
  Wegpunkt der Runde (`PreferenceSnapper.force`), unabhängig von den übrigen Wegarten. Ohne Treffer ein Hinweis.
  Wechselt man die Disziplin, fällt die Wegart weg.
- **Punkte unterwegs:** Trinkbrunnen (`amenity=drinking_water`) bei allen Disziplinen, beim Spazieren zusätzlich
  Hundewiesen und Kotbeutel (`vending=excrement_bags`, `amenity=dog_toilet`). Abgefragt im Rechteck der Route,
  angezeigt nur bis 120 m neben der Linie, je Art höchstens einer je 300 m. Fehlt Overpass, fehlen nur die Symbole.
- **Vorlagen (`coach.routeTemplates`, mit `username`):** Disziplin, Form (Rundweg/Richtung), Distanz, Wegarten und
  Start; Name vorgeschlagen aus Favorit bzw. Adresse („Gassi 3 km ab Zuhause“). Antippen unter *Routen* plant sofort.
- **Route folgen:** Fortschritt als Projektion auf die Linie, gesucht nur im Fenster 150 m zurück bis 1,5 km voraus –
  sonst gälte ein Rundweg am Start sofort als fertig. Abseits ab 50 m (Rad 60 m) nach zwei Messungen in Folge
  (GPS-Sprünge), dann starke Vibration; Ankunft, wenn weniger als 30 m fehlen. Ortung nur im Vordergrund
  (`geolocator`-Stream, alle 5 m), Bildschirm bleibt an. **Bewusst nicht:** Ortung bei gesperrtem Bildschirm – das
  bräuchte unter iOS `UIBackgroundModes: location` und „Immer“-Freigabe, unter Android einen Vordergrunddienst, und
  kostet Akku.

## 2026-11-23 – Routenplaner: Kurs direkt an Garmin Connect

Punkt 9 der Verbesserungsliste.

- **Weg:** derselbe inoffizielle Garmin-Connect-Zugang wie bei den Workouts (`GarminConnectSession.sendJson`), POST
  an `/course-service/course` im Format, das Garmin Connect beim Anlegen eines Kurses selbst schickt (`geoPoints` mit
  Strecke und Höhe, höchstens 1000 Punkte; Typ Laufen 1, Rad 2, Gehen 9). Antwort `courseId`.
- **Erneut senden** löscht den alten Kurs (`DELETE /course-service/course/<id>`) und legt ihn neu an; die ID steht in
  der Route (`garminCourseID`, optional im JSON – ältere Stände bleiben lesbar).
- **Ausweichen:** ohne Anmeldung, bei Ablehnung oder Fehler steht die Meldung im Blatt „An Uhr senden“, darunter der
  bisherige Weg über die FIT-Datei. Auf die Uhr kommt der Kurs weiterhin über „An Gerät senden“ in Garmin Connect;
  einen dokumentierten Weg, ihn direkt aufs Gerät zu schieben, gibt es nicht.

## 2026-11-23 – Routenplaner: Kartendienste mit Schlüssel über den Worker

Punkt 10 der Verbesserungsliste.

- **Schlüssel nur im Worker** (`ORS_API_KEY`, `MAPTILER_API_KEY`, `worker/src/maps.ts`), Zugriff nur mit Anmeldung
  (Haupt-, Gast- oder Sitzungs-Token). Beide optional: ohne sie bleibt alles wie bisher.
- **openrouteservice nur als Ausweich für Rundwege:** Liefern Valhalla und BRouter für eine Rundweg-Variante nichts
  (gestört oder kein Weg), fragt der Planer `round_trip` von openrouteservice, Länge bis zu dreimal proportional
  nachgeführt. Bewusst nicht als erster Weg: Die Wegpunkt-Planung kennt Wegarten, Hundewiese, Varianten und die
  ±2,5 %-Regel; `round_trip` trifft die Länge nur grob.
- **Kacheln von MapTiler** (Raster 256 px; `streets-v2`, `streets-v2-dark`, `outdoor-v2`): im Dunkelmodus der dunkle
  Stil. Die App fragt `/v1/health` einmal je Sitzung; meldet der Worker keine Kacheln, bleibt es bei OSM. Das Token
  geht als `Authorization`-Header nur an den eigenen Worker.
- **Zwischenspeicher:** Cloudflare-Cache-API (Rundwege 1 Tag, gerundeter Start ~10 m; Kacheln 7 Tage), damit die
  freien Kontingente reichen. In den Cache kommt die Antwort mit `public`, an die App geht sie mit `private`.
- **Tageslimit:** Rundwege je Person 200/Tag (KV `LEAGUE`, Schlüssel `maps:<Tag>:<Person>`), Kacheln ohne Limit.

## 2026-11-23 – Routenplaner: Wetter und Wind für den geplanten Tag

Punkt 11 der Verbesserungsliste.

- **Quelle:** Open-Meteo (frei, ohne Schlüssel, direkt aus der App), stündlich am Start der Route für den geplanten
  Tag (sonst heute); Vorhersage bis 15 Tage voraus, sonst nur ein Hinweis. Eine halbe Stunde im Speicher.
- **Spanne:** wählbare Startzeit (7, 10, 13, 16, 19 Uhr; heute die nächste) über die geschätzte Dauer: Temperatur
  von–bis, schlechtestes Wetter, höchste Regenwahrscheinlichkeit, mittlerer Wind (Richtung als Vektor gemittelt),
  Böen.
- **Wind je Hälfte:** Gegenwind-Anteil = Windstärke × cos(Fahrtrichtung − Herkunft des Winds), nach Streckenlänge
  gemittelt. Ab 10 km/h ein Hinweis. Rundweg mit mindestens 6 km/h mehr Gegenwind in der zweiten Hälfte:
  „Richtung umkehren“ (Gegenwind, solange man frisch ist). Umkehren behält ID und Planung; ein Garmin-Kurs passt
  dann nicht mehr und wird vergessen.
- **Bewusst nicht:** Wetter beim Planen selbst (Wind ändert die Vorschläge nicht – die Regeln für Distanz und Wegarten
  bleiben vorn).

