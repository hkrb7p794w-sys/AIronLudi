# Umsetzungsplan

Kleine, einzeln mergebare PRs. Reihenfolge: erst schnelle Gewinne und Fehler, dann Designsystem, dann der Umbau der
Informationsarchitektur Bereich für Bereich. Nach deiner Freigabe gelten wieder die Regeln aus `CLAUDE.md` (eine PR je
Schritt, Tests, `flutter analyze` ohne Befund, Mergen bei grünem `check` und `apk`, bei `ios/` zusätzlich iOS-Build).

Jede PR aktualisiert den Prüfstand (`flutter test --tags screenshots --dart-define=SCREENSHOTS=true --update-goldens
test/screenshots`) für die betroffenen Screens, damit Vorher/Nachher im PR sichtbar ist.

**Freigabe nötig für:** den ganzen Plan; einzeln die Fragen F-1 bis F-6 im [Roast](roast-2026-11-24.md#fragen-an-dich-gebündelt).

---

## Stufe 1 – Fehler und schnelle Gewinne (je S, unabhängig voneinander)

| # | PR | Befunde | Akzeptanzkriterien |
|---|---|---|---|
| 1 | `fix(whoop): Scope offline, verständliche Fehler` | B-06 | `docs/einrichtung.md` nennt `offline`; `invalid_scope`, `invalid_client`, `redirect_uri_mismatch`, `access_denied` haben deutsche Texte mit Lösungsweg (Test je Code in `whoop_service_test.dart`); Fußzeile ohne Entwicklerpfad |
| 2 | `fix(ui): Überläufe bei großer Schrift und kleinem Android` | B-28 | Prüfstand ohne Einträge in `screenshots/layoutfehler.md` für Ernährung und Einrichtung; Widget-Test mit Textskalierung 1,3 auf 360 dp |
| 3 | `fix(today): Hinweis mit Knopf, Strain-Farbe` | B-10, B-11 | Hinweis hat „Quelle verbinden“ → Datenquellen und erscheint nur ohne Tageswerte der letzten 7 Tage; Ist-Belastung 0 ist neutral; Tests in `today_screen_test.dart` |
| 4 | `fix(coach): WHOOP-Skala in der Ampel` | B-09 | Readiness-Schwellen je Quelle; Testfälle WHOOP 30 → Pause, 50 → locker, Garmin unverändert (alle bestehenden `today-cases.json` grün) |
| 5 | `chore: .gitattributes, Windows-Tests, Doku-Stand` | B-18, B-20, B-21, B-24 | `npm run lint` und `flutter test` laufen unter Windows grün; Migrationsplan Abschnitt 8 ohne „in PR“; `CLAUDE.md` nennt `ironludi://` und „Clean Liquid Design“ |
| 6 | `perf(today): kleineres Ladefenster` | B-16 | Heute lädt ≤ 60 Tage Tageswerte und ≤ 42 Tage Aktivitäten; Ampel- und Strain-Tests unverändert grün |
| 7 | `fix(privacy): Exporte je Benutzer` | B-23 | Temp-Ordner je Benutzer, nach dem Teilen gelöscht; Test im `user_session_test.dart` |

## Stufe 2 – Designsystem (Grundlage für alles Weitere)

| # | PR | Befunde | Akzeptanzkriterien |
|---|---|---|---|
| 8 | `feat(ui): Tokens für Farbe, Typo, Abstand` | B-05 | `lib/ui/tokens.dart` (semantische Farben, Typo-Rollen, Abstände) mit Doku; Test `ui_tokens_test.dart`, der **neue** `Colors.*`, `Color(0x…)` und `fontSize:`-Literale in `lib/features` verbietet (Bestand als Liste erlaubt, die nur schrumpfen darf) |
| 9 | `refactor(ui): Bereich Heute und Ernährung auf Tokens` | B-05, B-12 | Bestandsliste schrumpft um diese Dateien; Prüfstand-Bilder ohne sichtbare Regression; „KI“ statt „AI“ |
| 10 | `refactor(ui): übrige Bereiche auf Tokens` | B-05 | Bestandsliste leer; alle Schriftgrößen ≥ 12 |
| 11 | `feat(ui): Karten deckend, Glas nur für Leisten und Sheets` (nach F-3) | B-17, B-27 | Kontrast Fußtext ≥ 4,5 : 1 in hell/dunkel (Test mit `meetsGuideline(textContrastGuideline)` auf den Kernscreens); ein Symbolsatz in der Tab-Leiste |
| 11b | `feat(ui): gemeinsame Diagramm-Achsen` | B-30 | Ein Baustein für Achsen (deutsches Zahlenformat, runde Marken, Textskalierung); alle `fl_chart`-Diagramme nutzen ihn; Prüfstand zeigt keine umgebrochenen Achsen |
| 12 | `test: Barrierefreiheit der Kernscreens` | 3.4 | `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline` für Heute, Ernährung, Live-Einheit grün |

## Stufe 3 – Inhalt und Flüsse

| # | PR | Befunde | Akzeptanzkriterien |
|---|---|---|---|
| 13 | `feat(today): Ausdauerplan unter „Jetzt dran“` | B-01 | Einheit des Ausdauerplans erscheint auf Heute; gleiche Sportart aus Wochenplan wird nicht doppelt gezeigt; Tests in coach_core (`today_focus_test.dart`) und Widget-Test |
| 14 | `feat(today): Ernährungsmodul` | B-02 | Neues `TodayModule.nutrition` (Standard an): übrige kcal, Protein, nächste Mahlzeit mit „+“; alte Werte von `coach.todayDashboard` bleiben lesbar (Test) |
| 15 | `feat(plan): Route, Verpflegung, An Uhr senden je Einheit` | B-04 | Wochen- und Saisonplan zeigen `RouteForSlotSection`/`FuelForSlotSection`; ein gemeinsames „An Uhr senden“-Sheet |
| 16 | `feat(coach): HRV-Regel für WHOOP und Health` | B-08 | 7-Tage-Schnitt vs. eigene Baseline für Quellen ohne Garmin-Status; RMSSD und SDNN getrennt; Quelle in `docs/decisions.md`; Tests |
| 16b | `refactor(coach): eine Tagesbewertung mit einem Wortlaut` | B-29 | Heute, Gesundheit und KI zeigen dieselbe Stufe mit demselben Titel und denselben Hauptgründen; Morning Report ergänzt nur Kontext; Tests in `morning_report_test.dart` und `recovery_test.dart` |
| 17 | `feat(demo): Demo-Modus` (nach F-1) | B-07 | „Ich › Erweitert › Demo ansehen“ legt Wegwerf-Benutzer mit den Prüfstand-Daten an; nichts geht an Worker/Garmin; Test |

## Stufe 4 – Informationsarchitektur, Bereich für Bereich (nach F-2)

| # | PR | Akzeptanzkriterien |
|---|---|---|
| 18 | `feat(nav): fünf Reiter, Router mit benannten Unterseiten` | `go_router`-Routen für alle Hauptseiten; `coach://open/<route>` unverändert kompatibel (Tests in `app_route_test.dart`); Reiter Heute · Plan · Verlauf · Ernährung · Ich; Inhalte vorerst per Weiterleitung auf die alten Seiten |
| 19 | `feat(ich): Ich-Reiter mit neu geordneten Einstellungen` | Gliederung aus Konzept Abschnitt 4; jede Einstellung hat einen Heimatort; „Erweitert“ eingeklappt; Funktionsliste Konzept Abschnitt 7 vollständig abgehakt |
| 20 | `feat(plan): Plan-Reiter mit einer Woche für alle Pläne` | Woche zeigt Wochen-/Saisonplan, Ausdauerplan und Gym-Routinen zusammen; Unterseiten Ausdauerplan, Gym, Routen, Saison |
| 21 | `feat(verlauf): Verlauf-Reiter` | Aktivitäten nach Wochen gruppiert mit Summen; Auswertungen (Trends, Erholung, …) als Abschnitt; Freunde als Filter |
| 22 | `refactor: Training-Reiter auflösen, Dateien teilen` | B-15: keine Datei in `lib/features` über 800 Zeilen; Logik aus `TodayScreen`-State in Controller |
| 23 | `feat(ernaehrung): Reihenfolge und Gruppen` | Konzept 6.4; Prüfstand-Bilder als Vorher/Nachher im PR |
| 24 | `docs: Anleitung und Screenshots auf die neue Struktur` | `docs/anleitung.md` mit neuen Wegen; Prüfstand-Übersicht aktualisiert |

Abschluss jeder Stufe: Geräte-Checkliste aus dem Roast für die betroffenen Teile.
