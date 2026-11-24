# Design-Konzept: ruhig, klar, nichts geht verloren

Stand 24.11.2026. Grundlage: [Roast](roast-2026-11-24.md) und die Bilder in [`screenshots/`](screenshots.md).
Leitsatz: **Ein Blick am Morgen reicht. Alles andere ist einen Tap entfernt – aber immer am selben Ort.**

---

## 1. Prinzipien

1. **Heute zuerst.** „Heute“ beantwortet drei Fragen und nicht mehr: *Wie erholt bin ich? Was steht an? Was esse ich?*
2. **Ein Heimatort je Funktion.** Jede Funktion und jede Einstellung hat genau einen Ort. Andere Stellen dürfen
   verlinken („Mehr dazu in Plan › Ausdauer“), aber nicht duplizieren.
3. **Progressive Offenlegung.** Standard: Zahl + ein Satz. Ein Tap: Verlauf und Begründung. Zwei Taps: Experten-Werte,
   Rohdaten, Regeln.
4. **Farbe heißt etwas.** Rot nur für „Achtung, handeln“. Grün nur für „gut“. Alles Neutrale ist grau oder
   Akzentblau. Zähler (Abzeichen) sind neutral, nicht rot.
5. **Regeln entscheiden, KI formuliert** – auch optisch: Regel-Ergebnisse stehen oben und stabil; KI-Texte sind als
   solche markiert und stehen darunter.
6. **Jeder Hinweis hat einen Knopf.** Kein Text „Verbinde in den Einstellungen …“ ohne den Weg dorthin.

---

## 2. Informationsarchitektur

### 2.1 Empfehlung: fünf Reiter

| Reiter | Frage | Inhalt (Heimatort) |
|---|---|---|
| **Heute** | Was ist jetzt dran? | Morgen-Karte (Erholung, Einheit, Essen), Jetzt dran aus **allen** Plänen, KI-Notiz, Hinweise |
| **Plan** | Was kommt? | Woche (Wochen-/Saisonplan **und** Ausdauerplan in einer Ansicht), Ausdauerplan-Einstellungen, Gym-Routinen, Routen, Fuel Planner (je Einheit), An Uhr senden |
| **Verlauf** | Was war? | Aktivitäten (nach Wochen gruppiert), Trends, Erholung, Herzfrequenz, Schlaf, Fitness & Form, Wochenbericht, Gesundheit, Freunde-Feed als Filter |
| **Ernährung** | Was esse ich? | Tag, Erfassen, Woche, Gewicht, Rezepte, Kühlschrank, Fuel-Vorrat und Produkte |
| **Ich** | Wer bin ich, was habe ich verbunden? | Profil & Ziele, Datenquellen, Freunde & Liga, Motivation/Begleiter, KI (Empfehlungen-Archiv, Chat, Export/Import), Einstellungen, Erweitert |

Gym als **Live-Einheit** startet von „Heute“ (Jetzt dran) und aus „Plan“; die laufende Einheit bleibt als schwebende
Leiste über allen Reitern (wie heute die Live-Aktivität).

**Warum fünf statt vier?** Heute steckt der „Training“-Reiter voller Dinge der Vergangenheit (Trends, Erholung,
Wochenbericht) **und** der Zukunft (Plan, Ausdauerplan, Routen). Diese Trennung nach Zeit (*war · ist · kommt*) ist für
Ausdauersportler intuitiv und löst den Plan-Wildwuchs (B-01, B-04). „Ich“ gibt Einstellungen und Social einen
sichtbaren Ort (B-03).

**Alternative mit vier Reitern** (falls du bei vier bleiben willst): Heute · Plan · Verlauf · Ernährung; „Ich“ als
Avatar-Knopf oben rechts auf jedem Reiter (Einstellungen, Freunde, KI). Nachteil: Social bleibt versteckt.

### 2.2 Baum alt → neu

