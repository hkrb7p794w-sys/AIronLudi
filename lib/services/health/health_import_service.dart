import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/metrics_repository.dart';
import '../../data/repositories/source_store.dart';
import '../../data/settings/settings_store.dart';
import '../garmin/activity_stores.dart';
import 'health_source.dart';

/// Liest Tageswerte, Schlaf, Workouts und Gewicht aus Apple Health bzw. Health Connect (Uhr, Handy, andere Apps) und
/// ergänzt damit die Garmin-Daten. Garmin hat Vorrang; Health füllt nur Lücken (`HealthImport`). Health ist optional:
/// Ohne Berechtigung bleibt es bei einer Meldung.
final class HealthImportService extends ChangeNotifier {
  HealthImportService({
    required this._source,
    required this._settings,
    required this._metrics,
    required this._activities,
    this.sources,
    this.reportStore,
    this.ownBundle = 'io.github.hkrb7p794w.coach',
  });

  static const enabledKey = SettingsKeys.healthImportEnabled;
  static const lastImportKey = SettingsKeys.healthLastImport;
  static const weightsKey = SettingsKeys.healthWeights;
  static const failedRecordingsKey = SettingsKeys.healthRecordingFailures;
  static const firstImportDays = 120;

  /// Workouts je Import, deren Verlauf nachgeladen wird (der Rest folgt beim nächsten Import).
  static const maxRecordingsPerImport = 8;

  final HealthSource _source;
  final SettingsStore _settings;
  final MetricsRepository _metrics;
  final ActivityRepository _activities;

  /// Gemeinsame Ablage aller Quellen (Herkunft, Vorrang je Datenart).
  SourceStore? sources;

  /// Ablage der vollständigen Aktivitätsberichte (gemeinsam mit dem Garmin-Abruf).
  ActivityReportStore? reportStore;

  /// Eigene App-Kennung: Selbst geschriebene Workouts (Krafteinheiten) werden nicht wieder eingelesen.
  final String ownBundle;

  bool isImporting = false;
  String? lastResult;

  /// Fehler des letzten Imports (`null` = alles lesbar), für den Synchronisierungsstatus.
  String? lastProblem;

  Future<bool> get isAvailable => _source.isAvailable;

  bool get isEnabled => _settings.boolValue(enabledKey);
  set isEnabled(bool value) {
    _settings.setBool(enabledKey, value);
    notifyListeners();
  }

  DateTime? get lastImport => _settings.date(lastImportKey);

  /// Wägungen aus Health (letzte 120 Tage).
  List<WeightEntry> get weights =>
      _settings.read(weightsKey, (json) => listStrict(json, WeightEntry.fromJson), const <WeightEntry>[]);

  Future<void> requestAccess() => _source.requestAccess();

  static DateTime _startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

  /// Import seit dem letzten Mal (mit drei Tagen Überlappung, weil Schlaf und Werte nachträglich eintreffen).
  /// [garminConnected]: HRV aus Health nur ohne Garmin (SDNN statt RMSSD, siehe `HealthImport`).
  Future<void> importNow({required bool garminConnected, DateTime? now}) async {
    if (!isEnabled || isImporting || !await isAvailable) return;
    isImporting = true;
    notifyListeners();
    try {
      await _import(garminConnected, now ?? DateTime.now());
    } finally {
      isImporting = false;
      notifyListeners();
    }
  }

