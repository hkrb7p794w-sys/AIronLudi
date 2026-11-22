# AIronLudi installieren – Anleitungen

Drei Wege, je nach Ausgangslage:

- **A – iPhone, neu:** Die Person hatte noch keine Coach-/AIronLudi-App.
- **B – Umstieg von der bisherigen App:** iPhone (Swift-App „AIronLudi“/„Coach“) bzw. Android (Kotlin-App „IronLudi“).
- **C – Android, neu.**

Alles läuft über den KI-Worker der Betreiberin bzw. des Betreibers (Einrichtung: [`einrichtung.md`](einrichtung.md)).
Niemand sonst braucht ein Konto bei Cloudflare, GitHub oder einem KI-Anbieter. Die Links, die du bekommst, sind
**privat** – nicht weitergeben.

> **Solange die neue App noch getestet wird** (Repo-Variablen `DEPLOY_SIDESTORE`/`DEPLOY_ANDROID` nicht auf `true`),
> liefern SideStore-Quelle und Android-Download-Seite noch die **alte** App. Die neue gibt es dann nur so:
> iPhone – Datei `AIronLudi.ipa` aus dem neuesten Release unter
> <https://github.com/hkrb7p794w-sys/AIronLudi/releases> (in Safari laden, dann SideStore › **My Apps** › **+** › Datei
> wählen); Android – Artefakt `AIronLudi-<Laufnummer>` des letzten Laufs „Android“ in GitHub Actions (nur für die
> Betreiberin bzw. den Betreiber, ZIP entpacken, APK aufs Handy).

---

## A – iPhone, neu

**Vorher bereitlegen:** iPhone mit Code-Sperre und iOS 18 oder neuer, USB-Kabel, WLAN, eine **eigene Apple-ID**
(kostenlos reicht), einmalig einen **Windows-PC oder Mac**. Von der Betreiberin bzw. dem Betreiber zwei Links:
**SideStore-Link** und **Einladungslink**. Dauer: 30–45 Minuten.

### 1. SideStore installieren (einmal, mit Computer)

1. **Am iPhone:** im App Store **LocalDevVPN** installieren, öffnen, **Connect**, VPN erlauben.
2. **Am Computer:**
   - *Windows:* iTunes von Apple installieren (<https://www.apple.com/itunes/download/win64>, sonst die App
     „Apple-Geräte“ aus dem Microsoft Store) und **iloader**
     (<https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.msi>).
   - *Mac:* nur **iloader** (<https://github.com/nab138/iloader/releases/latest>, Datei für macOS, in „Programme“
     ziehen; bei „nicht überprüfter Entwickler“: Rechtsklick › Öffnen).
3. iPhone per USB anschließen, am iPhone **Vertrauen** und Code eingeben.
4. **iloader** öffnen › mit der Apple-ID anmelden › iPhone wählen › **Install SideStore (Stable)** › warten bis
   „Success“. Das Kabel kann ab.

### 2. Am iPhone freischalten

1. *Einstellungen › Allgemein › VPN & Geräteverwaltung* › die Apple-ID › **Vertrauen**.
2. *Einstellungen › Datenschutz & Sicherheit › Entwicklermodus* einschalten, Neustart, **Einschalten** bestätigen.
3. **LocalDevVPN** › Connect (bei allen SideStore-Schritten verbunden lassen).
4. **SideStore** öffnen, mit derselben Apple-ID anmelden, *My Apps* › bei SideStore **7 DAYS** antippen.
5. *Sources* › **+** › **SideStore-Link** einfügen › Quelle öffnen › bei **AIronLudi** auf **Installieren**.
6. *SideStore › Settings:* **Background Refresh** an, Mitteilungen erlauben.

### 3. AIronLudi einrichten

1. AIronLudi öffnen, Einrichtung durchgehen (Sportarten, Ziel, Körperdaten). Apple Health erlauben, wenn die Uhr
   Daten liefern soll – es geht auch ohne.
2. Den **Einladungslink** antippen (Nachrichten/WhatsApp) › AIronLudi übernimmt KI-Zugang und Rangliste.
3. *Optional:* *Einstellungen › Konto › Konto erstellen* (für Freunde, Feed, Wettkämpfe; Wiederherstellungscode
   notieren).
4. *Optional:* Garmin unter *Einstellungen › Training und Fitness › Garmin-Konto*, WHOOP darunter (siehe
   [`einrichtung.md`](einrichtung.md), Abschnitte 6 und 7).
