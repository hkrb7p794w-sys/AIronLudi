// WHOOP-API v2: Antworten lesen (Felder wie in der OpenAPI-Beschreibung), Tageswerte je Aufwachtag, Aktivitäten,
// Token und Abrufzeitraum.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

Map<String, Object?> sleepJson({
  String id = 'ecfc6a15-4661-442f-a9a4-f160dd7afae8',
  String start = '2026-11-13T22:30:00.000Z',
  String end = '2026-11-14T06:00:00.000Z',
  bool nap = false,
  String state = 'SCORED',
  int light = 14400000,
}) => {
  'id': id,
  'cycle_id': 93845,
  'user_id': 10129,
  'created_at': end,
  'updated_at': end,
  'start': start,
  'end': end,
  'timezone_offset': '+01:00',
  'nap': nap,
  'score_state': state,
  'score': {
    'stage_summary': {
      'total_in_bed_time_milli': 27000000,
      'total_awake_time_milli': 1800000,
      'total_no_data_time_milli': 0,
      'total_light_sleep_time_milli': light,
      'total_slow_wave_sleep_time_milli': 5400000,
      'total_rem_sleep_time_milli': 5400000,
      'sleep_cycle_count': 4,
      'disturbance_count': 9,
    },
    'sleep_needed': {
      'baseline_milli': 27395716,
      'need_from_sleep_debt_milli': 352230,
      'need_from_recent_strain_milli': 208595,
      'need_from_recent_nap_milli': -12312,
    },
    'respiratory_rate': 16.1,
    'sleep_performance_percentage': 98,
    'sleep_consistency_percentage': 90,
    'sleep_efficiency_percentage': 91.7,
  },
};

const recoveryJson = {
  'cycle_id': 93845,
  'sleep_id': 'ecfc6a15-4661-442f-a9a4-f160dd7afae8',
  'user_id': 10129,
  'created_at': '2026-11-14T06:05:00.000Z',
  'updated_at': '2026-11-14T06:05:00.000Z',
  'score_state': 'SCORED',
  'score': {
    'user_calibrating': false,
    'recovery_score': 44,
    'resting_heart_rate': 64,
    'hrv_rmssd_milli': 31.813562,
    'spo2_percentage': 95.6875,
    'skin_temp_celsius': 33.7,
  },
};

const cycleJson = {
  'id': 93845,
  'user_id': 10129,
  'created_at': '2026-11-13T22:30:00.000Z',
  'updated_at': '2026-11-14T20:00:00.000Z',
  'start': '2026-11-13T22:30:00.000Z',
  'end': '2026-11-14T22:00:00.000Z',
  'timezone_offset': '+01:00',
  'score_state': 'SCORED',
  'score': {'strain': 5.2951527, 'kilojoule': 8288.297, 'average_heart_rate': 68, 'max_heart_rate': 141},
  'step_count': 8432,
};

const workoutJson = {
  'id': 'ecfc6a15-4661-442f-a9a4-f160dd7afae9',
  'user_id': 9012,
  'created_at': '2026-11-14T17:30:00.000Z',
  'updated_at': '2026-11-14T17:30:00.000Z',
  'start': '2026-11-14T16:30:00.000Z',
  'end': '2026-11-14T17:15:00.000Z',
  'timezone_offset': '+01:00',
  'sport_name': 'running',
  'score_state': 'SCORED',
  'score': {
    'strain': 8.2463,
    'average_heart_rate': 123,
    'max_heart_rate': 146,
    'kilojoule': 1569.34033203125,
    'percent_recorded': 100,
    'distance_meter': 7200.5,
    'altitude_gain_meter': 46.64,
    'altitude_change_meter': -0.78,
    'zone_durations': {
      'zone_zero_milli': 300000,
      'zone_one_milli': 600000,
      'zone_two_milli': 900000,
      'zone_three_milli': 600000,
      'zone_four_milli': 300000,
      'zone_five_milli': 0,
    },
  },
};