| Alt | Neu |
|---|---|
| Heute | **Heute** |
| Heute › Coach fragen (Chat) | Heute › KI-Notiz › „Fragen“ **und** Ich › KI › Chat |
| Heute › Heute anpassen | Heute › „Anpassen“ (unten) |
| Heute › Einstellungen (Zahnrad) | **Ich** › Einstellungen |
| Heute › AI-Empfehlungen | Heute zeigt die wichtigste; Archiv in Ich › KI › Empfehlungen |
| Heute › Woche | Plan › Woche |
| Heute › Gesundheit | Verlauf › Gesundheit (Morgen-Karte verlinkt) |
| Aktivitäten (Alle/Meine/Freunde) | **Verlauf** › Aktivitäten (Filter Meine/Freunde bleiben) |
| Aktivitäten › Freunde (Symbol) | Ich › Freunde & Liga; Feed bleibt als Filter in Verlauf |
| Freunde › Spiel/Liga | Ich › Freunde & Liga › Liga |
| Training › Plan (Saison/Meine Woche) | **Plan** › Woche |
| Training › Ausdauerplan | Plan › Woche (Einheiten) + Plan › Ausdauerplan (Einrichtung, Anpassungen, Schwellen) |
| Training › Gym | Plan › Gym (Routinen, Bibliothek); Verlauf › Kraft (Verlauf, Auswertung); Start aus Heute |
| Training › Gesundheit, Body Battery, Morning Report, Mobility | Verlauf › Gesundheit (Morning Report auch als Karte auf Heute bis 12 Uhr) |
| Training › Erholung, Herzfrequenz, Trends, Schlaf-Coach, Fitness & Form, Wochenbericht | Verlauf › (gleiche Seiten) |
| Training › Routen, Routenplaner, Archiv, Gebiete | Plan › Routen; je Einheit „Route“ |
| Training › Disziplinen, Almere/Marathon | Verlauf › Sportarten; Saisonziele unter Plan › Saison |
| Ernährung › Fuel Planner | Plan › Einheit › Verpflegung **und** Ernährung › Fuel (frei planen, Produkte, Vorrat) |
| Ernährung › alles andere | **Ernährung** (unverändert, nur Reihenfolge) |
| Einstellungen › Konto, Benutzer | Ich (oben) |
| Einstellungen › Profil, Ziele & Prioritäten | Ich › Profil & Ziele |
| Einstellungen › Datenquellen, Garmin, WHOOP, Health | Ich › Datenquellen (ein Bildschirm mit Status je Quelle) |
| Einstellungen › KI-Worker, Garmin Personal API, Diagnose, Rohantworten, Demo | Ich › Erweitert |
| Einstellungen › Sperrbildschirm, Erinnerungen | Ich › Mitteilungen & Sperrbildschirm (ein Ort) |
| Einstellungen › Ernährung | Ernährung › Einstellungen (Heimat); Ich verlinkt |
| Einstellungen › Training und Fitness (Gym, Ausdauer, Übungen) | Plan › Einstellungen (Heimat); Ich verlinkt |
| Einstellungen › Datensicherung, Export/Import | Ich › Daten & Sicherung |
| Onboarding | unverändert, am Ende „So ist die App aufgebaut“ (3 Karten) |

### 2.3 Was auf „Heute“ gehört – und was nicht

**Immer:** Morgen-Karte (3 Ringe: Erholung, Belastung, Essen), *Jetzt dran* (alle Pläne), eine KI-Notiz (eingeklappt).
**Situativ:** Morning Report (bis 12 Uhr), Nach dem Training (nach einer Einheit), Wochen-Check-in (sonntags), Hinweise mit
Knopf. **Nicht mehr auf Heute:** Wochenübersicht (→ Plan), Motivation/Begleiter (→ Ich, als kleines Abzeichen im Kopf),
Belastungs-Detailkarte (→ Tap auf Ring).

---

## 3. Designsystem-Regeln

### 3.1 Plattform-Linie: Empfehlung

**Plattformneutral mit iOS-Grammatik** – also die heutige Richtung, aber ehrlich:

- Eine Linie für beide Plattformen (du pflegst eine App, nicht zwei). Navigation, Listen und große Titel folgen iOS,
  weil das iPhone dein Hauptgerät ist.
- Plattformgerecht nur dort, wo Nutzer es *fühlen*: Schalter, Zurück-Geste, Datum-/Zeitwähler, Teilen-Menü, Haptik,
  System-Schrift (SF Pro bzw. Roboto). Das ist heute schon fast so (`SwitchListTile.adaptive`).
- **Glas dosieren** (Frage F-3): Unschärfe nur für Tab-Leiste, Kopfzeile beim Scrollen und Sheets. Karten deckend
  (`surface` + 4 % Tönung), dadurch besserer Kontrast, weniger GPU-Last auf kleinen Android-Geräten (B-17), ruhigeres Bild.
- Ein Symbolsatz: **Material Symbols Rounded** (passt zu SF Symbols, frei, eine Strichstärke) statt Cupertino + Material
  gemischt (B-27).