  Future<void> _import(bool garminConnected, DateTime now) async {
    final last = lastImport;
    final start = last == null
        ? DateTime(now.year, now.month, now.day - firstImportDays, now.hour, now.minute)
        : DateTime(last.year, last.month, last.day - 3, last.hour, last.minute);
    final dayStart = _startOfDay(start);
    final problems = <String>[];
    try {
      await _source.requestAccess();
    } on Object catch (error) {
      lastResult = 'Keine Berechtigung: $error';
      lastProblem = lastResult;
      return;
    }

    // Tageswerte
    final days = <CalendarDay, HealthDayValues>{};
    Future<void> record(
      HealthQuantity kind,
      Map<CalendarDay, double> Function(List<HealthQuantitySample>) statistic,
      void Function(HealthDayValues values, double value) assign,
    ) async {
      try {
        final samples = await _source.quantities(kind, from: dayStart, to: now);
        for (final MapEntry(key: day, value: value) in statistic(samples).entries) {
          assign(days[day] ??= HealthDayValues(day), value);
        }
      } on Object {
        problems.add(kind.name);
      }
    }

    await record(HealthQuantity.steps, cumulativeSum, (values, value) => values.steps = value);
    await record(HealthQuantity.activeEnergy, cumulativeSum, (values, value) => values.activeKilocalories = value);
    await record(HealthQuantity.basalEnergy, cumulativeSum, (values, value) => values.basalKilocalories = value);
    await record(HealthQuantity.restingHeartRate, average, (values, value) => values.restingHeartRate = value);
    await record(HealthQuantity.hrvSDNN, average, (values, value) => values.hrvSDNN = value);
    await record(HealthQuantity.respiratoryRate, average, (values, value) => values.respiratoryRate = value);
    await record(HealthQuantity.oxygenSaturation, average, (values, value) => values.oxygenSaturation = value);
    await record(HealthQuantity.oxygenSaturation, minimum, (values, value) => values.oxygenSaturationLowest = value);

    final map = <CalendarDay, DailyMetrics>{
      for (final MapEntry(key: day, value: values) in days.entries)
        day: HealthImport.metrics(values, includeHRV: !garminConnected),
    };
    try {
      final samples = await _source.sleep(from: dayStart.subtract(const Duration(days: 1)), to: now);
      for (final MapEntry(key: day, value: night) in HealthImport.sleep(samples).entries) {
        map[day] = map[day]?.merging(night) ?? night;
      }
    } on Object {
      problems.add('Schlaf');
    }
    final daysUpdated = await _saveMetrics(map, now);

    // Workouts
    var added = 0;
    try {
      final workouts = await _source.workouts(from: dayStart, to: now);
      final existing = await _activities.all();
      final known = {for (final activity in existing) activity.id};
      // Herkunft aller gelesenen Workouts (vollständiger Zeitraum: fehlende gelten als in Health gelöscht).
      final all = [
        for (final workout in workouts)
          if (workout.sourceBundle != ownBundle && !workout.sourceBundle.startsWith('$ownBundle.'))
            HealthImport.activity(workout),
      ];
      final allowed = await sources?.recordActivities(
        all,
        from: DataProvider.appleHealth,
        window: DateRange(CalendarDay.fromDate(dayStart), CalendarDay.fromDate(now)),
        complete: true,
        now: now,
      );
      final fresh = HealthImport.newActivities(
        workouts,
        existing: existing,
        ownBundle: ownBundle,
      ).where((activity) => allowed?.contains(activity.id) ?? true).toList();
      await _activities.upsertAll(fresh);
      added = fresh.where((activity) => !known.contains(activity.id)).length;
    } on Object {
      problems.add('Workouts');
    }

    // Gewicht
    try {
      final samples = await _source.quantities(
        HealthQuantity.bodyMass,
        from: DateTime(now.year, now.month, now.day - 120, now.hour, now.minute),
        to: now,
      );
      final entries = HealthImport.weights([
        for (final sample in samples) (date: sample.start, kilograms: sample.value),
      ]);
      await _settings.setJson(weightsKey, [for (final entry in entries) entry.toJson()]);
    } on Object {
      problems.add('Gewicht');
    }

    final detailed = await _detailWorkouts(now);
    await _settings.setDate(lastImportKey, now);
    final buffer = StringBuffer('$daysUpdated Tage, $added neue Workouts aus Apple Health');
    if (detailed > 0) buffer.write(', $detailed mit Verlauf');
    if (problems.isNotEmpty) buffer.write(' · nicht lesbar: ${problems.join(', ')}');
    lastResult = buffer.toString();
    lastProblem = problems.isEmpty ? null : 'Nicht lesbar: ${problems.join(', ')}';
  }

