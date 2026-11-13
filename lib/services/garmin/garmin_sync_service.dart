import 'dart:isolate';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';

import '../../data/repositories/metrics_repository.dart';
import '../../data/repositories/source_store.dart';
import '../../data/settings/settings_store.dart';
import 'activity_stores.dart';
import 'garmin_client.dart';
import 'garmin_connect_session.dart';

/// Ergebnis eines Abrufs für die Anzeige in den Einstellungen.
final class SyncReport {
  SyncReport(this.range, {DateTime? finishedAt}) : finishedAt = finishedAt ?? DateTime.now();

  final DateRange range;
  int daysUpdated = 0;
  int activitiesUpdated = 0;

  /// Per FIT-Datei ausgewertete Läufe und Fahrten (aerobe Kopplung, Pace-Check).
  int activitiesAnalyzed = 0;

  /// Aktivitäten, die mit Runden, Verlauf und allen Kennzahlen nachgeladen wurden.
  int activitiesDetailed = 0;

  /// Fehler einzelner Endpunkte; der Rest des Abrufs läuft trotzdem durch.
  final List<String> errors = [];

  /// Beantwortete Abrufe je Quelle (Garmin-Konto, Personal API).
  Map<String, int> sources = {};

  /// Grund, warum die Personal API einspringen musste.
  String? connectProblem;
  DateTime finishedAt;

  String get summary {
    final buffer = StringBuffer(
      '$daysUpdated Tage, $activitiesUpdated Aktivitäten (${range.start.iso} – ${range.end.iso})',
    );
    if (activitiesAnalyzed > 0) buffer.write(', $activitiesAnalyzed ausgewertet');
    if (activitiesDetailed > 0) buffer.write(', $activitiesDetailed mit Runden und Verlauf');
    if (errors.isNotEmpty) buffer.write(', ${errors.length} Fehler');
    if (sources.isNotEmpty) {
      final keys = sources.keys.toList()..sort();
      buffer.write(' · ${keys.map((key) => '$key: ${sources[key]}').join(', ')}');
    }
    return buffer.toString();
  }
}

/// Holt Garmin-Daten und speichert sie in der Datenbank.
///
/// Jeder Endpunkt ist einzeln abgesichert (wie `_safe` im Altbestand): Fällt einer aus – die Uhr kann etwas nicht oder
/// Garmin ändert ein Format –, laufen die anderen weiter.
final class GarminSyncService {
  GarminSyncService({
    required this._client,
    required this._settings,
    required this._metrics,
    required this._activities,
    required this._raw,
    ActivityAnalysisStore? analysisStore,
    ActivityReportStore? reportStore,
    this.sources,
  }) : analysisStore = analysisStore ?? ActivityAnalysisStore(),
       reportStore = reportStore ?? ActivityReportStore();

  final GarminClient _client;
  final SettingsStore _settings;
  final MetricsRepository _metrics;
  final ActivityRepository _activities;
  final RawResponseRepository _raw;
  final ActivityAnalysisStore analysisStore;
  final ActivityReportStore reportStore;

  /// Gemeinsame Ablage aller Quellen; ohne (Tests) wie bisher direkt in die Tageswerte.
  SourceStore? sources;

  /// Abrufe der Datei der Uhr in diesem Durchlauf (Garmin-Rate-Limit schonen; der Rest folgt beim nächsten Abruf).
  int _fileFetches = 0;
  static const maxFileFetchesPerSync = 8;

  static const failedReportsKey = SettingsKeys.garminReportFailures;
  static const lastSyncKey = SettingsKeys.garminLastSync;
  static const profileKey = SettingsKeys.garminProfile;
  static const profileDateKey = SettingsKeys.garminProfileDate;
  static const activityBackfillKey = SettingsKeys.garminActivityBackfill;
  static const racePredictionsKey = SettingsKeys.garminRacePredictions;
  static const weightsKey = SettingsKeys.garminWeights;

  DateTime? get lastSync => _settings.date(lastSyncKey);

  /// Wettkampfprognosen der Uhr (nur über das Garmin-Konto).
  RacePredictions? get racePredictions => _settings.read(racePredictionsKey, RacePredictions.fromJson, null);

  /// Wägungen aus Garmin Connect (letzte 120 Tage).
  List<WeightEntry> get weights =>
      _settings.read(weightsKey, (json) => listStrict(json, WeightEntry.fromJson), const <WeightEntry>[]);

  GarminProfile? get profile => _settings.contains(profileKey) && _settings.json(profileKey) is Map
      ? GarminProfile.fromJson(_settings.json(profileKey))
      : null;

