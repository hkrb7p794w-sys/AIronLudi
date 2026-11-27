// AIronLudi-Karte: Datenfeld für die Laufaktivität der Uhr. Zeigt die geplante Route mit dem Wegenetz rundherum,
// die eigene Position, Pace, Restdistanz und die nächste Abbiegung – unterwegs ohne Handy. Die Daten kommen vorher
// über den eigenen Worker (Format siehe FORMAT.md), solange das Handy in der Nähe ist.

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class AIronLudiMapApp extends Application.AppBase {
    public function initialize() {
        AppBase.initialize();
    }

    public function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new MapField()];
    }
}