### 3.2 Tokens (neu: `lib/ui/tokens.dart`)

**Abstände** – nur diese Werte: `4 · 8 · 12 · 16 · 24 · 32`. Seitenrand 16, Abstand zwischen Karten 12, innerhalb einer
Karte 12/16.

**Typografie** – nur über `Theme.of(context).textTheme`, keine `fontSize`-Literale in `lib/features`:

| Rolle | iOS-Größe | Verwendung |
|---|---|---|
| `largeTitle` | 34 bold | Reiter-Titel |
| `title` | 22 semibold | Seitentitel, Kennzahl groß |
| `headline` | 17 semibold | Kartentitel |
| `body` | 17 | Fließtext, Zeilen |
| `callout` | 15 | Unterzeilen |
| `footnote` | 13 | Fußtexte, Quellen |
| `caption` | 12 | Achsen, Abzeichen – **Untergrenze**, nichts darunter (heute 9–11 pt an 49 Stellen) |
| `kpi` | 28–48, Ziffern gleich breit | Ringe, Kennzahlen |

**Farben** – semantisch, nie `Colors.*` in `lib/features`:

| Token | Bedeutung | hell / dunkel |
|---|---|---|
| `good` | gut, erledigt | Systemgrün |
| `caution` | eingeschränkt, Hinweis | Systemorange |
| `alert` | handeln (Pause, Fehler, Löschen) | Systemrot |
| `info` / `accent` | Interaktion, Neutral-Hervorhebung | Systemblau |
| `muted` | Nebeninfo | `onSurfaceVariant`, Kontrast ≥ 4,5 : 1 |
| Sportfarben | Laufen grün, Rad orange, Kraft violett, Schwimmen blau, sonst grau | wie heute in den Diagrammen |
| Makros | Protein, Kohlenhydrate, Fett, Wasser – je eine feste Farbe | |

**Ampel**: `good`/`caution`/`alert` – nie für Mengen ohne Bewertung (B-10: Strain 0,0 ist neutral).

### 3.3 Bausteine

- **Karte** (`AppCard`): Titelzeile (Symbol 20 + `headline` + optional Wert rechts), Inhalt, optional eine Aktionszeile.
  Max. eine Primäraktion je Karte.
- **Kennzahl-Kachel** (`MetricTile`): *Beschriftung oben, Wert groß, Einordnung unten.* Heute ist es auf „Training“
  gemischt: mal Aktion („Erstellen“, „Einheit starten“), mal Wert („56 ms“), mal abgeschnittener Satz
  („Sehr hohe Belast…“). Regel: Kacheln zeigen **Werte**; Aktionen sind Knöpfe.
- **Listenzeile**: Symbol links nur, wenn alle Zeilen der Gruppe eins haben. Chevron nur bei Navigation.
- **Zustände**: Jeder datengetriebene Baustein hat *Laden* (Skelett, kein Spinner mitten im Text), *Leer* (ein Satz +
  ein Knopf), *Fehler* (was ist passiert + was kann ich tun + „Erneut versuchen“).
- **Abzeichen**: neutral (Akzentfarbe), rot nur bei Fehlern.

### 3.4 Barrierefreiheit (Pflicht für jeden neuen Baustein)

- Tap-Flächen ≥ 44 × 44 pt (heute: Häkchen-Kästchen in „Jetzt dran“ und auf „Heute“ deutlich kleiner, Bild `01-heute.png`).
- Text skaliert bis 200 % ohne Abschneiden in Karten: Kacheln brechen auf eine Spalte um (heute abgeschnitten, Bilder
  `iphone15/grossschrift/03-training.png`).
- Ringe und Balken haben `Semantics(label: 'Erholung 46 Prozent, eingeschränkt')` – heute vorhanden für Strain,
  prüfen für alle.
- Kontrast: Fußtexte auf Glas ≥ 4,5 : 1 (deckende Karten lösen das).

---

## 4. Einstellungen radikal ordnen

Heute: 13 Dateien, Bereiche Allgemein · Training und Fitness · Ernährung · Sperrbildschirm · Health und Erholung ·
KI und Automatisierung · Technik, plus Konto, Profil, Benutzer oben (Bild `12-einstellungen-lang.png`). Die Gliederung
ist ordentlich – das Problem sind Doppelungen (B-13) und Technik auf Augenhöhe (B-14).

**Neu, unter „Ich“:**

