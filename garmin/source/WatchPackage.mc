// Liest das Uhr-Paket (Format AIW1, siehe FORMAT.md) aus einem ByteArray. Die Zahlen bleiben im ByteArray und werden
// bei Bedarf gelesen; nur Startpositionen der Abschnitte und die Länge der Route werden einmal berechnet.

import Toybox.Lang;
import Toybox.Math;

class WatchPackage {
    // Rohdaten und Ursprung (Grad).
    public var bytes as ByteArray;
    public var originLat as Float = 0.0;
    public var originLon as Float = 0.0;
    public var nodeCount as Number = 0;
    public var edgeCount as Number = 0;
    public var nodesOffset as Number = 0;
    public var edgesOffset as Number = 0;

    // Hauptroute (die erste Strecke im Paket).
    public var routeName as String = "";
    public var routeDistance as Number = 0;
    public var pointCount as Number = 0;
    public var pointsOffset as Number = 0;
    public var maneuverCount as Number = 0;
    public var maneuversOffset as Number = 0;
    // Strecke vom Start bis zu jedem Routenpunkt (Meter).
    public var cumulative as Array<Number> = [];
    // Weitere Strecken (Varianten) im Paket.
    public var routeCount as Number = 0;

    private var _metersPerDegreeLon as Float = 1.0;

    public function initialize(data as ByteArray) {
        bytes = data;
        if (data.size() < 20 || data[0] != 65 || data[1] != 73 || data[2] != 87 || data[3] != 49 || data[4] != 1) {
            throw new Lang.InvalidValueException("Kein Uhr-Paket");
        }
        routeCount = data[5];
        nodeCount = u16(6);
        edgeCount = u16(8);
        originLat = s32(12).toFloat() / 1000000.0;
        originLon = s32(16).toFloat() / 1000000.0;
        _metersPerDegreeLon = (111320.0 * Math.cos(originLat * Math.PI / 180.0)).toFloat();
        nodesOffset = 20;
        edgesOffset = nodesOffset + nodeCount * 4;
        var offset = edgesOffset + edgeCount * 4;
        // Hauptroute: Art (1), Länge (4), Namenslänge (2), Name, Punkte, Abbiegungen, Zuordnung.
        routeDistance = u32(offset + 1);
        var nameLength = u16(offset + 5);
        var nameBytes = data.slice(offset + 7, offset + 7 + nameLength);
        routeName = Toybox.StringUtil.convertEncodedString(nameBytes, {
            :fromRepresentation => Toybox.StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => Toybox.StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
        }) as String;
        offset += 7 + nameLength;
        pointCount = u16(offset);
        pointsOffset = offset + 2;
        offset = pointsOffset + pointCount * 4;
        maneuverCount = u16(offset);
        maneuversOffset = offset + 2;
        cumulative = new Array<Number>[pointCount];
        var total = 0.0;
        if (pointCount > 0) {
            cumulative[0] = 0;
        }
        for (var i = 1; i < pointCount; i++) {
            var dx = (pointX(i) - pointX(i - 1)).toFloat();
            var dy = (pointY(i) - pointY(i - 1)).toFloat();
            total += Math.sqrt(dx * dx + dy * dy);
            cumulative[i] = total.toNumber();
        }
    }

    // Zahlen (Little Endian)

    public function u16(offset as Number) as Number {
        return bytes[offset] | (bytes[offset + 1] << 8);
    }

    public function s16(offset as Number) as Number {
        var value = u16(offset);
        return value >= 32768 ? value - 65536 : value;
    }

    public function u32(offset as Number) as Number {
        return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
    }

    public function s32(offset as Number) as Number {
        return u32(offset);
    }

    // Wegenetz

    public function nodeX(index as Number) as Number {
        return s16(nodesOffset + index * 4);
    }

    public function nodeY(index as Number) as Number {
        return s16(nodesOffset + index * 4 + 2);
    }

    public function edgeA(index as Number) as Number {
        return u16(edgesOffset + index * 4);
    }

    public function edgeB(index as Number) as Number {
        return u16(edgesOffset + index * 4 + 2);
    }

    // Route

    public function pointX(index as Number) as Number {
        return s16(pointsOffset + index * 4);
    }

    public function pointY(index as Number) as Number {
        return s16(pointsOffset + index * 4 + 2);
    }

    public function maneuverPoint(index as Number) as Number {
        return u16(maneuversOffset + index * 3);
    }

    public function maneuverTurn(index as Number) as Number {
        return bytes[maneuversOffset + index * 3 + 2];
    }

    // Position in Metern um den Ursprung (wie LocalProjection in coach_core).
    public function project(lat as Double or Float, lon as Double or Float) as [Float, Float] {
        var x = ((lon - originLon) * _metersPerDegreeLon).toFloat();
        var y = ((lat - originLat) * 111320.0).toFloat();
        return [x, y];
    }
}
