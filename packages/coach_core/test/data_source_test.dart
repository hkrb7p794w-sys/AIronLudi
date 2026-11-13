// Port von DataSourceTests.swift (SourcePreferenceTests, MetricsMergeTests, ActivityMergeTests, SyncLedgerTests,
// ProviderSyncStateTests). `TimeZone(secondsFromGMT: 0)` wird zu `utcOffset: Duration.zero`.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const day = CalendarDay(2026, 11, 2);
final now = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true);

GarminActivity activity(
  int id, {
  DataProvider? provider,
  required String start,
  required double minutes,
  String type = 'running',
  double calories = 500,
}) => GarminActivity(id)
  ..provider = provider
  ..typeKey = type
  ..startLocal = start
  ..durationSeconds = minutes * 60
  ..calories = calories;

ActivityMergePlan plan(List<GarminActivity> activities, SourcePreferences preferences, Set<DataProvider> connected) =>
    ActivityMerge.plan(activities, preferences: preferences, connected: connected, utcOffset: Duration.zero);

SourceEntry entry(
  String id, {
  DataProvider provider = DataProvider.garmin,
  CalendarDay? on,
  String hash = 'a',
  SourceEntryStatus status = SourceEntryStatus.active,
}) => SourceEntry(
  provider: provider,
  kind: DataKind.activities,
  externalID: id,
  day: on ?? day,
  importedAt: now,
  contentHash: hash,
  status: status,
);

