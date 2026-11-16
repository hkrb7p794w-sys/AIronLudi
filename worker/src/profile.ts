/**
 * Athletenprofil für die Prompts (aus dem Altbestand `garmin_ai_coach/plan.py`, Stand 14.10.2026).
 * Testwerte (FTP, CSS, Pace) liefert die App, weil sie dort in den Einstellungen gepflegt werden.
 */
export function athleteProfile(testValues: string): string {
  return `Ziele: erster Marathon am 02.05.2027 (Zwischenziel), Hauptziel Challenge Almere-Amsterdam, Mitteldistanz (1,9 km Schwimmen, 94 km Rad, 21,1 km Laufen; flach, windexponiert über den Polder, Schwimmen im Weerwater) am Sa 11.09.2027.

Wochenstruktur des Athleten (fester Rahmen, nicht verhandelbar, Stand 14.10.2026):
- Montag Push, Mittwoch Pull, Freitag Push und Pull kombiniert (Home-Gym, Homeoffice-Tage).
- Dienstag und Donnerstag (Bürotage, jeweils vor der Arbeit): 1x Schwimmen und 1x Beine,
  welche Einheit an welchem der beiden Tage liegt, wechselt von Woche zu Woche.
- Wochenende: Zwift-Einheit (Sa oder So).
- Unter der Woche zusätzlich ohne festen Tag: 1x lockerer Zone-2-Lauf (gemeinsam mit der
  Partnerin) und 1x Qualitätslauf, wöchentlich im Wechsel: Schwellenlauf oder 4x4-min-Intervall
  (4x4 min bei 90-95 % HFmax, 3 min Trab). Andere Intervallformen (z. B. 1000er) macht der
  Athlet bewusst nicht - nie vorschlagen.
- Hauptrennen Challenge Almere: Strecke flach und windanfällig (Aeroposition, gleichmäßige Watt),
  Schwimmen im See mit Neoprenanzug.
- Marathonblock (04.01.-11.04.2027): am Wochenende zusätzlich ein Longrun (bis 32 km),
  Zwift und Longrun auf Sa/So verteilt.
- Almere-Block (ab 17.05.2027): am Wochenende lange Radeinheit mit Koppellauf, Zwift-Intervall
  zusätzlich unter der Woche.
- Der Athlet will bewusst nicht mehr Zeit investieren. Diese Struktur ist der Idealfall
  und lässt sich in der Realität oft nicht vollständig umsetzen - fehlende Einheiten
  sind normal und kein Anlass für Vorwürfe.
- ${testValues}.

Coaching-Regeln daraus:
- Niemals mehr Gesamtzeit oder zusätzliche Einheiten fordern. Wenn etwas fehlt, sage
  was innerhalb des bestehenden Rahmens umgeschichtet werden sollte (Prioritäten setzen):
  im Marathonblock Longrun vor Qualitätslauf vor Zwift, im Almere-Block lange Radeinheit vor
  Zwift-Intervall vor Qualitätslauf; Home-Gym hat in beiden Blöcken die niedrigste Priorität.
- Berücksichtige den Wochentag: Schwimmen und Beine an den Bürotagen (Di/Do, Reihenfolge
  flexibel), Push/Pull an Homeoffice-Tagen, Zwift und lange Einheiten am Wochenende.
- Qualitätslauf möglichst nicht am Tag nach dem Beintraining legen.
- Beine im Marathonblock schwer und kurz, mindestens 48 h Abstand zu Longrun und Qualitätslauf.`;
}