  // Tagesstatistik (wie `HKStatisticsCollectionQuery` mit Tagesintervallen in der Zeitzone des Geräts)

  static Map<CalendarDay, List<HealthQuantitySample>> _byDay(List<HealthQuantitySample> samples) {
    final result = <CalendarDay, List<HealthQuantitySample>>{};
    for (final sample in samples) {
      (result[CalendarDay.fromDate(sample.start.toLocal())] ??= []).add(sample);
    }
    return result;
  }

  /// Summe je Tag. HealthKit führt Uhr und Handy zusammen, ohne doppelt zu zählen; hier zählt je Tag die Quelle mit der
  /// größten Summe.
  @visibleForTesting
  static Map<CalendarDay, double> cumulativeSum(List<HealthQuantitySample> samples) => {
    for (final MapEntry(key: day, value: list) in _byDay(samples).entries)
      day: () {
        final perSource = <String, double>{};
        for (final sample in list) {
          perSource[sample.source] = (perSource[sample.source] ?? 0) + sample.value;
        }
        return perSource.values.reduce((a, b) => a > b ? a : b);
      }(),
  };

  @visibleForTesting
  static Map<CalendarDay, double> average(List<HealthQuantitySample> samples) => {
    for (final MapEntry(key: day, value: list) in _byDay(samples).entries)
      day: list.map((sample) => sample.value).reduce((a, b) => a + b) / list.length,
  };

  @visibleForTesting
  static Map<CalendarDay, double> minimum(List<HealthQuantitySample> samples) => {
    for (final MapEntry(key: day, value: list) in _byDay(samples).entries)
      day: list.map((sample) => sample.value).reduce((a, b) => a < b ? a : b),
  };

  // Speichern

  Future<int> _saveMetrics(Map<CalendarDay, DailyMetrics> map, DateTime now) async {
    final useful = {
      for (final MapEntry(:key, :value) in map.entries)
        if (value.presentFields.isNotEmpty || value.sleepSeconds != null) key: value,
    };
    final sources = this.sources;
    if (sources != null) {
      await sources.ingestDays(useful, from: DataProvider.appleHealth, now: now);
      return useful.length;
    }
    var count = 0;
    for (final MapEntry(key: day, value: health) in useful.entries) {
      final stored = await _metrics.day(day);
      final filled = HealthImport.fill(stored, health);
      if (stored == null || filled != stored) {
        await _metrics.replace(filled, at: now);
        count += 1;
      }
    }
    return count;
  }

  // Verlauf je Workout

  List<int> get _failedRecordings => _settings.read(
    failedRecordingsKey,
    (json) => json is List ? json.whereType<int>().toList() : null,
    const <int>[],
  );

