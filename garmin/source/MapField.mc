// Datenseite „Karte“: Wegenetz grau, Route blau (Gelaufenes blasser), eigene Position als gelber Pfeil, Karte dreht
// sich in Laufrichtung. Oben die Restdistanz, unten Pace und Distanz, vor Abzweigungen ein Hinweis, abseits der Route
// ein roter Rand mit Entfernung. Antippen (wo die Uhr es an Datenfelder gibt) wechselt den Maßstab.

import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

class MapField extends WatchUi.DataField {
    // Abseits ab dieser Entfernung zur Route (Meter).
    private const OFF_ROUTE = 40.0;
    // Hinweis auf die nächste Abbiegung ab dieser Entfernung (Meter).
    private const TURN_AHEAD = 150;

    private const COLOR_NETWORK = 0x555555;
    private const COLOR_ROUTE = 0x0A84FF;
    private const COLOR_DONE = 0x1F4A7A;
    private const COLOR_ME = 0xFFD60A;
    private const COLOR_ALERT = 0xFF453A;

    // Maßstäbe in Pixel je Meter (Antippen wechselt).
    private const SCALES = [0.25, 0.5, 1.0];

    private var _sync as WatchSync;
    private var _scaleIndex as Number = 1;

    private var _x as Float? = null;
    private var _y as Float? = null;
    private var _heading as Float = 0.0;
    private var _speed as Float = 0.0;
    private var _elapsed as Float = 0.0;

    // Abschnitt der Route, auf dem man gerade ist, Fortschritt und Abstand zur Route.
    private var _segment as Number = 0;
    private var _progress as Float = 0.0;
    private var _offRoute as Float = 0.0;
    private var _nearestX as Float = 0.0;
    private var _nearestY as Float = 0.0;

    public function initialize() {
        DataField.initialize();
        _sync = new WatchSync();
    }

    public function compute(info as Activity.Info) as Void {
        _sync.tick(info.timerState != null && info.timerState != Activity.TIMER_STATE_OFF);
        var speed = info.currentSpeed;
        _speed = speed != null ? speed : 0.0;
        var elapsed = info.elapsedDistance;
        _elapsed = elapsed != null ? elapsed : 0.0;
        var heading = info.currentHeading;
        if (heading == null) {
            heading = info.track;
        }
        if (heading != null) {
            _heading = heading;
        }
        var routePackage = _sync.routePackage;
        var location = info.currentLocation;
        if (routePackage == null || location == null) {
            return;
        }
        var degrees = location.toDegrees();
        var position = routePackage.project(degrees[0], degrees[1]);
        _x = position[0];
        _y = position[1];
        match(routePackage, position[0], position[1]);
    }

    // Nächster Abschnitt der Route: erst in der Nähe des bisherigen, sonst über die ganze Route.
    private function match(routePackage as WatchPackage, x as Float, y as Float) as Void {
        var count = routePackage.pointCount;
        if (count < 2) {
            return;
        }
        var from = _segment - 20;
        var to = _segment + 200;
        if (_offRoute > OFF_ROUTE * 2) {
            from = 0;
            to = count;
        }
        if (from < 0) {
            from = 0;
        }
        if (to > count - 1) {
            to = count - 1;
        }
        var best = 1.0e9;
        for (var i = from; i < to; i++) {
            var ax = routePackage.pointX(i).toFloat();
            var ay = routePackage.pointY(i).toFloat();
            var dx = routePackage.pointX(i + 1).toFloat() - ax;
            var dy = routePackage.pointY(i + 1).toFloat() - ay;
            var length2 = dx * dx + dy * dy;
            var t = 0.0;
            if (length2 > 0) {
                t = ((x - ax) * dx + (y - ay) * dy) / length2;
                if (t < 0) {
                    t = 0.0;
                } else if (t > 1) {
                    t = 1.0;
                }
            }
            var px = ax + t * dx;
            var py = ay + t * dy;
            var distance = Math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
            if (distance < best) {
                best = distance;
                _segment = i;
                _progress = (routePackage.cumulative[i] + t * Math.sqrt(length2)).toFloat();
                _nearestX = px;
                _nearestY = py;
            }
        }
        _offRoute = best.toFloat();
    }

