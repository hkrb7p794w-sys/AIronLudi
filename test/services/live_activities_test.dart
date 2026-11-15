// Live-Aktivitäten: Stand der laufenden Einheit, Knöpfe vom Sperrbildschirm, „Mahlzeiten heute“ aus dem Widget-Stand.
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/gym_repository.dart';
import 'package:aironludi/data/repositories/meal_repository.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/features/gym/gym_controller.dart';
import 'package:aironludi/services/activities/live_activities.dart';
import 'package:aironludi/services/gym/rest_alarm.dart';
import 'package:aironludi/services/widgets/widget_publisher.dart';
import 'package:aironludi/services/widgets/widget_store.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  final now = DateTime(2026, 11, 16, 18);

  setUpAll(() => initializeDateFormatting('de_DE'));

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  test('laufende Einheit: erst ab dem ersten Satz, Knöpfe ändern Satz, Gewicht und Pause', () {
    final alarm = FakeRestAlarm();
    final gym = GymController(store: store, alarm: alarm, sound: alarm, clock: () => now)
      ..update(sessions: const [], activities: const [], days: const [], now: now)
      ..startEmpty(now: now)
      ..addExercise(ExerciseLibrary.byID['bankdruecken']!)
      ..addExercise(ExerciseLibrary.byID['schulterdruecken']!);
    expect(gym.liveState(now: now), isNull);

    final bench = gym.active!.exercises.first;
    gym.setWeight(60, set: 0, of: bench.id);
    gym.perform(const CompleteSetAction());
    final state = gym.liveState(now: now)!;
    expect(state.exercise, bench.name);
    expect(state.detail, 'Satz 2 von ${bench.sets.length}');
    expect(state.doneSets, 1);
    expect(state.allDone, isFalse);
    expect(state.restEndsAt, isNotNull);
    expect(state.reps, endsWith('Wdh.'));
    expect(state.next, 'Danach: ${gym.active!.exercises[1].name}');

    final before = gym.active!.exercises.first.sets[1].weightKg;
    final step = ExerciseLibrary.rule(bench.exerciseID, name: bench.name).step;
    gym.perform(const AdjustWeightAction(1));
    expect(gym.active!.exercises.first.sets[1].weightKg, before + step);
    final reps = gym.active!.exercises.first.sets[1].reps;
    gym.perform(const AdjustRepsAction(-1));
    expect(gym.active!.exercises.first.sets[1].reps, reps - 1);
    gym.perform(const SkipRestAction());
    expect(gym.liveState(now: now)!.restEndsAt, isNull);
  });

  test('Knöpfe aus dem Kanal', () {
    expect(WorkoutAction.fromChannel({'action': 'completeSet'}), isA<CompleteSetAction>());
    expect(WorkoutAction.fromChannel({'action': 'skipRest'}), isA<SkipRestAction>());
    expect((WorkoutAction.fromChannel({'action': 'weight', 'steps': -1})! as AdjustWeightAction).steps, -1);
    expect((WorkoutAction.fromChannel({'action': 'reps', 'steps': 1})! as AdjustRepsAction).delta, 1);
    expect(WorkoutAction.fromChannel({'action': 'unbekannt'}), isNull);
    expect(WorkoutAction.fromChannel(null), isNull);
  });

  test('Mahlzeiten heute: nur mit Schalter, auch ohne gemeinsamen Ordner; ausgeschaltet beendet', () async {
    final settings = CoachSettings(store);
    settings.profile = settings.profile.copy()..onboardingDone = true;
    final host = FakeLiveActivityHost();
    final publisher = WidgetPublisher(
      store: WidgetStore(DirectoryWidgetHost(null)),
      settings: settings,
      settingsStore: store,
      metrics: MetricsRepository(db),
      activities: ActivityRepository(db),
      gymSessions: GymRepository(db),
      meals: MealRepository(db),
      gym: GymController(store: store, clock: () => now),
      garminProfile: () => null,
      schedule: null,
      liveActivities: host,
    );
    await publisher.publish(now: now);
    expect(host.meals, [null]);

    await store.setBool(SettingsKeys.mealsLiveActivity, true);
    await publisher.publish(now: now);
    final state = host.meals.last!;
    expect(state.meals.map((meal) => meal.id), [for (final category in MealSplit.order) category.rawValue]);
    expect(state.meals.every((meal) => meal.kcal == 0), isTrue);
    expect(state.headline, isNotEmpty);
    expect(state.toChannel()['meals'], hasLength(MealSplit.order.length));
  });

  test('Vorrang der Einheit: Mahlzeiten treten zurück; Ansicht und nächste Mahlzeit im Kanal', () async {
    final settings = CoachSettings(store);
    settings.profile = settings.profile.copy()..onboardingDone = true;
    settings.gym = settings.gym..liveActivityLayout = WorkoutActivityLayout.timer;
    final host = FakeLiveActivityHost();
    final alarm = FakeRestAlarm();
    final gym = GymController(store: store, alarm: alarm, sound: alarm, clock: () => now)
      ..update(sessions: const [], activities: const [], days: const [], gym: settings.gym, now: now);
    final publisher = WidgetPublisher(
      store: WidgetStore(DirectoryWidgetHost(null)),
      settings: settings,
      settingsStore: store,
      metrics: MetricsRepository(db),
      activities: ActivityRepository(db),
      gymSessions: GymRepository(db),
      meals: MealRepository(db),
      gym: gym,
      garminProfile: () => null,
      schedule: null,
      liveActivities: host,
    );
    await store.setBool(SettingsKeys.mealsLiveActivity, true);
    await store.setBool(SettingsKeys.mealsLiveReminders, true);
    await publisher.publish(now: now);
    final before = host.meals.last!;
    // 18 Uhr, nichts eingetragen: Abendessen um 19 Uhr steht an.
    expect(before.nextMeal?.category, MealCategory.dinner);
    expect(before.toChannel()['nextMealID'], 'abendessen');
    expect(before.toChannel()['nextMealTitle'], 'Abendessen');
    expect(before.toChannel()['dayEndsAt'], DateTime(2026, 11, 17).millisecondsSinceEpoch / 1000);

    // Einheit mit erstem Satz: Live-Aktivität der Einheit zeigt sich, „Mahlzeiten heute“ endet.
    gym
      ..startEmpty(now: now)
      ..addExercise(ExerciseLibrary.byID['bankdruecken']!)
      ..perform(const CompleteSetAction());
    final state = gym.liveState(now: now)!;
    expect(state.layout, WorkoutActivityLayout.timer);
    expect(state.toChannel()['layout'], 'timer');
    expect(state.withLayout(WorkoutActivityLayout.exercise).toChannel()['layout'], 'exercise');
    expect(publisher.showsMealsActivity(now: now), isFalse);
    await publisher.publish(now: now);
    expect(host.meals.last, isNull);

    // Live-Aktivität der Einheit ausgeschaltet: kein Vorrang nötig.
    settings.gym = settings.gym..liveActivity = false;
    expect(publisher.showsMealsActivity(now: now), isTrue);
    await publisher.publish(now: now);
    expect(host.meals.last, isNotNull);

    // Ohne Erinnerung auf dem Sperrbildschirm keine nächste Mahlzeit.
    await store.setBool(SettingsKeys.mealsLiveReminders, false);
    await publisher.publish(now: now);
    expect(host.meals.last!.nextMeal, isNull);
  });
}
