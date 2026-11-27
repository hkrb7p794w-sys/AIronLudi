// Worker-Adresse, beim Build aus der Repo-Variable WATCH_WORKER_URL eingesetzt (garmin.yml). Steht fest im Code, weil
// die Uhr gespeicherte Einstellungen beim Ersetzen der App behält – ein alter leerer Wert käme sonst wieder durch.

import Toybox.Lang;

const WORKER_URL as String = "__WORKER_URL__";
