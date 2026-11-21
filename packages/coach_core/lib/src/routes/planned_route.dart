import 'dart:typed_data';

import '../calendar/calendar_day.dart';
import '../fit/fit_encoder.dart';
import '../util/enum_codec.dart';
import '../util/swift_date.dart';
import 'geo.dart';
import 'route_planning.dart';

/// Geplante (vorgeschlagene oder gespeicherte) Route. Gehört genau einem Benutzer ([username]).
final class PlannedRoute {
  PlannedRoute({
    required this.id,
    required this.username,
    required this.name,
    required this.request,
    required this.variant,
    required this.points,
    required this.engine,
    required this.createdAt,
    this.plannedDay,
    this.slotID,
    this.slotTitle,
    Duration? duration,
    int? runThresholdPace,
  }) : stats = RouteStats.of(points),
       duration =
           duration ??
           RouteDuration.estimate(
             discipline: request.discipline,
             distanceMeters: Geo.length(points),
             ascentMeters: RouteStats.of(points).ascentMeters,
             runThresholdPace: runThresholdPace,
           );

  final String id;
  final String username;
  String name;
  final RouteRequest request;
  final RouteVariant variant;
  final List<GeoPoint> points;
  final RouteStats stats;
  final Duration duration;

  /// Quelle der Strecke (Router) für die Quellenangabe.
  final String engine;
  final DateTime createdAt;

  /// Übernommen in eine Einheit: Tag und optional die Einheit des Ausdauerplans.
  CalendarDay? plannedDay;
  String? slotID;
  String? slotTitle;

  RouteDiscipline get discipline => request.discipline;

  bool get isLoop => request.shape == RouteShape.loop;

  /// Höchstzahl gespeicherter Punkte (vereinfacht auf ~3 m genau, sonst gleichmäßig ausgedünnt).
  static const maxStoredPoints = 2500;

  static List<GeoPoint> storable(List<GeoPoint> points) {
    final simplified = Geo.simplify(points, 3);
    return Geo.thin(simplified, maxStoredPoints);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'name': name,
    'request': request.toJson(),
    'variant': variant.rawValue,
    'shape': Geo.encodePolyline(points),
    if (points.any((point) => point.elevation != null))
      'elevation': [for (final point in points) point.elevation == null ? null : (point.elevation! * 10).round()],
    'durationSeconds': duration.inSeconds,
    'engine': engine,
    'createdAt': swiftDateToJson(createdAt),
    'plannedDay': ?plannedDay?.iso,
    'slotID': ?slotID,
    'slotTitle': ?slotTitle,
  };

  /// Nur Routen von [username]; fremde oder kaputte Einträge: `null`.
  static PlannedRoute? fromJson(Object? json, {required String username}) {
    if (json is! Map) return null;
    final id = json['id'];
    final owner = json['username'];
    final name = json['name'];
    final request = RouteRequest.fromJson(json['request']);
    final variant = enumFromRaw(RouteVariant.values, json['variant']);
    final shape = json['shape'];
    final created = swiftDateFromJson(json['createdAt']);
    if (id is! String || owner != username || name is! String || request == null || variant == null) return null;
    if (shape is! String || created == null) return null;
    var points = Geo.decodePolyline(shape);
    final elevation = json['elevation'];
    if (elevation is List && elevation.length == points.length) {
      points = [
        for (final (index, point) in points.indexed)
          point.withElevation(elevation[index] is num ? (elevation[index] as num) / 10 : null),
      ];
    }
    if (points.length < 2) return null;
    final seconds = json['durationSeconds'];
    final day = json['plannedDay'];
    return PlannedRoute(
      id: id,
      username: owner as String,
      name: name,
      request: request,
      variant: variant,
      points: points,
      engine: '${json['engine'] ?? ''}',
      createdAt: created,
      duration: seconds is num ? Duration(seconds: seconds.toInt()) : null,
      plannedDay: day is String ? CalendarDay.tryParse(day) : null,
      slotID: json['slotID'] is String ? json['slotID'] as String : null,
      slotTitle: json['slotTitle'] is String ? json['slotTitle'] as String : null,
    );
  }

  /// Vorschlag für den Namen: „Rundweg 10,2 km · Grün & verkehrsarm“.
  static String suggestedName(RouteRequest request, RouteVariant variant, double meters) {
    final kilometers = (meters / 100).round() / 10;
    final distance = '${kilometers.toStringAsFixed(1).replaceAll('.', ',')} km';
    return '${request.shape.label} $distance · ${variant.label}';
  }
}

/// Alle gespeicherten Routen eines Benutzers (Schlüssel `coach.routes`).
final class RouteLibrary {
  RouteLibrary({required this.username, List<PlannedRoute>? routes}) : routes = routes ?? [];

  final String username;
  final List<PlannedRoute> routes;

  static const maxRoutes = 60;

  /// Neue Route vorn; bei gleicher ID ersetzt. Ältere über [maxRoutes] fallen weg.
  void save(PlannedRoute route) {
    if (route.username != username) throw StateError('Die Route gehört einem anderen Benutzer.');
    routes
      ..removeWhere((item) => item.id == route.id)
      ..insert(0, route);
    if (routes.length > maxRoutes) routes.removeRange(maxRoutes, routes.length);
  }

  void delete(String id) => routes.removeWhere((route) => route.id == id);

  PlannedRoute? route(String id) => routes.where((route) => route.id == id).firstOrNull;

  /// Routen, die für [day] in eine Einheit übernommen wurden.
  List<PlannedRoute> plannedOn(CalendarDay day) => [
    for (final route in routes)
      if (route.plannedDay == day) route,
  ];

  Map<String, Object?> toJson() => {
    'username': username,
    'routes': [for (final route in routes) route.toJson()],
  };