void main() {
  test('Zeitzone aus timezone_offset', () {
    expect(whoopOffset('+01:00'), const Duration(hours: 1));
    expect(whoopOffset('-05:30'), const Duration(hours: -5, minutes: -30));
    expect(whoopOffset('Z'), Duration.zero);
    expect(whoopOffset('kaputt'), isNull);
  });

  test('Schlaf, Erholung und Zyklus ergeben die Tageswerte des Aufwachtags', () {
    final sleep = WhoopSleep.fromJson(sleepJson())!;
    expect(sleep.asleepSeconds, 25200);
    expect(sleep.neededMilliseconds, closeTo(27944229, 0.5));
    final days = WhoopImport.days(
      recoveries: [WhoopRecovery.fromJson(recoveryJson)!],
      sleeps: [
        sleep,
        // Nickerchen am Nachmittag zählt nicht als Nachtschlaf.
        WhoopSleep.fromJson(
          sleepJson(id: 'nap', start: '2026-11-14T13:00:00.000Z', end: '2026-11-14T13:30:00.000Z', nap: true),
        )!,
      ],
      cycles: [WhoopCycle.fromJson(cycleJson)!],
    );
    final day = days[const CalendarDay(2026, 11, 14)]!;
    expect(days.keys, [const CalendarDay(2026, 11, 14)]);
    expect(day.sleepSeconds, 25200);
    expect(day.deepSleepSeconds, 5400);
    expect(day.remSleepSeconds, 5400);
    expect(day.awakeSleepSeconds, 1800);
    expect(day.sleepScore, 98);
    expect(day.respirationSleep, 16.1);
    // Ortszeit +01:00: 23:30 bis 07:00.
    expect(day.sleepStartMinutes, 23 * 60 + 30);
    expect(day.sleepEndMinutes, 7 * 60);
    expect(day.restingHeartRate, 64);
    expect(day.hrvLastNightAverage, closeTo(31.81, 0.01));
    expect(day.trainingReadiness, 44);
    expect(day.trainingReadinessLevel, 'MODERATE');
    expect(day.spo2Average, closeTo(95.69, 0.01));
    expect(day.totalKilocalories, 1981);
    expect(day.steps, 8432);
    expect(day.maxHeartRate, 141);
  });

  test('ohne Bewertung keine Messwerte; längster Hauptschlaf der Nacht gewinnt', () {
    expect(WhoopRecovery.fromJson({...recoveryJson, 'score_state': 'PENDING_SCORE'}), isNull);
    final pending = WhoopSleep.fromJson(sleepJson(state: 'PENDING_SCORE'))!;
    expect(pending.asleepSeconds, isNull);
    final short = WhoopSleep.fromJson(sleepJson(id: 'kurz', light: 3600000))!;
    final long = WhoopSleep.fromJson(sleepJson())!;
    final days = WhoopImport.days(recoveries: const [], sleeps: [short, long, pending], cycles: const []);
    expect(days.values.single.sleepSeconds, 25200);
    expect(WhoopRecovery.fromJson({...recoveryJson, 'score': null}), isNull);
    expect(WhoopSleep.fromJson({'id': 'x'}), isNull);
  });

  test('Erholung ohne passenden Schlaf zählt zum Tag des Zyklus; Stufen wie WHOOP-Farben', () {
    final days = WhoopImport.days(
      recoveries: [
        WhoopRecovery.fromJson({...recoveryJson, 'sleep_id': 'anders'})!,
      ],
      sleeps: const [],
      cycles: [WhoopCycle.fromJson(cycleJson)!],
    );
    expect(days[const CalendarDay(2026, 11, 14)]!.trainingReadiness, 44);
    WhoopRecovery recovery(double score) =>
        WhoopRecovery(cycleID: 1, sleepID: null, score: score, restingHeartRate: 50, hrvMilliseconds: 60);
    expect([recovery(80).level, recovery(50).level, recovery(20).level], ['HIGH', 'MODERATE', 'LOW']);
  });

  test('Training wird zur Aktivität mit Herkunft WHOOP, Zonen 1–5 und Strain', () {
    final activity = WhoopImport.activity(WhoopWorkout.fromJson(workoutJson)!);
    expect(activity.provider, DataProvider.whoop);
    expect(activity.externalID, 'ecfc6a15-4661-442f-a9a4-f160dd7afae9');
    expect(activity.id, isNegative);
    expect(activity.id, HealthImport.activityID('ecfc6a15-4661-442f-a9a4-f160dd7afae9'));
    expect(activity.sport, ActivitySport.run);
    expect(activity.name, 'Laufen · WHOOP');
    expect(activity.startLocal, '2026-11-14 17:30:00');
    expect(activity.durationSeconds, 2700);
    expect(activity.distanceMeters, 7200.5);
    expect(activity.averageSpeed, closeTo(2.667, 0.001));
    expect(activity.calories, 375);
    expect(activity.averageHeartRate, 123);
    expect(activity.secondsInZones, [600, 900, 600, 300, 0]);
    expect(activity.trainingEffectLabel, 'WHOOP-Strain 8,2');
    expect(activity.day, const CalendarDay(2026, 11, 14));
    // Gespeichert und wieder gelesen wie jede andere Aktivität.
    expect(GarminActivity.fromJson(activity.toJson())!.provider, DataProvider.whoop);
  });

  test('Sportarten auf Garmin-Typen abgebildet', () {
    expect(WhoopImport.typeKey('weightlifting'), 'strength_training');
    expect(WhoopImport.typeKey('Functional Fitness'), 'strength_training');
    expect(WhoopImport.typeKey('cycling'), 'cycling');
    expect(WhoopImport.typeKey('swimming'), 'lap_swimming');
    expect(WhoopImport.typeKey('hiking-rucking'), 'hiking');
    expect(WhoopImport.typeKey('pickleball'), 'pickleball');
    final unknown = WhoopImport.activity(WhoopWorkout.fromJson({...workoutJson, 'sport_name': 'pickleball'})!);
    expect(unknown.name, 'Pickleball · WHOOP');
    expect(unknown.sport, ActivitySport.other);
  });

  test('Token aus dem Tausch, Ablauf mit Puffer, gespeichert und gelesen', () {
    final now = DateTime.utc(2026, 11, 14, 12);
    final token = WhoopToken.fromResponse({'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600}, now: now)!;
    expect(token.expiresAt, DateTime.utc(2026, 11, 14, 13));
    expect(token.isExpired(now.add(const Duration(minutes: 58))), isFalse);
    expect(token.isExpired(now.add(const Duration(minutes: 59))), isTrue);
    final stored = WhoopToken.fromJson(token.toJson())!;
    expect((stored.accessToken, stored.refreshToken, stored.expiresAt), ('a', 'r', token.expiresAt));
    expect(WhoopToken.fromResponse({'error': 'x'}, now: now), isNull);
  });

  test('Abrufzeitraum: erst 90 Tage, dann ab dem letzten Abruf mit zwei Tagen Überlappung', () {
    final now = DateTime.utc(2026, 11, 14);
    expect(WhoopImport.syncStart(now: now, lastSync: null), DateTime.utc(2026, 8, 16));
    expect(WhoopImport.syncStart(now: now, lastSync: DateTime.utc(2026, 11, 13)), DateTime.utc(2026, 11, 11));
    expect(WhoopImport.syncStart(now: now, lastSync: DateTime.utc(2025, 1, 1)), DateTime.utc(2026, 8, 16));
  });

  test('Körperwerte und Profil', () {
    final body = WhoopBody.fromJson({'height_meter': 1.83, 'weight_kilogram': 82.1, 'max_heart_rate': 189})!;
    expect(WhoopBody.fromJson(body.toJson())!.maxHeartRate, 189);
    final profile = WhoopProfile.fromJson({
      'user_id': 10129,
      'email': 'x@example.com',
      'first_name': 'Sam',
      'last_name': 'L',
    })!;
    expect(profile.toJson(), {'user_id': 10129, 'first_name': 'Sam'});
  });
}