5. *Empfohlen:* *Einstellungen › KI und Automatisierung › Datensicherung* › Ordner in iCloud Drive wählen.
6. *Optional:* Widgets (Homescreen lange drücken › **+** › AIronLudi) und *Einstellungen › Sperrbildschirm*
   (Live-Aktivitäten für Gym und Ernährung).

**Laufend:** Mit kostenloser Apple-ID läuft die App **7 Tage**. Mindestens einmal pro Woche SideStore öffnen
(LocalDevVPN verbunden) › *My Apps* › **Refresh All**. Updates meldet SideStore; *My Apps* › **Update** – die Daten
bleiben.

---

## B – Umstieg von der bisherigen App

### B1 – iPhone (bisherige Swift-App)

Die neue App hat dieselbe Kennung und ersetzt die alte in SideStore. Sie liest die alte Datenbank aber **nicht**
direkt – deine Daten ziehen über eine **Sicherungsdatei** um. Deshalb unbedingt in dieser Reihenfolge:

1. **In der alten App sichern:** *Einstellungen › KI und Automatisierung › Datensicherung* ›
   **„Sicherung teilen oder in ‚Dateien‘ sichern“** › *In Dateien sichern* › z. B. *iCloud Drive* ›
   Datei `IronLudi-Sicherung-<Datum>.json` sichern. (Ist dort schon ein Ordner für die automatische Sicherung
   gewählt, liegt dort zusätzlich `IronLudi-Sicherung.json`.)
2. **Neue App installieren:** SideStore › *My Apps* › bei AIronLudi **Update**, sobald die neue Version in der Quelle
   ist – bzw. während der Testphase die `AIronLudi.ipa` wie oben im Kasten beschrieben.
3. **Sicherung einspielen:** Beim ersten Start auf dem ersten Bildschirm oben **„Sicherung einspielen“** › die Datei aus
   Schritt 1 wählen. (Später geht das auch unter *Einstellungen › KI und Automatisierung › Datensicherung ›
   Sicherung einspielen*.) Übernommen werden Gym-Einheiten, Mahlzeiten, Lebensmittel und alle Einstellungen;
   Garmin-Werte holt die App beim nächsten Abruf neu.
4. **Zugänge prüfen:** Die Sicherung enthält aus Sicherheitsgründen keine Schlüssel. Meist übernimmt die neue App
   KI-Zugang, Garmin und Konto aus dem Schlüsselbund; falls nicht:
   - KI: Einladungslink erneut antippen (bzw. als Betreiber:in *Einstellungen › Technik › KI-Worker*, siehe unten),
   - Garmin: *Einstellungen › Training und Fitness › Garmin-Konto* neu anmelden,
   - Konto: *Einstellungen › Konto › Anmelden*.
5. Widgets und Live-Aktivitäten neu einrichten (*Einstellungen › Sperrbildschirm*).

### B2 – Android (bisherige Kotlin-App „IronLudi“)

Die neue App liest die Sicherung der bisherigen Android-App (`IronLudi-Gym-Sicherung-<Datum>.json`) ein:
Trainings, Pläne, eigene Übungen, Mahlzeiten, Favoriten, Lebensmittel, eigene Rezepte, Gewichte, Körperwerte,
Rezept-Wünsche und Mahlzeiten-Erinnerungen. Nicht übernommen werden ein gerade laufendes Training (vorher beenden),
Tagestypen (die neue App leitet sie aus Wochenplan und Training ab) und die Rezeptideen der Woche (neu erstellen).
**Reihenfolge einhalten:**

1. In der alten App ein laufendes Training beenden, dann *Training › Zahnrad › „Sicherung speichern“* (z. B. in
   Google Drive oder „Downloads“). Prüfen, dass die Datei da ist.
2. **Alte App deinstallieren** (erst nach Schritt 1!), dann die neue über den Android-Link installieren. Ein Update
   über die alte App geht nicht: Die neue App ist mit einem anderen Schlüssel signiert (Keystore vom 16.11.2026),
   Android lehnt sie sonst mit „App nicht installiert“ ab.
3. In der neuen App auf dem ersten Bildschirm oben **„Sicherung einspielen“** (bzw. später *Einstellungen › KI und
   Automatisierung › Datensicherung › Sicherung einspielen*) › Datei aus Schritt 1 wählen › **Einspielen**. Die App
   schließt sich danach einmal; neu öffnen.
4. **Einrichtung abschließen** (Sportarten, Ziel): Die Android-App kannte kein Profil. Körperwerte und Ernährungsweise
   sind schon eingetragen; Ziel und Tempo wählst du neu, damit die Schutzgrenzen gelten.
5. KI-Zugang: Android-Link erneut öffnen › **„In der App verbinden“**.

---

## C – Android, neu

