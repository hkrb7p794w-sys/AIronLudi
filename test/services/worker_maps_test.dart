// Rundwege und Kacheln über den Worker (openrouteservice, MapTiler) gegen einen nachgebildeten Worker.
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/routing/worker_maps.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const start = GeoPoint(52.52, 13.405);

void main() {
  late CoachDatabase db;
  late SettingsStore settings;
  late (int, Object?) Function(HttpRequest request) handler;
  late List<HttpRequest> requests;
  late AIClient ai;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
    requests = [];
    handler = (_) => (200, <String, Object?>{});
    ai = AIClient(
      secrets: Secrets.memory({SecretKey.aiAppToken: 'app-token'}),
      settings: settings,
      transport: FakeHttpTransport((request) {
        requests.add(request);
        final (status, body) = handler(request);
        return HttpResponse(status, utf8.encode(jsonEncode(body)));
      }),
    );
    await settings.setString(SettingsKeys.workerURL, 'https://w.example');
  });

  tearDown(() async {
    await settings.close();
    await db.close();
  });

  test('Rundweg: Anfrage mit Token, Antwort als Strecke; Fehler als Router-Fehler', () async {
    final source = WorkerRoundTripSource(ai);
    handler = (_) => (
      200,
      {
        'points': [
          [52.52, 13.405, 34],
          [52.53, 13.41, 40],
          [52.52, 13.405, 34],
        ],
        'distanceMeters': 2400,
        'engine': 'openrouteservice',
      },
    );
    final path = await source.roundTrip(start, discipline: RouteDiscipline.walk, lengthMeters: 2400, seed: 5);
    expect(path.points.length, 3);
    expect(path.engine, 'openrouteservice');
    expect(requests.single.url.toString(), 'https://w.example/v1/maps/roundtrip');
    expect(requests.single.headers['Authorization'], 'Bearer app-token');
    expect(jsonDecode(utf8.decode(requests.single.body!)), containsPair('discipline', 'walk'));

    handler = (_) => (404, {'error': 'Kein Rundweg gefunden', 'code': 'no_route'});
    await expectLater(
      source.roundTrip(start, discipline: RouteDiscipline.run, lengthMeters: 5000, seed: 1),
      throwsA(isA<NoRouteFound>()),
    );
    // Nicht eingerichtet: danach fragt die Quelle nicht mehr.
    handler = (_) => (503, {'error': 'ORS_API_KEY fehlt', 'code': 'not_configured'});
    await expectLater(
      source.roundTrip(start, discipline: RouteDiscipline.run, lengthMeters: 5000, seed: 1),
      throwsA(isA<RoutingUnavailable>()),
    );
    final count = requests.length;
    await expectLater(
      source.roundTrip(start, discipline: RouteDiscipline.run, lengthMeters: 5000, seed: 1),
      throwsA(isA<RoutingUnavailable>()),
    );
    expect(requests.length, count);
  });

  test('Ohne Worker: kein Rundweg-Ausweich und OSM-Kacheln, ohne Anfrage', () async {
    await settings.setString(SettingsKeys.workerURL, '');
    await expectLater(
      WorkerRoundTripSource(ai).roundTrip(start, discipline: RouteDiscipline.run, lengthMeters: 5000, seed: 1),
      throwsA(isA<RoutingUnavailable>()),
    );
    expect(await WorkerTiles.probe(ai), isNull);
    expect(requests, isEmpty);
  });

  test('Kacheln nur, wenn der Worker sie meldet; heller und dunkler Stil', () async {
    handler = (_) => (
      200,
      {
        'status': 'ok',
        'maps': {'roundTrip': false, 'tiles': false},
      },
    );
    expect(await WorkerTiles.probe(ai), isNull);
    handler = (_) => (
      200,
      {
        'status': 'ok',
        'maps': {'roundTrip': true, 'tiles': true},
      },
    );
    final tiles = await WorkerTiles.probe(ai);
    expect(requests.last.headers['Authorization'], isNull);
    expect(tiles!.urlTemplate(dark: true), 'https://w.example/v1/maps/tiles/dark/{z}/{x}/{y}.png');
    expect(tiles.urlTemplate(dark: false), contains('/tiles/light/'));
    expect(tiles.headers, {'Authorization': 'Bearer app-token'});
  });
}
