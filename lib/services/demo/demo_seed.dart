// Demo-Daten für den Demo-Modus (Ich › Technik › Demo ansehen) und den Screenshot-Prüfstand: eine erfundene Person
// („Demo“), 35 Tage Tageswerte, Läufe, Radfahrten, Gym-Einheiten, Mahlzeiten und Gewicht. Alles relativ zu heute,
// damit „Heute“, Woche und Verläufe immer gefüllt sind. Keine echten Personendaten.
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/storage.dart';
import '../providers.dart';

String _two(int value) => value.toString().padLeft(2, '0');

String _local(CalendarDay day, int hour, int minute) => '${day.iso} ${_two(hour)}:${_two(minute)}:00';

DateTime _at(CalendarDay day, int hour, [int minute = 0]) {
  final parts = day.iso.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2], hour, minute);
}

/// Profil: persönlicher Modus, Laufen + Rad + Kraft, Halbmarathon in elf Wochen.
UserProfile demoProfile(CalendarDay today) {
  final profile = UserProfile(
    mode: ProfileMode.personal,
    onboardingDone: true,
    sports: const [TrainingSport.run, TrainingSport.bike, TrainingSport.strength],
    targets: const ImprovementTargets(restingHeartRate: 50),
  );
  // Wochenplan: Mo Kraft, Di Lauf, Mi Rad, Do Kraft, Fr Ruhe, Sa langer Lauf, So Rad.
  var schedule = profile.schedule;
  schedule = schedule.withSlots(const [SessionSlot(TrainingSport.strength)], Weekday.values[0]);
  schedule = schedule.withSlots(const [SessionSlot(TrainingSport.run)], Weekday.values[1]);
  schedule = schedule.withSlots(const [SessionSlot(TrainingSport.bike)], Weekday.values[2]);
  schedule = schedule.withSlots(const [SessionSlot(TrainingSport.strength)], Weekday.values[3]);
  schedule = schedule.withSlots(const [SessionSlot(TrainingSport.run)], Weekday.values[5]);
  schedule = schedule.withSlots(const [SessionSlot(TrainingSport.bike)], Weekday.values[6]);
  profile.schedule = schedule;
  return profile;
}

NutritionSettings demoNutrition() => NutritionSettings()
  ..goal = NutritionGoal.maintain
  ..diet = Diet.omnivore
  ..weightKilograms = 74
  ..heightCentimeters = 180
  ..age = 34
  ..isFemale = false;

/// Tageswerte der letzten 35 Tage mit leichtem Wellengang; heute etwas müde (HRV unausgeglichen, kurzer Schlaf).
List<DailyMetrics> demoMetrics(CalendarDay today) => [
  for (var offset = 34; offset >= 0; offset--)
    () {
      final day = today.adding(-offset);
      final wave = math.sin(offset / 3.0);
      final isToday = offset == 0;
      return DailyMetrics(day)
        ..restingHeartRate = (isToday ? 55 : 50 + wave * 2).roundToDouble()
        ..hrvLastNightAverage = (isToday ? 52 : 62 + wave * 6).roundToDouble()
        ..hrvWeeklyAverage = isToday ? 56 : 61
        ..hrvBaselineLow = 57
        ..hrvBaselineHigh = 70
        ..hrvStatus = isToday ? 'UNBALANCED' : 'BALANCED'
        ..sleepSeconds = (isToday ? 6.2 : 7.3 + wave * 0.5) * 3600
        ..sleepScore = isToday ? 68 : 80 + wave * 6
        ..deepSleepSeconds = 1.3 * 3600
        ..remSleepSeconds = 1.6 * 3600
        ..lightSleepSeconds = 3.6 * 3600
        ..awakeSleepSeconds = 0.3 * 3600
        ..sleepStartMinutes = 23 * 60 + 10
        ..sleepEndMinutes = 6 * 60 + 40
        ..bodyBatteryAtWake = isToday ? 58 : 78 + wave * 8
        ..bodyBatteryHigh = isToday ? 62 : 85
        ..bodyBatteryLow = 22
        ..bodyBatteryLatest = isToday ? 47 : 30
        ..bodyBatteryCharged = 55
        ..bodyBatteryDrained = 60
        ..stressAverage = isToday ? 34 : 26 + wave * 4
        ..steps = isToday ? 4200 : 9000 + wave * 2500
        ..activeKilocalories = 650 + wave * 150
        ..restingKilocalories = 1750
        ..totalKilocalories = 2400 + wave * 150
        ..trainingReadiness = isToday ? 46 : 70 + wave * 10
        ..trainingReadinessLevel = isToday ? 'LOW' : 'MODERATE'
        ..vo2Max = 52
        ..fitnessAge = 29
        ..spo2Average = 96
        ..respirationSleep = 14;
    }(),
];

