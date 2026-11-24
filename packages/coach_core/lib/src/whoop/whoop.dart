import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../health/health_import.dart';
import '../integration/data_provider.dart';
import '../util/german_format.dart';

// Antworten der WHOOP-API v2 (Felder wie in der OpenAPI-Beschreibung
// https://api.prod.whoop.com/developer/doc/openapi.json, Stand 14.11.2026). Gelesen wird tolerant: Fehlt ein
// Pflichtfeld, entfällt nur dieser Eintrag; Werte ohne `score_state == SCORED` tragen keine Messwerte.

double? _num(Object? value) => value is num ? value.toDouble() : null;
String? _str(Object? value) => value is String && value.isNotEmpty ? value : null;
Map<String, Object?>? _map(Object? value) => value is Map ? value.cast<String, Object?>() : null;

/// Abstand zu UTC aus `timezone_offset` („+02:00“, „-05:00“, „Z“).
Duration? whoopOffset(String? text) {
  if (text == null) return null;
  if (text == 'Z') return Duration.zero;
  final match = RegExp(r'^([+-])(\d{2}):?(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final minutes = int.parse(match.group(2)!) * 60 + int.parse(match.group(3)!);
  return Duration(minutes: match.group(1) == '-' ? -minutes : minutes);
}

/// Uhrzeit vor Ort zum Zeitpunkt der Aufzeichnung (Zeitzone aus `timezone_offset`, sonst die des Geräts).
DateTime whoopWall(DateTime utc, Duration? offset) => offset == null ? utc.toLocal() : utc.toUtc().add(offset);

/// Tag, zu dem Schlaf und Erholung gehören: Aufwachtag (Ende bzw. Beginn plus sechs Stunden, wie beim Health-Import).
CalendarDay whoopNightDay(DateTime time, Duration? offset) =>
    CalendarDay.fromDate(whoopWall(time.add(const Duration(hours: 6)), offset));

bool _scored(Map<String, Object?> json) => json['score_state'] == 'SCORED';

/// Erholung eines Zyklus (`GET /v2/recovery`).
final class WhoopRecovery {
  const WhoopRecovery({
    required this.cycleID,
    required this.sleepID,
    required this.score,
    required this.restingHeartRate,
    required this.hrvMilliseconds,
    this.spo2,
    this.skinTemperature,
    this.calibrating = false,
  });

  final int cycleID;
  final String? sleepID;

  /// Recovery 0–100 %.
  final double score;
  final double restingHeartRate;

  /// HRV als RMSSD in Millisekunden (wie Garmins nächtlicher HRV-Wert).
  final double hrvMilliseconds;
  final double? spo2;
  final double? skinTemperature;

  /// WHOOP kalibriert noch (erste Tage): Werte sind vorläufig.
  final bool calibrating;

  static WhoopRecovery? fromJson(Object? value) {
    final json = _map(value);
    if (json == null || !_scored(json)) return null;
    final score = _map(json['score']);
    final cycle = json['cycle_id'];
    final (recovery, resting, hrv) = (
      _num(score?['recovery_score']),
      _num(score?['resting_heart_rate']),
      _num(score?['hrv_rmssd_milli']),
    );
    if (cycle is! int || recovery == null || resting == null || hrv == null) return null;
    return WhoopRecovery(
      cycleID: cycle,
      sleepID: _str(json['sleep_id']),
      score: recovery,
      restingHeartRate: resting,
      hrvMilliseconds: hrv,
      spo2: _num(score?['spo2_percentage']),
      skinTemperature: _num(score?['skin_temp_celsius']),
      calibrating: score?['user_calibrating'] == true,
    );
  }

  /// Stufe in WHOOP-Farben (grün ab 67 %, gelb ab 34 %, sonst rot). Eigene Werte statt Garmins „HIGH/LOW“, damit die
  /// Tagesampel WHOOPs Skala erkennt und nicht Garmins Readiness-Stufen darauf anwendet (`RecoveryEvaluator`).
  String get level => score >= 67
      ? WhoopRecoveryLevel.green
      : score >= 34
      ? WhoopRecoveryLevel.yellow
      : WhoopRecoveryLevel.red;
}

/// Werte von `DailyMetrics.trainingReadinessLevel`, wenn der Erholungswert von WHOOP stammt.
abstract final class WhoopRecoveryLevel {
  static const green = 'WHOOP_GREEN';
  static const yellow = 'WHOOP_YELLOW';
  static const red = 'WHOOP_RED';

  static bool isWhoop(String? level) => level != null && level.toUpperCase().startsWith('WHOOP_');
}

/// Physiologischer Zyklus, etwa ein Tag (`GET /v2/cycle`).
final class WhoopCycle {
  const WhoopCycle({
    required this.id,
    required this.start,
    required this.end,
    required this.offset,
    this.strain,
    this.kilojoules,
    this.averageHeartRate,
    this.maxHeartRate,
    this.steps,
  });

  final int id;
  final DateTime start;

  /// `null`: läuft noch.
  final DateTime? end;
  final Duration? offset;
  final double? strain;
  final double? kilojoules;
  final double? averageHeartRate;
  final double? maxHeartRate;
  final int? steps;

  static WhoopCycle? fromJson(Object? value) {
    final json = _map(value);
    if (json == null) return null;
    final id = json['id'];
    final start = DateTime.tryParse(_str(json['start']) ?? '');
    if (id is! int || start == null) return null;
    final score = _scored(json) ? _map(json['score']) : null;
    return WhoopCycle(
      id: id,
      start: start,
      end: DateTime.tryParse(_str(json['end']) ?? ''),
      offset: whoopOffset(_str(json['timezone_offset'])),
      strain: _num(score?['strain']),
      kilojoules: _num(score?['kilojoule']),
      averageHeartRate: _num(score?['average_heart_rate']),
      maxHeartRate: _num(score?['max_heart_rate']),
      steps: json['step_count'] is int ? json['step_count'] as int : null,
    );
  }

  CalendarDay get day => whoopNightDay(start, offset);
}

/// Schlaf (`GET /v2/activity/sleep`).
final class WhoopSleep {
  const WhoopSleep({
    required this.id,
    required this.start,
    required this.end,
    required this.offset,
    required this.nap,
    this.inBedMilliseconds,
    this.awakeMilliseconds,
    this.lightMilliseconds,
    this.deepMilliseconds,
    this.remMilliseconds,
    this.disturbances,
    this.performance,
    this.efficiency,
    this.consistency,
    this.respiratoryRate,
    this.neededMilliseconds,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final Duration? offset;
  final bool nap;
  final double? inBedMilliseconds;
  final double? awakeMilliseconds;
  final double? lightMilliseconds;

  /// Tiefschlaf (Slow Wave Sleep).
  final double? deepMilliseconds;
  final double? remMilliseconds;
  final double? disturbances;

  /// Schlafleistung 0–100 % (geschlafen im Verhältnis zum Bedarf) – WHOOPs Schlaf-Score.
  final double? performance;
  final double? efficiency;
  final double? consistency;
  final double? respiratoryRate;

  /// Schlafbedarf: Grundbedarf plus Schlafschuld und Belastung, minus Nickerchen.
  final double? neededMilliseconds;

  static WhoopSleep? fromJson(Object? value) {
    final json = _map(value);
    if (json == null) return null;
    final id = _str(json['id']);
    final start = DateTime.tryParse(_str(json['start']) ?? '');
    final end = DateTime.tryParse(_str(json['end']) ?? '');
    if (id == null || start == null || end == null || !end.isAfter(start)) return null;
    final score = _scored(json) ? _map(json['score']) : null;
    final stages = _map(score?['stage_summary']);
    final needed = _map(score?['sleep_needed']);
    double? neededTotal;
    if (needed != null) {
      neededTotal = [
        'baseline_milli',
        'need_from_sleep_debt_milli',
        'need_from_recent_strain_milli',
        'need_from_recent_nap_milli',
      ].fold<double>(0, (sum, key) => sum + (_num(needed[key]) ?? 0));
    }
    return WhoopSleep(
      id: id,
      start: start,
      end: end,
      offset: whoopOffset(_str(json['timezone_offset'])),
      nap: json['nap'] == true,
      inBedMilliseconds: _num(stages?['total_in_bed_time_milli']),
      awakeMilliseconds: _num(stages?['total_awake_time_milli']),
      lightMilliseconds: _num(stages?['total_light_sleep_time_milli']),
      deepMilliseconds: _num(stages?['total_slow_wave_sleep_time_milli']),
      remMilliseconds: _num(stages?['total_rem_sleep_time_milli']),
      disturbances: _num(stages?['disturbance_count']),
      performance: _num(score?['sleep_performance_percentage']),
      efficiency: _num(score?['sleep_efficiency_percentage']),
      consistency: _num(score?['sleep_consistency_percentage']),
      respiratoryRate: _num(score?['respiratory_rate']),
      neededMilliseconds: neededTotal,
    );
  }

  /// Geschlafen (leicht, tief, REM) in Sekunden; ohne Bewertung keine Angabe.
  double? get asleepSeconds {
    final parts = [lightMilliseconds, deepMilliseconds, remMilliseconds];
    if (parts.every((part) => part == null)) return null;
    return parts.fold<double>(0, (sum, part) => sum + (part ?? 0)) / 1000;
  }

  CalendarDay get day => whoopNightDay(end, offset);
}

/// Training (`GET /v2/activity/workout`).
final class WhoopWorkout {
  const WhoopWorkout({
    required this.id,
    required this.start,
    required this.end,
    required this.offset,
    required this.sport,
    this.strain,
    this.averageHeartRate,
    this.maxHeartRate,
    this.kilojoules,
    this.distanceMeters,
    this.altitudeGainMeters,
    this.zoneMilliseconds,
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final Duration? offset;

  /// `sport_name`, z. B. „running“, „weightlifting“.
  final String sport;
  final double? strain;
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? kilojoules;
  final double? distanceMeters;
  final double? altitudeGainMeters;

  /// Zeit in den WHOOP-Zonen 0–5 in Millisekunden.
  final List<double>? zoneMilliseconds;

  static WhoopWorkout? fromJson(Object? value) {
    final json = _map(value);
    if (json == null) return null;
    final id = _str(json['id']);
    final start = DateTime.tryParse(_str(json['start']) ?? '');
    final end = DateTime.tryParse(_str(json['end']) ?? '');
    if (id == null || start == null || end == null || !end.isAfter(start)) return null;
    final score = _scored(json) ? _map(json['score']) : null;
    final zones = _map(score?['zone_durations']);
    return WhoopWorkout(
      id: id,
      start: start,
      end: end,
      offset: whoopOffset(_str(json['timezone_offset'])),
      sport: _str(json['sport_name']) ?? 'activity',
      strain: _num(score?['strain']),
      averageHeartRate: _num(score?['average_heart_rate']),
      maxHeartRate: _num(score?['max_heart_rate']),
      kilojoules: _num(score?['kilojoule']),
      distanceMeters: _num(score?['distance_meter']),
      altitudeGainMeters: _num(score?['altitude_gain_meter']),
      zoneMilliseconds: zones == null
          ? null
          : [
              for (final key in const ['zero', 'one', 'two', 'three', 'four', 'five'])
                _num(zones['zone_${key}_milli']) ?? 0,
            ],
    );
  }
}

/// Körperwerte (`GET /v2/user/measurement/body`).
final class WhoopBody {
  const WhoopBody({required this.heightMeters, required this.weightKilograms, required this.maxHeartRate});

  final double heightMeters;
  final double weightKilograms;
  final double maxHeartRate;

  static WhoopBody? fromJson(Object? value) {
    final json = _map(value);
    final (height, weight, maxHR) = (
      _num(json?['height_meter']),
      _num(json?['weight_kilogram']),
      _num(json?['max_heart_rate']),
    );
    if (height == null || weight == null || maxHR == null) return null;
    return WhoopBody(heightMeters: height, weightKilograms: weight, maxHeartRate: maxHR);
  }

  Map<String, Object?> toJson() => {
    'height_meter': heightMeters,
    'weight_kilogram': weightKilograms,
    'max_heart_rate': maxHeartRate,
  };
}

/// Profil (`GET /v2/user/profile/basic`); nur der Vorname wird angezeigt.
final class WhoopProfile {
  const WhoopProfile({required this.userID, required this.firstName});

  final int userID;
  final String firstName;

  static WhoopProfile? fromJson(Object? value) {
    final json = _map(value);
    final id = json?['user_id'];
    if (id is! int) return null;
    return WhoopProfile(userID: id, firstName: _str(json?['first_name']) ?? '');
  }

  Map<String, Object?> toJson() => {'user_id': userID, 'first_name': firstName};
}

/// Zugang bei WHOOP (OAuth); liegt nur im sicheren Speicher.
final class WhoopToken {
  const WhoopToken({required this.accessToken, required this.refreshToken, required this.expiresAt});

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  /// Aus der Antwort des Token-Tauschs (`expires_in` in Sekunden).
  static WhoopToken? fromResponse(Object? value, {required DateTime now}) {
    final json = _map(value);
    final access = _str(json?['access_token']);
    if (access == null) return null;
    final seconds = _num(json?['expires_in']) ?? 3600;
    return WhoopToken(
      accessToken: access,
      refreshToken: _str(json?['refresh_token']),
      expiresAt: now.add(Duration(seconds: seconds.round())),
    );
  }

  /// Eine Minute Puffer, damit kein Abruf mit einem gerade ablaufenden Token startet.
  bool isExpired(DateTime now) => !now.isBefore(expiresAt.subtract(const Duration(minutes: 1)));

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': ?refreshToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };

  static WhoopToken? fromJson(Object? value) {
    final json = _map(value);
    final access = _str(json?['access_token']);
    final expires = DateTime.tryParse(_str(json?['expires_at']) ?? '');
    if (access == null || expires == null) return null;
    return WhoopToken(accessToken: access, refreshToken: _str(json?['refresh_token']), expiresAt: expires);
  }
}

/// Umrechnung der WHOOP-Daten in die herstellerunabhängigen Modelle der App (Tageswerte, Aktivitäten).
abstract final class WhoopImport {
  /// Kilojoule in Kilokalorien.
  static double kilocalories(double kilojoules) => kilojoules / 4.184;

  /// Tageswerte je Aufwachtag: Schlaf (Hauptschlaf, längster der Nacht), Erholung mit HRV und Ruhepuls (über den
  /// Schlaf bzw. den Zyklus zugeordnet), Kalorien und Schritte des Zyklus.
  static Map<CalendarDay, DailyMetrics> days({
    required List<WhoopRecovery> recoveries,
    required List<WhoopSleep> sleeps,
    required List<WhoopCycle> cycles,
  }) {
    final result = <CalendarDay, DailyMetrics>{};
    DailyMetrics on(CalendarDay day) => result[day] ??= DailyMetrics(day);

    final mainSleeps = <CalendarDay, WhoopSleep>{};
    for (final sleep in sleeps.where((sleep) => !sleep.nap)) {
      final current = mainSleeps[sleep.day];
      if (current == null || (sleep.asleepSeconds ?? 0) > (current.asleepSeconds ?? 0)) mainSleeps[sleep.day] = sleep;
    }
    for (final MapEntry(key: day, value: sleep) in mainSleeps.entries) {
      final asleep = sleep.asleepSeconds;
      if (asleep == null) continue;
      final start = whoopWall(sleep.start, sleep.offset);
      final end = whoopWall(sleep.end, sleep.offset);
      on(day)
        ..sleepSeconds = asleep
        ..deepSleepSeconds = sleep.deepMilliseconds == null ? null : sleep.deepMilliseconds! / 1000
        ..lightSleepSeconds = sleep.lightMilliseconds == null ? null : sleep.lightMilliseconds! / 1000
        ..remSleepSeconds = sleep.remMilliseconds == null ? null : sleep.remMilliseconds! / 1000
        ..awakeSleepSeconds = sleep.awakeMilliseconds == null ? null : sleep.awakeMilliseconds! / 1000
        ..sleepScore = sleep.performance
        ..respirationSleep = sleep.respiratoryRate
        ..sleepStartMinutes = (start.hour * 60 + start.minute).toDouble()
        ..sleepEndMinutes = (end.hour * 60 + end.minute).toDouble();
    }

    final sleepsByID = {for (final sleep in sleeps) sleep.id: sleep};
    final cyclesByID = {for (final cycle in cycles) cycle.id: cycle};
    for (final recovery in recoveries) {
      final day = sleepsByID[recovery.sleepID]?.day ?? cyclesByID[recovery.cycleID]?.day;
      if (day == null) continue;
      on(day)
        ..restingHeartRate = recovery.restingHeartRate
        ..hrvLastNightAverage = recovery.hrvMilliseconds
        ..trainingReadiness = recovery.score
        ..trainingReadinessLevel = recovery.level
        ..spo2Average = recovery.spo2;
    }

    for (final cycle in cycles) {
      final kilojoules = cycle.kilojoules;
      if (kilojoules == null && cycle.steps == null && cycle.maxHeartRate == null && cycle.strain == null) continue;
      final metrics = on(cycle.day);
      // Tages-Strain (0–21) des Zyklus; der laufende Zyklus zählt mit seinem bisherigen Stand.
      if (cycle.strain case final strain? when strain >= 0) metrics.dayStrain = (strain * 10).roundToDouble() / 10;
      if (kilojoules != null) metrics.totalKilocalories = kilocalories(kilojoules).roundToDouble();
      if (cycle.steps case final steps?) metrics.steps = steps.toDouble();
      if (cycle.maxHeartRate case final maxHR?) metrics.maxHeartRate = maxHR;
    }
    return result;
  }

  /// Typ wie bei Garmin (`typeKey`), damit Sportart, Plan-Abgleich und Auswertungen wie gewohnt greifen.
  static String typeKey(String sport) {
    final key = sport.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    return switch (key) {
      'running' || 'track_and_field' => 'running',
      'trail_running' => 'trail_running',
      'treadmill' || 'treadmill_running' => 'treadmill_running',
      'cycling' || 'road_cycling' || 'mountain_biking' || 'gravel_cycling' => 'cycling',
      'spin' || 'spinning' || 'indoor_cycling' || 'assault_bike' => 'indoor_cycling',
      'swimming' || 'swim' => 'lap_swimming',
      'open_water_swimming' => 'open_water_swimming',
      'weightlifting' ||
      'powerlifting' ||
      'strength_trainer' ||
      'functional_fitness' ||
      'crossfit' ||
      'weightlifting_msk' => 'strength_training',
      'walking' => 'walking',
      'hiking' || 'hiking_rucking' || 'rucking' => 'hiking',
      'yoga' || 'hot_yoga' => 'yoga',
      'hiit' => 'hiit',
      'rowing' || 'indoor_rowing' => 'indoor_rowing',
      'elliptical' => 'elliptical',
      _ => key,
    };
  }

  /// Aktivität aus einem WHOOP-Training. Zonen 1–5 wie bei Garmin (Zone 0 = sehr leicht entfällt), Strain als Text.
  static GarminActivity activity(WhoopWorkout workout) {
    final type = typeKey(workout.sport);
    final duration = workout.end.difference(workout.start).inMilliseconds / 1000;
    final wall = whoopWall(workout.start, workout.offset);
    final label = HealthImport.label(type);
    final activity = GarminActivity(HealthImport.activityID(workout.id))
      ..typeKey = type
      ..name = '${label == 'Training' ? _title(workout.sport) : label} · WHOOP'
      ..startLocal =
          '${wall.year.toString().padLeft(4, '0')}-${_two(wall.month)}-${_two(wall.day)} '
          '${_two(wall.hour)}:${_two(wall.minute)}:${_two(wall.second)}'
      ..durationSeconds = duration
      ..elapsedSeconds = duration
      ..averageHeartRate = workout.averageHeartRate
      ..maxHeartRate = workout.maxHeartRate
      ..distanceMeters = workout.distanceMeters != null && workout.distanceMeters! > 0 ? workout.distanceMeters : null
      ..elevationGain = workout.altitudeGainMeters
      ..provider = DataProvider.whoop
      ..externalID = workout.id;
    if (workout.kilojoules case final kilojoules?) {
      activity
        ..calories = kilocalories(kilojoules).roundToDouble()
        ..activeKilocalories = activity.calories;
    }
    if (activity.distanceMeters case final distance? when duration > 0) activity.averageSpeed = distance / duration;
    if (workout.zoneMilliseconds case final zones? when zones.length == 6) {
      activity.secondsInZones = [for (final zone in zones.skip(1)) zone / 1000];
    }
    if (workout.strain case final strain?) {
      activity.trainingEffectLabel = 'WHOOP-Strain ${GermanFormat.decimal(strain)}';
    }
    return activity;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _title(String sport) {
    final words = sport.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (words.isEmpty) return 'Training';
    return words[0].toUpperCase() + words.substring(1);
  }

  /// Abrufzeitraum: beim ersten Mal [initialDays] Tage, danach ab dem letzten Abruf mit zwei Tagen Überlappung (WHOOP
  /// bewertet Schlaf und Erholung nachträglich).
  static DateTime syncStart({required DateTime now, required DateTime? lastSync, int initialDays = 90}) {
    final initial = now.subtract(Duration(days: initialDays));
    if (lastSync == null) return initial;
    final overlap = lastSync.subtract(const Duration(days: 2));
    return overlap.isBefore(initial) ? initial : overlap;
  }

  /// Höchstens so viele Seiten je Liste und Abruf (Grenze 100 Anfragen je Minute, 25 Einträge je Seite).
  static int maxPages(int days) => math.max(2, (days / 20).ceil() + 1);
}

/// Fehler der WHOOP-Anmeldung (OAuth-Code aus `coach://whoop?error=…`) in Sätzen mit Lösungsweg. Die meisten Ursachen
/// liegen in der Developer-App der Betreiberin bzw. des Betreibers, nicht bei der Person, die verbinden will – das
/// sagt der Text dann auch.
abstract final class WhoopAuthErrors {
  /// Hinweis für Fehler, die nur die Betreiberin bzw. der Betreiber des Workers beheben kann.
  static const operatorHint =
      'Bitte gib das an die Person weiter, die den KI-Worker betreibt (Anleitung: '
      'Einrichtung, Abschnitt WHOOP).';

  static String message(String code) => switch (code) {
    'access_denied' => 'Freigabe bei WHOOP abgelehnt. Du kannst es jederzeit erneut versuchen.',
    'invalid_scope' =>
      'In der WHOOP-Developer-App fehlt eine Berechtigung (Scope). Nötig sind „offline“, „read:recovery“, '
          '„read:cycles“, „read:workout“, „read:sleep“, „read:profile“ und „read:body_measurement“. $operatorHint',
    'unauthorized_client' || 'invalid_client' =>
      'Die WHOOP-Developer-App ist im Worker falsch hinterlegt (Client-ID oder Client-Secret). $operatorHint',
    'invalid_request' || 'redirect_uri_mismatch' =>
      'Die Rücksprung-Adresse der WHOOP-Developer-App passt nicht zum Worker (…/w/whoop). $operatorHint',
    'server_error' || 'temporarily_unavailable' => 'WHOOP ist gerade nicht erreichbar. Bitte später erneut verbinden.',
    _ => 'WHOOP hat die Anmeldung abgebrochen ($code). Bitte erneut verbinden; tritt es wieder auf: $operatorHint',
  };
}