1. **Profil & Ziele** (Sportarten, Ziel, Körperdaten, Prioritäten, Saison)
2. **Datenquellen** (Garmin, WHOOP, Health – je eine Zeile mit Status-Punkt; Vorrang je Datenart darunter)
3. **Mitteilungen & Sperrbildschirm** (alle Erinnerungen und Live-Aktivitäten an einem Ort)
4. **Datenschutz & KI** (Datenschutzmodus, KI an/aus, Quellen bei Empfehlungen zeigen)
5. **Daten & Sicherung** (Sicherung, Export/Import für externe KI, Umzug)
6. **Darstellung** (hell/dunkel, Einheiten)
7. **Erweitert** (eingeklappt): KI-Worker-URL, Garmin Personal API, Diagnosen, Rohantworten, Integrationsmatrix,
   Demo-Modus (F-1)

**Automatisch statt fragen:** Worker-URL aus dem Einladungslink; primäres Gerät aus der zuletzt synchronisierten
Quelle vorschlagen; Plattformname (Apple Health vs. Health Connect) nie fragen.

Ernährungs- und Trainings-Einstellungen bleiben in ihren Reitern (Heimatort) und sind von „Ich“ aus verlinkt.

---

## 5. Glossar (eine Schreibweise je Sache)

| Statt | Immer |
|---|---|
| AI, KI | **KI** |
| Strain, Belastung, Daily Strain | **Belastung** (Skala 0–21); bei WHOOP „WHOOP-Strain“ |
| Recovery, Readiness, Erholung, Tagesform | **Erholung** (Quelle in der Unterzeile) |
| Einheit, Training, Workout, Session | **Einheit** (geplant), **Aktivität** (aufgezeichnet) |
| Gym, Krafttraining, Kraft | **Kraft** (Sportart), **Gym** nur für die Live-Einheit |
| Fuel Planner, Verpflegung | **Verpflegung** (Titel), „Fuel Planner“ als Untertitel bis zur Gewöhnung |
| Morning Report | **Morgenbericht** |

---

## 6. Vorher / Nachher der Kernscreens

Die Nachher-Skizzen sind bewusst textuell (kein Figma verbunden). Als nächster Schritt rendert der Prüfstand sie als
Flutter-Prototypen (PR 7 im Umsetzungsplan), damit du sie auf GitHub neben den Vorher-Bildern siehst.

### 6.1 Heute

**Vorher** (`iphone15/hell/01-heute-lang.png`): Datenquellen-Hinweis ohne Knopf · 3 Ringe (Strain „0,0“ rot) ·
Jetzt dran mit Begründung, zwei Unterzeilen, „Verschieben“, „Diese Woche auslassen“ · AI-Empfehlungen ·
Woche · „Heute anpassen“. Kein Essen.

**Nachher:**

```
Heute                                    Di 24.11.   (Avatar → Ich)
┌──────────────────────────────────────────────────────────┐
│  ◔ Erholung 46 %     ◔ Belastung 0 / ~8     ◔ Essen 1554 │
│  eingeschränkt       Plan heute eher viel    kcal übrig   │
│  „HRV unter Baseline, Schlaf 6,2 h“            Protein 55 g│
└──────────────────────────────────────────────────────────┘
JETZT DRAN
┌──────────────────────────────────────────────────────────┐
│ 🏃 Lockerer Lauf · 45 min (statt 80)          [Starten ▸] │
│ Route · Verpflegung · An Uhr senden            Mehr ⌄     │
└──────────────────────────────────────────────────────────┘
┌ Mobility · 10 min ─────────────────────────────── ☐ ┐
NÄCHSTE MAHLZEIT
┌ Mittagessen: „Wie gestern“ 603 kcal     [+]  Andere ▸ ┐
KI-NOTIZ (eingeklappt, eine Zeile)                    ▸
```

### 6.2 Plan (neu, ersetzt Training › Plan/Ausdauerplan/Routen)

**Vorher:** drei getrennte Seiten (`30-plan-woche`, `31-ausdauerplan`, `40-routen`), Ausdauerplan ohne Bezug zur
Woche. **Nachher:** eine Woche, Tage als Zeilen, je Tag alle Einheiten (Quelle als kleines Etikett „Ausdauerplan“/
„Wochenplan“/„Routine“); Tippen öffnet die Einheit mit *Anleitung · Route · Verpflegung · An Uhr senden*. Darunter
„Ausdauerplan“, „Gym-Routinen“, „Routen“ als Zeilen zu den Einstellungen.