/// Ausdaueraktivitäten der letzten fünf Wochen nach dem Wochenplan.
List<GarminActivity> demoActivities(CalendarDay today) {
  final list = <GarminActivity>[];
  var id = 90000;
  for (var offset = 34; offset >= 1; offset--) {
    final day = today.adding(-offset);
    final weekday = day.weekdayIndex;
    if (weekday == 1) {
      list.add(
        GarminActivity(id++)
          ..typeKey = 'running'
          ..name = 'Intervalle 6 × 800 m'
          ..startLocal = _local(day, 18, 5)
          ..durationSeconds = 52 * 60
          ..distanceMeters = 10200
          ..averageHeartRate = 156
          ..maxHeartRate = 182
          ..calories = 690
          ..trainingLoad = 118
          ..aerobicTrainingEffect = 3.6
          ..anaerobicTrainingEffect = 2.4
          ..elevationGain = 42,
      );
    } else if (weekday == 2 || weekday == 6) {
      list.add(
        GarminActivity(id++)
          ..typeKey = weekday == 2 ? 'virtual_ride' : 'road_biking'
          ..name = weekday == 2 ? 'Zwift Grundlage' : 'Sonntagsrunde'
          ..startLocal = _local(day, weekday == 2 ? 19 : 9, 30)
          ..durationSeconds = (weekday == 2 ? 60 : 150) * 60
          ..distanceMeters = weekday == 2 ? 31000 : 72000
          ..averageHeartRate = 132
          ..maxHeartRate = 158
          ..averagePower = weekday == 2 ? 190 : 175
          ..normalizedPower = weekday == 2 ? 196 : 188
          ..calories = weekday == 2 ? 680 : 1650
          ..trainingLoad = weekday == 2 ? 72 : 165
          ..aerobicTrainingEffect = 3.0
          ..elevationGain = weekday == 2 ? 120 : 640,
      );
    } else if (weekday == 5) {
      list.add(
        GarminActivity(id++)
          ..typeKey = 'running'
          ..name = 'Langer Lauf'
          ..startLocal = _local(day, 8, 15)
          ..durationSeconds = 95 * 60
          ..distanceMeters = 17600
          ..averageHeartRate = 141
          ..maxHeartRate = 158
          ..calories = 1180
          ..trainingLoad = 140
          ..aerobicTrainingEffect = 3.4
          ..elevationGain = 110,
      );
    }
  }
  return list;
}

GymSession _gym(CalendarDay day, String title, double bench) => GymSession(
  workoutKey: 'demo-${day.iso}',
  title: title,
  start: _at(day, 7, 10),
  end: _at(day, 8, 5),
  exercises: [
    LoggedExercise(
      exerciseID: 'bankdruecken',
      name: 'Bankdrücken',
      group: MuscleGroup.chest,
      sets: [
        LoggedSet(reps: 10, weightKg: 40, kind: SetKind.warmup),
        LoggedSet(reps: 8, weightKg: bench),
        LoggedSet(reps: 8, weightKg: bench),
        LoggedSet(reps: 6, weightKg: bench + 2.5),
      ],
    ),
    LoggedExercise(
      exerciseID: 'kniebeuge',
      name: 'Kniebeuge',
      group: MuscleGroup.legs,
      sets: [
        LoggedSet(reps: 8, weightKg: bench + 20),
        LoggedSet(reps: 8, weightKg: bench + 20),
        LoggedSet(reps: 8, weightKg: bench + 20),
      ],
    ),
    LoggedExercise(
      exerciseID: 'klimmzuege',
      name: 'Klimmzüge',
      group: MuscleGroup.back,
      sets: [LoggedSet(reps: 8, weightKg: 0), LoggedSet(reps: 7, weightKg: 0), LoggedSet(reps: 6, weightKg: 0)],
    ),
  ],
);

