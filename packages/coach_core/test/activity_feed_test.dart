// Port von ActivityFeedTests (ActivityFeedTests.swift), ChartZoomTests.swift, den Abschnitts- und Format-Fällen aus
// ActivityDetailsTests.swift (FIT-Fälle folgen mit dem FIT-Modul), den WeekLoad-Fällen aus TrainingTodayTests.swift
// und `loadWarningUsesGivenThreshold` aus PersonalizationTests.swift. Zeitzone der Tests: UTC (wie die CI).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

DateTime utc(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void main() {
  group('ActivityFeed', () {
    const day = CalendarDay(2026, 10, 28);
    GarminActivity activity(int id, String typeKey, {String time = '07:00:00', double minutes = 45}) =>
        GarminActivity(id)
          ..typeKey = typeKey
          ..startLocal = '${day.iso} $time'
          ..durationSeconds = minutes * 60;

    /// 28.10.2026, volle Stunde in UTC.
    DateTime date(int hour) => utc(1793145600 + hour * 3600);

    test('führt Gym und Garmin-Kraft zusammen', () {
      final garmin = activity(5, 'strength_training', time: '18:10:00', minutes: 50);
      final run = activity(6, 'running');
      final gym = GymItem(id: 'A', title: 'Push', start: date(18), minutes: 55, sets: 18, volumeKg: 4230);
      final other = GymItem(id: 'B', title: 'Pull', start: date(10), minutes: null, sets: 12, volumeKg: 0);
      final entries = ActivityFeed.entries(activities: [garmin, run], gym: [gym, other]);
      expect(entries.map((entry) => entry.title), ['Push', 'Pull', 'running']);
      expect(entries[0].sources, [ActivitySource.app, ActivitySource.garmin]);
      expect(entries[0].values, ['50:00', '18 Sätze', '4230 kg']);
      expect(entries[1].sources, [ActivitySource.app]);
      expect(entries[1].values, ['12 Sätze']);
      expect(entries[2].intensity, SessionKind.easy);
    });

    test('Quellen und Bezug zum Plan', () {
      expect(ActivitySource.of(1), ActivitySource.garmin);
      final manual = ManualActivity.make(sport: TrainingSport.run, start: date(7), minutes: 30, effort: 5);
      expect(ActivitySource.of(manual.id), ActivitySource.manual);
      final run = activity(6, 'running');
      final result = SessionResult(
        planned: PlannedSession(day: day, slot: const SessionSlot(TrainingSport.run)),
        status: SessionStatus.done,
        activityID: 6,
        actualMinutes: 45,
      );
      final entries = ActivityFeed.entries(activities: [run], gym: [], results: [result]);
      expect(entries.first.planned?.status, SessionStatus.done);
    });

    test('Tempo, Zonen und Fehlendes', () {
      final run = activity(1, 'running', minutes: 50)..distanceMeters = 10000;
      expect(ActivityFeed.pace(run), '5:00 /km');
      expect(ActivityFeed.pace(activity(2, 'lap_swimming', minutes: 30)..distanceMeters = 1500), '2:00 /100 m');
      expect(ActivityFeed.pace(activity(3, 'cycling', minutes: 60)..distanceMeters = 30000), '30 km/h');
      run.secondsInZones = [600, 1200, 600, 300, 300];
      expect(ActivityFeed.zoneShares(run), [0.2, 0.4, 0.2, 0.1, 0.1]);
      final notes = ActivityFeed.missing(activity(4, 'running'));
      expect(notes.any((note) => note.startsWith('Keine Herzfrequenz')), isTrue);
      expect(notes.any((note) => note.startsWith('Keine Strecke')), isTrue);
      expect(notes.any((note) => note.startsWith('Keine Trainingsbelastung')), isTrue);
      final manual = ManualActivity.make(sport: TrainingSport.swim, start: date(7), minutes: 30, effort: 5);
      expect(ActivityFeed.missing(manual).length, 1);
    });

    test('Filter nach Sportart, Plan, Härte, Zeitraum und Text', () {
      final run = activity(1, 'running')..name = 'Intervalle 6x800';
      final bike = activity(2, 'cycling')..name = 'Lockere Runde';
      final entries = ActivityFeed.entries(activities: [run, bike], gym: []);
      expect(const FeedFilter(sport: TrainingSport.bike).apply(entries, today: day).map((entry) => entry.id), ['a2']);
      expect(const FeedFilter(onlyHard: true).apply(entries, today: day).map((entry) => entry.id), ['a1']);
      expect(const FeedFilter(onlyPlanned: true).apply(entries, today: day), isEmpty);
      expect(const FeedFilter(search: 'runde').apply(entries, today: day).map((entry) => entry.id), ['a2']);
      expect(const FeedFilter(period: FeedPeriod.weeks4).apply(entries, today: day.adding(40)), isEmpty);
      expect(const FeedFilter(onlyHard: true).narrows, isTrue);
    });
  });

  group('ActivityDetails', () {
    final list = JsonValue([
      {
        'activityId': 42,
        'activityName': 'Lauf',
        'activityType': {'typeKey': 'running'},
        'startTimeLocal': '2026-10-25 08:00:00',
        'duration': 3000,
        'movingDuration': 2950,
        'distance': 10000,
        'averageSpeed': 3.333,
        'maxSpeed': 4.5,
        'averageHR': 148,
        'maxHR': 171,
        'elevationGain': 85,
        'elevationLoss': 84,
        'averageRunningCadenceInStepsPerMinute': 172,
        'avgStrideLength': 116.4,
        'avgGroundContactTime': 242,
        'avgVerticalOscillation': 8.6,
        'avgVerticalRatio': 7.4,
        'aerobicTrainingEffect': 3.4,
        'trainingEffectLabel': 'TEMPO',
        'hrTimeInZone_1': 300,
        'hrTimeInZone_2': 900,
        'hrTimeInZone_3': 1200,
        'hrTimeInZone_4': 600,
        'hrTimeInZone_5': 0,
      },
    ]);

    test('Abschnitte beim Laufen wie in Garmin Connect', () {
      final activity = GarminActivityParser.activities(list).first;
      final sections = ActivityDetails.sections(activity);
      final titles = sections.map((section) => section.title);
      expect(titles, contains('Laufdynamik'));
      expect(titles, isNot(contains('Schwimmen')));
      final rows = <String, String>{};
      for (final row in sections.expand((section) => section.rows)) {
        rows.putIfAbsent(row.label, () => row.value);
      }
      expect(rows['Distanz'], '10 km');
      expect(rows['Zeit'], '50:00');
      expect(rows['Ø Pace'], '5:00 /km');
      expect(rows['Beste Pace'], '3:42 /km');
      expect(rows['Ø Schrittlänge'], '1,16 m');
      expect(rows['Ø Bodenkontaktzeit'], '242 ms');
      expect(rows['Schwerpunkt'], 'Tempo');
      expect(rows['Zone 3'], '20:00 (40 %)');
      expect(ActivityDetails.effectLabel('NEW_THING'), 'New_thing');
    });

    test('Details ergänzen fehlende Werte', () {
      final base = GarminActivityParser.activities(list).first;
      final sparse = GarminActivity(42)..distanceMeters = 9999;
      final detail = JsonValue({
        'activityId': 42,
        'activityTypeDTO': {'typeKey': 'running'},
        'summaryDTO': {'distance': 10000, 'maxRunCadence': 188, 'normalizedPower': 260, 'minElevation': 4},
      });
      final merged = GarminActivityParser.detail(detail, sparse);
      expect(merged.distanceMeters, 9999);
      expect(merged.maxCadence, 188);
      expect(merged.normalizedPower, 260);
      expect(merged.minElevation, 4);
      expect(merged.typeKey, 'running');
      expect(GarminActivityParser.detail(JsonValue.nullValue, base), base);
    });

    test('Formate für Schwimmen und Rad', () {
      expect(ActivityDetails.speed(1.0, ActivitySport.swim), '1:40 /100 m');
      expect(ActivityDetails.speed(8.0, ActivitySport.bike), '28,8 km/h');
      expect(ActivityDetails.distance(1500, ActivitySport.swim), '1500 m');
      expect(ActivityDetails.duration(3930), '1:05:30');
    });
  });

  group('WeekLoad', () {
    const today = CalendarDay(2026, 10, 28);
    GarminActivity activity(int id, String typeKey, CalendarDay day, double minutes, {double? load, String? name}) =>
        GarminActivity(id)
          ..typeKey = typeKey
          ..startLocal = '${day.iso} 07:00:00'
          ..durationSeconds = minutes * 60
          ..trainingLoad = load
          ..name = name;

    test('Wochenbelastung über alle Sportarten', () {
      final earlier = [
        for (var week = 0; week < 3; week++) activity(week, 'running', today.adding(-10 - 7 * week), 60, load: 100),
      ];
      final recent = [
        activity(10, 'running', today, 60, load: 100),
        activity(11, 'cycling', today.adding(-2), 60, load: 100),
        activity(12, 'running', today.adding(-3), 60),
      ];
      final gym = GymItem(id: 'G', title: 'Push', start: utc(1793095200), minutes: 50, sets: 12, volumeKg: 3000);
      final result = WeekLoad.check(activities: [...earlier, ...recent], gym: [gym], today: today);
      expect(result.baseline, 100);
      expect(result.last, 310);
      expect(result.bySport[TrainingSport.strength], 50);
      expect(result.bySport[TrainingSport.bike], 100);
      expect(result.increase, 2.1);
      expect(result.warning, contains('210 % mehr'));
      expect((result.estimatedShare - 110 / 310).abs(), lessThan(0.001));
    });

    test('keine Warnung ohne Verlauf oder bei kleiner Differenz', () {
      expect(WeekLoad.check(activities: [activity(1, 'running', today, 60, load: 100)], today: today).warning, isNull);
      final earlier = [
        for (var week = 0; week < 3; week++) activity(10 + week, 'running', today.adding(-10 - 7 * week), 30, load: 40),
      ];
      expect(
        WeekLoad.check(activities: [...earlier, activity(1, 'running', today, 60, load: 80)], today: today).warning,
        isNull,
      );
    });

    test('geschätzte Belastung nach Intensität', () {
      expect(WeekLoad.load(activity(1, 'running', today, 40)).value, 40);
      expect(WeekLoad.load(activity(1, 'running', today, 40, name: 'Intervalle')).value, 80);
      final measured = WeekLoad.load(activity(1, 'running', today, 40, load: 55));
      expect(measured.value, 55);
      expect(measured.estimated, isFalse);
    });

    test('Warnschwelle aus den Zielen', () {
      // 4 Wochen je 300 min locker, dann eine Woche mit 375 (+25 %): Standard (30 %) still, vorsichtig (20 %) warnt.
      const day = CalendarDay(2026, 11, 2);
      final activities = [
        for (var week = 0; week < 4; week++)
          for (var offset = 0; offset < 3; offset++)
            activity(week * 10 + offset + 1, 'running', day.adding(-(week * 7) - offset), week == 0 ? 125 : 100),
      ];
      expect(WeekLoad.check(activities: activities, today: day).warning, isNull);
      expect(WeekLoad.check(activities: activities, today: day, maxIncrease: 0.20).warning, isNotNull);
    });
  });

  group('ChartZoom', () {
    final start = utc(1700000000);
    DateTime date(double day) => start.add(Duration(milliseconds: (day * 86400000).round()));

    test('Zoom zwischen zwei Wochen und allem', () {
      final span = ChartZoom.spanDays([date(0), date(600)]);
      expect(span, 601);
      expect(ChartZoom.clamp(3, span: span), 14);
      expect(ChartZoom.clamp(2000, span: span), 601);
      expect(ChartZoom.initialDays(span), 91);
      expect(ChartZoom.initialDays(ChartZoom.spanDays([date(0), date(20)])), 21);
    });

    test('Y-Achse folgt den sichtbaren Punkten', () {
      final points = [(date: date(0), value: 40.0), (date: date(300), value: 60.0), (date: date(330), value: 62.0)];
      final visible = ChartZoom.yDomain(points, from: date(290), days: 60);
      expect(visible.low > 50 && visible.high < 70, isTrue);
      final all = ChartZoom.yDomain(points, from: date(-10), days: 400);
      expect(all.low < 40 && all.high > 62, isTrue);
      expect(ChartZoom.yDomain(points, from: date(290), days: 60, includesZero: true).low, 0);
    });

    test('Punkte verschwinden, wenn sie zu dicht liegen', () {
      expect(ChartZoom.showsPoints(days: 91, count: 170, span: 1000), isTrue);
      expect(ChartZoom.showsPoints(days: 1000, count: 170, span: 1000), isFalse);
    });
  });
}
