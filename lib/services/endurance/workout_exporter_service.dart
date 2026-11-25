import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:path/path.dart' as p;

import '../garmin/garmin_connect_session.dart';

/// Sendet eine JSON-Anfrage an Garmin Connect (Methode, Pfad, Körper) und liefert die Antwort.
typedef GarminJsonSender = Future<List<int>> Function({
  required String method,
  required String path,
  required List<int> json,
});

/// Ergebnis des Kalender-Abgleichs.
final class CalendarSyncResult {
  const CalendarSyncResult({this.created = 0, this.replaced = 0, this.removed = 0, this.failed = 0, this.message});

  final int created;
  final int replaced;
  final int removed;
  final int failed;

  /// Fehlermeldung, wenn der Abgleich gar nicht laufen konnte.
  final String? message;

  bool get changed => created + replaced + removed > 0;

  String get summary {
    if (message case final message?) return message;
    if (!changed && failed == 0) return 'Garmin-Kalender ist aktuell.';
    final parts = [
      if (created > 0) '$created neu',
      if (replaced > 0) '$replaced aktualisiert',
      if (removed > 0) '$removed entfernt',
      if (failed > 0) '$failed fehlgeschlagen',
    ];
    return 'Garmin-Kalender: ${parts.join(', ')}.';
  }
}