    public function onTap(event as WatchUi.ClickEvent) as Boolean {
        _scaleIndex = (_scaleIndex + 1) % SCALES.size();
        WatchUi.requestUpdate();
        return true;
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var routePackage = _sync.routePackage;
        // Kleines Feld: nur Restdistanz bzw. Stand.
        if (width < 200 || height < 200) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var text = routePackage == null ? _sync.status : remainingText(routePackage);
            drawWrapped(dc, text, Graphics.FONT_SMALL, width, height);
            return;
        }
        if (routePackage == null || _x == null) {
            drawStatus(dc, routePackage);
            return;
        }
        drawMap(dc, routePackage, _x as Float, _y as Float);
        drawData(dc, routePackage);
    }

    private function drawStatus(dc as Graphics.Dc, routePackage as WatchPackage?) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height / 4, Graphics.FONT_SMALL, "AIronLudi-Karte", Graphics.TEXT_JUSTIFY_CENTER);
        var code = _sync.code;
        if (code != null) {
            dc.setColor(COLOR_ME, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 2 - 30, Graphics.FONT_NUMBER_MEDIUM, code, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height * 2 / 3, Graphics.FONT_XTINY, "Code in AIronLudi eingeben:\nAn Uhr senden › Uhr koppeln", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var text = routePackage != null ? routePackage.routeName + "\nGPS wird gesucht …" : _sync.status;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        drawWrapped(dc, text, Graphics.FONT_TINY, width * 3 / 4, height / 2);
    }

    // Text mittig, umgebrochen und notfalls gekürzt, damit er auf dem runden Bildschirm ganz zu sehen ist.
    private function drawWrapped(dc as Graphics.Dc, text as String, font as Graphics.FontType, areaWidth as Number, areaHeight as Number) as Void {
        var fitted = Graphics.fitTextToArea(text, font, areaWidth, areaHeight, true);
        var shown = fitted != null ? fitted : text;
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, font, shown, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawMap(dc as Graphics.Dc, routePackage as WatchPackage, x as Float, y as Float) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var scale = SCALES[_scaleIndex] as Float;
        var cx = width / 2;
        var cy = height / 2 + height / 8;
        var cos = Math.cos(_heading);
        var sin = Math.sin(_heading);
        // Nur zeichnen, was in die Nähe des Bildschirms fällt (Meter).
        var reach = (width / scale).toNumber();
        var ix = x.toNumber();
        var iy = y.toNumber();

        // Wegenetz
        dc.setPenWidth(3);
        dc.setColor(COLOR_NETWORK, Graphics.COLOR_TRANSPARENT);
        for (var e = 0; e < routePackage.edgeCount; e++) {
            var a = routePackage.edgeA(e);
            var b = routePackage.edgeB(e);
            var ax = routePackage.nodeX(a) - ix;
            var ay = routePackage.nodeY(a) - iy;
            var bx = routePackage.nodeX(b) - ix;
            var by = routePackage.nodeY(b) - iy;
            if ((ax > reach && bx > reach) || (ax < -reach && bx < -reach) || (ay > reach && by > reach) || (ay < -reach && by < -reach)) {
                continue;
            }
            dc.drawLine(
                cx + ((ax * cos - ay * sin) * scale).toNumber(),
                cy - ((ax * sin + ay * cos) * scale).toNumber(),
                cx + ((bx * cos - by * sin) * scale).toNumber(),
                cy - ((bx * sin + by * cos) * scale).toNumber()
            );
        }

        // Route: Gelaufenes blasser.
        dc.setPenWidth(7);
        for (var i = 0; i < routePackage.pointCount - 1; i++) {
            var ax = routePackage.pointX(i) - ix;
            var ay = routePackage.pointY(i) - iy;
            var bx = routePackage.pointX(i + 1) - ix;
            var by = routePackage.pointY(i + 1) - iy;
            if ((ax > reach && bx > reach) || (ax < -reach && bx < -reach) || (ay > reach && by > reach) || (ay < -reach && by < -reach)) {
                continue;
            }
            dc.setColor(i < _segment ? COLOR_DONE : COLOR_ROUTE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(
                cx + ((ax * cos - ay * sin) * scale).toNumber(),
                cy - ((ax * sin + ay * cos) * scale).toNumber(),
                cx + ((bx * cos - by * sin) * scale).toNumber(),
                cy - ((bx * sin + by * cos) * scale).toNumber()
            );
        }

        // Abseits: Linie zum nächsten Punkt der Route, roter Rand.
        if (_offRoute > OFF_ROUTE) {
            var nx = _nearestX - x;
            var ny = _nearestY - y;
            dc.setPenWidth(3);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx, cy, cx + ((nx * cos - ny * sin) * scale).toNumber(), cy - ((nx * sin + ny * cos) * scale).toNumber());
            dc.setPenWidth(8);
            dc.setColor(COLOR_ALERT, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(width / 2, height / 2, width / 2 - 4);
        }

        // Ich: gelber Pfeil in Laufrichtung (oben).
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 17);
        dc.setColor(COLOR_ME, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, cy - 12], [cx + 9, cy + 9], [cx, cy + 4], [cx - 9, cy + 9]]);
    }

    private function remainingText(routePackage as WatchPackage) as String {
        var remaining = routePackage.routeDistance - _progress;
        if (remaining < 0) {
            remaining = 0;
        }
        return "noch " + kilometers(remaining);
    }

    private function kilometers(meters as Float or Number) as String {
        var text = (meters / 1000.0).format("%.1f");
        return replaceDot(text) + " km";
    }

    private function replaceDot(text as String) as String {
        var index = text.find(".");
        return index == null ? text : text.substring(0, index) + "," + text.substring(index + 1, text.length());
    }

    private function drawData(dc as Graphics.Dc, routePackage as WatchPackage) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER;

        // Oben: Hinweis auf Abbiegung, Abseits-Warnung oder Restdistanz.
        var banner = null as String?;
        var bannerColor = COLOR_ME;
        if (_offRoute > OFF_ROUTE) {
            banner = "Abseits · " + _offRoute.toNumber() + " m";
            bannerColor = COLOR_ALERT;
        } else {
            for (var m = 0; m < routePackage.maneuverCount; m++) {
                var point = routePackage.maneuverPoint(m);
                if (point <= _segment) {
                    continue;
                }
                var ahead = routePackage.cumulative[point] - _progress;
                if (ahead <= TURN_AHEAD) {
                    banner = "in " + ((ahead / 10).toNumber() * 10) + " m " + turnText(routePackage.maneuverTurn(m));
                }
                break;
            }
        }
        if (banner != null) {
            dc.setColor(bannerColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(width / 5, height / 10, width * 3 / 5, 44, 18);
            dc.setColor(bannerColor == COLOR_ALERT ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 10 + 22, Graphics.FONT_TINY, banner, center | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2, height / 10 + 6, Graphics.FONT_SMALL, remainingText(routePackage), center);
        }

        // Unten: Pace und gelaufene Distanz.
        var pace = "--:--";
        if (_speed > 0.5) {
            var secondsPerKm = (1000.0 / _speed).toNumber();
            pace = (secondsPerKm / 60) + ":" + (secondsPerKm % 60).format("%02d");
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(width / 4, height - height / 5 - 4, width / 2, 52, 24);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width * 3 / 8, height - height / 5, Graphics.FONT_SMALL, pace, center);
        dc.drawText(width * 5 / 8, height - height / 5, Graphics.FONT_SMALL, kilometers(_elapsed), center);
    }

    private function turnText(code as Number) as String {
        switch (code) {
            case 1:
                return "leicht rechts";
            case 2:
                return "rechts";
            case 3:
                return "scharf rechts";
            case 4:
                return "wenden";
            case 5:
                return "scharf links";
            case 6:
                return "links";
            case 7:
                return "leicht links";
        }
        return "";
    }
}
