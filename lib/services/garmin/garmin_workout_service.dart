import 'dart:convert';

import 'package:coach_core/coach_core.dart';

import '../../data/settings/coach_settings.dart';
import 'garmin_connect_session.dart';

/// Sendet eine Einheit als Workout in den Garmin-Connect-Kalender; von dort kommt sie beim nächsten Synchronisieren auf
/// die Uhr. Nur auf ausdrücklichen Wunsch je Einheit. Schickt man dieselbe Einheit für denselben Tag erneut, wird das
/// alte Workout gelöscht und ersetzt.
abstract final class GarminWorkoutService {
  static Future<String> send(
    WorkoutPlan plan, {
    required CalendarDay day,
    required GarminConnectSession? connect,
    required CoachSettings settings,
    DateTime? now,
  }) async {
    if (connect == null || !connect.isLoggedIn) {
      return 'Dafür ist die Anmeldung mit dem Garmin-Konto nötig (Einstellungen › Garmin).';
    }
    final key = SentWorkouts.key(name: plan.name, day: day);
    try {
      if (settings.sentWorkouts.ids[key] case final old?) {
        // Altes Workout entfernen (samt Kalendereintrag); scheitert das, bleibt es eben stehen.
        try {
          await connect.sendJson(method: 'DELETE', path: GarminWorkout.workoutPath(old), json: const []);
        } on Object {
          // Bleibt stehen.
        }
      }
      final body = utf8.encode(jsonEncode(GarminWorkout.payload(plan)));
      final response = decodeGarminJson(
        await connect.sendJson(method: 'POST', path: GarminWorkout.createPath, json: body),
      );
      final id = GarminWorkout.workoutID(response);
      if (id == null) return 'Garmin hat das Workout nicht angenommen.';
      final schedule = utf8.encode(jsonEncode(GarminWorkout.scheduleBody(day)));
      await connect.sendJson(method: 'POST', path: GarminWorkout.schedulePath(id), json: schedule);
      final sent = SentWorkouts(ids: {...settings.sentWorkouts.ids})
        ..prune(CalendarDay.fromDate(now ?? DateTime.now()));
      sent.ids[key] = id;
      settings.sentWorkouts = sent;
      return 'Im Garmin-Kalender am ${GermanFormat.date(day)}. Auf die Uhr kommt es beim nächsten Synchronisieren.';
    } on Object catch (error) {
      final detail = switch (error) {
        GarminAPIError(:final message) || GarminConnectError(:final message) => message,
        _ => '$error',
      };
      return 'Senden hat nicht geklappt: $detail';
    }
  }
}
