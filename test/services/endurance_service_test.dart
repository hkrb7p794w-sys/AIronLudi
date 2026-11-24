// Ausdauerplan: Speicher je Benutzer, Export-Dateien und Abgleich mit dem Garmin-Kalender.
import 'dart:convert';
import 'dart:io';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/endurance/endurance_controller.dart';
import 'package:aironludi/services/endurance/endurance_plan_store.dart';
import 'package:aironludi/services/endurance/workout_exporter_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final monday = CalendarDay(2026, 11, 16);

TrainingPlanRequest request(String username) => TrainingPlanRequest(
  username: username,
  mode: PlanningMode.period,
  sports: const [EnduranceSport.run, EnduranceSport.bike],
  start: monday,
  weeklyMinutes: 300,
  days: const [Weekday.tuesday, Weekday.thursday, Weekday.saturday, Weekday.sunday],
  longDay: Weekday.sunday,
  weeks: 4,
  thresholds: const AthleteThresholds(runThresholdPace: 280, ftpWatts: 220),
);

/// Garmin-Connect-Attrappe: merkt sich Anfragen, vergibt fortlaufende Workout-Kennungen.
final class FakeGarmin {
  final calls = <(String, String)>[];
  final bodies = <Map<String, Object?>>[];
  var next = 100;
  var loggedIn = true;
  var fail = false;

  Future<List<int>> send({required String method, required String path, required List<int> json}) async {
    calls.add((method, path));
    if (fail) throw const SocketException('offline');
    if (method == 'POST' && path == GarminWorkout.createPath) {
      bodies.add(jsonDecode(utf8.decode(json)) as Map<String, Object?>);
      next += 1;
      return utf8.encode(jsonEncode({'workoutId': next}));
    }
    return utf8.encode('{}');
  }

  int count(String method, {String? prefix}) =>
      calls.where((call) => call.$1 == method && (prefix == null || call.$2.startsWith(prefix))).length;
}

