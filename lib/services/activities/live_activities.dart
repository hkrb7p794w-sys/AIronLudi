import 'dart:async';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Inhalt der Live-Aktivität der laufenden Einheit (`WorkoutActivityAttributes.ContentState`).
@immutable
final class WorkoutLiveState {
  const WorkoutLiveState({
    required this.exercise,
    required this.detail,
    required this.restEndsAt,
    required this.doneSets,
    required this.allDone,
    this.weight,
    this.reps,
    this.weightStep,
    this.repsStep,
    this.next,
  });

  /// Übung des nächsten offenen Satzes.
  final String exercise;

  /// „Satz 2 von 4“.
  final String detail;
  final DateTime? restEndsAt;
  final int doneSets;

  /// Alle Sätze erledigt – nur noch beenden.
  final bool allDone;

  /// Werte des aktuellen Satzes zum Ändern auf dem Sperrbildschirm („80 kg“, „10 Wdh.“) und die Schrittweiten.
  final String? weight;
  final String? reps;
  final String? weightStep;
  final String? repsStep;

  /// „Danach: Schulterdrücken“.
  final String? next;

  /// Für den Kanal: Zeitpunkte in Sekunden seit 1970.
  Map<String, Object?> toChannel() => {
    'exercise': exercise,
    'detail': detail,
    'restEndsAt': restEndsAt == null ? null : restEndsAt!.millisecondsSinceEpoch / 1000,
    'doneSets': doneSets,
    'allDone': allDone,
    'weight': weight,
    'reps': reps,
    'weightStep': weightStep,
    'repsStep': repsStep,
    'next': next,
  };

  @override
  bool operator ==(Object other) =>
      other is WorkoutLiveState &&
      other.exercise == exercise &&
      other.detail == detail &&
      other.restEndsAt == restEndsAt &&
      other.doneSets == doneSets &&
      other.allDone == allDone &&
      other.weight == weight &&
      other.reps == reps &&
      other.weightStep == weightStep &&
      other.repsStep == repsStep &&
      other.next == next;

  @override
  int get hashCode =>
      Object.hash(exercise, detail, restEndsAt, doneSets, allDone, weight, reps, weightStep, repsStep, next);
}

/// Eine Mahlzeit der Live-Aktivität „Mahlzeiten heute“.
@immutable
final class MealsLiveMeal {
  const MealsLiveMeal({required this.id, required this.title, required this.kcal, required this.fraction});

  /// Rohwert der Mahlzeit (`MealCategory`), auch für den Link zum Erfassen.
  final String id;
  final String title;
  final int kcal;

  /// Anteil am Ziel der Mahlzeit; `null` ohne Ziel.
  final double? fraction;

  Map<String, Object?> toChannel() => {'id': id, 'title': title, 'kcal': kcal, 'fraction': fraction};

  @override
  bool operator ==(Object other) =>
      other is MealsLiveMeal &&
      other.id == id &&
      other.title == title &&
      other.kcal == kcal &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(id, title, kcal, fraction);
}

/// Inhalt der Live-Aktivität „Mahlzeiten heute“ (`MealsActivityAttributes.ContentState`).
@immutable
final class MealsLiveState {
  const MealsLiveState({
    required this.meals,
    required this.streakDays,
    required this.streakActive,
    required this.kcalRemaining,
    required this.headline,
  });

  final List<MealsLiveMeal> meals;
  final int streakDays;
  final bool streakActive;

  /// Übrige Kalorien (negativ = darüber); `null` ohne Ziel.
  final int? kcalRemaining;
  final String headline;

  /// Aus dem Widget-Stand (Port von `MealsActivityController.state(from:)`).
  static MealsLiveState? fromSnapshot(WidgetSnapshot snapshot, {required DateTime now}) {
    final nutrition = snapshot.nutrition;
    if (nutrition == null) return null;
    final parts =
        nutrition.meals ??
        [for (final category in MealSplit.order) WidgetMealPart(category: category, kcal: 0, target: null)];
    return MealsLiveState(
      meals: [
        for (final part in parts)
          MealsLiveMeal(
            id: part.category.rawValue,
            title: part.category.label,
            kcal: part.kcal.round(),
            fraction: part.fraction,
          ),
      ],
      streakDays: snapshot.mealStreak?.days ?? 0,
      streakActive: snapshot.mealStreak?.activeToday ?? false,
      kcalRemaining: nutrition.kcalRemaining?.round(),
      headline: MealHeadline.forSnapshot(snapshot, hour: now.hour),
    );
  }

