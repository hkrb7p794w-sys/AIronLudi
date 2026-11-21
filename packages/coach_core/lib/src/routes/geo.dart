import 'dart:math' as math;

/// Punkt auf der Erde (WGS 84) mit optionaler Höhe in Metern.
final class GeoPoint {
  const GeoPoint(this.latitude, this.longitude, {this.elevation});

  final double latitude;
  final double longitude;
  final double? elevation;

  GeoPoint withElevation(double? value) => GeoPoint(latitude, longitude, elevation: value);

  bool get isValid => latitude.isFinite && longitude.isFinite && latitude.abs() <= 90 && longitude.abs() <= 180;

  /// Kompakt als `[lat, lon]` bzw. `[lat, lon, ele]` (6 bzw. 1 Nachkommastelle).
  List<double> toJson() => [
    _round(latitude, 1e6),
    _round(longitude, 1e6),
    if (elevation case final elevation?) _round(elevation, 10),
  ];

  static GeoPoint? fromJson(Object? json) {
    if (json is! List || json.length < 2) return null;
    final [latitude, longitude, ...rest] = json;
    if (latitude is! num || longitude is! num) return null;
    final elevation = rest.firstOrNull;
    final point = GeoPoint(
      latitude.toDouble(),
      longitude.toDouble(),
      elevation: elevation is num ? elevation.toDouble() : null,
    );
    return point.isValid ? point : null;
  }

  static double _round(double value, double factor) => (value * factor).roundToDouble() / factor;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitude == latitude && other.longitude == longitude && other.elevation == elevation;

  @override
  int get hashCode => Object.hash(latitude, longitude, elevation);

  @override
  String toString() => 'GeoPoint($latitude, $longitude${elevation == null ? '' : ', $elevation m'})';
}

/// Geometrie auf der Kugel: Abstände, Richtungen, Polylinien, Vereinfachung und Flächen.
abstract final class Geo {
  /// Mittlerer Erdradius (IUGG) in Metern.
  static const earthRadius = 6371008.8;

  static double _rad(double degrees) => degrees * math.pi / 180;
  static double _deg(double radians) => radians * 180 / math.pi;

  /// Großkreisabstand (Haversine) in Metern.
  static double distance(GeoPoint a, GeoPoint b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLon / 2), 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Anfangsrichtung von [a] nach [b] in Grad (0 = Nord, 90 = Ost).
  static double bearing(GeoPoint a, GeoPoint b) {
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (_deg(math.atan2(y, x)) + 360) % 360;
  }

  /// Punkt in [meters] Entfernung von [from] in Richtung [bearingDegrees].
  static GeoPoint destination(GeoPoint from, double bearingDegrees, double meters) {
    final angular = meters / earthRadius;
    final theta = _rad(bearingDegrees);
    final lat1 = _rad(from.latitude);
    final lon1 = _rad(from.longitude);
    final lat2 = math.asin(math.sin(lat1) * math.cos(angular) + math.cos(lat1) * math.sin(angular) * math.cos(theta));
    final lon2 =
        lon1 +
        math.atan2(
          math.sin(theta) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );
    return GeoPoint(_deg(lat2), (_deg(lon2) + 540) % 360 - 180);
  }

  /// Mittelpunkt zweier Punkte (für kurze Strecken ausreichend genau).
  static GeoPoint midpoint(GeoPoint a, GeoPoint b) => destination(a, bearing(a, b), distance(a, b) / 2);

  /// Länge der Linie in Metern.
  static double length(List<GeoPoint> points) {
    var total = 0.0;
    for (var index = 1; index < points.length; index++) {
      total += distance(points[index - 1], points[index]);
    }
    return total;
  }

  /// Zurückgelegte Strecke bis zu jedem Punkt (erster Wert 0).
  static List<double> cumulative(List<GeoPoint> points) {
    final result = <double>[];
    var total = 0.0;
    for (var index = 0; index < points.length; index++) {
      if (index > 0) total += distance(points[index - 1], points[index]);
      result.add(total);
    }
    return result;
  }

  // Polylinien (Google-Format, wie Valhalla mit Genauigkeit 6)

  static List<GeoPoint> decodePolyline(String encoded, {int precision = 6}) {
    final factor = math.pow(10, precision).toDouble();
    final points = <GeoPoint>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    int next() {
      var result = 0;
      var shift = 0;
      while (index < encoded.length) {
        final byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
        if (byte < 0x20) break;
      }
      return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    }

    while (index < encoded.length) {
      latitude += next();
      if (index >= encoded.length) break;
      longitude += next();
      points.add(GeoPoint(latitude / factor, longitude / factor));
    }
    return points;
  }

