# Analyse: GYMKY im Vergleich mit AIronLudi

Stand 15.11.2026. Ziel: Was löst GYMKY, wo sind wir schon weiter, was lohnt sich nachzuziehen – ohne unnötige
Komplexität.

## 0. Quellenlage (ehrlich benannt)

- GYMKY wurde **nicht selbst installiert oder getestet**. Grundlage sind die App-Store-Einträge (DE/AT/MK), die
  Hersteller-Seite und Drittseiten (mwm.ai, futurezone.at). Store-Texte sind Werbung; Aussagen dazu gelten als
  „laut Store-Eintrag“.
- Nicht belegbar waren: Sperrbildschirm-Widgets oder Live-Aktivitäten von GYMKY, ihr Backend-Aufbau und ob es dort
  „Datenüberschneidungen“ gibt. Der Vergleich in Abschnitt 2 behandelt das deshalb als **Annahme**, nicht als Befund.
- Unsere Seite ist am Code belegt (Stand `main`, Commit `3b4cb7f`), mit Verweisen auf `docs/decisions.md`.

## 1. GYMKY – Kernfunktionen (laut Store-Eintrag)

| Bereich | GYMKY | Einordnung |
|---|---|---|
| Training | Pläne von Fitness-Creators oder eigene per Plan-Creator; Stretching, Mobility, Erholung; Statistiken und Verlauf; automatisches Tracken von Aktivitäten | Geschäftsmodell um **Creator-Inhalte** (Abo GYMKY PRO, ≈ 90 €/Jahr). Splits sind fertige Programme der Creator. Zur Übungsdatenbank und zur Offline-Fähigkeit macht der Store keine Angaben |
| Live-Tracking | Smartwatch-App für Apple Watch (watchOS 26.4+) und Android: „Workouts direkt von der Uhr steuern“ | Echte Begleit-App auf der Uhr – das haben wir nicht (siehe 3.4) |
| Ernährung | Ernährungstagebuch, Kalorientabelle, **Barcode-Scanner**, **KI-Food-Scanner** (Foto → kcal/Makros), Tagespläne und Rezepte vom Creator oder selbst erstellt | Klassischer Umfang: Erfassen einer Mahlzeit. Kein Hinweis auf Vorrats- oder Kühlschrank-Erkennung |
| Widgets / Live-Aktivitäten | nicht belegt | Annahme des Auftrags: Standard-Mitteilungen/Widgets |
| Teilen | Trainingspläne, Workouts und Rezepte per WhatsApp & Co.; **geteilte Rezepte öffnen sich direkt in GYMKY** | Rezept-Link mit Übernahme – das fehlt uns als eigener Linktyp (siehe 3.3) |
| Motivation | „Transformation-Video“ (Vorher/Nachher) | Marketing-Funktion, für uns nicht nötig |

## 2. Vergleich mit unserer App

### 2.1 Live-Aktivitäten und Widgets