  Future<SyncReport> sync({DateTime? now}) async {
    final at = now ?? DateTime.now();
    if (!_client.isConfigured) throw GarminAPIError.missingKey;
    _client.resetSources();
    final connect = _client.connect;
    if (connect?.isLoggedIn ?? false) {
      // Token früh erneuern: Ist die Anmeldung abgelaufen und kein Key da, gleich klar melden.
      try {
        await connect!.validToken();
      } on Object {
        if (!_client.hasKey) rethrow;
      }
    } else {
      // Schlägt schon der Token-Tausch fehl, ist der Key das Problem – dann nicht jeden Endpunkt einzeln melden.
      await _client.validToken();
    }

    final today = CalendarDay.fromDate(at);
    final range = SyncPlan.range(latestStored: await _metrics.latestDay(), today: today);
    final report = SyncReport(range);

    final requests = <(GarminEndpoint, DayMap Function(JsonValue))>[
      for (final chunk in range.chunks(180)) ...[
        (GarminEndpoint.dailySummaries(chunk), GarminMetricsParser.dailySummaries),
        (GarminEndpoint.hrvSummaries(chunk), GarminMetricsParser.hrv),
      ],
      for (final chunk in range.chunks(28)) ...[
        (GarminEndpoint.sleepSummaries(chunk), GarminMetricsParser.sleep),
        (GarminEndpoint.bodyBattery(chunk), GarminMetricsParser.bodyBattery),
      ],
      // Einzeltage für heute: Zusammenfassungen hängen teils hinterher.
      (GarminEndpoint.hrv(today), GarminMetricsParser.hrv),
      (GarminEndpoint.dailySleep(today), GarminMetricsParser.sleep),
      (GarminEndpoint.spo2(today.adding(-1)), GarminMetricsParser.spo2),
      (GarminEndpoint.spo2(today), GarminMetricsParser.spo2),
      (GarminEndpoint.fitnessAge(today), (json) => GarminMetricsParser.fitnessAge(json, today)),
    ];

    final maps = <DayMap>[];
    for (final (endpoint, parse) in requests) {
      if (await _fetch(endpoint, report) case final json?) maps.add(parse(json));
    }
    if (connect?.isLoggedIn ?? false) maps.addAll(await _connectExtras(today, report));
    // Nichts kam an (z. B. offline): Das ist kein erfolgreicher Abruf, sonst wartet die App zu Unrecht bis zum nächsten.
    if (maps.isEmpty && report.errors.isNotEmpty) {
      throw const GarminAPIError.network('Garmin ist gerade nicht erreichbar. Die App versucht es später erneut.');
    }
    final merged = {
      for (final MapEntry(:key, :value) in GarminMetricsParser.merge(maps).entries)
        if (range.start <= key && key <= range.end) key: value,
    };
    report.daysUpdated = await _store(merged, at);
    report.activitiesUpdated = await _syncActivities(range.start, report: report);
    if (_settings.string(activityBackfillKey) == null) {
      // Einmalig 13 Wochen Aktivitäten für die Wochenbalken und die HFmax nachladen.
      final errorsBefore = report.errors.length;
      report.activitiesUpdated += await _syncActivities(
        today.adding(-SyncPlan.activityHistoryDays),
        ignoreKnown: true,
        report: report,
      );
      if (report.errors.length == errorsBefore) await _settings.setString(activityBackfillKey, today.iso);
    }
    await _refreshProfileIfNeeded(today, report);
    _fileFetches = 0;
    report.activitiesAnalyzed = await _analyzeActivities(today, report);
    report.activitiesDetailed = await _detailActivities(today, report);

    await _settings.setDate(lastSyncKey, at);
    report
      ..sources = {for (final MapEntry(:key, :value) in _client.sources.entries) key.label: value}
      ..connectProblem = _client.lastConnectError
      ..finishedAt = at;
    return report;
  }

  // Schritte

  static String _message(Object error) => switch (error) {
    GarminAPIError(:final message) || GarminConnectError(:final message) => message,
    _ => '$error',
  };

  Future<JsonValue?> _fetch(GarminEndpoint endpoint, SyncReport report) async {
    try {
      final data = await _client.data(endpoint);
      await _raw.store(endpoint.request.path, data);
      return decodeGarminJson(data);
    } on Object catch (error) {
      report.errors.add('${endpoint.request.path}: ${_message(error)}');
      return null;
    }
  }

  Future<int> _store(DayMap metrics, DateTime at) async {
    final sources = this.sources;
    if (sources != null) {
      await sources.ingestDays(metrics, from: DataProvider.garmin, now: at);
      return metrics.length;
    }
    for (final value in metrics.values) {
      await _metrics.merge(value, at: at);
    }
    return metrics.length;
  }