/// Export und Übertragung strukturierter Ausdauer-Einheiten: FIT-Workout-Datei, Zwift-Workout (`.zwo`), „An Uhr
/// senden“ über den Garmin-Connect-Kalender und automatischer Abgleich kommender Einheiten bei Planänderungen.
///
/// Gehört genau einem Benutzer: Dateien liegen in seinem Ordner, die Garmin-Anmeldung stammt aus seinem sicheren
/// Speicher, und Pläne anderer Benutzer werden abgewiesen.
final class WorkoutExporterService {
  WorkoutExporterService({
    required this.username,
    required this._isLoggedIn,
    required this._send,
    required this._folder,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  factory WorkoutExporterService.garmin(
    GarminConnectSession connect, {
    required String username,
    required Future<Directory> Function() folder,
  }) => WorkoutExporterService(
    username: username,
    isLoggedIn: () => connect.isLoggedIn,
    send: connect.sendJson,
    folder: folder,
  );

  final String username;
  final bool Function() _isLoggedIn;
  final GarminJsonSender _send;
  final Future<Directory> Function() _folder;
  final DateTime Function() _clock;

  /// So viele Tage im Voraus hält der automatische Abgleich den Garmin-Kalender aktuell.
  static const syncDays = 14;

  static const loginHint = 'Dafür ist die Anmeldung mit dem Garmin-Konto nötig (Einstellungen › Garmin).';

  bool get canSend => _isLoggedIn();

  // Dateien

  Future<File> _write(String name, List<int> bytes) async {
    final folder = Directory(p.join((await _folder()).path, 'workouts'));
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final file = File(p.join(folder.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// FIT-Workout-Datei (für Uhren und Apps, die FIT-Workouts importieren).
  Future<File> fitFile(EnduranceWorkout workout, CalendarDay day) =>
      _write('${WorkoutExport.fileName(workout, day)}.fit', FitWorkoutFile.bytes(workout, created: _clock()));

  /// Zwift-Workout (`.zwo`), nur für Rad-Einheiten.
  Future<File> zwoFile(EnduranceWorkout workout, CalendarDay day) =>
      _write('${WorkoutExport.fileName(workout, day)}.zwo', utf8.encode(ZwiftWorkoutFile.xml(workout)));

  // Garmin

  Future<int?> _create(EnduranceWorkout workout, CalendarDay day) async {
    final body = utf8.encode(jsonEncode(GarminEnduranceWorkout.payload(workout)));
    final response = decodeGarminJson(await _send(method: 'POST', path: GarminWorkout.createPath, json: body));
    final id = GarminWorkout.workoutID(response);
    if (id == null) return null;
    await _send(
      method: 'POST',
      path: GarminWorkout.schedulePath(id),
      json: utf8.encode(jsonEncode(GarminWorkout.scheduleBody(day))),
    );
    return id;
  }

  Future<void> _delete(int id) async {
    try {
      await _send(method: 'DELETE', path: GarminWorkout.workoutPath(id), json: const []);
    } on Object {
      // Schon gelöscht oder nicht erreichbar: bleibt eben stehen.
    }
  }

  static String _detail(Object error) => switch (error) {
    GarminAPIError(:final message) || GarminConnectError(:final message) => message,
    _ => '$error',
  };

  /// „Einheit an Uhr senden“: legt das Workout im Garmin-Connect-Kalender an (beim nächsten Synchronisieren auf der
  /// Uhr). Ein bereits gesendetes Workout derselben Einheit wird ersetzt. Liefert Meldung und neuen Stand.
  Future<(String, SyncedWorkout?)> sendToWatch(
    EnduranceWorkout workout, {
    required CalendarDay day,
    SyncedWorkout? previous,
  }) async {
    if (!canSend) return (loginHint, null);
    if (workout.isRest) return ('Ein Ruhetag wird nicht gesendet.', null);
    try {
      if (previous != null) await _delete(previous.workoutID);
      final id = await _create(workout, day);
      if (id == null) return ('Garmin hat die Einheit nicht angenommen.', null);
      return (
        'Im Garmin-Kalender am ${GermanFormat.date(day)}. Auf die Uhr kommt es beim nächsten Synchronisieren.',
        SyncedWorkout(workoutID: id, fingerprint: WorkoutExport.fingerprint(workout, day), day: day),
      );
    } on Object catch (error) {
      return ('Senden hat nicht geklappt: ${_detail(error)}', null);
    }
  }

  /// Hält die kommenden [syncDays] Tage im Garmin-Kalender aktuell: neue Einheiten anlegen, geänderte (anderer
  /// Fingerabdruck) ersetzen, zu Ruhetagen gewordene oder entfernte löschen. Ändert `plan.synced`.
  Future<CalendarSyncResult> syncCalendar(EndurancePlan plan, {required CalendarDay today}) async {
    if (plan.username != username) {
      return const CalendarSyncResult(message: 'Der Plan gehört einem anderen Benutzer.');
    }
    if (!canSend) return const CalendarSyncResult(message: loginHint);
    final end = today.adding(syncDays - 1);
    final wanted = <String, PlanSlot>{
      for (final slot in plan.slots)
        if (slot.day >= today && slot.day <= end && slot.status == SlotStatus.planned && !slot.current.isRest)
          slot.id: slot,
    };
    var created = 0;
    var replaced = 0;
    var removed = 0;
    var failed = 0;
    // Nicht mehr gewollte, aber noch kommende Workouts löschen (vergangene bleiben als Verlauf bei Garmin).
    for (final entry in [...plan.synced.entries]) {
      if (wanted.containsKey(entry.key)) continue;
      if (entry.value.day < today) {
        if (entry.value.day < today.adding(-60)) plan.synced.remove(entry.key);
        continue;
      }
      await _delete(entry.value.workoutID);
      plan.synced.remove(entry.key);
      removed += 1;
    }
    for (final slot in wanted.values) {
      final fingerprint = WorkoutExport.fingerprint(slot.current, slot.day);
      final previous = plan.synced[slot.id];
      if (previous?.fingerprint == fingerprint) continue;
      try {
        if (previous != null) await _delete(previous.workoutID);
        final id = await _create(slot.current, slot.day);
        if (id == null) {
          failed += 1;
          plan.synced.remove(slot.id);
          continue;
        }
        plan.synced[slot.id] = SyncedWorkout(workoutID: id, fingerprint: fingerprint, day: slot.day);
        if (previous == null) {
          created += 1;
        } else {
          replaced += 1;
        }
      } on Object catch (error) {
        failed += 1;
        if (failed == 1 && created + replaced == 0) {
          // Erster Versuch scheitert: vermutlich grundsätzlich (Anmeldung, Netz) – nicht weiter versuchen.
          return CalendarSyncResult(
            removed: removed,
            failed: failed,
            message: 'Abgleich hat nicht geklappt: ${_detail(error)}',
          );
        }
      }
    }
    return CalendarSyncResult(created: created, replaced: replaced, removed: removed, failed: failed);
  }

  /// Alle kommenden übertragenen Workouts entfernen (beim Löschen des Plans oder Ausschalten des Abgleichs).
  Future<int> removeUpcoming(EndurancePlan plan, {required CalendarDay today}) async {
    if (plan.username != username || !canSend) return 0;
    var removed = 0;
    for (final entry in [...plan.synced.entries]) {
      if (entry.value.day < today) continue;
      await _delete(entry.value.workoutID);
      plan.synced.remove(entry.key);
      removed += 1;
    }
    return removed;
  }
}