void main() {
  late CoachDatabase db;
  late SettingsStore settings;
  late Directory folder;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    settings = await SettingsStore.open(db);
    folder = Directory.systemTemp.createTempSync('endurance');
  });

  tearDown(() async {
    await db.close();
    folder.deleteSync(recursive: true);
  });

  WorkoutExporterService exporter(FakeGarmin garmin, {String username = 'anna'}) => WorkoutExporterService(
    username: username,
    isLoggedIn: () => garmin.loggedIn,
    send: garmin.send,
    folder: () async => folder,
    clock: () => DateTime.utc(2026, 11, 16, 7),
  );

  group('Speicher je Benutzer', () {
    test('Plan wird nur für seinen Benutzer geladen und gespeichert', () async {
      final plan = TrainingPlanEngine.generate(request('anna'), now: DateTime.utc(2026, 11, 16), id: 'A');
      final anna = EndurancePlanStore(settings, username: 'anna');
      await anna.save(plan);
      expect(anna.load()?.id, 'A');
      expect(anna.hasForeignPlan, isFalse);
      expect(AppBackup.isBackedUp(EndurancePlanStore.key), isTrue);

      final ben = EndurancePlanStore(settings, username: 'ben');
      expect(ben.load(), isNull);
      expect(ben.hasForeignPlan, isTrue);
      expect(() => ben.save(plan), throwsStateError);

      await anna.delete();
      expect(anna.load(), isNull);
    });
  });

  group('Export', () {
    final workout = EnduranceWorkouts.build(
      sport: EnduranceSport.bike,
      type: EnduranceWorkoutType.threshold,
      minutes: 60,
      thresholds: const AthleteThresholds(ftpWatts: 220),
    );

    test('FIT- und Zwift-Datei im Ordner des Benutzers', () async {
      final service = exporter(FakeGarmin());
      final fit = await service.fitFile(workout, monday);
      expect(fit.path, endsWith(p.join('workouts', '2026-11-16-rad-schwelle-2x10-min.fit')));
      expect(fit.path, startsWith(folder.path));
      final bytes = fit.readAsBytesSync();
      expect(ascii.decode(bytes.sublist(8, 12)), '.FIT');
      final zwo = await service.zwoFile(workout, monday);
      expect(zwo.readAsStringSync(), contains('<IntervalsT Repeat="2"'));
    });

    test('An Uhr senden ersetzt ein schon gesendetes Workout', () async {
      final garmin = FakeGarmin();
      final service = exporter(garmin);
      final (first, synced) = await service.sendToWatch(workout, day: monday);
      expect(first, startsWith('Im Garmin-Kalender am 16.11.2026'));
      expect(synced?.workoutID, 101);
      expect(garmin.calls, [('POST', '/workout-service/workout'), ('POST', '/workout-service/schedule/101')]);
      final (_, again) = await service.sendToWatch(workout, day: monday, previous: synced);
      expect(again?.workoutID, 102);
      expect(garmin.calls[2], ('DELETE', '/workout-service/workout/101'));
      garmin.loggedIn = false;
      final (hint, none) = await service.sendToWatch(workout, day: monday);
      expect(hint, WorkoutExporterService.loginHint);
      expect(none, isNull);
    });
  });

  group('Kalender-Abgleich', () {
    test('anlegen, nichts doppelt, bei Änderung ersetzen, Ruhetag entfernen', () async {
      final garmin = FakeGarmin();
      final service = exporter(garmin);
      final plan = TrainingPlanEngine.generate(request('anna'), now: DateTime.utc(2026, 11, 16), id: 'A');
      final upcoming = plan.slots.where((slot) => slot.day <= monday.adding(13)).toList();

      final first = await service.syncCalendar(plan, today: monday);
      expect(first.created, upcoming.length);
      expect(plan.synced.keys.toSet(), upcoming.map((slot) => slot.id).toSet());
      expect(garmin.count('POST', prefix: '/workout-service/schedule/'), upcoming.length);
      // Ziele kommen mit: Rad mit Watt.
      final bike = garmin.bodies.firstWhere((body) => (body['sportType']! as Map)['sportTypeKey'] == 'cycling');
      expect(jsonEncode(bike), contains('power.zone'));

      final second = await service.syncCalendar(plan, today: monday);
      expect(second.changed, isFalse);
      expect(second.summary, 'Garmin-Kalender ist aktuell.');

      // Schlechte Erholung am Dienstag: die Einheit wird zum Ruhetag und verschwindet aus dem Kalender.
      final tuesday = monday.adding(1);
      final adapted = TrainingPlanEngine.adapt(
        plan,
        activities: const [],
        metrics: [DailyMetrics(tuesday)..hrvStatus = 'POOR'],
        today: tuesday,
        now: DateTime.utc(2026, 11, 17),
      ).plan;
      final third = await service.syncCalendar(adapted, today: tuesday);
      expect(third.removed, 1);
      expect(adapted.synced.containsKey(adapted.slotsOn(tuesday).single.id), isFalse);

      // Andere Schwellen: alle kommenden Einheiten ändern sich und werden ersetzt.
      for (final slot in adapted.slots) {
        if (slot.day > tuesday) {
          slot.current = EnduranceWorkouts.build(
            sport: slot.current.sport,
            type: slot.current.type,
            minutes: slot.current.minutes,
            thresholds: const AthleteThresholds(runThresholdPace: 260, ftpWatts: 240),
          );
        }
      }
      final fourth = await service.syncCalendar(adapted, today: tuesday);
      expect(fourth.replaced, greaterThan(0));
      expect(fourth.created, 0); // Montag rückt ins Fenster, ist aber kein Trainingstag
      expect(fourth.summary, startsWith('Garmin-Kalender:'));
    });

    test('ohne Anmeldung, fremder Plan, Netzfehler', () async {
      final garmin = FakeGarmin();
      final plan = TrainingPlanEngine.generate(request('anna'), now: DateTime.utc(2026, 11, 16), id: 'A');
      final foreign = await exporter(garmin, username: 'ben').syncCalendar(plan, today: monday);
      expect(foreign.message, 'Der Plan gehört einem anderen Benutzer.');
      expect(garmin.calls, isEmpty);
      garmin.fail = true;
      final offline = await exporter(garmin).syncCalendar(plan, today: monday);
      expect(offline.message, startsWith('Abgleich hat nicht geklappt'));
      expect(plan.synced, isEmpty);
      garmin
        ..fail = false
        ..loggedIn = false;
      final hint = await exporter(garmin).syncCalendar(plan, today: monday);
      expect(hint.message, WorkoutExporterService.loginHint);
    });
  });

  group('Controller', () {
    test('Erstellen, Anpassen an Erholung, automatischer Abgleich, Löschen', () async {
      final garmin = FakeGarmin();
      var metrics = <DailyMetrics>[];
      final controller = EnduranceController(
        store: EndurancePlanStore(settings, username: 'anna'),
        exporter: exporter(garmin),
        activities: (_, _) async => const [],
        metrics: (_, _) async => metrics,
        clock: () => DateTime(2026, 11, 17, 7),
      );
      expect(controller.plan, isNull);
      await controller.create(request('anna'));
      expect(controller.plan?.username, 'anna');
      expect(EndurancePlanStore(settings, username: 'anna').load(), isNotNull);
      expect(() => controller.create(request('ben')), throwsStateError);

      await controller.setAutoSync(true);
      final created = garmin.count('POST', prefix: '/workout-service/schedule/');
      expect(created, greaterThan(0));

      metrics = [DailyMetrics(CalendarDay(2026, 11, 17))..sleepSeconds = 4 * 3600];
      await controller.refresh();
      final today = controller.plan!.slotsOn(CalendarDay(2026, 11, 17)).single;
      expect(today.current.isRest, isTrue);
      expect(controller.recovery?.level, RecoveryLevel.pause);
      expect(controller.message, contains('Garmin-Kalender'));
      expect(garmin.count('DELETE'), 1);

      await controller.delete();
      expect(controller.plan, isNull);
      expect(EndurancePlanStore(settings, username: 'anna').load(), isNull);
      expect(garmin.count('DELETE'), greaterThan(1));
    });

    test('Vorschlag der Schwellen nur im Saisonplan', () {
      final season = SeasonConfig.standard;
      final personal = EnduranceController.suggestedThresholds(UserProfile(mode: ProfileMode.personal), season);
      expect(personal.ftpWatts, isNull);
      final own = EnduranceController.suggestedThresholds(UserProfile(mode: ProfileMode.season), season);
      expect(own.ftpWatts, season.ftpWatts);
    });
  });
}
