# Fuel Planner – sportwissenschaftliche Grundlage und Algorithmus

Stand 23.11.2026 (zweite Fassung). Diese Spezifikation ist die Quelle der Wahrheit für
`packages/coach_core/lib/src/fuel/` (Regeln entscheiden, KI formuliert). Jede Zahl unten steht genau so im Code und
ist in `packages/coach_core/test/fuel_planner_test.dart` abgesichert. Ändert sich eine Zahl, dann hier **und** dort.

**Ehrlich vorweg:** Nicht jede Zahl stammt aus einer Studie. Abschnitt 9 trennt, was belegt ist, was aus belegten
Spannen abgeleitet ist und was eine eigene Schätzung ist. Tests beweisen, dass der Code diese Regeln exakt umsetzt –
nicht, dass jede Regel richtig ist.

Der Planer ersetzt keine Ernährungsberatung. Er rechnet Richtwerte aus Positionspapieren in einen konkreten Plan um;
Verträglichkeit wird im Training ausprobiert, nicht am Wettkampftag.

## 0. Quellen (über PubMed geprüft)

| Kürzel | Quelle | Wofür |
|---|---|---|
| **ACSM 2016** | Thomas, Erdman, Burke: *Nutrition and Athletic Performance*, Med Sci Sports Exerc 48(3):543–68 ([DOI](https://doi.org/10.1249/MSS.0000000000000852)) | Pre 1–4 g/kg 1–4 h vorher, Carboloading 10–12 g/kg, Intra 30–60 / bis 90 g/h, Post 1,0–1,2 g/kg/h |
| **ACSM 2007** | Sawka et al.: *Exercise and Fluid Replacement*, Med Sci Sports Exerc 39(2):377–90 ([DOI](https://doi.org/10.1249/mss.0b013e31802ca597)) | Vorab 5–7 ml/kg, Verlust < 2 % Körpergewicht, nicht mehr trinken als schwitzen, 150 % nachher; Getränke 20–30 mmol/l Natrium, 5–10 % Kohlenhydrate |
| **Jeukendrup 2014** | *A step towards personalized sports nutrition: carbohydrate intake during exercise*, Sports Med 44 Suppl 1:S25–33 ([DOI](https://doi.org/10.1007/s40279-014-0148-z)) | Stufen nach Dauer; bei niedriger Intensität nach unten anpassen; ab ~60 g/h mehrere Zucker |
| **Burke 2011** | Burke, Hawley, Wong, Jeukendrup: *Carbohydrates for training and competition*, J Sports Sci 29 Suppl 1:S17–27 ([DOI](https://doi.org/10.1080/02640414.2011.585473)) | Mundspülung ~1 h, 30–60 g/h, > 2,5 h bis 90 g/h, Carboloading |
| **Jeukendrup 2017** | *Training the Gut for Athletes*, Sports Med 47 Suppl 1:101–110 ([DOI](https://doi.org/10.1007/s40279-017-0690-6)) | Darm ist trainierbar (SGLT1, Magenentleerung) |
| **Podlogar 2022** | Podlogar et al., Eur J Appl Physiol 122(11):2393–2401 ([DOI](https://doi.org/10.1007/s00421-022-05019-w)) | 120 g/h im Verhältnis 0,8:1 (Fruktose:Glukose-Quellen) oxidiert mehr als 90 g/h 1:2 |
| **Morton 2026** | Morton et al.: *Revisiting Carbohydrate Guidelines …*, J Nutr 156(5):101442 ([DOI](https://doi.org/10.1016/j.tjnut.2026.101442)) | Obergrenze für Trainierte von 90 auf 120 g/h; mehr nicht belegt |
| **Pfeiffer 2012** | Pfeiffer et al., Med Sci Sports Exerc 44(2):344–51 ([DOI](https://doi.org/10.1249/MSS.0b013e31822dc809)) | Marathon 35 g/h vs. Rad 53 g/h vs. Ironman 62–71 g/h; mehr KH ↔ mehr Übelkeit, aber bessere Zeit |
| **ISSN 2017** | Kerksick et al.: *Nutrient timing*, J Int Soc Sports Nutr 14:33 ([DOI](https://doi.org/10.1186/s12970-017-0189-4)) | Schnelles Auffüllen < 4 h: 1,2 g/kg/h; Protein 20–40 g (0,25–0,40 g/kg) |
| **ISSN 2021** | Guest et al.: *Caffeine and exercise performance*, J Int Soc Sports Nutr 18(1):1 ([DOI](https://doi.org/10.1186/s12970-020-00383-4)) | 3–6 mg/kg, meist 60 min vorher, ab 9 mg/kg viele Nebenwirkungen |
| **Barnes 2019** | Barnes et al., J Sports Sci 37(20):2356–66 ([DOI](https://doi.org/10.1080/02640414.2019.1633159)) | Ausdauer: 1,28 ± 0,57 l/h Schweiß, 51,7 ± 27,8 mmol/h Natrium (≈ 930 mg/l) |
| **Moore 2015** | Moore et al., J Gerontol A 70(1):57–62 ([DOI](https://doi.org/10.1093/gerona/glu103)) | MPS-Plateau 0,24 g/kg (jung) bzw. 0,40 g/kg (älter) |
| **King 2022** | King et al. (Meta-Analyse), Sports Med 52(11):2691–2712 ([DOI](https://doi.org/10.1007/s40279-022-01716-w)) | KH beim Krafttraining nützen bei > 45 min und nach ≥ 8 h nüchtern |
| **SDA 2020** | McCubbin et al.: *Nutrition for Exercise in Hot Environments*, IJSNEM 30(1):83–98 ([DOI](https://doi.org/10.1123/ijsnem.2019-0300)) | Hitze: individuelle Flüssigkeitsbilanz, kalte Getränke, Verträglichkeit prüfen |

## 1. Eingaben

| Feld | Werte | Herkunft |
|---|---|---|
| Sportart | Laufen, Rad, Schwimmen, Triathlon, Kraft, Hybrid (Hyrox, CrossFit, Koppeltraining) | Einheit oder Hand |
| Dauer | Minuten (Triathlon optional Schwimm- und Radminuten) | Einheit oder Hand |
| Intensität | locker (Z1–2), Tempo (Z3), Schwelle (Z4–5/Intervalle) | Einheit oder Hand |
| Wettkampf | ja/nein – eigene, höchste Spalte in allen Tabellen | Einheit „Wettkampf“ oder Hand |
| Körpergewicht, Alter | kg, Jahre | Ernährungseinstellungen › Uhr › Standardwerte |
| Temperatur, Luftfeuchte, drinnen | °C; trocken/normal/schwül; ja/nein | Hand oder Vorhersage (Abschnitt 8) |
| Verträglichkeit | Einsteiger / Gewohnt / Gut-Trained | Profil, je Plan änderbar |
| Schweißrate, Salzverlust | l/h gemessen (optional); niedrig/mittel/hoch oder mg/l | Profil |
| Koffein, nüchtern, nächste Einheit, Takt, Start | – | Plan bzw. Profil |

Ausdauerplan: Regeneration, Grundlage, Lange Einheit → *locker*; Tempo → *Tempo*; Schwelle, VO2max → *Schwelle*;
Wettkampf → *Schwelle* + Schalter *Wettkampf*. Wochenplan: locker und lang → *locker*, intensiv → *Schwelle*;
Dauer aus dem Laufplan der Woche, sonst Standarddauer der Einheit (Kraft 45, locker 45, intensiv 50, lang 90 min).

## 2. Kohlenhydrate während der Belastung

### 2.1 Grundwert in g/h – Stützstellen, dazwischen linear

Unter 45 min: 0 (Glykogen reicht). Ab 45 min linear zwischen diesen Stützstellen, danach konstant, auf 5 g gerundet:

| Minuten | locker | Tempo | Schwelle | Wettkampf |
|---|---|---|---|---|
| 45 | 0 | 0 | 15 | 30 |
| 60 | 0 | 30 | 45 | 60 |
| 90 | 40 | 60 | 75 | 90 |
| 150 | 60 | 80 | 90 | 100 |

Beispiele: 75 min locker 20 g/h, 2 h Schwelle 85 g/h. Eine Minute mehr ändert höchstens 5 g/h (getestet). Locker unter
90 min ist „optional“; 45–59 min hart: Mundspülung reicht auch.

### 2.2 Verträglichkeit und Disziplin

Obergrenzen nach Verträglichkeit: Einsteiger 60, Gewohnt 90, Gut-Trained 120 g/h. Gut-Trained bei Schwelle oder
Wettkampf: Zuschlag linear von 0 (120 min) auf +20 g/h (150 min).

Obergrenzen nach Disziplin: Rad 120, Laufen und Hybrid 90, Schwimmen 60 g/h. Ziel = min(Grundwert + Zuschlag,
Verträglichkeit, Disziplin).

### 2.3 Krafttraining (King 2022)

30 g/h, wenn nüchtern und ≥ 45 min, oder ≥ 75 min ab *Tempo*, oder ≥ 90 min; sonst 0.

### 2.4 Glukose-zu-Fruktose-Verhältnis

≤ 60 g/h eine Quelle; 61–90 g/h 2 : 1 (33 % Fruktose); > 90 g/h 1 : 0,8 (44 %). Warnung ab 8 Prozentpunkten zu wenig.

### 2.5 Gut-Training-Hinweis

Nur wenn die Verträglichkeit das Ziel **tatsächlich begrenzt** (Ziel ohne Verträglichkeitsgrenze liegt darüber) oder
vor einem Wettkampf ≥ 150 min ohne *Gut-Trained*: „4–6 Wochen üben, je Woche etwa 10 g/h mehr“.

### 2.6 Triathlon in Abschnitten

Schwimmen 12 %, Rad 52 %, Laufen den Rest der Zeit (eigene Angaben haben Vorrang). Im Wasser keine Aufnahme; auf dem
Rad gelten die Rad-Grenzen, beim Laufen die Lauf-Grenzen, jeweils mit der Gesamtdauer als Maß. Das angezeigte Ziel
je Stunde ist das Zeitmittel über Rad und Laufen. Vor dem Start ein Gel (15–30 min vorher).

## 3. Vorher und Carboloading

### 3.1 Zeitpunkte (ACSM 2016, ACSM 2007)

| Zeitpunkt | Inhalt |
|---|---|
| 3–4 h vorher (−210 min) | Mahlzeit: KH siehe unten; Protein 0,25 g/kg (höchstens 25 g); Fett ≤ 0,15 g/kg (höchstens 15 g); 6 ml/kg |
| 1–2 h vorher (−90 min) | Snack 0,5 g/kg KH, 3 ml/kg – ab 90 min oder Wettkampf |
| 15–30 min vorher (−20 min) | 20 g KH, 200 ml – ab 60 min nicht locker; Schwimmen und Triathlon ab 45 min immer |

KH der Mahlzeit (g/kg), linear: ohne Wettkampf 1,0 (45 min) → 1,5 (60) → 2,0 (90+); Wettkampf 1,5 (45) → 2,5 (90) → 3,0
(150+). Tempo/Schwelle mindestens 1,5; Einsteiger −0,5 (mindestens 1,0). Kraft: 1,0 g/kg, 0,3 g/kg Protein, 5 ml/kg
2 h vorher. Nüchtern: nur 5 ml/kg Wasser.

### 3.2 Carboloading (Entscheidung, daher in Stufen)

Wettkampf ≥ 90 min: 2 Tage 10 g/kg (Einsteiger 8). Wettkampf 60–89 min oder Schlüsseleinheit ≥ 150 min: Vortag
7 g/kg. Ballaststoff- und fettarm; +1–2 kg sind Glykogen samt Wasser.

## 4. Flüssigkeit, Natrium, Koffein

### 4.1 Schweißrate (l/h) – eigene Schätzung, kalibriert auf Barnes 2019

```
Grundwert (70 kg, 20 °C): locker 0,6 · Tempo 0,9 · Schwelle 1,1 · Wettkampf 1,2
× Gewicht/70 (begrenzt 0,7–1,4) · + 0,03 je °C über 20 · − 0,02 je °C unter 15
× 1,15 schwül · × 1,15 drinnen (nicht Schwimmen)
× Laufen/Hybrid 1,0 · Triathlon 0,95 · Rad 0,9 · Kraft 0,6 · Schwimmen 0,4 · begrenzt 0,2–2,5
```

Die App zeigt „geschätzt“ und empfiehlt die Messung (vorher/nachher wiegen); eine gemessene Rate hat Vorrang.

### 4.2 Trinken unterwegs (ml/h) – ACSM 2007

Unter 45 min: 0. Bedarf = max(0, Schweiß − 2 % Körpergewicht) / Stunden. Untergrenze 40 % der Schweißrate, linear
von 0 (45 min) auf voll (75 min). Obergrenze = min(Schweißrate, Magen: 750 / 900 / 1000 ml/h). Auf 50 ml gerundet.

### 4.3 Natrium (mg/h)

Schweiß: niedrig 500, mittel 900, hoch 1300 mg/l oder gemessen. Ersetzt wird ein Anteil, linear von 0 (60 min) auf
50 % (150 min), bei ≥ 25 °C × 1,2; höchstens 1500 mg/h. Die App zeigt die Konzentration im Getränk neben der ACSM-Spanne
(460–690 mg/l).

### 4.4 Koffein (ISSN 2021)

Dosis = mg/kg (1–6, Standard 3) × Gewicht, höchstens 6 mg/kg und 400 mg. Bis 150 min alles 60 min vorher, darüber
⅔ vorher und ⅓ als **Budget** ab Beginn des letzten Drittels.

- Koffein-Produkte (Gels, Getränke) nur ab dem letzten Drittel und nur, solange sie ins Budget passen – ein Produkt
  darf das Rest-Budget um höchstens 20 % überschreiten (feste Dosis), der ganze Plan nie 6 mg/kg bzw. 400 mg.
- Passt kein Koffein-Produkt: ein Gel ohne Koffein aus der Auswahl (sonst „Gel klassisch“) und ein eigener Schritt
  mit dem Budget. Koffein aus: keine Koffein-Produkte.
- Start ab 15 Uhr: Hinweis auf den Schlaf.

## 5. Danach (ACSM 2016, ISSN 2017, Moore 2015)

- Nächste Einheit ≤ 8 h: 1,0 g/kg je Stunde für 4 h; < 4 h: 1,2 g/kg/h für die verfügbaren Stunden. Protein sofort.
- Sonst Ausdauer: linear 0,5 g/kg (60 min) → 1,0 g/kg (90 min); Schwelle/Wettkampf 1,0; Kraft 0,5.
- Protein 0,3 g/kg (ab 60 Jahren 0,4), 20–40 g; Fett ≤ 0,2 g/kg (höchstens 20 g).
- Flüssigkeit: Defizit × 1,5 ab 200 ml Defizit, Natrium 700 mg je Liter.

## 6. Zeitstrahl und Produkte

- Takt 15/20/30 min (Schwimmen mindestens 20, „am Beckenrand“). Einnahmen je Abschnitt ab Abschnittsbeginn im Takt,
  nicht in den letzten 10 min bzw. 5 min vor einem Wechsel. Jede Einnahme deckt einen Takt.
- **Laufende Salden** für Kohlenhydrate, Flüssigkeit und Natrium – Rundungen gleichen sich über die Einheit aus
  (Flüssigkeit trifft das Soll auf ±25 ml, getestet für jeden Takt).
- Zuordnung: (0) im letzten Drittel zuerst ein Koffein-Produkt, solange es ins Budget passt (sonst ginge das Budget
  hinter einem kohlenhydratreichen Getränk verloren); (1) Getränke im Wechsel Flasche für Flasche, so viel wie offen
  ist und die Kohlenhydrate zulassen – mit gewählten Gels/Riegeln höchstens die Hälfte der offenen Kohlenhydrate;
  (2) Gels/Riegel/Kaudragees/Essen in ganzen Portionen, im Wechsel, bis 3 je Einnahme, Koffein nach 4.4;
  (3) Salztabletten über den Natrium-Saldo; (4) Wasser für den Rest, auf 50 ml. Ohne Auswahl „Gel klassisch“.
- Einnahmen ohne Inhalt (z. B. nur 20 ml offen) erscheinen nicht.
- Warnungen: Kohlenhydrate um mehr als 15 % bzw. 15 g verfehlt, Natrium unter 70 %, zu wenig Fruktose, eigene
  Mischung über 10 % (ACSM 2007: 5–10 %), Koffein über der Grenze, gelöschtes Produkt.
- Packliste: Portionen je Produkt, Flaschen aufgerundet, Pulver für eigene Mischungen.
- DIY-Mischung: Maltodextrin × 0,95 + Dextrose × 0,91 + Fruktose + Zucker (zur Hälfte Fruktose); Natrium = Salz ×
  393 mg/g.

## 7. Ernährungstagebuch – ohne Doppelzählung

- Je Phase eine Mahlzeit „Snack“ auf dem Tag des Plans, Uhrzeit aus Start und Phase (ohne Start: jetzt bzw. 10 Uhr).
- Unterwegs mit den echten Produkten. Vorher und danach als **Platzhalter** „… (Plan)“ mit den Makros plus Wasser.
- Jeder Eintrag trägt im Hinweis eine Markierung `[fuel:<Plan>:<Phase>]`.
- **Platzhalter weichen der echten Mahlzeit:** Wird am selben Tag eine Mahlzeit eingetragen, die höchstens 90 min
  entfernt liegt und mindestens 100 kcal bzw. 30 % des Platzhalters hat, wird der Platzhalter entfernt („Rückgängig“
  holt ihn zurück). Wasser und Einträge des Plans selbst ersetzen nichts.
- **Schon eingetragen:** Deckt eine vorhandene Mahlzeit eine Phase nach derselben Regel ab, ist die Phase beim
  Übernehmen abgewählt und der Grund steht daneben.
- **Erneut übernehmen** ersetzt die bisherigen Einträge des Plans. Ein im Editor bearbeiteter Eintrag verliert die
  Markierung und gehört dann dir.
- **Rückgängig** entfernt die neuen Einträge, stellt ersetzte wieder her und setzt den Plan auf den Stand davor.

## 8. Wetter, Benutzer, veraltete Pläne

- **Wetter:** Open-Meteo wie beim Routenplaner (bis 15 Tage). Ort: Start einer Route zur Einheit, sonst Favorit
  „Zuhause“ bzw. der erste Favorit, sonst der Standort. Mittel über die Stunden der Einheit (ohne Start ab 9 Uhr);
  schwül ab 70 % bei ≥ 20 °C, trocken bis 40 %.
- **Benutzer:** Alles unter `coach.fuelPlanner` mit `username`; ein fremder Stand wird weder geladen noch
  überschrieben. Keine KI.
- **Veraltet:** Ein Plan zu einer Einheit merkt, wenn sich Sportart, Dauer, Strecke, Intensität, Wettkampf oder Tag
  geändert haben, und bietet „anpassen“ an (eigene Einstellungen bleiben). Gelöschte Produkte werden gemeldet.

## 9. Was belegt ist und was geschätzt

| Wert | Status |
|---|---|
| Kohlenhydrat-Spannen nach Dauer, 90/120 g/h, Verhältnisse 2:1 und 1:0,8, Krafttraining ab 45 min/nüchtern | **belegt** (Jeukendrup 2014, Burke 2011, ACSM 2016, Podlogar 2022, Morton 2026, King 2022) |
| Lage der Stützstellen in 2.1 (z. B. Tempo 60 min = 30 g/h) und lineare Verbindung | **abgeleitet** aus den Spannen; die Linearität ist eine Annahme |
| Verträglichkeitsstufen 60/90/120 g/h, Zuschlag +20 g/h | **abgeleitet** (Jeukendrup 2017, Morton 2026) |
| Disziplin-Grenzen Laufen 90, Rad 120, Schwimmen 60 | **abgeleitet** aus Beobachtungen (Pfeiffer 2012), keine harte Studiengrenze |
| Triathlon-Anteile 12/52/36 % | **eigene Schätzung** (Mittel üblicher Zeiten Sprint bis Langdistanz) |
| Pre 1–4 g/kg, Protein 0,25 g/kg, Carboloading 10 g/kg, 5–7 ml/kg | **belegt** (ACSM 2016/2007) |
| Pre-Werte je Dauer (1,0 … 3,0 g/kg) | **abgeleitet** innerhalb 1–4 g/kg |
| Schweißrate: Grundwerte, +0,03 je °C, Faktoren je Sportart, schwül/drinnen × 1,15 | **eigene Schätzung**, nur der Mittelwert ist auf Barnes 2019 kalibriert – darum „geschätzt“ und Messung empfohlen |
| < 2 % Gewichtsverlust, nie mehr als geschwitzt, 150 % danach | **belegt** (ACSM 2007) |
| Trink-Untergrenze 40 % der Schweißrate und ihr Anstieg 45–75 min | **eigene Festlegung** (damit Kohlenhydrate Flüssigkeit haben) |
| Schweiß-Natrium 500/900/1300 mg/l | **abgeleitet** (Mittel Barnes 2019 ≈ 930 mg/l, Spannweite ±30 mmol/h) |
| Natrium-Anteil bis 50 % und × 1,2 bei Hitze | **eigene Festlegung**; geprüft gegen die ACSM-Getränkespanne 460–690 mg/l, die angezeigt wird |
| Koffein 3–6 mg/kg, 60 min vorher | **belegt** (ISSN 2021) |
| ⅔/⅓-Aufteilung ab 150 min, 20 % Toleranz für Koffein-Produkte | **eigene Festlegung** |
| Post 1,0–1,2 g/kg/h, Protein 0,24–0,40 g/kg, 20–40 g | **belegt** (ACSM 2016, ISSN 2017, Moore 2015) |
| Post-Kohlenhydrate 0,5 → 1,0 g/kg nach Dauer | **eigene Festlegung** innerhalb der ACSM-Spanne |
| Fett der Plan-Mahlzeiten (0,15/0,2 g/kg) | **eigene Festlegung** („wenig Fett“ ist belegt, die Zahl nicht) |
| Fruktose-Warnschwelle 8 Prozentpunkte, Kohlenhydrat-Warnung 15 %/15 g, Natrium-Warnung 70 % | **eigene Festlegung** (Rundung einer Portion) |
| Platzhalter-Regel (±90 min, ≥ 100 kcal bzw. 30 %) | **eigene Festlegung** (App-Verhalten, keine Physiologie) |
| Getränk höchstens 50 % der Kohlenhydrate, wenn Gels/Riegel gewählt sind | **eigene Festlegung** (Abwechslung; Studien nutzen beide Formen) |
| Luftfeuchte-Stufen (70 % bei ≥ 20 °C, 40 %) | **eigene Festlegung** |