### 6.3 Verlauf (ersetzt Aktivitäten + Rückblick-Teil von Training)

**Vorher** (`02-aktivitaeten-lang.png`): flache Liste über Wochen hinweg, oben eine Werbekarte für Freunde.
**Nachher:** Kopf mit 4 Kacheln (Woche: Zeit, Belastung, Kraft-Sätze, Distanz) → Abschnitte je Woche mit Summe →
Aktivitäten. Filter: Alle · Meine · Freunde · Sportart. Unten „Auswertungen“: Trends, Erholung, Herzfrequenz, Schlaf,
Fitness & Form, Wochenbericht, Gesundheit.

### 6.4 Ernährung

**Vorher** (`04-ernaehrung-lang.png`): Wochen-Check-in oben, Tagesring, Wasser, „Was esse ich jetzt?“, Schnell-Zeile,
Mahlzeiten, Nährstoffe, dann 6 Navigationszeilen. Grundsätzlich gut. **Nachher:** Tagesring + Makros oben, darunter
Mahlzeiten mit „+“ je Mahlzeit, Wasser als kompakte Zeile; Wochen-Check-in nur sonntags/montags als Karte;
Navigationszeilen als zwei Gruppen „Planen“ (Woche, Rezepte, Verpflegung) und „Verlauf“ (Gewicht).

### 6.5 Training-Übersicht → entfällt als Reiter

**Vorher** (`03-training-lang.png`): Belastung heute, Wochenbalken, 11 Kacheln gemischter Art, Sportarten. **Nachher:**
Wochenbalken und Kacheln wandern nach *Verlauf*; „Belastung heute“ ist der Ring auf *Heute*.

### 6.6 KI

**Vorher** (`10-ki-empfehlungen-lang.png`): Titel „AI“, rote Zähler, 7 Empfehlungen als „Neu“, Muskelgruppen mit
Lauf-Symbol, KI-Funktionen gemischt mit Einstellungen. **Nachher:** Titel „KI“; oben die *eine* wichtigste Empfehlung
mit „Umsetzen / Später / Verwerfen“; darunter gruppiert nach Bereich (eingeklappt mit Zähler); Kraft-Empfehlungen mit
Hantel-Symbol; „Weitere KI-Funktionen“ als eigene Seite unter Ich › KI.

### 6.7 Einstellungen → Ich

Siehe Abschnitt 4.

---

## 7. Nachweis: Jede Funktion hat einen neuen Ort