  Map<String, Object?> toChannel() => {
    'meals': [for (final meal in meals) meal.toChannel()],
    'streakDays': streakDays,
    'streakActive': streakActive,
    'kcalRemaining': kcalRemaining,
    'headline': headline,
  };
}

/// Knopf der Live-Aktivität (Sperrbildschirm, Dynamic Island).
sealed class WorkoutAction {
  const WorkoutAction();

  static WorkoutAction? fromChannel(Object? arguments) {
    if (arguments is! Map) return null;
    final steps = arguments['steps'] is int ? arguments['steps'] as int : 0;
    return switch (arguments['action']) {
      'completeSet' => const CompleteSetAction(),
      'skipRest' => const SkipRestAction(),
      'weight' => AdjustWeightAction(steps),
      'reps' => AdjustRepsAction(steps),
      _ => null,
    };
  }
}

final class CompleteSetAction extends WorkoutAction {
  const CompleteSetAction();
}

final class SkipRestAction extends WorkoutAction {
  const SkipRestAction();
}

/// Gewicht um ganze Schritte der Übung ändern.
final class AdjustWeightAction extends WorkoutAction {
  const AdjustWeightAction(this.steps);

  final int steps;
}

/// Wiederholungen um ±1 (Halteübungen ±5 s) ändern.
final class AdjustRepsAction extends WorkoutAction {
  const AdjustRepsAction(this.delta);

  final int delta;
}

/// Plattformteil der Live-Aktivitäten (iOS: ActivityKit im `AppDelegate`; Android: laufende Mitteilung der Einheit in
/// `WorkoutNotification.kt`).
abstract interface class LiveActivityHost {
  /// `state == null` beendet die Aktivität.
  Future<void> updateWorkout(WorkoutLiveState? state, {required String title});

  /// `state == null` beendet die Aktivität; starten darf iOS nur, solange die App sichtbar ist.
  Future<void> updateMeals(MealsLiveState? state, {required DateTime now});

  /// Knöpfe der Live-Aktivität; laufen im Prozess der App, auch wenn iOS sie dafür im Hintergrund startet.
  set onWorkoutAction(void Function(WorkoutAction action)? handler);

  /// Android: Knöpfe der laufenden Mitteilung, die getippt wurden, während die App nicht lief.
  Future<List<WorkoutAction>> takePendingActions();
}

/// Kanal `aironludi/activities`.
final class ChannelLiveActivityHost implements LiveActivityHost {
  ChannelLiveActivityHost({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('aironludi/activities') {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'workoutAction') return;
      if (WorkoutAction.fromChannel(call.arguments) case final action?) _handler?.call(action);
    });
  }

  final MethodChannel _channel;
  void Function(WorkoutAction action)? _handler;

  @override
  set onWorkoutAction(void Function(WorkoutAction action)? handler) => _handler = handler;

  static bool get _supported => Platform.isIOS || Platform.isAndroid;

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on Object {
      // Älterer Build ohne Plattformteil oder Live-Aktivitäten abgeschaltet.
    }
  }

  @override
  Future<List<WorkoutAction>> takePendingActions() async {
    if (!Platform.isAndroid) return const [];
    try {
      final pending = await _channel.invokeMethod<List<Object?>>('takePendingActions') ?? const [];
      return [for (final item in pending) ?WorkoutAction.fromChannel(item)];
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> updateWorkout(WorkoutLiveState? state, {required String title}) =>
      _invoke('updateWorkout', {'state': state?.toChannel(), 'title': title});

  @override
  Future<void> updateMeals(MealsLiveState? state, {required DateTime now}) =>
      _invoke('updateMeals', {'state': state?.toChannel(), 'now': now.millisecondsSinceEpoch / 1000});
}

/// Für Tests: merkt sich die letzten Stände.
final class FakeLiveActivityHost implements LiveActivityHost {
  final List<WorkoutLiveState?> workout = [];
  final List<MealsLiveState?> meals = [];
  void Function(WorkoutAction action)? handler;

  @override
  set onWorkoutAction(void Function(WorkoutAction action)? handler) => this.handler = handler;

  @override
  Future<void> updateWorkout(WorkoutLiveState? state, {required String title}) async => workout.add(state);

  @override
  Future<void> updateMeals(MealsLiveState? state, {required DateTime now}) async => meals.add(state);

  List<WorkoutAction> pending = [];

  @override
  Future<List<WorkoutAction>> takePendingActions() async {
    final taken = pending;
    pending = [];
    return taken;
  }
}
