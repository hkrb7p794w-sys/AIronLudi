// „Karte auf die Uhr“: Varianten, Wegenetz, Paket und Hochladen zum Worker; Kopplung mit dem Code der Uhr.
import 'dart:convert';
import 'dart:typed_data';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/routing/watch_export.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/route_planner_screen_test.dart' show FakeRouting;

const start = GeoPoint(52.52, 13.405);

/// Straßenraster 100 m (31 × 31) um den Start.
final class GridNetwork implements WatchNetworkSource {
  int calls = 0;
  List<List<GeoPoint>> lines = const [];

  @override
  Future<OsmWays> network(List<List<GeoPoint>> lines, {double radius = 400}) async {
    calls++;
    this.lines = lines;
    final projection = LocalProjection(start);
    final nodes = <int, GeoPoint>{
      for (var row = 0; row <= 60; row++)
        for (var col = 0; col <= 60; col++) row * 100 + col: projection.unproject((col - 30) * 100, (row - 30) * 100),
    };
    return OsmWays(
      nodes: nodes,
      ways: [
        for (var row = 0; row <= 60; row++) [for (var col = 0; col <= 60; col++) row * 100 + col],
        for (var col = 0; col <= 60; col++) [for (var row = 0; row <= 60; row++) row * 100 + col],
      ],
    );
  }
}

PlannedRoute loop() {
  final center = Geo.destination(start, 0, 950);
  final points = [for (var angle = 180; angle <= 540; angle += 10) Geo.destination(center, angle.toDouble(), 950)];
  return PlannedRoute(
    id: 'r-1',
    username: 'anna',
    name: 'Runde',
    request: const RouteRequest(
      discipline: RouteDiscipline.run,
      shape: RouteShape.loop,
      start: start,
      distanceMeters: 6000,
    ),
    variant: RouteVariant.balanced,
    points: points,
    engine: 'Test',
    createdAt: DateTime.utc(2026, 11, 27),
  );
}

void main() {
  late CoachDatabase db;
  late SettingsStore settings;
  late List<HttpRequest> requests;
  late (int, Object?) Function(HttpRequest request) handler;
  late AIClient ai;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
    requests = [];
    handler = (_) => (200, {'routes': <Object?>[]});
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

  test('Rundweg: Varianten kürzer und länger, Wegenetz um alle, Paket in Teilen hochgeladen', () async {
    final network = GridNetwork();
    final service = WatchExportService(ai: ai, backend: FakeRouting(), network: network);
    final progress = <String>[];
    final result = await service.export(loop(), onProgress: progress.add);
    expect(result.variants, greaterThanOrEqualTo(2));
    expect(network.lines.length, 1 + result.variants);
    expect(progress, contains('Wegenetz wird geladen …'));
    final upload = requests.single;
    expect(upload.method, 'PUT');
    expect(upload.url.toString(), 'https://w.example/v1/watch/routes/r-1');
    final body = jsonDecode(utf8.decode(upload.body!)) as Map<String, Object?>;
    final chunks = (body['chunks']! as List).cast<String>();
    final bytes = Uint8List.fromList([for (final chunk in chunks) ...base64.decode(chunk)]);
    expect(bytes.length, body['bytes']);
    final package = WatchPackage.decode(bytes);
    expect(package.routes.length, 1 + result.variants);
    expect(package.routes.skip(1).map((route) => route.kind), everyElement(isNot(WatchRouteKind.main)));
    expect(package.nodes.length, result.nodes);
  });

  test('Ohne Worker: verständlicher Hinweis; Kopplung prüft den Code', () async {
    final service = WatchExportService(ai: ai, backend: FakeRouting(), network: GridNetwork());
    await expectLater(service.pair('abc'), throwsA(isA<WatchExportFailed>()));
    await service.pair('k7q-2px');
    expect(jsonDecode(utf8.decode(requests.single.body!)), {'code': 'K7Q2PX'});
    handler = (_) => (404, {'error': 'Code unbekannt', 'code': 'unknown_code'});
    await expectLater(
      service.pair('K7Q2PX'),
      throwsA(isA<WatchExportFailed>().having((error) => error.message, 'message', contains('abgelaufen'))),
    );

    await settings.setString(SettingsKeys.workerURL, '');
    expect(service.isAvailable, isFalse);
    await expectLater(service.export(loop()), throwsA(isA<WatchExportFailed>()));
  });
}