  /// Gehört die Ablage einem anderen Benutzer, `null` (wird nicht geladen und nicht überschrieben).
  static RouteLibrary? fromJson(Object? json, {required String username}) {
    if (json is! Map || json['username'] != username) return null;
    final list = json['routes'];
    return RouteLibrary(
      username: username,
      routes: [
        if (list is List)
          for (final item in list) ?PlannedRoute.fromJson(item, username: username),
      ],
    );
  }
}

/// GPX 1.1 für Sportuhren, Radcomputer und Karten-Apps.
abstract final class GpxExport {
  static String xml(PlannedRoute route, {String creator = 'AIronLudi'}) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="${_escape(creator)}" xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(route.name)}</name>')
      ..writeln(
        '    <copyright author="OpenStreetMap-Mitwirkende"><license>https://opendatacommons.org/licenses/odbl/</license></copyright>',
      )
      ..writeln('    <time>${route.createdAt.toUtc().toIso8601String().split('.').first}Z</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(route.name)}</name>')
      ..writeln('    <type>${route.discipline.isBike ? 'cycling' : 'running'}</type>')
      ..writeln('    <trkseg>');
    for (final point in route.points) {
      final position = 'lat="${point.latitude.toStringAsFixed(6)}" lon="${point.longitude.toStringAsFixed(6)}"';
      if (point.elevation case final elevation?) {
        buffer.writeln('      <trkpt $position><ele>${elevation.toStringAsFixed(1)}</ele></trkpt>');
      } else {
        buffer.writeln('      <trkpt $position/>');
      }
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  /// Dateiname ohne Sonderzeichen: `route-2026-11-21-rundweg-10-2-km.gpx`.
  static String fileName(PlannedRoute route, {String extension = 'gpx'}) {
    final day = CalendarDay.fromDate(route.createdAt.toLocal()).iso;
    final slug = route.name
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss')
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    final short = slug.length > 40 ? slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '') : slug;
    return 'route-$day${short.isEmpty ? '' : '-$short'}.$extension';
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// FIT-Kurs (Dateityp „course“) für Garmin-Uhren und Radcomputer: Kurs, Runde, Punkte mit Strecke und Höhe.
abstract final class FitCourseFile {
  static const fileTypeCourse = 6;

  /// Halbkreise (FIT-Einheit für Koordinaten).
  static int semicircles(double degrees) => (degrees * 2147483648 / 180).round();

  static Uint8List bytes(PlannedRoute route, {required DateTime created}) {
    final encoder = FitEncoder();
    final stamp = FitEncoder.timestamp(created);
    final sport = route.discipline.isBike ? 2 : 1;
    encoder
      ..add(
        global: 0,
        fields: [
          const FitField(0, FitBaseType.enumeration, fileTypeCourse),
          const FitField(1, FitBaseType.uint16, 255), // Hersteller: development
          const FitField(2, FitBaseType.uint16, 1),
          FitField(3, FitBaseType.uint32z, stamp == 0 ? 1 : stamp),
          FitField(4, FitBaseType.uint32, stamp),
        ],
      )
      ..add(
        global: 31, // course
        fields: [FitField(4, FitBaseType.enumeration, sport), FitField.text(5, route.name, size: 32)],
      );
    final points = route.points;
    final cumulative = Geo.cumulative(points);
    // Zeitstempel aus der geschätzten Dauer (gleichmäßig über die Strecke), damit Uhren ein virtuelles Tempo haben.
    final total = cumulative.last <= 0 ? 1.0 : cumulative.last;
    int timeAt(int index) => stamp + (route.duration.inSeconds * cumulative[index] / total).round();
    final first = points.first;
    final last = points.last;
    encoder
      ..add(
        global: 19, // lap
        fields: [
          FitField(253, FitBaseType.uint32, stamp),
          FitField(2, FitBaseType.uint32, stamp),
          FitField(3, FitBaseType.sint32, semicircles(first.latitude)),
          FitField(4, FitBaseType.sint32, semicircles(first.longitude)),
          FitField(5, FitBaseType.sint32, semicircles(last.latitude)),
          FitField(6, FitBaseType.sint32, semicircles(last.longitude)),
          FitField(7, FitBaseType.uint32, route.duration.inSeconds * 1000),
          FitField(8, FitBaseType.uint32, route.duration.inSeconds * 1000),
          FitField(9, FitBaseType.uint32, (total * 100).round()),
          FitField(21, FitBaseType.uint16, route.stats.ascentMeters.round()),
          FitField(22, FitBaseType.uint16, route.stats.descentMeters.round()),
        ],
      )
      ..add(
        global: 21, // event: Timer Start
        fields: [
          FitField(253, FitBaseType.uint32, stamp),
          const FitField(0, FitBaseType.enumeration, 0),
          const FitField(1, FitBaseType.enumeration, 0),
        ],
      );
    for (final (index, point) in points.indexed) {
      encoder.add(
        global: 20, // record
        fields: [
          FitField(253, FitBaseType.uint32, timeAt(index)),
          FitField(0, FitBaseType.sint32, semicircles(point.latitude)),
          FitField(1, FitBaseType.sint32, semicircles(point.longitude)),
          FitField(5, FitBaseType.uint32, (cumulative[index] * 100).round()),
          if (point.elevation case final elevation?)
            FitField(2, FitBaseType.uint16, ((elevation + 500) * 5).round().clamp(0, 0xFFFE)),
        ],
      );
    }
    encoder.add(
      global: 21, // event: Timer Stop (alle)
      fields: [
        FitField(253, FitBaseType.uint32, timeAt(points.length - 1)),
        const FitField(0, FitBaseType.enumeration, 0),
        const FitField(1, FitBaseType.enumeration, 9),
      ],
    );
    return encoder.data();
  }
}