  static String encodePolyline(List<GeoPoint> points, {int precision = 6}) {
    final factor = math.pow(10, precision).toDouble();
    final buffer = StringBuffer();
    var lastLatitude = 0;
    var lastLongitude = 0;
    void write(int value) {
      var rest = value < 0 ? ~(value << 1) : value << 1;
      while (rest >= 0x20) {
        buffer.writeCharCode((0x20 | (rest & 0x1F)) + 63);
        rest >>= 5;
      }
      buffer.writeCharCode(rest + 63);
    }

    for (final point in points) {
      final latitude = (point.latitude * factor).round();
      final longitude = (point.longitude * factor).round();
      write(latitude - lastLatitude);
      write(longitude - lastLongitude);
      lastLatitude = latitude;
      lastLongitude = longitude;
    }
    return buffer.toString();
  }

  // Ebene Näherung um einen Bezugspunkt (für Vereinfachung, Flächen, Punkt-in-Polygon)

  static ({double x, double y}) _project(GeoPoint point, GeoPoint origin) {
    final x = _rad(point.longitude - origin.longitude) * math.cos(_rad(origin.latitude)) * earthRadius;
    final y = _rad(point.latitude - origin.latitude) * earthRadius;
    return (x: x, y: y);
  }

  /// Douglas-Peucker mit Toleranz in Metern; erster und letzter Punkt bleiben.
  static List<GeoPoint> simplify(List<GeoPoint> points, double toleranceMeters) {
    if (points.length < 3 || toleranceMeters <= 0) return [...points];
    final origin = points.first;
    final projected = [for (final point in points) _project(point, origin)];
    final keep = List<bool>.filled(points.length, false)
      ..[0] = true
      ..[points.length - 1] = true;
    final stack = <(int, int)>[(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (first, last) = stack.removeLast();
      if (last - first < 2) continue;
      final a = projected[first];
      final b = projected[last];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final lengthSquared = dx * dx + dy * dy;
      var farthest = -1.0;
      var farthestIndex = first;
      for (var index = first + 1; index < last; index++) {
        final p = projected[index];
        double distance;
        if (lengthSquared == 0) {
          distance = math.sqrt(math.pow(p.x - a.x, 2) + math.pow(p.y - a.y, 2));
        } else {
          final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared).clamp(0.0, 1.0);
          distance = math.sqrt(math.pow(p.x - (a.x + t * dx), 2) + math.pow(p.y - (a.y + t * dy), 2));
        }
        if (distance > farthest) {
          farthest = distance;
          farthestIndex = index;
        }
      }
      if (farthest > toleranceMeters) {
        keep[farthestIndex] = true;
        stack
          ..add((first, farthestIndex))
          ..add((farthestIndex, last));
      }
    }
    return [
      for (var index = 0; index < points.length; index++)
        if (keep[index]) points[index],
    ];
  }

  /// Höchstens [maxPoints] Punkte in gleichmäßigen Abständen (erster und letzter bleiben).
  static List<GeoPoint> thin(List<GeoPoint> points, int maxPoints) {
    if (points.length <= maxPoints || maxPoints < 2) return [...points];
    final step = (points.length - 1) / (maxPoints - 1);
    return [for (var index = 0; index < maxPoints; index++) points[(index * step).round()]];
  }

  /// Fläche des (geschlossenen gedachten) Polygons in m² (Gauß'sche Trapezformel, ebene Näherung).
  static double area(List<GeoPoint> polygon) {
    if (polygon.length < 3) return 0;
    final origin = polygon.first;
    final projected = [for (final point in polygon) _project(point, origin)];
    var sum = 0.0;
    for (var index = 0; index < projected.length; index++) {
      final a = projected[index];
      final b = projected[(index + 1) % projected.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  /// Liegt [point] im Polygon (Strahlverfahren, gerade-ungerade)?
  static bool contains(List<GeoPoint> polygon, GeoPoint point) {
    var inside = false;
    for (var index = 0, previous = polygon.length - 1; index < polygon.length; previous = index++) {
      final a = polygon[index];
      final b = polygon[previous];
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude)) {
        final crossing =
            (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude;
        if (point.longitude < crossing) inside = !inside;
      }
    }
    return inside;
  }

  /// Umgebendes Rechteck (Süd, West, Nord, Ost).
  static ({double south, double west, double north, double east}) bounds(List<GeoPoint> points) {
    var south = 90.0, west = 180.0, north = -90.0, east = -180.0;
    for (final point in points) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    return (south: south, west: west, north: north, east: east);
  }
}