| | GYMKY (Annahme) | AIronLudi (umgesetzt, PR #72) |
|---|---|---|
| Mehrere Bereiche gleichzeitig | nicht bekannt | **Vorrang der Gym-Einheit**: läuft die Einheit (erster Satz gemacht), endet „Mahlzeiten heute“ und startet danach mit neuem Stand. Dart entscheidet (`WidgetPublisher.showsMealsActivity`), iOS-`AppDelegate` und Android-Mitteilung sichern zusätzlich ab |
| Ansicht der Gym-Karte | – | `GymSettings.liveActivityLayout`: nur Pause, nur Übung/Sätze, beides (Standard) |
| Ernährung auf dem Sperrbildschirm | Push-Erinnerungen üblich | „Mahlzeiten heute“ als Live-Aktivität bzw. lautlose Android-Mitteilung; **Erinnerung ändert die Karte statt eine Mitteilung zu schicken** (`MealLiveReminder`, `staleDate`) |
| Doppelte Karten | – | behoben (Brücke merkt sich angestoßene Enden) |

**Bewertung:** Hier sind wir klar feiner steuerbar. Ehrliche Grenzen: Live-Aktivitäten ändern sich nicht von selbst
zeitgesteuert – ohne App-Start endet die Karte nach etwa acht Stunden, unter Android aktualisiert sich die Mitteilung
nur mit einem neuen Stand der App. Der Test auf echten Geräten steht noch aus (Migrationsplan, Abschnitt 8).

### 2.2 KI-Ernährung und Vorräte

| | GYMKY | AIronLudi |
|---|---|---|
| Foto einer Mahlzeit | KI-Food-Scanner | vorhanden (`MealPhoto`: 1280 px, ohne EXIF/GPS; KI nur über den Worker) |
| Barcode | vorhanden | vorhanden (`mobile_scanner`, Open Food Facts, „Produkt unbekannt“ → Etikett fotografieren) |
| Nach Gramm / gegessene Menge | Rezepte selbst erstellen | Mahlzeit-Editor mit Positionen, BLS-Portionen, „gegessene Menge anpassen“, eigene Rezepte/Meal-Prep |
| Vorrat → Rezepte | nicht bekannt | **Kühlschrank-Foto** (`PantryRecipes`): Erkennung, Abgleich mit Einkaufsliste, höchstens zwei kleine fehlende Standardzutaten je Gericht, Rückfragen „Ist noch Butter da?“ (höchstens vier), Antworten wirken sofort ohne neue KI-Anfrage |

**Bewertung:** Beim Erfassen sind beide gleichauf; beim Vorrat sind wir weiter. Ein offener Punkt verhindert den
Nutzen heute: **Die Worker-Aufgabe `pantry_recipes` fehlt noch in Coach-App** (`docs/worker-pantry-recipes.md`).
Bis dahin meldet die App den Fehler des Workers. Das ist die wichtigste offene Aufgabe aus diesem Vergleich.

### 2.3 Datensicherheit und mehrere Benutzer

| | GYMKY (Annahme) | AIronLudi (umgesetzt, PR #73) |
|---|---|---|
| Speicherort | Cloud-Konto, Server-Backend | **lokal zuerst**; KI nur über den eigenen Cloudflare Worker, Datenschutzmodus „reduziert“ als Standard |
| Mehrere Personen | ein Konto je Gerät/Login | bis zu 20 Benutzer je Gerät, **Trennung über den Speicherort**: eigene Datenbankdatei, eigene Schlüssel (`u.<id>.…`), eigene Ordner, eigener Provider-Container; Wechsel verwirft den gesamten Zustand |
| Kennung | – | feste UUID; Benutzername eindeutig nach `AccountRules`, Anzeigename änderbar |

**Bewertung:** Lokal ist die Trennung strukturell sicher – keine Abfrage kann die Datei eines anderen erreichen,
eine vergessene `WHERE username = …`-Bedingung ist gar nicht möglich. Das ist robuster als ein Filter je Tabelle.

Zur Aussage „100 % getrennt, auch remote“ zwei Einschränkungen, die man kennen sollte:

1. **Remote hängt am Worker.** Die App gibt jedem Benutzer ein eigenes App-Token und eine eigene Konto-Sitzung. Ob der
   Worker (Coach-App, nicht in diesem Repo) serverseitig Konto-, Social-, Liga- und Kochpartner-Daten wirklich je Konto
   trennt, ist hier nicht prüfbar und sollte dort mit Tests belegt werden (siehe 3.2).
2. **Bewusst gerätebezogen** bleiben Apple Health / Health Connect, System-Wecker (AlarmKit) und die Anzeige der
   Widgets (zeigen den aktiven Benutzer). Health ist für neue Benutzer ausgeschaltet. Das ist kein Leck, aber auch
   keine absolute Trennung – auf einem gemeinsam genutzten Gerät sieht man auf dem Sperrbildschirm den aktiven
   Benutzer.

Dass GYMKY Daten vermischt, ist nicht belegt; der Vorteil unserer App liegt darin, dass die Trennung **nachweisbar**
ist (Aufbau plus Tests `user_directory_test.dart`, `user_session_test.dart`), nicht in einer Vermutung über andere.

## 3. Empfehlungen

Grundsatz: Wir bauen kein zweites GYMKY (kein Creator-Marktplatz, kein eigenes Cloud-Backend für Nutzerdaten).
Unsere Stärke sind deterministische Regeln, lokale Daten und ein fein steuerbarer Sperrbildschirm. Die Liste ist nach
Nutzen je Aufwand sortiert.

### 3.1 Worker-Aufgabe `pantry_recipes` fertigstellen (hoch, klein)

In Coach-App nach dem Vertrag in `docs/worker-pantry-recipes.md`, an einen Anbieter mit Bildeingabe. Ohne sie ist
unser stärkstes Unterscheidungsmerkmal in der Ernährung nicht nutzbar.

### 3.2 Remote-Trennung mit Tests absichern (hoch, klein bis mittel)

Im Worker je Endpunkt (`v1/account/*`, `v1/social/*`, `v1/game/*`, `v1/league/*`, Kochpartner, geteilte Mahlzeiten)
einen Test „Konto A kann Daten von Konto B weder lesen noch schreiben“. Dazu: KV-/D1-Schlüssel immer mit der
Konto-Kennung aus dem Token bilden, nie aus Angaben im Request. Geteilte Inhalte (Mahlzeit, Kochpartner) bleiben
bewusst über Codes erreichbar – das ist Teilen, keine Überschneidung; Codes kurzlebig und nicht erratbar halten.
In der App: keine Änderung nötig, der Aufbau mit Container je Benutzer reicht.

### 3.3 Rezept teilen als Link (mittel, klein)

GYMKY öffnet geteilte Rezepte direkt in der App. Wir haben das für Trainingspläne (`coach://routine/<base64url>`,
ohne Server) und Mahlzeiten (`coach://meal/<code>`). Ein `coach://recipe/<base64url(JSON)>` nach demselben Muster wie
`RoutineLink` (kurzes JSON, Werte begrenzt, neue Kennungen beim Übernehmen, Nährwerte nach denselben
Plausibilitätsregeln prüfen) schließt die Lücke ohne Backend und ohne Benutzerbezug. Eintrag in `docs/decisions.md`
nötig, da ohne Swift-Gegenstück.

### 3.4 Sperrbildschirm: Regeln statt Schalter-Wildwuchs (mittel, klein)

Die Vorrang-Logik liegt heute verteilt (`WidgetPublisher`, `RootShell`, `AppDelegate`, Android). Empfehlung: eine
reine Funktion in `coach_core`, z. B. `LockScreenPlan decide(state, settings, now)`, die genau eine Karte samt Ansicht
und `staleDate` liefert; die Plattformen führen nur aus. Vorteile: ein Ort für neue Bereiche (z. B. Ausdauer-Einheit),
mit `dart test` vollständig prüfbar, und die Absicherungen in `AppDelegate`/Android bleiben reines Sicherheitsnetz.
Keine weiteren Ansichten oder Schalter hinzufügen, bevor der Gerätetest durch ist.

### 3.5 Uhr-Steuerung der Gym-Einheit (niedrig, groß)

GYMKYs Smartwatch-App ist der einzige Punkt, an dem sie spürbar vorn liegen. Eine watchOS-/Wear-OS-App wäre nativ, ohne
Mac nur per CI baubar und auf der Uhr kaum über SideStore zu testen. Erst nach der Umstellung auf die Flutter-App
erwägen; bis dahin decken Live-Aktivität, Android-Mitteilung und die Garmin-Workouts den Bedarf ab.

### 3.6 Bewusst nicht übernehmen

- **Creator-Pläne und Abo:** passt nicht zu „Regeln entscheiden, KI formuliert“ und bräuchte ein Inhalte-Backend.
- **Eigenes Cloud-Konto für alle Nutzerdaten:** würde die einfache, sichere lokale Trennung gegen ein
  Mandanten-Backend tauschen, das bei jeder Abfrage richtig gefiltert sein muss. Der Umzug läuft weiter über
  `AppBackup` (je Benutzer eine eigene Sicherungsdatei).
- **Benutzername an die KI:** bringt keine Trennung, widerspricht dem Datenschutzmodus (siehe `docs/decisions.md`,
  15.11.2026).

## Quellen

- App Store DE: https://apps.apple.com/DE/app/id6470682855
- App Store AT (englisch): https://apps.apple.com/at/app/gymky-fitness-ai-nutrition/id6470682855?l=en-GB
- App Store MK: https://apps.apple.com/mk/app/gymky-fitness-ai-nutrition/id6470682855
- Hersteller: https://gymky.com/en/support
- mwm.ai (inoffiziell): https://mwm.ai/apps/gymky-fitness-ai-nutrition/6470682855
- futurezone.at, KI-Ernährungstracker: https://futurezone.at/apps/beste-ki-ernaehrung-tracker-android-ios-mahlzeit-kalorien-abnehmen-muskeln/403098613
