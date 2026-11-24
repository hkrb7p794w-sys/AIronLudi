part of 'gym_controller.dart';

/// Was der Abschluss-Bildschirm nach dem Speichern zeigt.
final class FinishedWorkout {
  FinishedWorkout({
    required this.title,
    required this.summary,
    required this.records,
    required this.status,
    this.exerciseIDs = const [],
    this.muscles = const {},
    this.volumeChange,
    this.share,
    this.shareKeys = const [],
    this.shareText,
  });

  final String title;
  final FlowSummary summary;
  final List<String> records;
  String status;

  /// Für „Nächstes Mal“ (Progression nach dem Speichern).
  final List<String> exerciseIDs;

  /// Effektive Sätze je Muskel dieser Einheit (Heatmap im Abschluss).
  final Map<Muscle, double> muscles;

  /// Volumen gegenüber der letzten gleichen Einheit in %.
  final int? volumeChange;

  /// Was „Mit Freunden teilen“ senden würde (ohne Körperwerte).
  final WorkoutShare? share;

  /// Schlüssel der Einheit im Reiter „Aktivitäten“ (`SocialTimeline.keys`).
  final List<String> shareKeys;

  /// Text mit Link für „Teilen …“ über das System (`GymShareText`).
  final String? shareText;
}

/// Abfragen ohne Zustandsänderung: Vorbelegung, Aufwärmen, letzte Leistungen, Live-Aktivität, Verlauf.
extension GymControllerQueries on GymController {
  /// Gewicht und Wiederholungen für den nächsten Besuch: Steigerung nur, wenn die Regel es sagt und die Tagesampel
  /// nicht dagegen spricht; sonst wie beim letzten Mal; ohne Verlauf wie im Plan.
  ({double weight, List<int> reps}) prefillPlanned(String exerciseID, {PlannedExercise? planned}) {
    final range =
        planned?.planRepRange ?? ranges[exerciseID] ?? gym.exercise(exerciseID)?.repRange ?? const IntRange(8, 12);
    return prefill(exerciseID, range: range, startWeight: planned?.weightKg, plannedReps: planned?.reps);
  }

  ({double weight, List<int> reps}) prefill(
    String exerciseID, {
    required IntRange range,
    required double? startWeight,
    int? plannedReps,
  }) {
    // Mit Unterstützung (negatives Gewicht) wie beim letzten Mal; die Progression rechnet nur mit Last.
    final last = GymStats.history(exerciseID, sessions: sessions).lastOrNull;
    if (last != null) {
      if (last.sets.where((set) => set.weightKg < 0).firstOrNull case final assisted?) {
        return (weight: assisted.weightKg, reps: [for (final set in last.sets) set.reps]);
      }
    }
    if (progress.where((item) => item.exerciseID == exerciseID).firstOrNull case final item?) {
      switch (item.status) {
        case ProgressStatus.increase when recovered != false:
          return (weight: item.nextWeightKg ?? item.weightKg, reps: [range.lower]);
        case ProgressStatus.restart:
          return (weight: item.nextWeightKg ?? item.weightKg, reps: [range.lower]);
        default:
          return (weight: item.weightKg, reps: item.reps);
      }
    }
    return (weight: startWeight ?? 0, reps: [plannedReps ?? range.upper]);
  }

  /// Aufwärmvorschlag für eine Übung; berücksichtigt Niveau und ob der Muskel heute schon gearbeitet hat.
  List<WarmUpStep> warmUpSteps(LoggedExercise exercise, {required ExperienceLevel? level}) {
    final session = active;
    final info = gym.exercise(exercise.exerciseID);
    if (!gym.suggestsWarmUp || session == null || info == null) return const [];
    return WarmUp.suggestion(
      exercise,
      info: info,
      bar: gym.bar(info.id),
      level: level,
      warmedUp: WarmUp.isWarmedUp(exercise, info: info, session: session),
    );
  }

  /// „Letztes Mal (Mo, 12.10.): 60×10, 60×9“.
  String? lastTime(String exerciseID) {
    final point = GymStats.history(exerciseID, sessions: sessions).lastOrNull;
    if (point == null) return null;
    final sets = [
      for (final set in point.sets)
        set.weightKg > 0 ? '${GermanFormat.number(set.weightKg)}×${set.reps}' : '${set.reps}',
    ];
    return 'Letztes Mal (${DateFormat('EEE, d.M.', 'de_DE').format(point.day.referenceDate)}): ${sets.join(', ')}';
  }

  /// Stillstand, Volumen und Häufigkeit je Muskel aus dem Verlauf (Regeln, ohne KI).
  List<String> get observations => GymCoach.observations(sessions: sessions, today: today);

  /// Die letzten Leistungen einer Übung als Orientierung unter der Eingabe (neueste zuerst).
  List<GymPerformance> recentPerformances(String exerciseID, {int limit = 5}) =>
      GymStats.recentPerformances(exerciseID, sessions: sessions, limit: limit);

  /// Nächster offener Satz wie auf der Fokus-Karte.
  FlowPosition? get currentPosition => switch (active) {
    final session? => WorkoutFlow.current(session, preferring: focusExerciseID),
    null => null,
  };

  /// Stand der Live-Aktivität (Port von `GymViewModel.liveState`). Keine Live-Aktivität, solange nur geöffnet und noch
  /// kein Satz gemacht ist.
  WorkoutLiveState? liveState({DateTime? now}) {
    final session = active;
    if (session == null || !sessionState(now: now).showsLiveActivity) return null;
    final position = currentPosition;
    if (position == null) {
      return WorkoutLiveState(
        exercise: 'Plan geschafft',
        detail: '${session.doneSetCount} Sätze – beenden oder fortsetzen',
        restEndsAt: restEndsAt,
        doneSets: session.doneSetCount,
        allDone: true,
        layout: gym.liveActivityLayout,
      );
    }
    final exercise = session.exercises[position.exercise];
    final set = exercise.sets[position.set];
    final info = gym.exercise(exercise.exerciseID);
    final isTime = info?.tracking == ExerciseTracking.time;
    final weight = ExerciseUnits.weightText(set.weightKg, info: info);
    final step = ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: gym.customExercises).step;
    final following = WorkoutFlow.nextExercise(position.exercise, session);
    // Immer nur der Name der Übung: „Pause“ bzw. „Jetzt“ und der Satz stehen in eigenen Zeilen der Karte.
    return WorkoutLiveState(
      exercise: exercise.name,
      detail: 'Satz ${position.set + 1} von ${exercise.sets.length}',
      restEndsAt: restEndsAt,
      doneSets: session.doneSetCount,
      allDone: false,
      weight: weight.unit.isEmpty ? weight.value : '${weight.value} ${weight.unit}',
      reps: isTime ? '${set.reps} s' : '${set.reps} Wdh.',
      weightStep: GermanFormat.number(step),
      repsStep: isTime ? '5 s' : '1',
      next: following == null ? null : 'Danach: ${session.exercises[following].name}',
      layout: gym.liveActivityLayout,
    );
  }

  /// Verlauf einer Übung je Tag (Höchstgewicht, geschätztes 1RM, Sätze).
  List<GymStatsPoint> history(String exerciseID) => GymStats.history(exerciseID, sessions: sessions);

  /// Regelbasierter Ersatz für die KI-Hinweise (ohne Benachrichtigung).
  void _showFallbackHints() {
    hints = GymHints.fallback(progress, observations: observations);
    hintSource = 'Regeln (ohne KI)';
    hintEvidence = const ['gym.progression', 'gym.rir'];
  }
}
