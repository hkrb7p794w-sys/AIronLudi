// Gebiete ohne vorheriges Öffnen: schon geladene Dateien still, fehlende der letzten Wochen begrenzt und mit Pause.
import 'dart:typed_data';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/route_repository.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/routing/exploration_import.dart';
import 'package:aironludi/services/routing/route_stores.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const start = GeoPoint(52.52, 13.405);
const today = CalendarDay(2026, 11, 23);

/// Runde mit GPS als FIT-Datei (Kurs-Format; die Punkte liest der Decoder gleich).
Uint8List ringFile(double shift) {
  final center = Geo.destination(start, 90, shift);
  final points = [for (var angle = 0; angle <= 360; angle += 5) Geo.destination(center, angle.toDouble(), 600)];
  final route = PlannedRoute(
    id: 'r',
    username: 'anna',
    name: 'Runde',
    request: RouteRequest(
      discipline: RouteDiscipline.run,
      shape: RouteShape.loop,
      start: points.first,
      distanceMeters: 3800,
    ),
    variant: RouteVariant.balanced,
    points: points,
    engine: 'Test',
    createdAt: DateTime.utc(2026, 11, 1),
  );
  return FitCourseFile.bytes(route, created: DateTime.utc(2026, 11, 1));
}

GarminActivity run(int id, CalendarDay day) => GarminActivity(id)
  ..typeKey = 'running'
  ..name = 'Lauf $id'
  ..startLocal = '${day.iso} 08:00:00';

final class FakeFiles implements ActivityFiles {
  FakeFiles({this.cache = const {}, this.failing = const {}});

  final Map<int, Uint8List> cache;
  final Set<int> failing;
  final downloads = <int>[];

  @override
  Uint8List? cached(int id) => cache[id];

  @override
  Future<Uint8List> download(int id) async {
    downloads.add(id);
    if (failing.contains(id)) throw StateError('offline');
    return ringFile(id * 50.0);
  }
}

void main() {
  late CoachDatabase db;
  late RouteStore store;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    final settings = await SettingsStore.open(db);
    store = RouteStore(settings, username: 'anna', routes: RouteRepository(db));
    await store.ready;
  });

  tearDown(() => db.close());

  test('ausgeschaltet: nichts geladen', () async {
    final files = FakeFiles();
    final result = await ExplorationImport(store: store, files: files).importRecent([run(1, today)], today: today);
    expect(result.tracks, 0);
    expect(files.downloads, isEmpty);
  });

  test('still nur schon geladene Dateien; auf Wunsch fehlende der letzten Wochen, jüngste zuerst, mit Pause', () async {
    await store.updateSettings((settings) => settings.explorationEnabled = true);
    final pauses = <Duration>[];
    final files = FakeFiles(cache: {1: ringFile(0)});
    final importer = ExplorationImport(store: store, files: files, sleep: (pause) async => pauses.add(pause));
    final activities = [
      run(5, today.adding(-120)), // zu alt
      run(1, today.adding(-3)),
      run(2, today.adding(-2)),
      run(3, today.adding(-1)),
      GarminActivity(-7)
        ..typeKey = 'running'
        ..startLocal = '${today.iso} 07:00:00', // Apple Health: keine Datei
    ];

    final cached = await importer.importCached(activities);
    expect(cached.tracks, 1);
    expect(files.downloads, isEmpty);
    expect(store.isExplored('a1'), isTrue);

    final recent = await importer.importRecent(activities, today: today);
    expect(files.downloads, [3, 2]);
    expect(recent.tracks, 2);
    expect(recent.remaining, 0);
    expect(pauses, [ExplorationImport.downloadPause]);
    expect(store.isExplored('a5'), isFalse);
    expect(store.exploration.territories, isNotEmpty);

    // Ein zweiter Durchgang lädt nichts doppelt.
    files.downloads.clear();
    await importer.importRecent(activities, today: today);
    expect(files.downloads, isEmpty);
  });

  test('Obergrenze je Durchgang und Abbruch nach zwei Fehlern in Folge', () async {
    await store.updateSettings((settings) => settings.explorationEnabled = true);
    final many = [for (var id = 10; id < 10 + ExplorationImport.maxDownloads + 3; id++) run(id, today.adding(-1))];
    final files = FakeFiles();
    final result = await ExplorationImport(
      store: store,
      files: files,
      sleep: (_) async {},
    ).importRecent(many, today: today);
    expect(files.downloads.length, ExplorationImport.maxDownloads);
    expect(result.remaining, 3);

    // Jüngste zuerst: 42 und 41 scheitern, 40 und 43 werden dann nicht mehr versucht.
    final broken = FakeFiles(failing: {40, 41, 42});
    final failed = await ExplorationImport(
      store: store,
      files: broken,
      sleep: (_) async {},
    ).importRecent([run(43, today), run(40, today), run(41, today), run(42, today)], today: today);
    expect(broken.downloads.length, 2);
    expect(failed.tracks, 0);
    expect(failed.remaining, 4);
  });
}