  Future<int> _syncActivities(CalendarDay start, {bool ignoreKnown = false, required SyncReport report}) async {
    final knownIDs = (await _activities.all()).map((activity) => activity.id).toSet();
    const pageSize = GarminEndpoint.maxActivitiesPerPage;
    var updated = 0;
    var pages = 0;
    while (true) {
      final json = await _fetch(GarminEndpoint.activities(start: pages * pageSize, limit: pageSize), report);
      if (json == null) break;
      pages += 1;
      final page = GarminActivityParser.activities(json);
      // Herkunft festhalten; als ersetzt markierte (andere Quelle bevorzugt) nicht wieder anlegen.
      final allowed = await sources?.recordActivities(page, from: DataProvider.garmin, window: null, complete: false);
      final accepted = [
        for (final activity in page)
          if (((activity.day ?? start) >= start || !knownIDs.contains(activity.id)) &&
              (allowed?.contains(activity.id) ?? true))
            activity,
      ];
      // Wie `record.update(activity)`: vorhandene Datensätze werden ersetzt.
      await _activities.upsertAll(accepted);
      updated += accepted.length;
      final more = SyncPlan.shouldLoadNextPage(
        page: page,
        pageSize: pageSize,
        knownIDs: ignoreKnown ? const {} : knownIDs,
        rangeStart: start,
        pagesLoaded: pages,
      );
      if (!more) break;
    }
    return updated;
  }

  /// Werte, die nur das Garmin-Konto liefert, plus Tageswerte und Schlaf in der Connect-Form.
  Future<List<DayMap>> _connectExtras(CalendarDay today, SyncReport report) async {
    final maps = <DayMap>[];
    for (final day in [today.adding(-1), today]) {
      if (await _fetchConnect(ConnectEndpoint.trainingReadiness(day), report) case final json?) {
        maps.add(GarminConnectMetrics.trainingReadiness(json, day));
      }
    }
    if (await _fetchConnect(ConnectEndpoint.trainingStatus(today), report) case final json?) {
      maps.add(GarminConnectMetrics.trainingStatus(json, today));
    }
    if (await _fetchConnect(ConnectEndpoint.enduranceScore(today), report) case final json?) {
      maps.add(GarminConnectMetrics.enduranceScore(json, today));
    }
    if (_client.connect?.displayName case final name?) {
      for (final day in [today.adding(-1), today]) {
        if (await _fetchConnect(ConnectEndpoint.userSummary(displayName: name, day: day), report) case final json?) {
          maps.add(GarminMetricsParser.dailySummaries(json));
        }
        if (await _fetchConnect(ConnectEndpoint.dailySleepData(displayName: name, day: day), report) case final json?) {
          maps.add(GarminMetricsParser.sleep(json));
        }
      }
      if (await _fetchConnect(ConnectEndpoint.racePredictions(displayName: name), report) case final json?) {
        if (RacePredictions.fromGarmin(json) case final predictions?) {
          await _settings.setJson(racePredictionsKey, predictions.toJson());
        }
      }
    }
    if (await _fetchConnect(ConnectEndpoint.weightRange(start: today.adding(-27), end: today), report)
        case final json?) {
      final start = today.adding(-119);
      final fresh = WeightTrend.garminEntries(json);
      final freshDays = {for (final entry in fresh) entry.day};
      final kept = weights.where((entry) => entry.day >= start && !freshDays.contains(entry.day));
      final all = [...kept, ...fresh]..sort((a, b) => a.day.compareTo(b.day));
      await _settings.setJson(weightsKey, [for (final entry in all) entry.toJson()]);
    }
    return maps;
  }

  Future<JsonValue?> _fetchConnect(ConnectEndpoint endpoint, SyncReport report) async {
    try {
      return await _client.connectJson(endpoint);
    } on Object catch (error) {
      report.errors.add('Konto ${endpoint.path}: ${_message(error)}');
      return null;
    }
  }

  /// FIT-Dateien neuer Läufe und Fahrten auswerten (höchstens sechs je Abruf, der Rest folgt beim nächsten).
  Future<int> _analyzeActivities(CalendarDay today, SyncReport report) async {
    // Nur Garmin-Aktivitäten (positive IDs) haben eine FIT-Datei; Workouts aus Apple Health nicht.
    final activities = [
      for (final activity in await _activities.all())
        if (activity.id >= 0) activity,
    ];
    final analyzed = analysisStore.load();
    var fetches = 0;
    var count = 0;
    for (final activity in ActivityAnalysisPlanner.pending(activities, analyzed: analyzed, today: today)) {
      FitActivity? fit;
      double? rpe;
      if (ActivityAnalysisPlanner.needsFile(activity)) {
        if (fetches >= ActivityAnalysisPlanner.maxFetchesPerSync) continue;
        fetches += 1;
        try {
          final data = await _fileData(activity.id);
          if (data == null) continue;
          try {
            fit = await decodeFit(data);
          } on Object {
            fit = null;
          }
        } on Object catch (error) {
          report.errors.add('FIT ${activity.id}: ${_message(error)}');
          continue;
        }
        if (ActivityAnalysisPlanner.paceKind(activity) != null) rpe = await _rpe(activity.id);
      }
      analyzed[activity.id] = ActivityAnalysisPlanner.analyze(activity, fit: fit, rpe: rpe);
      count += 1;
    }
    for (final id in ActivityAnalysisPlanner.needsRPE(analyzed.values.toList(), today: today)) {
      if (await _rpe(id) case final value?) analyzed[id]?.rpe = value;
    }
    analysisStore.save(analyzed, today: today);
    return count;
  }

