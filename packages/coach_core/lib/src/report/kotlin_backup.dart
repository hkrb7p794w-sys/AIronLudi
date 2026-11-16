import 'dart:convert';

import '../calendar/calendar_day.dart';
import '../gym/exercise_catalog.dart';
import '../gym/exercise_library.dart';
import '../gym/gym_session.dart';
import '../gym/routine.dart';
import '../nutrition/meal.dart';
import '../nutrition/meal_category.dart';
import '../nutrition/meal_library.dart';
import '../nutrition/meal_planning.dart';
import '../nutrition/meal_reminders.dart';
import '../nutrition/nutrition_settings.dart';
import '../nutrition/recipe_plan.dart';
import '../nutrition/weight_trend.dart';
import '../util/enum_codec.dart' show enumFromRaw, jsonDouble;
import '../util/text_prefix.dart';

/// Mahlzeit aus der Sicherung der Android-App (wird zu `StoredMeal`).
final class KotlinMeal {
  const KotlinMeal({
    required this.id,
    required this.day,
    required this.createdAt,
    required this.category,
    required this.title,
    required this.hint,
    required this.items,
  });

  final String id;
  final CalendarDay day;
  final DateTime createdAt;
  final MealCategory category;
  final String title;
  final String hint;
  final List<MealItem> items;
}

/// Körperwerte und Ernährungsweise aus der Android-App. Ziel und Tempo werden bewusst nicht übernommen: Sie gehen
/// durch die Schutzgrenzen (`GoalRules`) der Einrichtung bzw. der Ernährungseinstellungen.
final class KotlinBody {
  const KotlinBody({
    required this.weightKilograms,
    required this.heightCentimeters,
    required this.age,
    required this.isFemale,
    required this.activityFactor,
    required this.bodyFatPercent,
    required this.diet,
  });

  final double weightKilograms;
  final double heightCentimeters;
  final int age;
  final bool isFemale;
  final double activityFactor;
  final double? bodyFatPercent;
  final Diet? diet;
}

/// Sicherung der bisherigen Android-App „IronLudi“ (Kotlin, `IronLudi-Gym-Sicherung-<Datum>.json`, `AppData` in
/// Coach-App `android/core/.../Model.kt`). Gelesen wird alles, was die Flutter-App kennt; Positionen von Mahlzeiten,
/// Rezepten und Lebensmitteln haben schon dasselbe JSON wie hier (die Android-App war ein Port von CoachCore).
/// Was es in der Flutter-App nicht gibt, steht in [skipped] (für den Hinweis nach dem Einspielen).
final class KotlinBackup {
  KotlinBackup._();

  /// Neuere Sicherungen als diese kennt die Android-App selbst nicht.
  static const supportedVersion = 1;

  final List<GymSession> sessions = [];
  final List<Routine> routines = [];
  final List<ExerciseInfo> customExercises = [];
  final List<KotlinMeal> meals = [];
  final List<FavoriteMeal> favorites = [];
  final List<MealItem> foods = [];
  final List<OwnRecipe> ownRecipes = [];
  final List<WeightEntry> weights = [];
  KotlinBody? body;
  RecipePreferences? recipePreferences;
  MealReminderSettings? reminders;
  bool? reviewReminder;

  /// Pause nach einem Satz in Sekunden (0 = keine); `null`, wenn nicht gesetzt.
  int? restSeconds;
  bool? keepScreenOn;

  /// Nicht übernommen, mit Grund.
  final List<String> skipped = [];

  int get count =>
      sessions.length +
      routines.length +
      customExercises.length +
      meals.length +
      favorites.length +
      foods.length +
      ownRecipes.length +
      weights.length;

  /// Sieht der Text wie eine Sicherung der Android-App aus? (Die iPhone-Sicherung hat `createdAt` als Text und `gym`.)
  static bool looksLike(Object? json) =>
      json is Map &&
      json['createdAt'] is! String &&
      json['gym'] == null &&
      (json['sessions'] is List || json['meals'] is List || json['routines'] is List);

  /// `null`, wenn es keine Sicherung der Android-App ist. Einzelne unlesbare Einträge fallen weg.
  static KotlinBackup? decode(List<int> data) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
    if (!looksLike(json)) return null;
    final map = json as Map;
    final version = map['version'];
    if (version is int && version > supportedVersion) return null;
    final result = KotlinBackup._();
    final settings = map['settings'] is Map ? map['settings'] as Map : const <String, Object?>{};
    final rest = settings['restSeconds'];
    if (rest is int && rest >= 0) result.restSeconds = rest.clamp(0, 900);
    if (settings['keepScreenOn'] is bool) result.keepScreenOn = settings['keepScreenOn'] as bool;