void main() {
  group('Quellen je Datenart', () {
    const connected = {DataProvider.garmin, DataProvider.whoop, DataProvider.appleHealth};

    test('Ausnahme, dann Stärke des primären Geräts, dann Rangfolge', () {
      final preferences = SourcePreferences(primary: DataProvider.garmin);
      // Garmin ist primär, aber Schlaf gehört nicht zu Garmins Stärken: WHOOP vorne (allgemeine Rangfolge).
      expect(preferences.preferred(DataKind.sleep, connected: connected), DataProvider.whoop);
      expect(preferences.preferred(DataKind.activities, connected: connected), DataProvider.garmin);
      preferences.overrides[DataKind.sleep] = DataProvider.garmin;
      expect(preferences.order(DataKind.sleep, connected: connected), [
        DataProvider.garmin,
        DataProvider.whoop,
        DataProvider.appleHealth,
      ]);
      // WHOOP primär: Erholung und HRV von WHOOP, Aktivitäten trotzdem von Garmin.
      final whoop = SourcePreferences(primary: DataProvider.whoop);
      expect(whoop.preferred(DataKind.hrv, connected: connected), DataProvider.whoop);
      expect(whoop.preferred(DataKind.activities, connected: connected), DataProvider.garmin);
    });

    test('nur verbundene Anbieter, die die Art liefern', () {
      final preferences = SourcePreferences(
        primary: DataProvider.whoop,
        overrides: {DataKind.stress: DataProvider.whoop},
      );
      // WHOOP liefert keinen Stress und ist nicht verbunden.
      expect(preferences.order(DataKind.stress, connected: {DataProvider.garmin}), [DataProvider.garmin]);
      expect(preferences.order(DataKind.steps, connected: {DataProvider.whoop}), isEmpty);
    });

    test('Lesen überspringt unbekannte Werte', () {
      const json = '{"primary": "oura", "overrides": {"sleep": "whoop", "laune": "garmin", "hrv": "oura"}}';
      final decoded = SourcePreferences.fromJson(jsonDecode(json));
      expect(decoded.primary, isNull);
      expect(decoded.overrides, {DataKind.sleep: DataProvider.whoop});
      final original = SourcePreferences(primary: DataProvider.garmin, overrides: {DataKind.hrv: DataProvider.whoop});
      expect(SourcePreferences.fromJson(jsonDecode(jsonEncode(original.toJson()))), original);
    });

    test('der Katalog ist ehrlich', () {
      expect(DataProvider.garmin.availability, ProviderAvailability.available);
      expect(DataProvider.appleHealth.availability, ProviderAvailability.available);
      expect(DataProvider.whoop.availability, ProviderAvailability.planned);
      expect(DataProvider.polar.availability, ProviderAvailability.planned);
      expect(DataProvider.fitbit.availability, ProviderAvailability.unavailable);
      for (final provider in DataProvider.values) {
        expect(provider.capabilities.containsAll(provider.strengths), isTrue);
        expect(provider.availabilityNote, isNotEmpty);
      }
      for (final kind in DataKind.values) {
        expect(DataProvider.defaultOrder(kind).toSet(), DataProvider.values.toSet());
      }
    });
  });

  group('Tageswerte zusammenführen', () {
    test('jede Art von einer Quelle als ganze Gruppe', () {
      final garmin = DailyMetrics(day)
        ..sleepSeconds = 7 * 3600
        ..deepSleepSeconds = 4000
        ..restingHeartRate = 48
        ..steps = 12000
        ..activeKilocalories = 700
        ..hrvLastNightAverage = 55;
      final whoop = DailyMetrics(day)
        ..sleepSeconds = 7.5 * 3600
        ..hrvLastNightAverage = 62
        ..activeKilocalories = 900;
      final health = DailyMetrics(day)
        ..steps = 11500
        ..activeKilocalories = 650;
      final result = MetricsMerge.merge(
        {DataProvider.garmin: garmin, DataProvider.whoop: whoop, DataProvider.appleHealth: health},
        day: day,
        preferences: SourcePreferences(primary: DataProvider.garmin),
      );
      // Schlaf als ganze Gruppe von WHOOP: keine Tiefschlafphase von Garmin dazugemischt.
      expect(result.metrics.sleepSeconds, 7.5 * 3600);
      expect(result.metrics.deepSleepSeconds, isNull);
      expect(result.sources[DataKind.sleep], DataProvider.whoop);
      expect(result.metrics.hrvLastNightAverage, 62);
      // Kalorien und Schritte nur aus einer Quelle – nicht addiert.
      expect(result.metrics.activeKilocalories, 700);
      expect(result.metrics.steps, 12000);
      expect(result.sources[DataKind.calories], DataProvider.garmin);
      expect(result.metrics.restingHeartRate, 48);
    });

    test('weicht aus, wenn die bevorzugte Quelle keine Werte hat', () {
      final garmin = DailyMetrics(day)..steps = 9000;
      final health = DailyMetrics(day)..sleepSeconds = 6 * 3600;
      final result = MetricsMerge.merge(
        {DataProvider.garmin: garmin, DataProvider.appleHealth: health},
        day: day,
        preferences: SourcePreferences(overrides: {DataKind.sleep: DataProvider.garmin}),
      );
      expect(result.sources[DataKind.sleep], DataProvider.appleHealth);
      expect(result.metrics.sleepSeconds, 21600.0);
      expect(result.sources[DataKind.steps], DataProvider.garmin);
      expect(result.sources[DataKind.hrv], isNull);
    });

    test('jedes Feld gehört zu einer Art', () {
      // Ein voll befüllter Tag muss nach dem Zusammenführen gleich bleiben – sonst fehlt ein Feld in den Gruppen.
      final full = DailyMetrics(day)
        ..restingHeartRate = 1
        ..hrvLastNightAverage = 1
        ..hrvWeeklyAverage = 1
        ..hrvStatus = 'BALANCED'
        ..hrvBaselineLow = 1
        ..hrvBaselineHigh = 1
        ..sleepSeconds = 1
        ..sleepScore = 1
        ..bodyBatteryHigh = 1
        ..bodyBatteryLow = 1
        ..bodyBatteryLatest = 1
        ..stressAverage = 1
        ..steps = 1
        ..activeKilocalories = 1
        ..totalKilocalories = 1
        ..respirationWaking = 1
        ..respirationSleep = 1
        ..spo2Average = 1
        ..spo2Lowest = 1
        ..bodyBatteryCharged = 1
        ..bodyBatteryDrained = 1
        ..deepSleepSeconds = 1
        ..lightSleepSeconds = 1
        ..remSleepSeconds = 1
        ..awakeSleepSeconds = 1
        ..sleepStress = 1
        ..fitnessAge = 1
        ..vo2Max = 1
        ..trainingReadiness = 1
        ..trainingReadinessLevel = 'HIGH'
        ..trainingStatus = 'PRODUCTIVE'
        ..enduranceScore = 1
        ..sleepStartMinutes = 1
        ..sleepEndMinutes = 1
        ..bodyBatteryAtWake = 1
        ..bodyBatteryCurve = [const BodyBatterySample(minute: 0, value: 1)]
        ..restingKilocalories = 1
        ..minHeartRate = 1
        ..maxHeartRate = 1
        ..recoveryHours = 1
        ..acuteLoad = 1
        ..chronicLoad = 1;
      final result = MetricsMerge.merge({DataProvider.garmin: full}, day: day, preferences: SourcePreferences());
      expect(result.metrics, full);
      // Auch das JSON ist gleich (fängt neue Felder ab, die `==` vergessen könnte).
      expect(jsonEncode(result.metrics.toJson()), jsonEncode(full.toJson()));
    });
  });

  group('Aktivitäten zusammenführen', () {
    test('dieselbe Einheit nur von der bevorzugten Quelle', () {
      final garmin = activity(101, start: '2026-11-02 07:00:00', minutes: 50);
      final health = activity(-5, start: '2026-11-02 07:03:00', minutes: 48);
      final whoop = activity(
        -9,
        provider: DataProvider.whoop,
        start: '2026-11-02 07:01:00',
        minutes: 51,
        type: 'other',
      );
      final other = activity(102, start: '2026-11-02 18:00:00', minutes: 30, type: 'cycling');
      final result = plan(
        [health, whoop, garmin, other],
        SourcePreferences(),
        {DataProvider.garmin, DataProvider.appleHealth, DataProvider.whoop},
      );
      expect(result.kept.map((a) => a.id).toList()..sort(), [101, 102]);
      expect(result.superseded, {-5: 101, -9: 101});
      // Kalorien zählen nur einmal.
      expect(result.kept.fold(0.0, (sum, a) => sum + (a.calories ?? 0)), 1000);
    });

    test('die Einstellung entscheidet, welche Kopie bleibt', () {
      final garmin = activity(101, start: '2026-11-02 07:00:00', minutes: 50);
      final polar = activity(-3, provider: DataProvider.polar, start: '2026-11-02 07:00:30', minutes: 50);
      final result = plan(
        [garmin, polar],
        SourcePreferences(overrides: {DataKind.activities: DataProvider.polar}),
        {DataProvider.garmin, DataProvider.polar},
      );
      expect(result.kept.map((a) => a.id), [-3]);
      expect(result.superseded, {101: -3});
    });

    test('andere Sportart oder Zeit bleibt getrennt', () {
      final run = activity(1, start: '2026-11-02 07:00:00', minutes: 30);
      final bike = activity(-1, start: '2026-11-02 07:05:00', minutes: 30, type: 'cycling');
      final later = activity(-2, start: '2026-11-02 07:40:00', minutes: 30);
      final result = plan([run, bike, later], SourcePreferences(), {DataProvider.garmin, DataProvider.appleHealth});
      expect(result.kept.length, 3);
      expect(result.superseded, isEmpty);
    });

    test('derselbe Anbieter wird nie zusammengelegt', () {
      // Zwei Garmin-Aktivitäten kurz hintereinander (z. B. Ein- und Auslaufen) sind echte Einheiten.
      final a = activity(1, start: '2026-11-02 07:00:00', minutes: 10);
      final b = activity(2, start: '2026-11-02 07:05:00', minutes: 40);
      expect(plan([a, b], SourcePreferences(), {DataProvider.garmin}).kept.length, 2);
    });

    test('Anbieter ableiten und lokale IDs', () {
      expect(ActivityMerge.provider(GarminActivity(5)), DataProvider.garmin);
      expect(ActivityMerge.provider(GarminActivity(-5)), DataProvider.appleHealth);
      final a = ActivityMerge.localID(provider: DataProvider.whoop, externalID: 'abc');
      expect(a, lessThan(0));
      expect(a, ActivityMerge.localID(provider: DataProvider.whoop, externalID: 'abc'));
      expect(a, isNot(ActivityMerge.localID(provider: DataProvider.polar, externalID: 'abc')));
      // Gleicher Wert wie in Swift (FNV-1a über „whoop:abc“, mit Python nachgerechnet).
      expect(a, -1080687389841716475);
    });
  });

  group('Abgleich', () {
    test('neu, geändert, unverändert, gelöscht', () {
      final window = DateRange(day.adding(-2), day);
      final known = [
        entry('1'),
        entry('2', hash: 'b'),
        entry('3', on: day.adding(-1), hash: 'c'),
        entry('old', on: day.adding(-10), hash: 'd'),
        entry('x', provider: DataProvider.appleHealth, hash: 'e'),
      ];
      const incoming = [
        SyncIncoming(externalID: '1', day: day, contentHash: 'a'),
        SyncIncoming(externalID: '2', day: day, contentHash: 'B'),
        SyncIncoming(externalID: '4', day: day, contentHash: 'f'),
        SyncIncoming(externalID: '4', day: day, contentHash: 'f'),
      ];
      final later = now.add(const Duration(seconds: 60));
      SyncChanges reconcile({required bool complete}) => SyncLedger.reconcile(
        known: known,
        incoming: incoming,
        provider: DataProvider.garmin,
        kind: DataKind.activities,
        window: window,
        complete: complete,
        now: later,
      );
      final changes = reconcile(complete: true);
      expect(changes.newEntries.map((e) => e.externalID), ['4']);
      expect(changes.changed.map((e) => e.externalID), ['2']);
      expect(changes.changed.first.updatedAt, later);
      expect(changes.unchanged, ['1']);
      // „3“ fehlt im vollständigen Zeitraum → gelöscht; „old“ liegt davor, Apple Health ist ein anderer Anbieter.
      expect(changes.deleted.map((e) => e.externalID), ['3']);
      expect(changes.deleted.first.status, SourceEntryStatus.deleted);
      expect(reconcile(complete: false).deleted, isEmpty);
      // Der Bestand selbst bleibt unverändert.
      expect(known[1].contentHash, 'b');
    });

    test('Ersetztes bleibt ersetzt, Gelöschtes kommt zurück', () {
      final known = [
        entry('s', provider: DataProvider.appleHealth, status: SourceEntryStatus.superseded),
        entry('d', provider: DataProvider.appleHealth, status: SourceEntryStatus.deleted),
      ];
      final changes = SyncLedger.reconcile(
        known: known,
        incoming: const [
          SyncIncoming(externalID: 's', day: day, contentHash: 'z'),
          SyncIncoming(externalID: 'd', day: day, contentHash: 'a'),
        ],
        provider: DataProvider.appleHealth,
        kind: DataKind.activities,
        window: null,
        complete: false,
        now: now,
      );
      expect(changes.skipped, ['s']);
      expect(changes.changed.map((e) => e.externalID), ['d']);
      expect(changes.changed.first.status, SourceEntryStatus.active);
    });

    test('Prüfsumme ändert sich mit dem Inhalt', () {
      final a = DailyMetrics(day)..steps = 1;
      final b = a.copy();
      expect(SyncLedger.hash(a), SyncLedger.hash(b));
      b.steps = 2;
      expect(SyncLedger.hash(a), isNot(SyncLedger.hash(b)));
    });

    test('Einträge überstehen das Speichern', () {
      final original = entry('1')..start = now;
      expect(SourceEntry.fromJson(jsonDecode(jsonEncode(original.toJson()))), original);
    });
  });

  group('Zustand je Anbieter', () {
    test('Wartezeit nach Fehlern, zurückgesetzt nach Erfolg', () {
      final state = ProviderSyncState();
      const interval = Duration(seconds: 900);
      expect(state.isDue(now: now, minimumInterval: interval), isTrue);
      state.recordFailure(now: now, error: 'Netz');
      expect(state.isDue(now: now.add(const Duration(seconds: 30)), minimumInterval: interval), isFalse);
      expect(state.isDue(now: now.add(const Duration(seconds: 61)), minimumInterval: interval), isTrue);
      state
        ..recordFailure(now: now, error: 'Netz')
        ..recordFailure(now: now, error: 'Netz');
      expect(state.isDue(now: now.add(const Duration(minutes: 10)), minimumInterval: interval), isFalse);
      expect(ProviderSyncState.backoff(9), const Duration(hours: 6));
      state.recordSuccess(now: now, day: day);
      expect(state.failures, 0);
      expect(state.lastError, isNull);
      expect(state.isDue(now: now.add(const Duration(seconds: 60)), minimumInterval: interval), isFalse);
      final decoded = ProviderSyncState.fromJson(jsonDecode(jsonEncode(state.toJson())))!;
      expect(decoded.lastSuccessDay, day);
      expect(decoded.lastSuccess, now);
    });

    test('Zeitraum holt nach Fehlern auf', () {
      final state = ProviderSyncState();
      expect(state.window(today: day, initialDays: 28), DateRange.last(28, endingOn: day));
      state
        ..recordSuccess(now: now, day: day.adding(-5))
        ..recordFailure(now: now, error: 'Server');
      // Erfolg vor 5 Tagen, danach nur Fehler: Abruf ab Tag −8 (3 Tage Überlappung).
      expect(state.window(today: day, initialDays: 28), DateRange(day.adding(-8), day));
      state.recordSuccess(now: now, day: day.adding(-400));
      expect(state.window(today: day, initialDays: 28, maxDays: 180).start, day.adding(-179));
    });
  });
}