  /// Datei der Uhr: aus dem Zwischenspeicher, sonst von Garmin (begrenzt je Abruf). `null` = Budget aufgebraucht.
  Future<Uint8List?> _fileData(int id) async {
    if (reportStore.cachedFile(id) case final cached?) return cached;
    if (_fileFetches >= maxFileFetchesPerSync) return null;
    _fileFetches += 1;
    final data = await _client.data(GarminEndpoint.activityFile(id));
    reportStore.cacheFile(data, id: id);
    return data;
  }

  List<int> get _failedReports =>
      _settings.read(failedReportsKey, (json) => json is List ? json.whereType<int>().toList() : null, const <int>[]);

  /// Jede Aktivität der letzten Wochen vollständig übertragen: alle Kennzahlen (Aktivitätsdetails) und aus der Datei der
  /// Uhr Runden, Splits und Verlauf. Jüngste zuerst; was nicht mehr ins Budget passt, folgt beim nächsten Abruf.
  Future<int> _detailActivities(CalendarDay today, SyncReport report) async {
    final activities = await _activities.all();
    final reports = reportStore.load();
    // Aktivitäten ohne lesbare Datei (z. B. manuell eingetragen) nicht bei jedem Abruf erneut versuchen.
    final failed = <int>{..._failedReports};
    var count = 0;
    final pending = ActivityReportPlanner.pending(activities, known: reports, failed: failed, today: today);
    for (final activity in pending) {
      final Uint8List? data;
      try {
        data = await _fileData(activity.id);
      } on GarminRejectedRequest {
        // Keine Datei vorhanden (z. B. manuell eingetragen): nicht erneut versuchen.
        failed.add(activity.id);
        continue;
      } on Object {
        // Netz, Anmeldung oder Rate-Limit: beim nächsten Abruf weiter.
        break;
      }
      if (data == null) break;
      var detailed = activity;
      try {
        final json = await _client.json(GarminEndpoint.activity(activity.id));
        detailed = GarminActivityParser.detail(json, activity);
        if (detailed != activity) await _activities.upsert(detailed);
      } on Object {
        // Ohne Details bleibt die Aktivität wie geliefert.
      }
      final FitActivity fit;
      try {
        fit = await decodeFit(data);
      } on Object {
        failed.add(activity.id);
        continue;
      }
      reports[activity.id] = ActivityReportBuilder.build(detailed, fit);
      count += 1;
    }
    reportStore.save(reports, today: today);
    final list = failed.toList();
    await _settings.setJson(failedReportsKey, list.length > 200 ? list.sublist(list.length - 200) : list);
    return count;
  }

  /// Selbsteinschätzung (RPE) von der Uhr; fehlt sie, bleibt es still.
  Future<double?> _rpe(int id) async {
    try {
      return ActivityAnalysisPlanner.rpeFromActivityDetail(await _client.json(GarminEndpoint.activity(id)));
    } on Object {
      return null;
    }
  }

  /// Entpacken und Lesen im Hintergrund, damit die Oberfläche flüssig bleibt.
  static Future<FitActivity> decodeFit(Uint8List data) =>
      Isolate.run(() => FitDecoder.decode(ZipArchive.fitData(data)));

  Future<void> _refreshProfileIfNeeded(CalendarDay today, SyncReport report) async {
    if (_settings.string(profileDateKey) == today.iso) return;
    // Uhr-Zonen: Die Rohantwort genügt, die App liest sie aus den Rohantworten.
    await _fetch(GarminEndpoint.heartRateZones, report);
    final json = await _fetch(GarminEndpoint.profileSettings, report);
    if (json == null) return;
    await _settings.setJson(profileKey, GarminProfile.fromSettings(json).toJson());
    await _settings.setString(profileDateKey, today.iso);
  }

  /// Letzte gespeicherte Rohantwort eines Endpunkts.
  Future<JsonValue?> raw(GarminEndpoint endpoint) async {
    final body = await _raw.body(endpoint.request.path);
    if (body == null) return null;
    try {
      return decodeGarminJson(body);
    } on Object {
      return null;
    }
  }
}