List<GymSession> demoGym(CalendarDay today) => [
  for (var offset = 34; offset >= 1; offset--)
    if (today.adding(-offset).weekdayIndex == 0 || today.adding(-offset).weekdayIndex == 3)
      _gym(today.adding(-offset), offset.isEven ? 'Oberkörper' : 'Ganzkörper', 60 + (34 - offset) / 7 * 2.5),
];

MealItem _item(
  String name,
  double grams, {
  required double kcal,
  required double p,
  required double c,
  required double f,
}) => MealItem(
  name: name,
  grams: grams,
  source: MealItemSource.manual,
  per100g: NutrientValues({
    Nutrient.kcal: kcal,
    Nutrient.protein: p,
    Nutrient.carbs: c,
    Nutrient.fat: f,
    Nutrient.fiber: 2,
  }),
);

/// Mahlzeiten der letzten sieben Tage; heute Frühstück und Mittagessen.
List<StoredMeal> demoMeals(CalendarDay today) => [
  for (var offset = 6; offset >= 0; offset--) ...[
    StoredMeal(
      day: today.adding(-offset),
      createdAt: _at(today.adding(-offset), 7, 30),
      category: MealCategory.breakfast,
      title: 'Haferflocken mit Skyr und Beeren',
      items: [
        _item('Haferflocken', 70, kcal: 370, p: 13, c: 59, f: 7),
        _item('Skyr', 200, kcal: 63, p: 11, c: 4, f: 0.2),
        _item('Heidelbeeren', 100, kcal: 42, p: 0.6, c: 7.4, f: 0.6),
      ],
    ),
    StoredMeal(
      day: today.adding(-offset),
      createdAt: _at(today.adding(-offset), 12, 45),
      category: MealCategory.lunch,
      title: 'Hähnchen, Reis und Brokkoli',
      items: [
        _item('Hähnchenbrust', 160, kcal: 110, p: 23, c: 0, f: 1.5),
        _item('Basmatireis gekocht', 220, kcal: 130, p: 2.7, c: 28, f: 0.3),
        _item('Brokkoli', 150, kcal: 35, p: 3, c: 4, f: 0.4),
        _item('Olivenöl', 10, kcal: 884, p: 0, c: 0, f: 100),
      ],
    ),
    if (offset > 0)
      StoredMeal(
        day: today.adding(-offset),
        createdAt: _at(today.adding(-offset), 19, 15),
        category: MealCategory.dinner,
        title: 'Vollkornbrot mit Käse und Ei',
        items: [
          _item('Vollkornbrot', 120, kcal: 220, p: 8, c: 38, f: 2),
          _item('Gouda', 40, kcal: 356, p: 25, c: 0, f: 27),
          _item('Ei', 120, kcal: 155, p: 13, c: 1, f: 11),
        ],
      ),
  ],
];

List<WeightEntry> demoWeights(CalendarDay today) => [
  for (var offset = 34; offset >= 0; offset -= 2)
    WeightEntry(day: today.adding(-offset), kilograms: 75.2 - (34 - offset) * 0.03, source: WeightSource.manual),
];

/// Spielt alles in den Container ein.
Future<void> seedDemo(ProviderContainer container) async {
  final today = CalendarDay.today();
  final settings = container.read(coachSettingsProvider);
  settings
    ..profile = demoProfile(today)
    ..nutrition = demoNutrition()
    ..weights = demoWeights(today);
  final metrics = container.read(metricsRepositoryProvider);
  for (final day in demoMetrics(today)) {
    await metrics.replace(day);
  }
  final activities = container.read(activityRepositoryProvider);
  for (final activity in demoActivities(today)) {
    await activities.upsert(activity);
  }
  final gym = container.read(gymRepositoryProvider);
  for (final session in demoGym(today)) {
    await gym.save(session);
  }
  final meals = container.read(mealRepositoryProvider);
  for (final meal in demoMeals(today)) {
    await meals.save(meal);
  }
}