    for (final raw in _list(map['customExercises'])) {
      if (_exercise(raw) case final exercise?) result.customExercises.add(exercise);
    }
    final restForSets = result.restSeconds ?? 90;
    for (final raw in _list(map['sessions'])) {
      if (_session(raw, rest: restForSets) case final session?) result.sessions.add(session);
    }
    for (final raw in _list(map['routines'])) {
      if (_routine(raw, custom: result.customExercises, rest: restForSets) case final routine?) {
        result.routines.add(routine);
      }
    }
    for (final raw in _list(map['meals'])) {
      if (_meal(raw) case final meal?) result.meals.add(meal);
    }
    for (final raw in _list(map['favorites'])) {
      if (raw is! Map || raw['title'] is! String) continue;
      final items = _items(raw['items']);
      if (items.isEmpty) continue;
      result.favorites.add(
        FavoriteMeal(
          id: raw['id'] is String ? raw['id'] as String : null,
          title: textPrefix(raw['title'] as String, 80),
          items: items,
          category: MealCategory.fromRaw(raw['category'] as String?),
        ),
      );
    }
    result.foods.addAll(_items(map['foods']));
    for (final raw in _list(map['recipes'])) {
      if (OwnRecipe.fromJson(_withDefaults(raw, {'portions': 1})) case final recipe?) result.ownRecipes.add(recipe);
    }
    for (final raw in _list(map['weights'])) {
      if (raw is! Map) continue;
      final day = CalendarDay.tryParse(raw['day'] is String ? raw['day'] as String : '');
      final kilograms = jsonDouble(raw['kilograms']);
      if (day == null || kilograms == null || kilograms < 25 || kilograms > 350) continue;
      result.weights.add(WeightEntry(day: day, kilograms: kilograms, source: WeightSource.manual));
    }
    result.body = _body(map['nutrition']);
    result.recipePreferences = _preferences(map['recipePreferences']);
    if (map['reminders'] is Map) {
      final reminders = map['reminders'] as Map;
      final settings = MealReminderSettings();
      for (final (key, category) in const [
        ('breakfast', MealCategory.breakfast),
        ('lunch', MealCategory.lunch),
        ('snack', MealCategory.snack),
        ('dinner', MealCategory.dinner),
      ]) {
        settings[category] = MealReminderSlot.fromJson(_withDefaults(reminders[key], {'enabled': false}));
      }
      result.reminders = settings;
      if (reminders['review'] is bool) result.reviewReminder = reminders['review'] as bool;
    }

