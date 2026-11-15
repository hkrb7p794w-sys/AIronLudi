# AIronLudi installieren und nutzen

> Stand: Die App ist noch in der Migration (siehe [`migrationsplan.md`](migrationsplan.md)). Die automatische
> Bereitstellung für SideStore bzw. die Android-Download-Seite ist erst nach Freigabe aktiv (Repo-Variablen
> `DEPLOY_SIDESTORE`, `DEPLOY_ANDROID`). Bis dahin laden Sie die Dateien direkt von GitHub.

## Links

| Zweck | Link |
|---|---|
| Alle Versionen (iPhone-IPA) | https://github.com/hkrb7p794w-sys/AIronLudi/releases |
| Neueste Version | https://github.com/hkrb7p794w-sys/AIronLudi/releases/latest |
| Android-APK (Build-Artefakt) | https://github.com/hkrb7p794w-sys/AIronLudi/actions/workflows/android.yml |
| SideStore (iPhone-Installer) | https://sidestore.io |
| SideStore-Dokumentation | https://docs.sidestore.io |
| Quellcode | https://github.com/hkrb7p794w-sys/AIronLudi |

## iPhone (iOS 18+) – per SideStore

Die App liegt nicht im App Store. Sie wird als unsignierte IPA gebaut und mit SideStore auf dem iPhone signiert.

1. **SideStore einrichten** (einmalig, ohne Mac möglich): der Anleitung unter https://docs.sidestore.io folgen
   (Apple-ID, Entwicklermodus am iPhone aktivieren, SideStore installieren).
2. **IPA laden:** am iPhone https://github.com/hkrb7p794w-sys/AIronLudi/releases/latest öffnen und
   `AIronLudi.ipa` herunterladen (in „Dateien“ gespeichert).
3. **Installieren:** SideStore öffnen → Reiter „My Apps“ → „+“ → `AIronLudi.ipa` wählen.
4. **Vertrauen:** Einstellungen → Allgemein → VPN & Geräteverwaltung → Apple-ID bestätigen.
5. **Alle 7 Tage erneuern:** SideStore → „My Apps“ → „Refresh All“ (bei kostenloser Apple-ID läuft die Signatur
   nach 7 Tagen ab). Automatisches Erneuern geht mit aktivem SideStore-VPN/Shortcut.
6. **Updates:** neue IPA aus den Releases laden und ebenso installieren; die Daten bleiben erhalten
   (gleiche Bundle-ID wie die Swift-App `io.github.hkrb7p794w.coach`, sie wird dabei ersetzt).

## Android (8.0+)

1. APK beschaffen:
   - Sobald freigegeben: über die private Download-Seite (Link steht in der App unter Einstellungen → Technik).
   - Bis dahin: https://github.com/hkrb7p794w-sys/AIronLudi/actions/workflows/android.yml → jüngsten
     grünen Lauf auf `main` öffnen → Artefakt „apk“ herunterladen (GitHub-Anmeldung nötig, ZIP entpacken).
2. APK auf dem Handy antippen; bei Nachfrage „Installation aus dieser Quelle zulassen“ erlauben.
3. Installieren und öffnen. Updates: neue APK einfach darüberinstallieren.

## Erste Schritte in der App

1. **Profil:** Beim Start den Assistenten ausfüllen. Modus wählen: *Saisonplan* oder *persönlich*.
2. **Vier Reiter:** Heute (Tagesampel), Training, Ernährung, Gym.
3. **Garmin:** Einstellungen → Training → Garmin-Konto verbinden (Bestätigungscode eingeben). Der Key liegt nur im
   sicheren Speicher des Geräts.
4. **Health (optional):** Apple Health bzw. Health Connect in den Einstellungen freigeben. Alles geht auch ohne.
5. **Mitteilungen:** Erinnerungen und Uhrzeiten unter Einstellungen → Allgemein.
6. **KI-Funktionen:** laufen über den Cloudflare Worker; Datenschutzmodus „reduziert“ ist voreingestellt.
7. **Umzug von der alten Swift-App:** dort ein Backup exportieren, hier unter Einstellungen → Export/Import
   einlesen (`AppBackup` ist kompatibel).
8. **Sichern:** regelmäßig ein Backup exportieren, bevor man neue Versionen installiert.

## Probleme

- „App kann nicht installiert werden“: Entwicklermodus aktiv? SideStore auf dem neuesten Stand? Maximal 3 aktive
  Apps mit kostenloser Apple-ID.
- App startet nach 7 Tagen nicht mehr: in SideStore erneuern.
- Keine Release-Datei sichtbar: dann wurde noch kein iOS-Build erzeugt. In einer PR das Label `ios-build` setzen
  oder „Run workflow“ für `ios-build.yml` starten.
