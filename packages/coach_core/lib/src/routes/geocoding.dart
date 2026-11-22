// Adresssuche für Start und Ziel des Routenplaners (neu in AIronLudi): Photon (komoot, OSM-Daten) mit Vorschlägen
// beim Tippen, Nominatim (OSM Foundation) als Ausweich – beide ohne Schlüssel.
import 'geo.dart';
import 'routing_formats.dart';

/// Gefundener Ort: Titel („Hauptstraße 5“), Zusatz („10827 Berlin“) und Lage.
final class Place {
  const Place({required this.title, required this.detail, required this.point});

  final String title;
  final String detail;
  final GeoPoint point;

  /// Für das Adressfeld nach der Auswahl.
  String get label => detail.isEmpty ? title : '$title, $detail';

  @override
  bool operator ==(Object other) => other is Place && other.label == label && other.point == point;

  @override
  int get hashCode => Object.hash(label, point);
}

/// Sucht Orte zu einem Text; wirft [RoutingUnavailable], wenn kein Dienst antwortet.
abstract interface class PlaceSearch {
  /// [near]: bevorzugt Treffer in der Nähe (z. B. Kartenmitte). [typing]: Vorschläge beim Tippen (nur Photon).
  Future<List<Place>> search(String query, {GeoPoint? near, bool typing = false});
}

abstract final class GeocodingFormat {
  /// Kürzeste Eingabe für eine Suche.
  static const minLength = 3;
  static const maxResults = 6;

  static String? normalized(String query) {
    final text = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.length < minLength ? null : text;
  }

  // Photon

  static Uri photonUri(String query, {GeoPoint? near}) => Uri.https('photon.komoot.io', '/api/', {
    'q': query,
    'lang': 'de',
    'limit': '$maxResults',
    if (near != null) ...{'lat': near.latitude.toStringAsFixed(4), 'lon': near.longitude.toStringAsFixed(4)},
  });

  static List<Place> parsePhoton(Object? json) {
    if (json is! Map) throw const RoutingUnavailable('Antwort der Adresssuche unlesbar.');
    final features = json['features'];
    if (features is! List) return const [];
    final result = <Place>[];
    for (final feature in features) {
      if (feature is! Map) continue;
      final coordinates = feature['geometry'] is Map ? (feature['geometry'] as Map)['coordinates'] : null;
      final properties = feature['properties'] is Map ? feature['properties'] as Map : const <String, Object?>{};
      if (coordinates case [final num longitude, final num latitude, ...]) {
        String? text(String key) =>
            properties[key] is String && (properties[key] as String).isNotEmpty ? properties[key] as String : null;
        final street = [?text('street'), ?text('housenumber')].join(' ');
        final name = text('name');
        final title = name ?? (street.isEmpty ? null : street);
        if (title == null) continue;
        final city = [
          ?text('postcode'),
          ?(text('city') ?? text('town') ?? text('village') ?? text('district')),
        ].join(' ');
        final detail = [
          if (name != null && street.isNotEmpty && street != name) street,
          if (city.isNotEmpty) city,
          if (city.isEmpty) ?text('state'),
          if (text('countrycode') case final code? when code.toUpperCase() != 'DE') ?text('country'),
        ].join(', ');
        final point = GeoPoint(latitude.toDouble(), longitude.toDouble());
        if (point.isValid) result.add(Place(title: title, detail: detail, point: point));
      }
    }
    return _unique(result);
  }

  // Nominatim (nur bei ausdrücklicher Suche, nicht beim Tippen – Nutzungsregeln der OSM Foundation)

  static Uri nominatimUri(String query) => Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': query,
    'format': 'jsonv2',
    'limit': '$maxResults',
    'accept-language': 'de',
    'addressdetails': '0',
  });

  static List<Place> parseNominatim(Object? json) {
    if (json is! List) throw const RoutingUnavailable('Antwort der Adresssuche unlesbar.');
    final result = <Place>[];
    for (final item in json) {
      if (item is! Map) continue;
      final latitude = double.tryParse('${item['lat']}');
      final longitude = double.tryParse('${item['lon']}');
      final display = item['display_name'];
      if (latitude == null || longitude == null || display is! String) continue;
      final parts = display.split(', ');
      final name = item['name'] is String && (item['name'] as String).isNotEmpty ? item['name'] as String : parts.first;
      final rest = parts.skipWhile((part) => part == name).take(3).join(', ');
      final point = GeoPoint(latitude, longitude);
      if (point.isValid) result.add(Place(title: name, detail: rest, point: point));
    }
    return _unique(result);
  }

  static List<Place> _unique(List<Place> places) {
    final seen = <String>{};
    return [
      for (final place in places)
        if (seen.add(place.label)) place,
    ];
  }

  /// Koordinaten direkt eingegeben („52.52, 13.405“ oder „52,52 13,405“)?
  static GeoPoint? coordinates(String query) {
    final match = RegExp(r'^\s*(-?\d{1,2}(?:[.,]\d+)?)\s*[,; ]\s*(-?\d{1,3}(?:[.,]\d+)?)\s*$').firstMatch(query);
    if (match == null) return null;
    final latitude = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    final longitude = double.tryParse(match.group(2)!.replaceAll(',', '.'));
    if (latitude == null || longitude == null) return null;
    final point = GeoPoint(latitude, longitude);
    return point.isValid ? point : null;
  }

  /// Entfernung für die Vorschlagsliste („2,4 km“), sofern ein Bezugspunkt bekannt ist.
  static String? distanceLabel(Place place, GeoPoint? from) {
    if (from == null) return null;
    final meters = Geo.distance(from, place.point);
    if (meters < 1000) return '${meters.round()} m';
    final kilometers = meters / 1000;
    return kilometers >= 100 ? '${kilometers.round()} km' : '${kilometers.toStringAsFixed(1).replaceAll('.', ',')} km';
  }
}
