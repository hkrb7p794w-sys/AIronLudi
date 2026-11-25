import 'dart:async';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/user_providers.dart';
import '../../data/storage.dart';
import '../../services/endurance/endurance_plan_store.dart';
import '../../services/endurance/workout_exporter_service.dart';
import '../../services/providers.dart';

/// Ausdauerplan des aktiven Benutzers: erstellen, täglich anpassen (`TrainingPlanEngine.adapt` mit Aktivitäten und
/// Tageswerten aus allen Quellen), speichern und auf Wunsch automatisch mit dem Garmin-Kalender abgleichen.
final class EnduranceController extends ChangeNotifier {
  EnduranceController({
    required this.store,
    required this.exporter,
    required this._activities,
    required this._metrics,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    plan = store.load();
  }

  final EndurancePlanStore store;
  final WorkoutExporterService exporter;
  final Future<List<GarminActivity>> Function(CalendarDay from, CalendarDay to) _activities;
  final Future<List<DailyMetrics>> Function(CalendarDay from, CalendarDay to) _metrics;
  final DateTime Function() _clock;

  EndurancePlan? plan;
  bool isBusy = false;

  /// Letzte Meldung (Abgleich, Senden, Fehler).
  String? message;

  /// Heutige Erholungsampel, wie sie in die Anpassung eingeflossen ist (`null` ohne Werte).
  Recommendation? recovery;
  LoadState? load;

  CalendarDay get today => CalendarDay.fromDate(_clock());

  String get username => store.username;

  /// Ein Plan aus dem Speicher gehört einem anderen Benutzer (wird nicht angezeigt).
  bool get hasForeignPlan => store.hasForeignPlan;

  Future<void> _save() async {
    if (plan case final plan?) await store.save(plan);
  }

  /// Neuer Plan; ersetzt einen vorhandenen (dessen kommende Garmin-Workouts werden entfernt).
  Future<void> create(TrainingPlanRequest request) async {
    if (request.username != username) throw StateError('Falscher Benutzer.');
    final previous = plan;
    if (previous != null) await exporter.removeUpcoming(previous, today: today);
    plan = TrainingPlanEngine.generate(request, now: _clock())..autoSyncGarmin = previous?.autoSyncGarmin ?? false;
    await _save();
    notifyListeners();
    await refresh();
  }

  Future<void> delete() async {
    final current = plan;
    if (current == null) return;
    await exporter.removeUpcoming(current, today: today);
    plan = null;
    await store.delete();
    notifyListeners();
  }

  /// Anpassen an Aktivitäten und Erholung, dann (falls eingeschaltet) Garmin-Kalender abgleichen.
  Future<void> refresh() async {
    final current = plan;
    if (current == null || isBusy) return;
    isBusy = true;
    notifyListeners();
    try {
      final day = today;
      final from = current.firstDay.adding(-90);
      final (activities, days) = await (_activities(from, day), _metrics(day.adding(-8), day)).wait;
      final result = TrainingPlanEngine.adapt(
        current,
        activities: activities,
        metrics: days,
        today: day,
        now: _clock(),
      );
      plan = result.plan;
      recovery = TrainingPlanEngine.recoveryToday(days, today: day);
      load = TrainingLoad.state(TrainingLoad.daily(activities, current.request.thresholds), day: day);
      if (result.changed) {
        message = result.changes.length == 1
            ? 'Plan angepasst: ${result.changes.single.reason}'
            : '${result.changes.length} Einheiten angepasst.';
      }
      if (result.plan.autoSyncGarmin && exporter.canSend) {
        final sync = await exporter.syncCalendar(result.plan, today: day);
        if (sync.changed || sync.message != null || sync.failed > 0) message = sync.summary;
      }
      await _save();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> setAutoSync(bool on) async {
    final current = plan;
    if (current == null) return;
    current.autoSyncGarmin = on;
    if (on) {
      final result = await exporter.syncCalendar(current, today: today);
      message = result.summary;
    } else {
      final removed = await exporter.removeUpcoming(current, today: today);
      message = removed == 0 ? null : '$removed Einheiten aus dem Garmin-Kalender entfernt.';
    }
    await _save();
    notifyListeners();
  }

  /// „An Uhr senden“ für eine Einheit des Plans (ersetzt ein schon gesendetes Workout derselben Einheit).
  Future<String> send(PlanSlot slot) async {
    final current = plan;
    if (current == null) return 'Kein Plan.';
    final (text, synced) = await exporter.sendToWatch(slot.current, day: slot.day, previous: current.synced[slot.id]);
    if (synced != null) {
      current.synced[slot.id] = synced;
      await _save();
    }
    message = text;
    notifyListeners();
    return text;
  }

  /// Freie Einheit (nicht im Plan) an die Uhr senden.
  Future<String> sendAdHoc(EnduranceWorkout workout, CalendarDay day) async {
    final (text, _) = await exporter.sendToWatch(workout, day: day);
    return text;
  }

  Future<File> fitFile(EnduranceWorkout workout, CalendarDay day) => exporter.fitFile(workout, day);

  Future<File> zwoFile(EnduranceWorkout workout, CalendarDay day) => exporter.zwoFile(workout, day);

  /// Schwellen nach einem neuen Test übernehmen: kommende Einheiten werden mit den neuen Zielen neu gebaut.
  Future<void> updateThresholds(AthleteThresholds thresholds) async {
    final current = plan;
    if (current == null) return;
    final request = current.request.copyWith(thresholds: thresholds);
    final rebuilt = TrainingPlanEngine.generate(request, now: current.createdAt, id: current.id);
    final day = today;
    final slots = [
      for (final slot in current.slots)
        if (slot.day < day || slot.status != SlotStatus.planned) slot,
      for (final slot in rebuilt.slots)
        if (slot.day >= day && current.slot(slot.id)?.status != SlotStatus.completed) slot,
    ]..sort((a, b) => a.day.compareTo(b.day));
    plan = EndurancePlan(
      id: current.id,
      username: current.username,
      request: request,
      createdAt: current.createdAt,
      weeks: rebuilt.weeks,
      slots: slots,
      adjustments: current.adjustments,
      revision: current.revision + 1,
      autoSyncGarmin: current.autoSyncGarmin,
      synced: current.synced,
    );
    await _save();
    notifyListeners();
    await refresh();
  }

  /// Schwellen als Vorschlag: im Saisonplan die eigenen Testwerte, sonst nichts (keine Saisonwerte für andere).
  static AthleteThresholds suggestedThresholds(UserProfile profile, SeasonConfig season, {int? lactateThreshold}) {
    if (profile.mode != ProfileMode.season) return AthleteThresholds(runThresholdHeartRate: lactateThreshold);
    return AthleteThresholds(
      runThresholdPace: season.thresholdPaceSecondsPerKm,
      ftpWatts: season.ftpWatts,
      swimCss: season.cssSecondsPer100m,
      runThresholdHeartRate: lactateThreshold,
    );
  }
}

final enduranceControllerProvider = ChangeNotifierProvider<EnduranceController>((ref) {
  final user = ref.watch(currentUserProvider);
  final activities = ref.watch(activityRepositoryProvider);
  final metrics = ref.watch(metricsRepositoryProvider);
  return EnduranceController(
    store: EndurancePlanStore(ref.watch(settingsStoreProvider), username: user.username),
    exporter: WorkoutExporterService.garmin(
      ref.watch(garminConnectProvider),
      username: user.username,
      folder: ref.watch(userDirectoryProvider),
    ),
    activities: (from, to) => activities.range(from: from, to: to),
    metrics: (from, to) => metrics.range(from: from, to: to),
  );
});