    if (map['active'] is Map) result.skipped.add('laufendes Training (vorher in der alten App beenden)');
    if ((map['dayTypes'] is Map && (map['dayTypes'] as Map).isNotEmpty) ||
        (map['weekDayTypes'] is Map && (map['weekDayTypes'] as Map).isNotEmpty)) {
      result.skipped.add('Tagestypen (die neue App leitet sie aus Wochenplan und Training ab)');
    }
    if (map['weeklyPlan'] is Map) result.skipped.add('Rezeptideen der Woche (lassen sich neu erstellen)');
    if (_list(map['pending']).isNotEmpty) result.skipped.add('wartende KI-Auswertungen ohne Netz');
    return result;
  }

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// Kennung wie in der App (UUID in Großbuchstaben): Kotlin schreibt UUIDs klein. Stabil, damit erneutes Einspielen
  /// nichts doppelt anlegt; nur Unlesbares bekommt eine neue Kennung.
  static String _id(Object? value) => value is String && _uuid.hasMatch(value) ? value.toUpperCase() : newUuid();

  static Object? _withDefaults(Object? raw, Map<String, Object?> defaults) => raw is Map ? {...defaults, ...raw} : raw;

  static List<MealItem> _items(Object? raw) => [for (final item in _list(raw)) ?MealItem.fromJson(item)];

  static ExerciseInfo? _exercise(Object? raw) {
    if (raw is! Map) return null;
    final (id, name) = (raw['id'], raw['name']);
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) return null;
    final lower = raw['lowerReps'] is int ? raw['lowerReps'] as int : 8;
    final upper = raw['upperReps'] is int ? raw['upperReps'] as int : 12;
    return ExerciseInfo(
      id: id,
      name: textPrefix(name.trim(), 60),
      group: MuscleGroup.fromRaw(raw['group']) ?? MuscleGroup.other,
      secondary: [for (final item in _list(raw['secondary'])) ?MuscleGroup.fromRaw(item)],
      equipment: [for (final item in _list(raw['equipment'])) ?Equipment.fromRaw(item)],
      tracking: ExerciseTracking.fromRaw(raw['tracking']) ?? ExerciseTracking.weightReps,
      compound: raw['compound'] == true,
      lowerReps: lower.clamp(1, 600),
      upperReps: upper.clamp(1, 600),
      step: jsonDouble(raw['step']) ?? 2.5,
      percent: jsonDouble(raw['percent']) ?? 2.5,
      instructions: [
        for (final item in _list(raw['instructions']))
          if (item is String) item,
      ],
      isCustom: true,
    );
  }

  static DateTime? _millis(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true) : null;

  static GymSession? _session(Object? raw, {required int rest}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final start = _millis(raw['startedAt']);
    if (id is! String || !_uuid.hasMatch(id) || start == null) return null;
    final exercises = <LoggedExercise>[];
    for (final item in _list(raw['exercises'])) {
      if (item is! Map || item['exerciseId'] is! String) continue;
      final name = item['name'] is String ? item['name'] as String : item['exerciseId'] as String;
      exercises.add(
        LoggedExercise(
          exerciseID: item['exerciseId'] as String,
          name: name,
          group: MuscleGroup.fromRaw(item['group']) ?? MuscleGroup.other,
          restSeconds: rest,
          sets: [
            for (final set in _list(item['sets']))
              if (set is Map)
                LoggedSet(
                  reps: set['reps'] is int ? (set['reps'] as int).clamp(0, 10000) : 0,
                  weightKg: jsonDouble(set['weightKg']) ?? 0,
                  done: set['done'] == true,
                  kind: set['warmup'] == true ? SetKind.warmup : SetKind.working,
                ),
          ],
        ),
      );
    }
    final routine = raw['routineId'];
    return GymSession(
      id: _id(id),
      workoutKey: routine is String ? 'routine-${_id(routine)}' : null,
      title: raw['name'] is String ? raw['name'] as String : 'Training',
      start: start,
      end: _millis(raw['endedAt']),
      exercises: exercises,
    );
  }

  static Routine? _routine(Object? raw, {required List<ExerciseInfo> custom, required int rest}) {
    if (raw is! Map || raw['id'] is! String || raw['name'] is! String) return null;
    final items = <RoutineItem>[];
    for (final item in _list(raw['exercises'])) {
      if (item is! Map || item['exerciseId'] is! String) continue;
      final exerciseID = item['exerciseId'] as String;
      final info = ExerciseLibrary.info(exerciseID, custom: custom);
      items.add(
        RoutineItem(
          exerciseID: exerciseID,
          name: info?.name ?? exerciseID,
          sets: item['sets'] is int ? (item['sets'] as int).clamp(1, 20) : 3,
          lowerReps: info?.lowerReps ?? 8,
          upperReps: info?.upperReps ?? 12,
          restSeconds: rest,
        ),
      );
    }
    return Routine(id: _id(raw['id']), name: raw['name'] as String, items: items);
  }

  static KotlinMeal? _meal(Object? raw) {
    if (raw is! Map) return null;
    final (id, title) = (raw['id'], raw['title']);
    final createdAt = _millis(raw['createdAt']);
    final day = CalendarDay.tryParse(raw['day'] is String ? raw['day'] as String : '');
    final category = MealCategory.fromRaw(raw['category'] as String?);
    final items = _items(raw['items']);
    if (id is! String || title is! String || createdAt == null || day == null || category == null || items.isEmpty) {
      return null;
    }
    return KotlinMeal(
      id: id,
      day: day,
      createdAt: createdAt,
      category: category,
      title: title,
      hint: raw['hint'] is String ? raw['hint'] as String : '',
      items: items,
    );
  }

  static KotlinBody? _body(Object? raw) {
    if (raw is! Map || raw['configured'] != true) return null;
    final weight = jsonDouble(raw['weightKg']);
    final height = jsonDouble(raw['heightCm']);
    final age = raw['age'];
    if (weight == null || height == null || age is! int) return null;
    return KotlinBody(
      weightKilograms: weight.clamp(25, 350).toDouble(),
      heightCentimeters: height.clamp(100, 250).toDouble(),
      age: age.clamp(10, 110),
      isFemale: raw['isFemale'] == true,
      activityFactor: (jsonDouble(raw['activityFactor']) ?? 1.4).clamp(1.1, 2.5).toDouble(),
      bodyFatPercent: jsonDouble(raw['bodyFatPercent']),
      diet: Diet.fromRaw(raw['diet']),
    );
  }

  static RecipePreferences? _preferences(Object? raw) {
    if (raw is! Map) return null;
    final preferences = RecipePreferences()
      ..allergens = {for (final item in _list(raw['allergens'])) ?enumFromRaw(Allergen.values, item)};
    if (raw['dislikes'] is String) preferences.dislikes = textPrefix(raw['dislikes'] as String, 200);
    if (raw['maxMinutes'] is int) preferences.maxMinutes = (raw['maxMinutes'] as int).clamp(5, 240);
    if (raw['snacks'] is bool) preferences.snacks = raw['snacks'] as bool;
    if (raw['mealPrep'] is bool) preferences.mealPrep = raw['mealPrep'] as bool;
    return preferences;
  }
}
