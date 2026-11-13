# AIronLudi

Coach für Training, Ernährung und Gym als **Flutter-App für iPhone und Android** aus einer Codebasis. Nachfolger der
nativen iPhone-App aus [`hkrb7p794w-sys/Coach-App`](https://github.com/hkrb7p794w-sys/Coach-App) und der dortigen
Kotlin-App „IronLudi“.

```
App (Flutter, Dart; Regeln in packages/coach_core)
  ├─ HTTPS ─► Garmin Connect Personal API (offiziell, Key im sicheren Speicher)
  ├─ HTTPS ─► Open Food Facts (Barcode)
  └─ HTTPS ─► Cloudflare Worker aus Coach-App ─► KI-Anbieter (Keys nur im Worker)
```

## Stand

Migration läuft. Audit, Checkliste aller Funktionen und Reihenfolge: [`docs/migrationsplan.md`](docs/migrationsplan.md).
Bis die Flutter-App gleichwertig ist, bleiben die Swift- und die Kotlin-App die genutzten Apps; die CI stellt
erst nach Freigabe (Repo-Variablen `DEPLOY_SIDESTORE`, `DEPLOY_ANDROID`) für SideStore bzw. die Download-Seite bereit.

## Entwicklung

Kein Mac nötig: Android baut auf Linux, iOS in GitHub Actions (macOS), installiert per SideStore. Befehle und
Regeln: [`CLAUDE.md`](CLAUDE.md). Entscheidungen mit Quellen: [`docs/decisions.md`](docs/decisions.md).
