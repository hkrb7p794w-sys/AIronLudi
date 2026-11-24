// Heute: Kennzahlen-Ringe (Schlaf, Erholung, Strain 0–21), ausblendbare Bereiche und feinere Sportarten.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

DailyStrain strainOf({
  required double done,
  double planned = 0,
  StrainLevel level = StrainLevel.moderate,
  RecoveryLevel? recovery = RecoveryLevel.normal,
}) => DailyStrain(
  done: done,
  planned: planned,
  typical: 60,
  fatigue: 50,
  level: level,
  recovery: recovery,
  headline: '',
  advice: '',
  week: const [0, 0, 0, 0, 0, 0, 0],
);

void main() {
  group('Strain 0–21', () {
    test('logarithmische Skala, nie über 21', () {
      expect(TodayKpis.strainOf(0), 0);
      expect(TodayKpis.strainOf(50), closeTo(8.9, 0.05));
      expect(TodayKpis.strainOf(100), closeTo(14.0, 0.1));
      expect(TodayKpis.strainOf(150), closeTo(17.0, 0.1));
      expect(TodayKpis.strainOf(1000), lessThanOrEqualTo(21));
    });

    test('erledigt voll, geplant hell; Farbe nach Einordnung und Erholung', () {
      final kpi = TodayKpis.strain(strainOf(done: 50, planned: 50));
      expect(kpi.value, '8,9');
      expect(kpi.fraction, closeTo(8.9 / 21, 0.001));
      expect(kpi.secondaryFraction, closeTo(14.0 / 21, 0.01));
      expect(kpi.caption, '+5,1 geplant');
      expect(kpi.status, KpiStatus.good);
      expect(TodayKpis.strain(strainOf(done: 120, level: StrainLevel.high)).status, KpiStatus.moderate);
      expect(
        TodayKpis.strain(strainOf(done: 120, level: StrainLevel.high, recovery: RecoveryLevel.locker)).status,
        KpiStatus.critical,
      );
      expect(TodayKpis.strain(strainOf(done: 200, level: StrainLevel.veryHigh)).status, KpiStatus.critical);
      expect(TodayKpis.strain(strainOf(done: 0, level: StrainLevel.rest)).caption, 'von 21');
    });

    test('noch nichts trainiert, viel geplant: Wert neutral, Ring warnt', () {
      final kpi = TodayKpis.strain(
        strainOf(done: 0, planned: 120, level: StrainLevel.veryHigh, recovery: RecoveryLevel.locker),
      );
      expect(kpi.value, '0,0');
      expect(kpi.status, KpiStatus.critical);
      expect(kpi.valueStatus, KpiStatus.unknown);
      expect(TodayKpis.strain(strainOf(done: 50, planned: 50)).valueStatus, isNull);
    });
  });

  group('Schlaf', () {
    test('Schlafwert mit Stufen 80/60, Dauer darunter', () {
      final metrics = DailyMetrics(CalendarDay(2026, 11, 18))
        ..sleepScore = 82
        ..sleepSeconds = 7.4 * 3600;
      final kpi = TodayKpis.sleep(metrics);
      expect((kpi.value, kpi.caption, kpi.status), ('82', '7,4 h', KpiStatus.good));
      expect(TodayKpis.sleep(metrics..sleepScore = 65).status, KpiStatus.moderate);
      expect(TodayKpis.sleep(metrics..sleepScore = 40).status, KpiStatus.critical);
    });

    test('ohne Schlafwert: Dauer gegen das Ziel; ohne Daten grau', () {
      final metrics = DailyMetrics(CalendarDay(2026, 11, 18))..sleepSeconds = 6.5 * 3600;
      final kpi = TodayKpis.sleep(metrics, targetHours: 8);
      expect((kpi.value, kpi.caption, kpi.status), ('6,5 h', 'Ziel 8,0 h', KpiStatus.critical));
      expect(kpi.fraction, closeTo(6.5 / 8, 0.001));
      expect(TodayKpis.sleep(metrics..sleepSeconds = 7.2 * 3600).status, KpiStatus.moderate);
      expect(TodayKpis.sleep(null).status, KpiStatus.unknown);
    });
  });

  group('Erholung', () {
    test('Erholungswert mit WHOOP-Stufen, nie besser als die Tagesampel', () {
      final metrics = DailyMetrics(CalendarDay(2026, 11, 18))..trainingReadiness = 72;
      expect(TodayKpis.recovery(metrics, RecoveryLevel.normal).status, KpiStatus.good);
      expect(TodayKpis.recovery(metrics, RecoveryLevel.normal).value, '72 %');
      // Unter dem Ring die Herkunft, nicht noch einmal „Normal trainieren“.
      expect(TodayKpis.recovery(metrics, RecoveryLevel.normal).caption, 'Erholungswert');
      expect(TodayKpis.recovery(metrics, RecoveryLevel.pause).status, KpiStatus.critical);
      expect(TodayKpis.recovery(metrics..trainingReadiness = 50, RecoveryLevel.normal).status, KpiStatus.moderate);
      expect(TodayKpis.recovery(metrics..trainingReadiness = 20, null).status, KpiStatus.critical);
    });

    test('Body Battery als Ersatz, sonst nur die Ampel', () {
      final metrics = DailyMetrics(CalendarDay(2026, 11, 18))..bodyBatteryAtWake = 80;
      expect(TodayKpis.recovery(metrics, RecoveryLevel.normal).caption, 'Body Battery');
      final ruled = TodayKpis.recovery(null, RecoveryLevel.locker);
      expect((ruled.value, ruled.status, ruled.caption), ('Mäßig', KpiStatus.moderate, 'Tagesampel'));
      expect(TodayKpis.recovery(null, null).status, KpiStatus.unknown);
    });
  });

  group('Bereiche auf „Heute“', () {
    test('Standard schlank, umschaltbar, JSON hin und zurück', () {
      final dashboard = TodayDashboard();
      expect(dashboard.shows(TodayModule.kpis), isTrue);
      expect(dashboard.shows(TodayModule.training), isTrue);
      expect(dashboard.shows(TodayModule.ai), isTrue);
      expect(dashboard.shows(TodayModule.motivation), isFalse);
      dashboard
        ..set(TodayModule.ai, visible: false)
        ..set(TodayModule.motivation, visible: true);
      final restored = TodayDashboard.fromJson(dashboard.toJson())!;
      expect(restored, dashboard);
      expect(restored.shows(TodayModule.ai), isFalse);
      expect(restored.shows(TodayModule.motivation), isTrue);
      expect(
        TodayDashboard.fromJson({
          'hidden': ['ai', 'unbekannt'],
        })!.hidden,
        {TodayModule.ai},
      );
      expect(TodayDashboard.fromJson('kaputt'), isNull);
    });
  });

  group('Sportarten', () {
    test('Typen von Garmin, Health und WHOOP, Name als Ersatz', () {
      expect(ActivityKind.of('bouldering'), ActivityKind.bouldering);
      expect(ActivityKind.of('rock_climbing'), ActivityKind.climbing);
      expect(ActivityKind.of('indoor_climbing'), ActivityKind.climbing);
      expect(ActivityKind.of('stair_climbing'), ActivityKind.cardio);
      expect(ActivityKind.of('indoor_rowing'), ActivityKind.rowing);
      expect(ActivityKind.of('hiking'), ActivityKind.hiking);
      expect(ActivityKind.of('yoga'), ActivityKind.yoga);
      expect(ActivityKind.of('hiit'), ActivityKind.hiit);
      expect(ActivityKind.of('walking'), ActivityKind.walking);
      expect(ActivityKind.of('other', name: 'Bouldern im Kletterzentrum'), ActivityKind.bouldering);
      expect(ActivityKind.of('other', name: 'Abendrunde'), ActivityKind.other);
      expect(ActivityKind.of('other', name: 'Yoga am Morgen'), ActivityKind.yoga);
      expect(ActivityKind.of(null), ActivityKind.other);
    });

    test('Bouldern zählt als Training, ein Spaziergang nur, wenn geplant', () {
      GarminActivity activity(String type) => GarminActivity(1)
        ..typeKey = type
        ..durationSeconds = 3600;
      expect(activity('bouldering').sport, ActivitySport.other);
      expect(ScoreRules.countsAsTraining(activity('bouldering'), otherIsPlanned: false), isTrue);
      expect(ScoreRules.countsAsTraining(activity('walking'), otherIsPlanned: false), isFalse);
      expect(ScoreRules.countsAsTraining(activity('walking'), otherIsPlanned: true), isTrue);
      expect(HealthImport.label('bouldering'), 'Bouldern');
      expect(HealthImport.label('rock_climbing'), 'Klettern');
      expect(NutritionPlanner.isStrength('bouldering'), isTrue);
    });
  });

  test('Hinweis „Datenquelle verbinden“ nur ohne Quelle und ohne Werte der letzten Woche', () {
    final today = CalendarDay.tryParse('2026-11-24')!;
    expect(showsConnectSourceHint(hasSource: false, metricDays: const [], today: today), isTrue);
    expect(showsConnectSourceHint(hasSource: true, metricDays: const [], today: today), isFalse);
    // Werte aus einer Sicherung oder von Hand vor drei Tagen: kein Hinweis.
    expect(showsConnectSourceHint(hasSource: false, metricDays: [today.adding(-3)], today: today), isFalse);
    expect(showsConnectSourceHint(hasSource: false, metricDays: [today.adding(-7)], today: today), isFalse);
    expect(showsConnectSourceHint(hasSource: false, metricDays: [today.adding(-8)], today: today), isTrue);
  });
}
