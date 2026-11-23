// Routenplaner in der App: Router mit Ausweichen und Rate-Limit, Speicher strikt je Benutzer.
import 'dart:convert';
import 'dart:typed_data';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/routing/garmin_course_service.dart';
import 'package:aironludi/services/routing/route_stores.dart';
import 'package:aironludi/services/routing/route_weather_service.dart';
import 'package:aironludi/services/routing/routing_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const start = GeoPoint(52.52, 13.405);
const end = GeoPoint(52.53, 13.42);

HttpResponse json(Object body, {int status = 200, Map<String, String>? headers}) =>
    HttpResponse(status, utf8.encode(jsonEncode(body)), headers: headers);

Map<String, Object?> valhallaTrip(List<GeoPoint> points) => {
  'trip': {
    'legs': [
      {'shape': Geo.encodePolyline(points)},
    ],
    'summary': {'length': Geo.length(points) / 1000},
  },
};

Map<String, Object?> brouterTrip(List<GeoPoint> points) => {
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'properties': {'track-length': '${Geo.length(points).round()}'},
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final point in points) [point.longitude, point.latitude, 40.0],
        ],
      },
    },
  ],
};

RateGate instantGate() => RateGate(Duration.zero, wait: (_) async {});

void main() {
  group('Router', () {
    test('Valhalla: Anfrage als JSON-POST, Antwort mit Linie', () async {
      final transport = FakeHttpTransport((request) => json(valhallaTrip([start, end])));
      final engine = ValhallaEngine(transport, gate: instantGate());
      final path = await engine.route([start, end], discipline: RouteDiscipline.gravel, variant: RouteVariant.balanced);
      expect(path.points.length, 2);
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.url, ValhallaFormat.routeUri);
      final body = jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
      expect(body['costing'], 'bicycle');
      expect(request.headers['User-Agent'], contains('AIronLudi'));
    });

    test('Valhalla gestört (429): Ausweichen auf BRouter, danach Valhalla eine Weile übersprungen', () async {
      final transport = FakeHttpTransport((request) {
        if (request.url.host == 'valhalla1.openstreetmap.de') {
          return json({'error': 'Too many requests'}, status: 429, headers: {'retry-after': '30'});
        }
        return json(brouterTrip([start, end]));
      });
      final backend = FallbackRoutingBackend([
        ValhallaEngine(transport, gate: instantGate()),
        BRouterEngine(transport, gate: instantGate()),
      ]);
      final path = await backend.route([start, end], discipline: RouteDiscipline.run, variant: RouteVariant.green);
      expect(path.engine, BRouterFormat.engineName);
      expect(path.hasElevation, isTrue);
      await backend.route([end, start], discipline: RouteDiscipline.run, variant: RouteVariant.green);
      expect(transport.requests.where((request) => request.url.host == 'valhalla1.openstreetmap.de').length, 1);
      // Gleiche Anfrage: aus dem Zwischenspeicher.
      await backend.route([start, end], discipline: RouteDiscipline.run, variant: RouteVariant.green);
      expect(transport.requests.length, 3);
    });

    test('Kein Weg: kein Ausweichen (anderer Router hilft nicht), Fehler geht an den Planer', () async {
      final transport = FakeHttpTransport(
        (request) => json({'error_code': 442, 'error': 'No path could be found for input'}, status: 400),
      );
      final backend = FallbackRoutingBackend([
        ValhallaEngine(transport, gate: instantGate()),
        BRouterEngine(transport, gate: instantGate()),
      ]);
      await expectLater(
        backend.route([start, end], discipline: RouteDiscipline.run, variant: RouteVariant.balanced),
        throwsA(isA<NoRouteFound>()),
      );
      expect(transport.requests.length, 1);
    });

    test('Kein Netz: alle Router gestört', () async {
      final transport = FakeHttpTransport((request) => throw const HttpTransportException('offline'));
      final backend = FallbackRoutingBackend([
        ValhallaEngine(transport, gate: instantGate()),
        BRouterEngine(transport, gate: instantGate()),
      ]);
      await expectLater(
        backend.route([start, end], discipline: RouteDiscipline.run, variant: RouteVariant.balanced),
        throwsA(isA<RoutingUnavailable>()),
      );
      // Je Router ein zweiter Versuch nach dem Verbindungsabbruch.
      expect(transport.requests.length, 4);
    });

    test('Einzelner Verbindungsabbruch: zweiter Versuch gelingt', () async {
      var calls = 0;
      final transport = FakeHttpTransport((request) {
        calls++;
        if (calls == 1) throw const HttpTransportException('Verbindung abgebrochen');
        return json(valhallaTrip([start, end]));
      });
      final path = await ValhallaEngine(
        transport,
        gate: instantGate(),
      ).route([start, end], discipline: RouteDiscipline.run, variant: RouteVariant.balanced);
      expect(path.points.length, 2);
      expect(calls, 2);
    });

    test('Höhen über Valhalla', () async {
      final transport = FakeHttpTransport(
        (request) => json({
          'height': [34, 36],
        }),
      );
      final backend = FallbackRoutingBackend([
        ValhallaEngine(transport, gate: instantGate()),
        BRouterEngine(transport, gate: instantGate()),
      ]);
      expect(await backend.elevations([start, end]), [34, 36]);
      expect(transport.requests.single.url, ValhallaFormat.heightUri);
    });

    test('Wegarten gehen an Valhalla und BRouter', () async {
      final transport = FakeHttpTransport((request) {
        if (request.url.host == 'valhalla1.openstreetmap.de') return json({'error': 'busy'}, status: 503);
        return json(brouterTrip([start, end]));
      });
      final backend = FallbackRoutingBackend([
        ValhallaEngine(transport, gate: instantGate()),
        BRouterEngine(transport, gate: instantGate()),
      ]);
      await backend.route(
        [start, end],
        discipline: RouteDiscipline.gravel,
        variant: RouteVariant.balanced,
        preferences: {RoutePreference.nature},
      );
      final body = jsonDecode(utf8.decode(transport.requests.first.body!)) as Map<String, Object?>;
      expect(((body['costing_options']! as Map)['bicycle'] as Map)['bicycle_type'], 'Mountain');
      expect(transport.requests.last.url.queryParameters['profile'], 'mtb');
    });

    test(
      'Overpass: POST mit Abfrage, Knoten, Zwischenspeicher, Ausweichen auf Spiegel, Ausfall meldet Fehler',
      () async {
        final down = <String>{};
        final transport = FakeHttpTransport((request) {
          if (down.contains(request.url.host)) return json({'error': 'busy'}, status: 504);
          return json({
            'elements': [
              {'type': 'node', 'id': 7, 'lat': 52.521, 'lon': 13.41},
            ],
          });
        });
        final source = OverpassFeatureSource(transport, gate: instantGate());
        final points = await source.attractors(start, 3000, {RoutePreference.water});
        expect(points, [const GeoPoint(52.521, 13.41)]);
        final request = transport.requests.single;
        expect(request.method, 'POST');
        expect(request.url, OverpassFormat.uri);
        final query = Uri.splitQueryString(utf8.decode(request.body!))['data']!;
        expect(query, contains('waterway'));
        expect(query, contains('node(w.all)'));
        await source.attractors(start, 3000, {RoutePreference.water});
        expect(transport.requests.length, 1);
        // Hauptserver gestört: der erste Spiegel antwortet.
        down.add(OverpassFormat.uris.first.host);
        expect(await source.attractors(start, 3000, {RoutePreference.nature}), isNotEmpty);
        expect(transport.requests.last.url, OverpassFormat.uris[1]);
        // Alle gestört: Fehler statt still leerer Liste (der Planer zeigt dann einen Hinweis).
        down.addAll([for (final uri in OverpassFormat.uris) uri.host]);
        await expectLater(source.attractors(start, 4000, {RoutePreference.nature}), throwsA(isA<RoutingUnavailable>()));
        final offline = OverpassFeatureSource(
          FakeHttpTransport((request) => throw const HttpTransportException('offline')),
          gate: instantGate(),
        );
        await expectLater(offline.attractors(start, 3000, {RoutePreference.water}), throwsA(isA<RoutingUnavailable>()));
      },
    );

    test('Adresssuche: Photon zuerst, bei Ausfall Nominatim – beim Tippen nie Nominatim', () async {
      var photonDown = false;
      final transport = FakeHttpTransport((request) {
        if (request.url.host == 'photon.komoot.io') {
          if (photonDown) return json({'message': 'down'}, status: 503);
          return json({
            'features': [
              {
                'geometry': {
                  'coordinates': [13.35, 52.49],
                },
                'properties': {'street': 'Hauptstraße', 'housenumber': '5', 'city': 'Berlin', 'countrycode': 'DE'},
              },
            ],
          });
        }
        return json([
          {
            'lat': '52.49',
            'lon': '13.35',
            'name': 'Hauptstraße 5',
            'display_name': 'Hauptstraße 5, Berlin, Deutschland',
          },
        ]);
      });
      final search = OsmPlaceSearch(transport, photonGate: instantGate(), nominatimGate: instantGate());
      final places = await search.search('Hauptstraße 5', near: start, typing: true);
      expect(places.single.label, 'Hauptstraße 5, Berlin');
      expect(transport.requests.single.url.queryParameters['lat'], '52.5200');
      expect(transport.requests.single.headers['User-Agent'], contains('AIronLudi'));
      // Gleiche Suche: aus dem Zwischenspeicher.
      await search.search('Hauptstraße 5', near: start, typing: true);
      expect(transport.requests.length, 1);
      photonDown = true;
      await expectLater(search.search('Tempelhofer Feld', typing: true), throwsA(isA<RoutingUnavailable>()));
      expect(transport.requests.where((request) => request.url.host.startsWith('nominatim')), isEmpty);
      final fallback = await search.search('Tempelhofer Feld');
      expect(fallback.single.title, 'Hauptstraße 5');
      expect(transport.requests.last.url.host, 'nominatim.openstreetmap.org');
      // Koordinaten und zu kurze Eingaben brauchen keine Anfrage.
      final count = transport.requests.length;
      expect((await search.search('52.5, 13.4')).single.point, const GeoPoint(52.5, 13.4));
      expect(await search.search('ab'), isEmpty);
      expect(transport.requests.length, count);
    });

    test('Punkte unterwegs über Overpass: nur nahe der Strecke, Ausweichen, Ausfall meldet Fehler', () async {
      final down = <String>{};
      final transport = FakeHttpTransport((request) {
        if (down.contains(request.url.host)) return json({'error': 'busy'}, status: 504);
        return json({
          'elements': [
            {
              'type': 'node',
              'lat': 52.52,
              'lon': 13.405,
              'tags': {'amenity': 'drinking_water'},
            },
            {
              'type': 'node',
              'lat': 53.0,
              'lon': 13.0,
              'tags': {'amenity': 'drinking_water'},
            },
          ],
        });
      });
      final source = OverpassPoiSource(transport, gate: instantGate());
      final pois = await source.pois(const [start, end], kinds: {PoiKind.water});
      expect(pois.single.point, const GeoPoint(52.52, 13.405));
      expect(Uri.splitQueryString(utf8.decode(transport.requests.single.body!))['data'], contains('drinking_water'));
      down.add(OverpassFormat.uris.first.host);
      expect(await source.pois(const [start, end], kinds: {PoiKind.water, PoiKind.dogPark}), isNotEmpty);
      down.addAll([for (final uri in OverpassFormat.uris) uri.host]);
      await expectLater(source.pois(const [start, end], kinds: {PoiKind.bags}), throwsA(isA<RoutingUnavailable>()));
    });

    test('Rate-Limit: Anfragen nacheinander mit Mindestabstand', () async {
      var now = DateTime.utc(2026, 11, 21, 8);
      final waits = <Duration>[];
      final gate = RateGate(
        const Duration(seconds: 1),
        now: () => now,
        wait: (duration) async {
          waits.add(duration);
          now = now.add(duration);
        },
      );
      final order = <int>[];
      await Future.wait([for (var index = 0; index < 3; index++) gate.run(() async => order.add(index))]);
      expect(order, [0, 1, 2]);
      expect(waits, [const Duration(seconds: 1), const Duration(seconds: 1)]);
      gate.backOff(const Duration(seconds: 5));
      await gate.run(() async {});
      expect(waits.last, const Duration(seconds: 5));
    });
  });

  test('Wetter: Open-Meteo stündlich, eine halbe Stunde zwischengespeichert', () async {
    final urls = <Uri>[];
    var clock = DateTime.utc(2026, 11, 23, 8);
    final weather = OpenMeteoWeather(
      FakeHttpTransport((request) {
        urls.add(request.url);
        return json({
          'hourly': {
            'time': ['2026-11-24T10:00', '2026-11-24T11:00'],
            'temperature_2m': [7.5, 8],
            'wind_speed_10m': [12, 14],
            'wind_direction_10m': [250, 260],
          },
        });
      }),
      now: () => clock,
    );
    final hours = await weather.forecast(start, const CalendarDay(2026, 11, 24));
    expect(hours.length, 2);
    expect(urls.single.host, 'api.open-meteo.com');
    await weather.forecast(start, const CalendarDay(2026, 11, 24));
    expect(urls.length, 1);
    clock = clock.add(const Duration(minutes: 31));
    await weather.forecast(start, const CalendarDay(2026, 11, 24));
    expect(urls.length, 2);
  });

  group('Kurs an Garmin', () {
    PlannedRoute course() => PlannedRoute(
      id: 'k',
      username: 'anna',
      name: 'Kurs',
      request: const RouteRequest(
        discipline: RouteDiscipline.run,
        shape: RouteShape.loop,
        start: start,
        distanceMeters: 5000,
      ),
      variant: RouteVariant.balanced,
      points: const [start, end, start],
      engine: 'Test',
      createdAt: DateTime.utc(2026, 11, 22),
    );

    test('ohne Anmeldung: Hinweis, nichts gesendet', () async {
      var calls = 0;
      final result = await GarminCourseService.send(
        course(),
        isLoggedIn: false,
        sender: ({required method, required path, required json}) async {
          calls++;
          return utf8.encode('{}');
        },
      );
      expect(result, isA<GarminCourseFailed>().having((failed) => failed.needsLogin, 'needsLogin', isTrue));
      expect(calls, 0);
    });

    test('anlegen merkt die ID, erneut senden ersetzt den alten Kurs', () async {
      final requests = <String>[];
      final bodies = <Map<String, Object?>>[];
      var nextID = 100;
      Future<Uint8List> sender({required String method, required String path, required List<int> json}) async {
        requests.add('$method $path');
        if (json.isNotEmpty) bodies.add(jsonDecode(utf8.decode(json)) as Map<String, Object?>);
        return method == 'POST' ? utf8.encode(jsonEncode({'courseId': nextID++})) : Uint8List(0);
      }

      final route = course();
      final first = await GarminCourseService.send(route, isLoggedIn: true, sender: sender);
      expect(first, isA<GarminCourseSent>().having((sent) => sent.courseID, 'courseID', 100));
      expect(route.garminCourseID, 100);
      expect(bodies.single['activityTypePk'], 1);
      expect(PlannedRoute.fromJson(route.toJson(), username: 'anna')?.garminCourseID, 100);

      await GarminCourseService.send(route, isLoggedIn: true, sender: sender);
      expect(requests, [
        'POST /course-service/course',
        'DELETE /course-service/course/100',
        'POST /course-service/course',
      ]);
      expect(route.garminCourseID, 101);
    });

    test('Ablehnung oder Fehler: verständliche Meldung, ID bleibt', () async {
      final route = course()..garminCourseID = 7;
      final rejected = await GarminCourseService.send(
        route,
        isLoggedIn: true,
        sender: ({required method, required path, required json}) async =>
            method == 'POST' ? utf8.encode('{"message":"nope"}') : Uint8List(0),
      );
      expect(rejected, isA<GarminCourseFailed>());
      expect(rejected.message, contains('FIT'));
      final failed = await GarminCourseService.send(
        route,
        isLoggedIn: true,
        sender: ({required method, required path, required json}) async => throw StateError('offline'),
      );
      expect(failed.message, contains('Senden hat nicht geklappt'));
      expect(route.garminCourseID, 7);
    });
  });

  group('Speicher je Benutzer', () {
    PlannedRoute route(String username) => PlannedRoute(
      id: 'r-$username',
      username: username,
      name: 'Runde',
      request: const RouteRequest(
        discipline: RouteDiscipline.run,
        shape: RouteShape.loop,
        start: start,
        distanceMeters: 5000,
      ),
      variant: RouteVariant.balanced,
      points: const [start, end, start],
      engine: 'Test',
      createdAt: DateTime.utc(2026, 11, 21),
      plannedDay: CalendarDay(2026, 11, 21),
    );

    List<GeoPoint> ring() => [
      for (var angle = 0; angle <= 360; angle += 5) Geo.destination(Geo.destination(start, 0, 800), angle + 180.0, 800),
    ];

    test('Routen und Gebiete anderer Benutzer werden weder gezeigt noch überschrieben', () async {
      final settings = await SettingsStore.open(CoachDatabase(NativeDatabase.memory()));
      final anna = RouteStore(settings, username: 'anna');
      await anna.save(route('anna'));
      expect(() => anna.save(route('ben')), throwsStateError);
      expect(anna.plannedOn(CalendarDay(2026, 11, 21)).single.id, 'r-anna');

      // Gebiete sind aus, bis der Benutzer sie einschaltet.
      final track = ExplorationTrack(sourceID: 'a1', name: 'Runde', day: CalendarDay(2026, 11, 20), points: ring());
      expect(await anna.explore([track]), isEmpty);
      await anna.updateSettings((settings) => settings.explorationEnabled = true);
      final gains = await anna.explore([track]);
      expect(gains.single.territory, isNotNull);
      expect(anna.isExplored('a1'), isTrue);

      // Gleicher Speicher, anderer Benutzer (z. B. eingespielte Sicherung): nichts sichtbar, nichts überschreibbar.
      final ben = RouteStore(settings, username: 'ben');
      expect(ben.routes, isEmpty);
      expect(ben.exploration.tileCount, 0);
      expect(ben.hasForeignRoutes, isTrue);
      expect(ben.hasForeignExploration, isTrue);
      await expectLater(ben.save(route('ben')), throwsStateError);
      await ben.updateSettings((settings) => settings.explorationEnabled = true);
      expect(await ben.explore([track]), isEmpty);
      await ben.resetExploration();
      await ben.delete('r-anna');

      // Favoriten ebenso: nur für den eigenen Benutzer.
      final anna2 = RouteStore(settings, username: 'anna');
      await anna2.saveFavorite(
        FavoritePlace(id: 'f1', name: 'Zuhause', point: start, createdAt: DateTime.utc(2026, 11, 22)),
      );
      final ben2 = RouteStore(settings, username: 'ben');
      expect(ben2.favorites, isEmpty);
      expect(ben2.hasForeignFavorites, isTrue);
      await expectLater(
        ben2.saveFavorite(FavoritePlace(id: 'f2', name: 'Park', point: end, createdAt: DateTime.utc(2026, 11, 22))),
        throwsStateError,
      );
      await ben2.deleteFavorite('f1');

      // Archiv: Aktivität am geplanten Tag schließt die geplante Route ab (einmal).
      final archiveStore = RouteStore(settings, username: 'anna');
      final run = GarminActivity(42)
        ..typeKey = 'running'
        ..startLocal = '2026-11-21 08:00:00'
        ..distanceMeters = Geo.length(const [start, end, start]);
      expect(await archiveStore.completeFromActivities([run], now: DateTime.utc(2026, 11, 21, 10)), 1);
      expect(archiveStore.archive.single.activityID, 42);
      expect(archiveStore.openRoutes, isEmpty);
      expect(await archiveStore.completeFromActivities([run]), 0);
      await archiveStore.setCompleted(archiveStore.archive.single, completed: false);
      expect(archiveStore.openRoutes.single.isCompleted, isFalse);

      // Vorlagen ebenso nur für den eigenen Benutzer.
      await anna2.saveTemplate(
        const RouteTemplate(
          id: 't1',
          name: 'Gassi',
          discipline: RouteDiscipline.walk,
          shape: RouteShape.loop,
          kilometers: 3,
          start: start,
        ),
      );
      expect(ben2.templates, isEmpty);
      expect(RouteStore(settings, username: 'ben').hasForeignTemplates, isTrue);
      await expectLater(
        RouteStore(settings, username: 'ben').saveTemplate(
          const RouteTemplate(
            id: 't2',
            name: 'X',
            discipline: RouteDiscipline.run,
            shape: RouteShape.loop,
            kilometers: 5,
            start: end,
          ),
        ),
        throwsStateError,
      );

      final again = RouteStore(settings, username: 'anna');
      expect(again.templates.single.name, 'Gassi');
      expect(again.favorites.single.name, 'Zuhause');
      expect(AppBackup.isBackedUp(SettingsKeys.favoritePlaces), isTrue);
      expect(again.routes.single.id, 'r-anna');
      expect(again.exploration.territories.length, 1);
      expect(AppBackup.isBackedUp(SettingsKeys.routes), isTrue);
      expect(AppBackup.isBackedUp(SettingsKeys.exploration), isTrue);
    });
  });
}