  /// Für Workouts der letzten Wochen den Verlauf lesen und als Bericht speichern (Runden, Splits, Diagramme,
  /// Auswertung) – wie beim Garmin-Abruf, nur aus Health statt aus der Datei der Uhr.
  Future<int> _detailWorkouts(DateTime now) async {
    final reportStore = this.reportStore;
    if (reportStore == null) return 0;
    final today = CalendarDay.fromDate(now);
    final activities = await _activities.all();
    final reports = reportStore.load();
    final failed = <int>{..._failedRecordings};
    final pending = ActivityReportPlanner.pending(
      activities,
      known: reports,
      failed: failed,
      today: today,
      health: true,
    );
    if (pending.isEmpty) return 0;
    final start = DateTime(now.year, now.month, now.day - (ActivityReportPlanner.days + 1), now.hour, now.minute);
    final List<HealthWorkout> workouts;
    try {
      workouts = await _source.workouts(from: start, to: now);
    } on Object {
      return 0;
    }
    final byID = <int, HealthWorkout>{};
    for (final workout in workouts) {
      byID.putIfAbsent(HealthImport.activityID(workout.uuid), () => workout);
    }
    var count = 0;
    for (final activity in pending) {
      if (count >= maxRecordingsPerImport) break;
      // Nicht in Health (von Hand nachgetragen oder dort gelöscht): nicht erneut versuchen.
      final workout = byID[activity.id];
      if (workout == null) {
        failed.add(activity.id);
        continue;
      }
      final HealthRecordingInput input;
      try {
        input = await recordingInput(workout);
      } on Object {
        continue;
      }
      // Ohne Puls und ohne Distanz (z. B. von Hand eingetragen) gibt es nichts auszuwerten.
      if (input.heartRate.isEmpty && input.distance.isEmpty) {
        failed.add(activity.id);
        continue;
      }
      reports[activity.id] = ActivityReportBuilder.build(activity, HealthRecording.fit(input));
      count += 1;
    }
    reportStore.save(reports, today: today);
    final list = failed.toList();
    await _settings.setJson(failedRecordingsKey, list.length > 200 ? list.sublist(list.length - 200) : list);
    return count;
  }

  /// Aufzeichnung eines Workouts für die Detailansicht; `null`, wenn nicht lesbar.
  Future<FitActivity?> recording(int activityID, {CalendarDay? around}) async {
    if (!isEnabled || activityID >= 0 || !await isAvailable) return null;
    final center = around?.referenceDate ?? DateTime.now();
    try {
      final workouts = await _source.workouts(
        from: center.subtract(const Duration(days: 2)),
        to: center.add(const Duration(days: 2)),
      );
      final workout = workouts.where((item) => HealthImport.activityID(item.uuid) == activityID).firstOrNull;
      if (workout == null) return null;
      final fit = HealthRecording.fit(await recordingInput(workout));
      return fit.records.isEmpty ? null : fit;
    } on Object {
      return null;
    }
  }

  static double _seconds(DateTime date) => swiftReferenceDateToJson(date);

  /// Puls und Distanz eines Workouts. Das Paket kennt keine Zuordnung von Proben zum Workout, keine Strecke und keine
  /// Runden/Pausen; gelesen wird der Zeitraum des Workouts (siehe `docs/decisions.md`).
  @visibleForTesting
  Future<HealthRecordingInput> recordingInput(HealthWorkout workout) async {
    final input = HealthRecordingInput(start: _seconds(workout.start), end: _seconds(workout.end));
    final heart = await _source.quantities(HealthQuantity.heartRate, from: workout.start, to: workout.end);
    input.heartRate = [
      for (final sample in heart..sort((a, b) => a.start.compareTo(b.start)))
        HealthSample(time: _seconds(sample.start), value: sample.value),
    ];
    final distanceKind = switch (workout.typeKey) {
      'cycling' => HealthQuantity.distanceCycling,
      'lap_swimming' || 'open_water_swimming' => HealthQuantity.distanceSwimming,
      _ => HealthQuantity.distanceWalkingRunning,
    };
    final distance = await _source.quantities(distanceKind, from: workout.start, to: workout.end);
    // Mehrere Quellen (Uhr und Handy) würden doppelt zählen: nur die Quelle mit der größten Strecke.
    final perSource = <String, List<HealthQuantitySample>>{};
    for (final sample in distance) {
      (perSource[sample.source] ??= []).add(sample);
    }
    final best = perSource.values.isEmpty
        ? const <HealthQuantitySample>[]
        : perSource.values.reduce(
            (a, b) => a.fold(0.0, (sum, s) => sum + s.value) >= b.fold(0.0, (sum, s) => sum + s.value) ? a : b,
          );
    input.distance = [
      for (final sample in [...best]..sort((a, b) => a.start.compareTo(b.start)))
        HealthAmount(start: _seconds(sample.start), end: _seconds(sample.end), value: sample.value),
    ];
    return input;
  }
}
