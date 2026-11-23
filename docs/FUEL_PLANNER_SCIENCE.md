# Fuel Planner – sportwissenschaftliche Grundlage und Algorithmus

Stand 23.11.2026. Diese Spezifikation wurde **vor** dem Code geschrieben und ist die Quelle der Wahrheit für
`packages/coach_core/lib/src/fuel/` (Regeln entscheiden, KI formuliert). Jede Zahl unten steht genau so im Code und
ist in `packages/coach_core/test/fuel_planner_test.dart` abgesichert. Ändert sich eine Zahl, dann hier **und** dort.

Der Planer ersetzt keine Ernährungsberatung. Er rechnet Richtwerte aus Positionspapieren in einen konkreten Plan um;
Verträglichkeit wird im Training ausprobiert, nicht am Wettkampftag.

## 0. Quellen (über PubMed geprüft)

| Kürzel | Quelle | Wofür |
|---|---|---|
| **ACSM 2016** | Thomas, Erdman, Burke: *Nutrition and Athletic Performance*, Med Sci Sports Exerc 48(3):543–68 ([DOI](https://doi.org/10.1249/MSS.0000000000000852)) | Tagesbedarf, Pre 1–4 g/kg 1–4 h vorher, Carboloading 10–12 g/kg, Intra 30–60 / bis 90 g/h, Post 1,0–1,2 g/kg/h |
| **ACSM 2007** | Sawka et al.: *Exercise and Fluid Replacement*, Med Sci Sports Exerc 39(2):377–90 ([DOI](https://doi.org/10.1249/mss.0b013e31802ca597)) | Vorab trinken 5–7 ml/kg, Verlust < 2 % Körpergewicht, nicht mehr trinken als schwitzen, 150 % nachher |
| **Jeukendrup 2014** | *A step towards personalized sports nutrition: carbohydrate intake during exercise*, Sports Med 44 Suppl 1:S25–33 ([DOI](https://doi.org/10.1007/s40279-014-0148-z)) | Stufen nach Dauer: ~1 h Mundspülung/kleine Mengen, 2–3 h 60 g/h, > 2,5 h 90 g/h nur mit mehreren Zuckern; bei niedriger Intensität nach unten anpassen |
| **Burke 2011** | Burke, Hawley, Wong, Jeukendrup: *Carbohydrates for training and competition*, J Sports Sci 29 Suppl 1:S17–27 ([DOI](https://doi.org/10.1080/02640414.2011.585473)) | Kohlenhydrat-Verfügbarkeit, Mundspülung ~1 h, 30–60 g/h, > 2,5 h bis 90 g/h, Carboloading |
| **Jeukendrup 2017** | *Training the Gut for Athletes*, Sports Med 47 Suppl 1:101–110 ([DOI](https://doi.org/10.1007/s40279-017-0690-6)) | Darm ist trainierbar (SGLT1-Dichte, Magenentleerung) – Grundlage der Verträglichkeitsstufen |
| **Podlogar 2022** | Podlogar et al.: *120 g h⁻¹ vs 90 g h⁻¹ at different ratios*, Eur J Appl Physiol 122(11):2393–2401 ([DOI](https://doi.org/10.1007/s00421-022-05019-w)) | 120 g/h im Verhältnis 1:0,8 (Fruktose:Glukose-Quellen) oxidiert mehr als 90 g/h 2:1 |
| **Morton 2026** | Morton, Fell, Gonzalez, Hearris, Podlogar, Pugh, Wallis: *Revisiting Carbohydrate Guidelines for Fueling Endurance Athletes*, J Nutr 156(5):101442 ([DOI](https://doi.org/10.1016/j.tjnut.2026.101442)) | Obergrenze für Trainierte von 90 auf 120 g/h; 120–200 g/h nicht belegt |
| **Pfeiffer 2012** | Pfeiffer et al.: *Nutritional intake and GI problems during competitive endurance events*, Med Sci Sports Exerc 44(2):344–51 ([DOI](https://doi.org/10.1249/MSS.0b013e31822dc809)) | Marathon 35 g/h vs. Rad 53 g/h vs. Ironman 62–71 g/h; mehr KH ↔ mehr Übelkeit, aber bessere Zeit; GI-Vorgeschichte entscheidend |
| **ISSN 2017** | Kerksick et al.: *Nutrient timing*, J Int Soc Sports Nutr 14:33 ([DOI](https://doi.org/10.1186/s12970-017-0189-4)) | Schnelles Auffüllen < 4 h: 1,2 g/kg/h; 0,8 g/kg/h + 0,2–0,4 g/kg/h Protein; Protein 20–40 g (0,25–0,40 g/kg) |
| **ISSN 2021** | Guest et al.: *Caffeine and exercise performance*, J Int Soc Sports Nutr 18(1):1 ([DOI](https://doi.org/10.1186/s12970-020-00383-4)) | 3–6 mg/kg, meist 60 min vorher, ab 9 mg/kg viele Nebenwirkungen |
| **Barnes 2019** | Barnes et al.: *Normative data for sweating rate, sweat sodium …*, J Sports Sci 37(20):2356–66 ([DOI](https://doi.org/10.1080/02640414.2019.1633159)) | Ausdauer: 1,28 ± 0,57 l/h Schweiß, 51,7 ± 27,8 mmol/h Natrium (≈ 930 mg/l) |
| **Moore 2015** | Moore et al.: *Protein ingestion … older versus younger men*, J Gerontol A 70(1):57–62 ([DOI](https://doi.org/10.1093/gerona/glu103)) | MPS-Plateau bei 0,24 g/kg (jung) bzw. 0,40 g/kg (älter) je Mahlzeit |
| **King 2022** | King et al.: *Acute carbohydrate feeding on resistance exercise performance* (Meta-Analyse), Sports Med 52(11):2691–2712 ([DOI](https://doi.org/10.1007/s40279-022-01716-w)) | KH beim Krafttraining nützen bei Einheiten > 45 min und nach ≥ 8 h nüchtern |

## 1. Eingaben

| Feld | Werte | Herkunft |
|---|---|---|
| Sportart | Laufen, Rad, Schwimmen, Triathlon, Kraft, Hybrid (Hyrox, CrossFit, Koppeltraining) | Einheit oder Hand |
| Dauer | Minuten | Einheit oder Hand |
| Intensität | locker (Z1–2), Tempo (Z3), Schwelle (Z4–5/Intervalle) | Einheit (Typ → Stufe) oder Hand |
| Wettkampf | ja/nein – zählt in allen Tabellen als eigene, höchste Spalte | Einheit „Wettkampf“ oder Hand |
| Körpergewicht | kg | Ernährungseinstellungen › Uhr › 75 kg |
| Temperatur, Luftfeuchte, drinnen | °C; trocken/normal/schwül; ja/nein | Hand |
| Magen-Darm-Verträglichkeit | Einsteiger / Gewohnt / Gut-Trained | Profil, je Plan änderbar |
| Schweißrate | l/h gemessen (optional) | Profil |
| Salzverlust | niedrig / mittel / hoch oder mg/l gemessen | Profil |
| Koffein | aus/an, Dosis mg/kg (Standard 3) | Plan/Profil |
| Nüchtern | ja/nein | Plan |
| Nächste Einheit in | Stunden (leer = mehr als 24 h) | Plan |

Zuordnung aus dem Ausdauerplan: Regeneration, Grundlage, Lange Einheit → *locker*; Tempo → *Tempo*; Schwelle,
VO2max → *Schwelle*; Wettkampf → *Schwelle* mit Schalter *Wettkampf* (schaltet auch Carboloading ein).

## 2. Kohlenhydrate während der Belastung (Intra)

### 2.1 Grundwert in g/h nach Dauer und Intensität

Jeukendrup 2014 und Burke 2011 staffeln nach Dauer; bei niedriger Intensität wird nach unten angepasst, weil die
Kohlenhydrat-Oxidation dann gering ist. Die Spalte *Wettkampf* entspricht dem oberen Ende der Spanne, *locker* dem
unteren bzw. „nicht nötig“.

| Dauer | locker | Tempo | Schwelle | Wettkampf | Begründung |
|---|---|---|---|---|---|
| < 45 min | 0 | 0 | 0 | 0 | Glykogen reicht; Wasser nach Durst |
| 45–59 min | 0 | 0 | 15 | 30 | Mundspülung bzw. kleine Mengen (ZNS-Effekt) |
| 60–89 min | 0 | 30 | 45 | 60 | 30–60 g/h |
| 90–149 min | 40 | 60 | 75 | 90 | 60–90 g/h |
| ≥ 150 min | 60 | 80 | 90 | 100 | 80–120 g/h (siehe 2.2) |

Bei *locker* unter 90 min zeigt die App „optional bis 30 g/h“ – kein Muss.

### 2.2 Verträglichkeit (Gut-Training) und Disziplin

Verträglichkeits-Obergrenze (Jeukendrup 2017, Morton 2026, ACSM 2016 ≤ 90 g/h):

| Stufe | Obergrenze | Zuschlag ab 150 min, Schwelle/Wettkampf |
|---|---|---|
| Einsteiger | 60 g/h | – |
| Gewohnt | 90 g/h | – |
| Gut-Trained | 120 g/h | +20 g/h (Podlogar 2022: 120 g/h oxidiert mehr) |

Disziplin-Obergrenze (Magen-Darm-Belastung, Pfeiffer 2012):

| Disziplin | Obergrenze | Begründung |
|---|---|---|
| Rad | 120 g/h | ruhiger Oberkörper, Flaschen und Riegel gut erreichbar |
| Triathlon | 100 g/h | Großteil auf dem Rad aufnehmen, Laufen zurückhaltender |
| Laufen, Hybrid | 90 g/h | Erschütterung; Marathonläufer nahmen im Mittel nur 35 g/h auf |
| Schwimmen | 60 g/h | Aufnahme nur am Beckenrand bzw. an Verpflegungsbooten |

Ziel = min(Grundwert + Zuschlag, Verträglichkeit, Disziplin).

### 2.3 Krafttraining

Nach King 2022 nützen Kohlenhydrate beim Krafttraining, wenn die Einheit länger als 45 min dauert **und** nüchtern
(≥ 8 h) trainiert wird, oder bei hohem Volumen. Regel:

- nüchtern und ≥ 45 min → **30 g/h**
- ≥ 75 min und mindestens *Tempo* (hohes Volumen, viele Sätze bis nahe Muskelversagen) → **30 g/h**
- ≥ 90 min → **30 g/h**
- sonst **0** – Pre- und Post-Mahlzeit genügen.

### 2.4 Glukose-zu-Fruktose-Verhältnis

SGLT1 sättigt bei ~60 g/h Glukose; Fruktose nutzt GLUT5 zusätzlich. Empfehlung je Ziel:

| Ziel | Verhältnis (Glukose : Fruktose) | Fruktose-Anteil |
|---|---|---|
| ≤ 60 g/h | eine Quelle genügt (Glukose/Maltodextrin) | 0 % (bis 33 % erlaubt) |
| 61–90 g/h | 2 : 1 | 33 % |
| > 90 g/h | 1 : 0,8 | 44 % |

Der Plan rechnet den Anteil der gewählten Produkte aus und warnt, wenn er mehr als 8 Prozentpunkte unter der
Empfehlung liegt („zu wenig Fruktose für diese Menge“).

### 2.5 Gut-Training-Hinweis

Liegt das Ziel über der Grenze der *nächstniedrigeren* Stufe (also > 60 g/h bei *Gewohnt*, > 90 g/h bei
*Gut-Trained*) oder ist es ein Wettkampf ≥ 150 min, zeigt der Plan als Hinweis: „Im Training 4–6 Wochen üben, je Woche um etwa
10 g/h steigern, mit den Produkten vom Wettkampf.“

## 3. Vor der Belastung (Pre) und Carboloading

### 3.1 Zeitpunkte (ACSM 2016: 1–4 g/kg 1–4 h vorher; ACSM 2007: 5–7 ml/kg vorab)

**Ausdauer und Hybrid:**

| Zeitpunkt | Inhalt | Menge |
|---|---|---|
| 3–4 h vorher (−210 min) | Mahlzeit: komplexe KH, moderat Protein, wenig Fett und Ballaststoffe | KH je kg siehe unten; Protein 0,25 g/kg (höchstens 25 g); Flüssigkeit 6 ml/kg |
| 1–2 h vorher (−90 min) | leicht verdaulicher Snack, nur ab 90 min Dauer oder Wettkampf | 0,5 g/kg KH; 3 ml/kg Flüssigkeit |
| 15–30 min vorher (−20 min) | schnelle KH (Gel, Banane), ab 60 min und nicht *locker*; beim Schwimmen der Haupt-Booster | 20 g KH; 200 ml |

KH der Mahlzeit 3–4 h vorher (g/kg):

| Fall | g/kg |
|---|---|
| < 60 min, kein Wettkampf | 1,0 |
| 60–89 min oder Tempo/Schwelle | 1,5 |
| ≥ 90 min | 2,0 |
| Wettkampf ≥ 90 min | 2,5 |
| Wettkampf ≥ 150 min | 3,0 |

Einsteiger-Magen: −0,5 g/kg (mindestens 1,0).

**Kraft:** Mahlzeit 1–3 h vorher (−120 min): 1,0 g/kg KH, 0,3 g/kg Protein, 5 ml/kg Flüssigkeit (ISSN 2017).

**Nüchtern:** keine Mahlzeit; nur 5 ml/kg Wasser 2 h vorher (und ggf. Koffein).

### 3.2 Carboloading

Nach ACSM 2016 und Burke 2011:

| Fall | Protokoll |
|---|---|
| Wettkampf ≥ 90 min | 36–48 h (2 Tage) **10 g/kg/Tag** (Einsteiger 8 g/kg) |
| Wettkampf 60–89 min oder Schlüsseleinheit ≥ 150 min | Vortag kohlenhydratbetont: **7 g/kg** |
| sonst | – |

Hinweise: ballaststoff- und fettarm (Weißbrot, Reis, Nudeln, Säfte, Grieß), Training reduziert; +1–2 kg auf der
Waage sind Glykogen samt Wasser und gewollt.

## 4. Flüssigkeit, Natrium, Koffein

### 4.1 Schweißrate (l/h)

Gemessen (Gewicht vor/nach, plus Getrunkenes, Formel in der App) hat Vorrang. Sonst geschätzt:

```
Grundwert (70 kg, 20 °C): locker 0,6 · Tempo 0,9 · Schwelle 1,1 · Wettkampf 1,2
× Gewicht/70 (begrenzt 0,7–1,4)
+ 0,03 je °C über 20 · − 0,02 je °C unter 15
× 1,15 bei schwül · × 1,15 drinnen (kein Fahrtwind; nicht beim Schwimmen)
× Disziplin: Laufen/Hybrid 1,0 · Triathlon 0,95 · Rad 0,9 · Kraft 0,6 · Schwimmen 0,4
begrenzt auf 0,2–2,5 l/h
```

Kalibrierung: Wettkampf, 70 kg, 20 °C, Laufen → 1,2 l/h (Barnes 2019: Ausdauer 1,28 ± 0,57 l/h).

### 4.2 Trinken während der Belastung (ml/h)

ACSM 2007: Verlust unter 2 % Körpergewicht halten, aber **nie mehr trinken als schwitzen** (Hyponatriämie).

```
unter 45 min: 0 (nach Durst)
Bedarf = max(0, Schweiß gesamt − 2 % Körpergewicht) / Stunden
Untergrenze ab 60 min = 40 % der Schweißrate (Kohlenhydrate brauchen Flüssigkeit)
Obergrenze = min(Schweißrate, Magen: Einsteiger 750 · Gewohnt 900 · Gut-Trained 1000 ml/h)
auf 50 ml gerundet
```

### 4.3 Natrium (mg/h)

Konzentration im Schweiß: niedrig 500 · mittel 900 · hoch 1300 mg/l (Barnes 2019: Mittel ≈ 930 mg/l) oder gemessen.

| Dauer | Anteil des Verlusts, der ersetzt wird |
|---|---|
| < 60 min | 0 |
| 60–120 min | 0,3 nur bei ≥ 25 °C oder salzigem Schweiß, sonst 0 |
| > 120 min | 0,5; bei ≥ 25 °C 0,6 |

Natrium/h = Schweißrate × Konzentration × Anteil, auf 50 mg gerundet, höchstens 1500 mg/h. Die App zeigt zusätzlich
die Konzentration im Getränk (mg/l).

### 4.4 Koffein (nur wenn eingeschaltet)

ISSN 2021: 3–6 mg/kg, meist 60 min vorher; ab 9 mg/kg viele Nebenwirkungen.

- Dosis = gewählte mg/kg (Standard 3, erlaubt 1–6) × Gewicht, höchstens 6 mg/kg und 400 mg.
- bis 150 min: alles 60 min vorher.
- über 150 min: ⅔ 60 min vorher, ⅓ zu Beginn des letzten Drittels.
- Start ab 15 Uhr: Hinweis auf den Schlaf (Halbwertszeit ~5 h).

## 5. Nach der Belastung (Post)

| Fall | Kohlenhydrate | Protein |
|---|---|---|
| Nächste Einheit in ≤ 8 h (Doppeltag) | **1,0 g/kg je Stunde** für 4 h (nächste Einheit < 4 h: **1,2 g/kg/h** für die verfügbaren Stunden), stündlich | 0,3 g/kg sofort |
| Sonst, Ausdauer ≥ 90 min oder Schwelle/Wettkampf | 1,0 g/kg in den ersten 2 h | 0,3 g/kg |
| Sonst (kurz, locker, Kraft) | 0,5 g/kg mit der nächsten Mahlzeit | 0,3 g/kg |

Protein 0,3 g/kg, ab 60 Jahren 0,4 g/kg (Moore 2015), begrenzt auf 20–40 g; Hinweis Leucin-Schwelle ~2,5–3 g
(≈ 25–30 g Molke, Milch, Ei, Fleisch, Fisch oder größere Mengen pflanzliches Protein).

Flüssigkeit: verbliebenes Defizit (Schweiß − Getrunkenes) × 1,5 über 2–4 h (ACSM 2007), ab 200 ml Defizit;
Natrium dazu 700 mg je Liter (≈ 30 mmol/l).

## 6. Zeitstrahl und Produkte

- Takt 15, 20 oder 30 min (Schwimmen mindestens 20 min, „am Beckenrand“). Einnahmen bei Takt, 2 × Takt, … bis
  10 min vor Ende. Jede Einnahme deckt einen Takt: Ziel je Einnahme = Ziel je Stunde × Takt / 60.
- Unter Takt + 10 min Dauer gibt es keine Einnahme (betrifft nur Einheiten unter 45 min, die ohnehin nichts brauchen).
- Warnung, wenn die Produkte die Kohlenhydrate um mehr als 15 % bzw. 15 g verfehlen, oder Natrium unter 70 % liegt.
- **Produkte zuordnen (deterministisch):**
  1. *Getränk* (erstes gewähltes Getränk): die Flüssigkeit des Takts, aber nur so viel, wie die Kohlenhydrate des
     Takts zulassen; auf 50 ml gerundet.
  2. *Gels, Riegel, Kaudragees, Essen*: ganze Portionen über einen laufenden Saldo (eine Portion kommt dazu, solange
     sie den Rückstand verringert, d. h. Rückstand ≥ halbe Portion); mehrere Produkte im Wechsel.
  3. *Salztabletten*: ebenso über den Natrium-Saldo.
  4. *Wasser*: was an Flüssigkeit fehlt, auf 50 ml gerundet, ab 50 ml.
  5. Ohne gewähltes Produkt: „Gel klassisch“ und Wasser.
- **Packliste:** Portionen je Produkt, Flaschen = aufgerundet (Getränk gesamt ÷ Flaschengröße), Pulver für
  eigene Mischungen = Flaschen × Pulver je Flasche.
- **Eigene Mischung (DIY):** Maltodextrin × 0,95 + Dextrose × 0,91 (Monohydrat) + Fruktose + Haushaltszucker
  (zur Hälfte Fruktose) = Kohlenhydrate; Natrium = Salz × 393 mg/g. Über 10 % Konzentration: Hinweis, dass die
  Magenentleerung langsamer wird – mit Wasser nachspülen oder im Training testen.

## 7. Übernahme ins Ernährungstagebuch

- *Pre* und *Post* als je ein Eintrag „Plan“ mit den Makros (KH, Protein, Fett aus dem Plan; kcal = 4/4/9) und
  getrennt das Wasser – so stimmen Tagesbilanz und Flüssigkeit.
- *Intra* mit den echten Produkten und Mengen (Gel-Portionen, Getränk in ml, Wasser).
- Gebucht wird auf den Tag des Plans. Der Tagesbedarf enthält das Training bereits (Verbrauch aus der Uhr bzw.
  geplanten Einheiten); die Trainings-Kohlenhydrate erscheinen dadurch in der Tagesbilanz statt „außerhalb“.

## 8. Datenschutz und Benutzer

Alles (Profil, eigene Produkte und Mischungen, gespeicherte Pläne) liegt unter `coach.fuelPlanner` im Speicher des
aktiven Benutzers und trägt dessen `username`. Ein fremder Stand (z. B. aus einer eingespielten Sicherung) wird
weder geladen noch überschrieben. Keine KI, keine Netzaufrufe.
