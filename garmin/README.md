# AIronLudi-Karte (Garmin)

Connect-IQ-**Datenfeld** für die Laufaktivität der Uhr (Forerunner 265/265S): Route aus AIronLudi mit dem Wegenetz
rundherum, eigene Position (Karte in Laufrichtung), Restdistanz, nächste Abbiegung, Pace und Distanz; abseits der
Route roter Rand mit Entfernung und Linie zurück. Unterwegs ohne Handy – das Paket kommt vorher über den eigenen
Worker. Format: `FORMAT.md`; Entscheidungen: `docs/decisions.md` („Karte auf der Garmin-Uhr“).

| Datei | Inhalt |
|---|---|
| `source/MapField.mc` | Datenseite: Zeichnen, Position auf der Route, Hinweise |
| `source/WatchPackage.mc` | Paket lesen (Format `AIW1`) |
| `source/WatchSync.mc` | Koppeln und Laden über den Worker (nur mit Handy in der Nähe) |
| `ci/devices/` | Minimale Gerätebeschreibung für die Typprüfung ohne Garmin-Zugang (nicht zum Installieren) |

Bauen (Connect IQ SDK 9.3, Java 21):

```sh
monkeyc -f garmin/monkey.jungle -d fr265 -y developer.der -o AIronLudiKarte-fr265.prg -l 3 -w
```

In CI: `.github/workflows/garmin.yml`. Installieren und Einrichten: `docs/einrichtung.md`, Abschnitt „Garmin-Karte“.