| Funktion | Heute | Neu |
|---|---|---|
| Tagesampel / Erholung | Heute (Ringe), Training › Erholung | Heute (Ring), Verlauf › Erholung |
| Daily Strain | Heute, Training (Karte) | Heute (Ring) → Detail |
| Jetzt dran (Wochen-/Saisonplan) | Heute | Heute |
| Jetzt dran (Ausdauerplan) | **fehlt** | Heute (neu) |
| Verschieben, Auslassen, Nachholen | Heute, Plan | Heute (Mehr ⌄), Plan |
| Vorschläge zum Plan, Nächste Woche planen | Heute, Mitteilung | Heute (situativ), Plan |
| Morning Report | Heute (aus), Training › Gesundheit | Heute (bis 12 Uhr, an), Verlauf › Gesundheit |
| Nach dem Training | Heute (aus), Aktivität | Heute (situativ), Aktivität |
| Wochenrückblick, Wochenbericht | Heute, Training | Verlauf |
| Motivation, Begleiter, Serie, Abzeichen | Heute (aus), Einstellungen | Ich › Motivation; Serie als Abzeichen im Kopf von Heute |
| Hinweise | Heute (aus) | Heute (mit Knopf) |
| Saisonplan, Musterwoche, Saisonübersicht | Training › Plan | Plan › Woche, Plan › Saison |
| Meine Woche, Wochenplan-Editor, Nachtragen | Training › Plan | Plan › Woche |
| Ausdauerplan (Erstellen, Woche, Anpassungen, Schwellen, Ad-hoc, Export FIT/ZWO, Garmin-Abgleich) | Training › Ausdauerplan | Plan › Woche + Plan › Ausdauerplan |
| Gym Live-Einheit | Training › Gym, Schnellaktion | Heute (Starten), Plan › Gym, schwebende Leiste |
| Routinen, Bibliothek, eigene Übungen, Ausstattung | Training › Gym, Einstellungen | Plan › Gym |
| Gym-Verlauf, Auswertung, Muskelkarte | Training › Gym | Verlauf › Kraft |
| Gesundheit (Dashboard, Body Battery, Mobility, Mobility-Test) | Training, Heute | Verlauf › Gesundheit |
| Erholung, Herzfrequenz, Trends, Schlaf-Coach, Fitness & Form | Training | Verlauf |
| Disziplinseiten (CSS, FTP, Schwelle), Almere, Marathon | Training | Verlauf › Sportarten; Plan › Saison |
| Routen: Planer, Zeichnen, Detail, Folgen, Archiv, Gebiete, Wetter, An Uhr senden | Training › Routen, Ausdauerplan | Plan › Routen, je Einheit |
| Aktivitäten, Detail, Suche, Filter, Teilen | Aktivitäten | Verlauf |
| Freunde, Feed, Person, Kommentare, Beiträge | Aktivitäten (Symbol) | Verlauf (Filter Freunde), Ich › Freunde & Liga |
| Liga, Challenges, Spiel | Freunde › Spiel | Ich › Freunde & Liga |
| Konto, Anmelden, Passwort, Wiederherstellung, Einladungen | Einstellungen | Ich (oben) |
| Mehrere Benutzer | Einstellungen | Ich (oben) |
| Ernährung Tag, Ringe, Makros, Wasser, Mahlzeiten | Ernährung | Ernährung |
| Erfassen (Suche, Scan, Foto, Text, Nur kcal, Manuell) | Ernährung „+“, Schnellaktion, Widget | unverändert |
| Was esse ich jetzt? | Ernährung | Ernährung + Heute (nächste Mahlzeit) |
| Woche, Check-in, KI-Auswertung | Ernährung | Ernährung |
| Gewicht | Ernährung | Ernährung › Verlauf |
| Eigene Rezepte, Meal-Prep, Rezeptideen, Kochplan, Kühlschrank-Foto, Einkaufsliste, Kochpartner | Ernährung, AI | Ernährung › Planen |
| Fuel Planner (Plan, Szenario, Profil, Produkte, Vorrat, ins Tagebuch) | Ernährung, Ausdauerplan | Plan (je Einheit), Ernährung › Verpflegung |
| Geteilte Mahlzeit | Ernährung, Link | unverändert |
| KI-Empfehlungen, Analyse, Chat, Prompt-Bibliothek, Export/Import, Prüfen lassen | Heute › AI, Einstellungen, Meine Woche | Heute (wichtigste), Ich › KI |
| Quellen und Regeln, eigene Quellen | Einstellungen | Ich › Datenschutz & KI › Quellen |
| Datenquellen, Vorrang, Integrationsmatrix, Garmin, WHOOP, Health | Einstellungen | Ich › Datenquellen (Matrix unter Erweitert) |
| Sperrbildschirm, Live-Aktivitäten, Erinnerungen, Wecker | Einstellungen (3 Stellen) | Ich › Mitteilungen & Sperrbildschirm |
| Datenschutzmodus | Einstellungen › Allgemein | Ich › Datenschutz & KI |
| Urlaub/Pause | Einstellungen | Plan › Pause (Heimat), Ich verlinkt |
| Sicherung, Umzug, Android-Sicherung | Einstellungen, Onboarding | Ich › Daten & Sicherung, Onboarding |
| KI-Worker, Nutzung, Garmin Personal API, Diagnosen, Rohantworten | Einstellungen | Ich › Erweitert |
| Android-Link, SideStore-Quelle teilen | Einstellungen | Ich › Freunde & Liga › Einladen |
| Update-Hinweis Android | Banner | unverändert |
| Widgets, Schnellaktionen, Deep Links | System | unverändert (Ziele zeigen auf neue Orte, `coach://open/…` bleibt kompatibel) |
| Onboarding | Vollbild | unverändert + „So ist die App aufgebaut“ |
| Demo-Modus | toter Code | Ich › Erweitert (F-1) |

Kompatibilität: `AppRoute`-Rohwerte (`today`, `health`, `nutrition`, `logMeal`, `gym`, `startWorkout`, `ai`,
`aiAnalysis`) bleiben; nur `AppRoute.tab` zeigt auf die neuen Reiter. Einstellungsschlüssel `coach.*` ändern sich nicht;
`coach.todayDashboard` bekommt ein neues Modul `nutrition` (unbekannte Werte werden heute schon ignoriert – im PR
prüfen).