**Von der Betreiberin bzw. dem Betreiber:** ein **Android-Link** (in deren App unter *Einstellungen › Technik ›
KI-Worker › „Android-Link erstellen“ › „Android-Link teilen“* – je Person ein eigener Link mit eigenem Gastzugang).
Dauer: etwa 5 Minuten, nur das Handy (Android 8 oder neuer).

1. Link in Chrome öffnen › **„App herunterladen“**.
2. Heruntergeladene Datei öffnen. Fragt Android nach „unbekannten Apps“: **Einstellungen** › „Dieser Quelle
   vertrauen“ einschalten › zurück › **Installieren**.
3. Warnt **Google Play Protect**: *Weitere Details* › **Trotzdem installieren**.
4. Zurück auf der Seite **„In der App verbinden“** › AIronLudi öffnet sich und übernimmt den KI-Zugang.
5. Einrichtung durchgehen (Sportarten, Ziel, Körperdaten). Health Connect erlauben, wenn eine Uhr Daten liefern soll –
   es geht auch ohne.
6. *Optional:* Konto, Garmin, WHOOP wie bei A3; Sicherung unter *Einstellungen › KI und Automatisierung ›
   Datensicherung* (Ordner z. B. in Google Drive); laufende Gym-Einheit und „Mahlzeiten heute“ als Mitteilung:
   *Einstellungen › Sperrbildschirm*.

**Aktualisieren:** Gibt es eine neue Version, zeigt AIronLudi oben **„Neue Version … verfügbar“** (geprüft beim Öffnen,
höchstens alle sechs Stunden; nur mit verbundenem KI-Zugang). **„Jetzt laden“** öffnet die Download-Seite – die neue
Version dort genauso installieren wie oben, die Daten bleiben. **„Später“** blendet diese Version aus; die nächste
erscheint wieder. Ganz von selbst installiert Android Apps außerhalb des Play Stores nicht. Ohne Hinweis geht es auch
von Hand: denselben Link wieder öffnen.

---

## Ausdauerplan: Laufen, Rad/Zwift, Schwimmen

1. *Training › Ausdauerplan › Plan erstellen:* **Auf ein Ziel** (Wettkampf, Datum, optional Zielzeit h:mm) oder
   **Für einen Zeitraum** (4, 8 oder 12 Wochen). Disziplinen, Trainingstage, Tag der langen Einheit und Zeit je
   Woche wählen. Schwellenwerte (Lauf-Pace, FTP, CSS, Schwellenpuls) eintragen, soweit bekannt – daraus werden die
   Ziele je Schritt.
2. Der Plan passt sich jeden Tag selbst an (nach dem Abruf): härteres Training als geplant, ausgefallene Einheiten
   und schlechte Erholungswerte. Was sich geändert hat und warum, steht unter **Anpassungen**.
3. **An die Uhr:** In einer Einheit **Einheit an Uhr senden** (Garmin-Konto unter *Einstellungen › Training und
   Fitness › Garmin-Konto* nötig) – oder *Automatisch in den Garmin-Kalender* einschalten: Die nächsten 14 Tage
   stehen dann im Garmin-Kalender und werden bei jeder Planänderung ersetzt.
