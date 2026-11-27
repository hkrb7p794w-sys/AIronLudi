# Uhr-Paket `AIW1` (Version 1)

Geschrieben von `WatchPackage.encode()` (`packages/coach_core/lib/src/routes/watch_package.dart`), gelesen von
`garmin/source/WatchPackage.mc`. Alle Zahlen **Little Endian**, Koordinaten in ganzen **Metern** um den Ursprung
(Start der Route): `x` nach Osten, `y` nach Norden, `x = (lon − lon0) · 111320 · cos(lat0)`, `y = (lat − lat0) · 111320`.
Änderungen nur gemeinsam auf beiden Seiten und mit neuer Version.

| Offset | Typ | Inhalt |
|---|---|---|
| 0 | 4 × u8 | `AIW1` |
| 4 | u8 | Version (1) |
| 5 | u8 | Anzahl Strecken (Hauptroute + Varianten) |
| 6 | u16 | Anzahl Knoten `N` (höchstens 6000) |
| 8 | u16 | Anzahl Kanten `E` (höchstens 7000) |
| 10 | u16 | reserviert (0) |
| 12 | i32 | Breite des Ursprungs × 10⁶ |
| 16 | i32 | Länge des Ursprungs × 10⁶ |
| 20 | `N` × (i16 x, i16 y) | Knoten des Wegenetzes |
| … | `E` × (u16 a, u16 b) | Kanten (Knotenindizes) |
| … | je Strecke, siehe unten | erst die Hauptroute, dann die Varianten |

Strecke:

| Typ | Inhalt |
|---|---|
| u8 | Art: 0 Hauptroute, 1 kürzer, 2 länger |
| u32 | Länge in Metern |
| u16 + Bytes | Name (UTF-8, höchstens 40 Zeichen) |
| u16 + `P` × (i16 x, i16 y) | Punkte (vereinfacht auf 3 m, höchstens 1500) |
| u16 + `M` × (u16 Punkt, u8 Abbiegung) | Abbiegungen an Kreuzungen: 1 leicht rechts, 2 rechts, 3 scharf rechts, 4 wenden, 5 scharf links, 6 links, 7 leicht links |
| u16 + `A` × (u16 Knoten, u16 Abschnitt) | Knoten bis 15 m neben dem Abschnitt `Punkt[i] → Punkt[i+1]` (für den Rückweg zur Route) |

Übertragung: Base64-Teile zu je höchstens 6000 Bytes (`WatchPackage.chunks`), abgelegt beim Worker
(`worker/src/watch.ts`), auf der Uhr in `Application.Storage` (`chunk0`, `chunk1`, …).
