// Port von `GymViewModelTests`.
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/gym/gym_controller.dart';
import 'package:aironludi/services/gym/rest_alarm.dart';
import 'package:aironludi/services/health/health_writer.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final class StubWriter implements WorkoutSaving {
  bool available = true;
  final List<GymSession> saved = [];
  Object? error;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<void> save(GymSession session) async {
    if (error case final error?) throw error;
    saved.add(session);
  }
}

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  late GymRepository repository;
  late FakeRestAlarm alarm;

  /// Donnerstag, 22.10.2026: laut Plan flexible Beineinheit (Di/Do), wenn Dienstag nichts geloggt ist.
  final now = DateTime(2026, 10, 22, 12);

  setUpAll(() => initializeDateFormatting('de_DE'));

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    repository = GymRepository(db);
    alarm = FakeRestAlarm();
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  GymController controller() => GymController(store: store, alarm: alarm, sound: alarm, clock: () => now);

  test('Plan wählt Beine und befüllt aus der Progression', () {
    final gym = controller();
    const monday = CalendarDay(2026, 10, 19);
    final press = LoggedExercise(
      exerciseID: 'beinpresse',
      name: 'Beinpresse',
      group: MuscleGroup.legs,
      sets: [LoggedSet(reps: 12, weightKg: 149), LoggedSet(reps: 12, weightKg: 149)],
    );
    final old = GymSession(
      workoutKey: 'legs',
      title: 'Lower',
      start: monday.adding(-6).referenceDate,
      exercises: [press],
    );
    gym.update(sessions: [old], activities: const [], days: const [], now: now);

    expect(gym.todayWorkout?.key, 'legs');
    gym.startWorkout(gym.todayWorkout!, now: now);
    final active = gym.active!;
    final legPress = active.exercises.firstWhere((exercise) => exercise.exerciseID == 'beinpresse');
    expect(legPress.sets.length, 2);
    expect(legPress.sets.every((set) => set.weightKg == 154 && set.reps == 8 && !set.done), isTrue);
    final curl = active.exercises.firstWhere((exercise) => exercise.exerciseID == 'beinbeugen');
    expect(curl.sets.first.weightKg, 110);
    expect(curl.sets.first.reps, 12);
  });

  test('Beenden speichert erledigte Sätze und trägt in Health ein', () async {
    final gym = controller();
    gym.update(sessions: const [], activities: const [], days: const [], now: now);
    gym.startEmpty(now: now);
    gym.addExercise(ExerciseLibrary.byID['bankdruecken']!);
    final exercise = gym.active!.exercises.first;
    gym.setWeight(50, set: 0, of: exercise.id);
    // Nur dieser Satz (WorkoutEdits.setWeight); der Swift-Test erwartete noch das frühere Mitziehen, siehe decisions.md.
    expect([for (final set in gym.active!.exercises.first.sets) set.weightKg], [50, 0, 0]);
    gym.toggleDone(set: 0, of: exercise.id, now: now);
    expect(gym.restEndsAt, now.add(const Duration(seconds: 120)));
    expect(alarm.scheduled.last, now.add(const Duration(seconds: 120)));

    final writer = StubWriter();
    await gym.finish(repository: repository, writer: writer, now: now.add(const Duration(minutes: 30)));

    expect(gym.active, isNull);
    final records = await repository.all();
    expect(records.length, 1);
    expect(records.first.savedToHealth, isTrue);
    expect(records.first.session.exercises.first.sets.length, 1);
    expect(writer.saved.length, 1);
    expect(gym.message?.startsWith('Gespeichert und in Apple Health eingetragen.'), isTrue);
  });

  test('laufende Einheit übersteht den Neustart', () async {
    final first = controller()..startEmpty(now: now);
    await Future<void>.delayed(Duration.zero);
    expect(controller().active?.title, 'Krafttraining');
    first.cancelActive();
    await Future<void>.delayed(Duration.zero);
    expect(controller().active, isNull);
  });

  test('ohne erledigten Satz nichts zu speichern', () async {
    final gym = controller()..startEmpty(now: now);
    await gym.finish(repository: repository, writer: StubWriter(), now: now);
    expect(gym.message, contains('Noch kein Satz'));
    expect(gym.active, isNotNull);
  });

  test('Routine startet mit den letzten Werten und speichert RIR', () {
    final gym = controller();
    final last = GymSession(
      workoutKey: null,
      title: 'Ganzkörper A',
      start: now.subtract(const Duration(days: 3)),
      exercises: [
        LoggedExercise(
          exerciseID: 'goblet_squat',
          name: 'Goblet Squat',
          group: MuscleGroup.legs,
          sets: [LoggedSet(reps: 10, weightKg: 16), LoggedSet(reps: 9, weightKg: 16)],
        ),
      ],
    );
    final routine = Routine(
      name: 'Ganzkörper A',
      items: [
        RoutineItem(
          exerciseID: 'goblet_squat',
          name: 'Goblet Squat',
          sets: 3,
          lowerReps: 8,
          upperReps: 12,
          restSeconds: 120,
        ),
      ],
    );
    final settings = GymSettings()..routines = [routine];
    gym.update(sessions: [last], activities: const [], days: const [], gym: settings, now: now);
    expect(gym.lastTime('goblet_squat')?.endsWith('16×10, 16×9'), isTrue);

    gym.startRoutine(routine, now: now);
    final exercise = gym.active!.exercises.first;
    expect(exercise.sets.length, 3);
    expect(exercise.sets.every((set) => set.weightKg == 16), isTrue);
    expect(exercise.group, MuscleGroup.legs);
    expect(exercise.restSeconds, 120);
    gym.toggleDone(set: 0, of: exercise.id, now: now);
    gym.setRIR(2, set: 0, of: exercise.id);
    expect(gym.active!.exercises.first.sets.first.rir, 2);
    expect(gym.hints, isNotEmpty);
  });

  test('Ent-Haken lässt die Pause laufen und lässt sich rückgängig machen', () {
    final gym = controller();
    gym.update(sessions: const [], activities: const [], days: const [], now: now);
    gym.startEmpty(now: now);
    gym.addExercise(ExerciseLibrary.byID['bankdruecken']!);
    final exercise = gym.active!.exercises.first;
    gym.complete(set: 0, of: exercise.id, now: now);
    gym.complete(set: 1, of: exercise.id, now: now);
    final rest = gym.restEndsAt;
    expect(rest, isNotNull);

    // Versehentlich den ersten Satz ent-haken: Pause läuft weiter, Rückgängig stellt ihn wieder her.
    gym.toggleDone(set: 0, of: exercise.id, now: now);
    expect(gym.restEndsAt, rest);
    expect(gym.active!.exercises.first.sets[0].done, isFalse);
    expect(gym.undoLabel, 'Satz 1 wieder offen');
    gym.undo();
    expect(gym.active!.exercises.first.sets[0].done, isTrue);
    expect(gym.undoLabel, isNull);
  });

  test('Beenden kann vergessene Sätze abhaken', () async {
    final gym = controller();
    gym.update(sessions: const [], activities: const [], days: const [], now: now);
    gym.startEmpty(now: now);
    gym.addExercise(ExerciseLibrary.byID['bankdruecken']!);
    final exercise = gym.active!.exercises.first;
    gym.complete(set: 0, of: exercise.id, now: now);
    await gym.finish(
      repository: repository,
      writer: StubWriter(),
      completingOpenSets: true,
      now: now.add(const Duration(minutes: 30)),
    );
    expect(gym.active, isNull);
    expect(gym.finished?.summary.doneSets, 3);
    expect(gym.finished?.summary.minutes, 30);
  });

  test('Pause: ±15 s, Ende mit Ton nur pünktlich, Stoppuhr für Halteübungen', () {
    final gym = controller();
    gym.update(sessions: const [], activities: const [], days: const [], now: now);
    gym.startEmpty(now: now);
    gym.addExercise(ExerciseLibrary.byID['bankdruecken']!);
    final exercise = gym.active!.exercises.first;
    gym.complete(set: 0, of: exercise.id, now: now);
    final remembered = gym.adjustRestAndRemember(15, now: now);
    expect(remembered?.seconds, 135);
    expect(gym.restEndsAt, now.add(const Duration(seconds: 135)));
    gym.restFinished(now.add(const Duration(seconds: 135)), now: now.add(const Duration(seconds: 200)));
    expect(alarm.played, isEmpty);
    expect(gym.restEndsAt, isNull);

    gym.startHold(set: 1, of: exercise.id, now: now);
    gym.stopHold(now: now.add(const Duration(seconds: 42)));
    expect(gym.active!.exercises.first.sets[1].reps, 42);
    expect(gym.active!.exercises.first.sets[1].done, isTrue);
    gym.correctHold(-2);
    expect(gym.active!.exercises.first.sets[1].reps, 40);
    gym.restFinished(gym.restEndsAt!, now: gym.restEndsAt);
    expect(alarm.played, [RestSound.chime]);
  });
}