4. **Zwift:** Bei Rad-Einheiten **Für Zwift exportieren (.zwo)**, Datei am PC nach
   `Dokumente\Zwift\Workouts\<Zwift-ID>\` kopieren. In Zwift unter
   *Training › Eigene Workouts*. **FIT-Datei teilen** gibt es für alle Einheiten.

## Routen planen: Laufen und Rad (OpenStreetMap)

1. *Training › Routen › Neue Route planen:* Start als **Adresse** eingeben (Vorschläge erscheinen beim Tippen,
   Eingabetaste sucht), mit **Aktueller Standort** (fragt einmal nach der Freigabe) oder per Antippen der Karte. **Disziplin:** Laufen (Fuß- und Waldwege, Parks), Rennrad (Asphalt) oder Gravel/Allround
   (Schotter, Feld- und Waldwege). **Umgebung:** *Wald & Natur*, *Am Wasser* (Kanäle, Flüsse, Seen),
   *Straße & Asphalt* oder *Ausgewogener Mix*.
2. **Strecke:** *Rundweg*, *Zum Ziel* (Zieladresse eingeben oder Ziel-Pin setzen; ist es näher als die Wunschdistanz, gibt es einen Umweg)
   oder *Richtung* (Himmelsrichtung, offenes Ziel, genau auf die Distanz gekürzt). **Distanz** wählen (der Planer
   trifft sie auf ±2,5 %), optional **Höhenmeter vorgeben**.
3. **Routen vorschlagen:** bis zu drei Varianten – *Direkt & ausgeglichen*, *Höhenmeter-Fokus*, *Grün &
   verkehrsarm* – mit Karte, Richtungspfeilen, Höhenprofil, Anstieg/Abstieg und geschätzter Dauer. **Neu würfeln**
   probiert andere Wege. Solange Vorschläge da sind, kannst du die Karte gefahrlos zoomen und verschieben; einen
   Punkt verschiebst du mit **langem Drücken** oder **Startpunkt ändern**, ganz neu beginnst du mit ↺ oben rechts.
4. **In Einheit übernehmen:** heute, eine kommende Einheit des Ausdauerplans oder ein anderer Tag – die Route steht
   dann unter *Heute › Route für heute*. **GPX** oder **FIT** öffnet das Teilen-Menü (z. B. Garmin Connect, Komoot,
   Wahoo, Dateien).
5. **Frei planen:** oben auf *Frei planen* umschalten. *Punkte*: Start und weitere Punkte antippen oder über die Lupe als Adresse suchen; *Zeichnen*: mit
   dem Finger eine grobe Linie ziehen. Jeder Abschnitt wird auf echte Wege gelegt; unten stehen Distanz, Höhenmeter
   und Dauer. ↶ nimmt den letzten Abschnitt zurück, ⟳ schließt den Rundweg zum Start, **Speichern** legt die Route ab.
6. **Gebiete (optional):** *Training › Routen › Gebiete anzeigen*. Geschlossene Runden erobern die umschlossene
   Fläche, alle Läufe und Fahrten mit GPS füllen deine Kachel-Karte. Gezählt wird eine Aktivität, sobald ihr Verlauf
   einmal geladen wurde (Aktivität öffnen). Alles bleibt bei deinem Benutzer.

Die Routen kommen von öffentlichen, kostenlosen OSM-Diensten (Valhalla der FOSSGIS, ersatzweise BRouter; passende
Wege über Overpass; Adressen über Photon bzw. Nominatim). Sind sie
überlastet, hilft es, kurz zu warten.

## Für dich als Betreiber:in: KI-Worker in der App eintragen

Nur auf deinem eigenen Gerät (alle anderen nutzen den Einladungs- bzw. Android-Link):

1. *Actions › Worker* in GitHub: im letzten Lauf unter **Summary** steht die Adresse, z. B.
   `https://coach-ai.<subdomain>.workers.dev`.
2. AIronLudi › *Einstellungen › Technik › KI-Worker*: Adresse und **App-Token** (der Wert des Secrets
   `COACH_APP_TOKEN`) eintragen › **Speichern und testen**. Es erscheint ein Gruß der KI mit Anbieter und Modell.
3. Ab dann gibt es dort **„SideStore-Quelle teilen“** und **„Android-Link erstellen“**; Einladungslinks unter
   *Einstellungen › Begleiter & Rangliste*.

## Wenn etwas hakt

| Problem | Lösung |
|---|---|
| iloader sieht das iPhone nicht | anderes Kabel, iPhone entsperren, „Vertrauen“ erneut bestätigen; Windows: iTunes bzw. „Apple-Geräte“ installiert? |
| AIronLudi öffnet nicht mehr („nicht verfügbar“) | 7 Tage abgelaufen: LocalDevVPN verbinden › SideStore › My Apps › Refresh |
| „KI-Worker ist nicht eingerichtet“ | Einladungslink erneut antippen bzw. *Einstellungen › Technik › KI-Worker* prüfen |
| Android: „App nicht installiert“ | Auf dem Handy ist noch die alte Kotlin-App (anderer Signaturschlüssel): erst sichern, dann deinstallieren (Abschnitt B2). Kommt die Meldung bei einem Update der **neuen** App, fehlten beim Build die Secrets `ANDROID_KEYSTORE_*` – Betreiber:in fragen |
| Foto-Analyse meldet „KI nicht erreichbar … (Fehlercode 502)“ | Kein Bildmodell hat geantwortet. Betreiber:in: Unter *Settings › Secrets and variables › Actions* alle KI-Keys anlegen (`GROQ_API_KEY`, `MISTRAL_API_KEY`, `CEREBRAS_API_KEY`, `GH_MODELS_TOKEN`, `GEMINI_API_KEY` – dieselben Werte wie bisher), dann *Actions › Worker › Run workflow*. `…/v1/health` zeigt, welche Anbieter aktiv sind |
| Kühlschrank-Rezepte melden einen Fehler | Der Worker ist noch nicht neu bereitgestellt (*Actions › Worker › Run workflow*) |
