import 'dart:async';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/settings/settings_store.dart';
import '../../services/ai/ai_client.dart';
import '../../services/garmin/garmin_connect_session.dart';
import '../../services/gym/garmin_strength_service.dart';
import '../../services/gym/rest_alarm.dart';
import '../../services/health/health_writer.dart';

/// Einheit im Wochenplan.
typedef PlannedWorkout = ({CalendarDay day, Workout workout, bool done});

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
}

/// Trainingsplan, laufende Einheit, Progression und Wochenvolumen (Port von `GymViewModel`).
///
/// Die laufende Einheit liegt zusätzlich in den Einstellungen (`gym.activeSession`) – beendet das System die App im
/// Gym, ist nichts verloren.
final class GymController extends ChangeNotifier {
  GymController({required SettingsStore store, this._alarm, this._sound, DateTime Function()? clock})
    : _store = store,
      _clock = clock ?? DateTime.now {
    active = switch (GymSession.fromJson(store.json(activeKey))) {
      final session? => ExerciseAliases.normalized(session),
      null => null,
    };
    discardAbandoned();
  }

  static const activeKey = SettingsKeys.gymActiveSession;

  final SettingsStore _store;
  final RestAlarm? _alarm;
  final RestSoundPlaying? _sound;
  final DateTime Function() _clock;

  GymPlan plan = GymPlan.standard;
  CalendarDay today = CalendarDay.today();

  /// Einheit laut Plan für heute (`null` = kein Gym-Tag oder schon erledigt).
  Workout? todayWorkout;
  List<PlannedWorkout> weekPlan = const [];
  List<ExerciseProgress> progress = const [];
  Map<MuscleGroup, int> volume = const {};
  int? daysSinceLegs;
  bool? recovered;
  GymSession? active;

  /// Pausenende nach dem letzten abgehakten Satz.
  DateTime? restEndsAt;

  /// Länge der laufenden Pause (für den Fortschrittsring).
  int restSeconds = 0;

  /// Zuletzt abgehakter Satz – in der Pause wird dafür RIR abgefragt.
  ({String exercise, int set})? lastDone;

  /// Übung, die die Person auf der Fokus-Karte gewählt hat (`null` = automatisch der nächste offene Satz).
  String? focusExerciseID;

  /// Rückgängig für die letzte Änderung, die etwas wegnimmt (Ent-Haken, Satz oder Übung löschen).
  String? undoLabel;
  GymSession? _undoSession;

  /// Ergebnis der zuletzt beendeten Einheit (Abschluss-Bildschirm).
  FinishedWorkout? finished;
  String? message;
  bool isSaving = false;

  /// KI-Hinweise zur Gewichtssteigerung (oder regelbasierter Ersatz).
  List<String> hints = const [];
  String hintSource = '';
  List<String> hintEvidence = const [];
  bool isLoadingHints = false;

  /// Zielbereiche je Übung: Saisonplan und eigene Routinen.
  Map<String, IntRange> ranges = const {};
  GymSettings gym = GymSettings();
  List<GymSession> sessions = const [];

  /// Pause wurde für den letzten Satz schon wegen RIR verlängert.
  bool _restExtended = false;

  /// Zählt hoch, sobald der letzte offene Satz des Plans erledigt (oder übersprungen) ist – die Ansicht fragt dann
  /// „Training beenden“ oder „fortsetzen“.
  int planCompleteCount = 0;

  /// Laufende Stoppuhr einer Halteübung: Satz und Startzeit.
  ({String exercise, int set, DateTime start})? hold;

  /// Pause, die bei abgeschaltetem Automatismus auf „Pause starten“ wartet.
  int? pendingRest;

  /// Zählt hoch, wenn eine Pause im Vordergrund abläuft (Vibration).
  int restFinishedCount = 0;

  DateTime _now(DateTime? now) => now ?? _clock();

  /// Zustand der offenen Einheit: erst der erste Satz macht sie zum Training (Live-Aktivität, zählt als gemacht).
  ActiveSessionState sessionState({DateTime? now}) => ActiveSessionState.of(active, now: _now(now));

  /// Nur geöffnet, nie ein Satz und schon alt (z. B. gestern): still verwerfen, damit sie nicht als laufend gilt.
  void discardAbandoned({DateTime? now}) {
    if (sessionState(now: now) != ActiveSessionState.abandoned) return;
    _setActive(null);
  }

  void update({
    required List<GymSession> sessions,
    required List<GarminActivity> activities,
    required List<DailyMetrics> days,
    GymSettings? gym,
    DateTime? now,
  }) {
    final today = CalendarDay.fromDate(_now(now));
    this.today = today;
    this.sessions = sessions;
    this.gym = gym ?? GymSettings();
    ranges = {...plan.repRanges, ...this.gym.routines.repRanges};
    // Dieselbe Ampel wie unter „Heute“.
    final state = RecoveryEvaluator.today(
      days: days,
      form: FitnessForm.seriesUntil(activities, today: today),
      today: today,
    );
    recovered = state.level == null ? null : state.level == RecoveryLevel.normal;

    // Erledigt: eigene Einheiten und Krafttrainings von Garmin.
    final doneDays = {
      for (final session in sessions) session.day,
      for (final activity in activities)
        if (activity.sport == ActivitySport.strength) ?activity.day,
    };
    final monday = today.adding(-today.weekdayIndex);
    final planned = plan.plannedDays(monday: monday, today: today, doneDays: doneDays);
    weekPlan = [
      for (final day in planned.keys.toList()..sort())
        if (plan.workout(planned[day] ?? '') case final workout?)
          (day: day, workout: workout, done: doneDays.contains(day)),
    ];
    todayWorkout = doneDays.contains(today)
        ? null
        : switch (planned[today]) {
            final key? => plan.workout(key),
            null => null,
          };

    progress = GymProgression.evaluateRanges(
      sessions: sessions,
      ranges: ranges,
      custom: this.gym.customExercises,
      today: today,
      recovered: recovered,
    );
    if (hints.isEmpty) _showFallbackHints();
    volume = MuscleVolume.setsPerGroup(sessions: sessions, today: today);
    daysSinceLegs = MuscleVolume.daysSinceLegs(sessions: sessions, today: today);
    notifyListeners();
  }

  // Laufende Einheit

  /// Startet eine Einheit aus dem Plan, vorbefüllt mit den letzten Werten bzw. der Progression.
  void startWorkout(Workout workout, {DateTime? now}) {
    final exercises = [
      for (final planned in workout.exercises)
        () {
          final rule = planned.rule;
          final suggestion = prefillPlanned(rule.id, planned: planned);
          return LoggedExercise(
            exerciseID: rule.id,
            name: planned.name,
            group: rule.group,
            sets: [
              for (var index = 0; index < math.max(planned.sets, 1); index++)
                LoggedSet(
                  reps: _at(suggestion.reps, index) ?? suggestion.reps.lastOrNull ?? 0,
                  weightKg: suggestion.weight,
                  done: false,
                ),
            ],
            restSeconds: gym.rest(
              rule.id,
              compound: gym.exercise(rule.id)?.compound ?? false,
              planned: planned.restSeconds,
            ),
          );
        }(),
    ];
    _setActive(GymSession(workoutKey: workout.key, title: workout.name, start: _now(now), exercises: exercises));
  }

  /// Startet eine eigene Routine, vorbefüllt mit den letzten Werten bzw. der Progression.
  void startRoutine(Routine routine, {DateTime? now}) {
    final exercises = [
      for (final item in routine.items)
        () {
          final info = gym.exercise(item.exerciseID);
          final suggestion = prefill(item.exerciseID, range: item.repRange, startWeight: item.weightKg);
          return LoggedExercise(
            exerciseID: item.exerciseID,
            name: item.name,
            group: info?.group ?? MuscleGroup.other,
            sets: [
              for (var index = 0; index < item.sets; index++)
                LoggedSet(
                  reps: _at(suggestion.reps, index) ?? suggestion.reps.lastOrNull ?? item.upperReps,
                  weightKg: suggestion.weight,
                  done: false,
                ),
            ],
            restSeconds: gym.rest(item.exerciseID, compound: info?.compound ?? false, planned: item.restSeconds),
          );
        }(),
    ];
    // „Supersatz mit nächster Übung“ aus der Routine: Ketten bekommen eine gemeinsame Kennung.
    String? group;
    for (final (index, item) in routine.items.indexed) {
      if (index >= exercises.length) break;
      final linked = index > 0 && routine.items[index - 1].supersetWithNext;
      if (item.supersetWithNext || linked) {
        if (!linked) group = newUuid();
        exercises[index].supersetID = group;
      } else {
        group = null;
      }
    }
    _setActive(
      GymSession(workoutKey: 'routine-${routine.id}', title: routine.name, start: _now(now), exercises: exercises),
    );
  }

  void startEmpty({DateTime? now}) =>
      _setActive(GymSession(workoutKey: null, title: 'Krafttraining', start: _now(now), exercises: []));

  static int? _at(List<int> values, int index) => index < values.length ? values[index] : null;

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

  void addExercise(ExerciseInfo exercise) {
    final session = active;
    if (session == null) return;
    final suggestion = prefillPlanned(exercise.id);
    session.exercises.add(
      LoggedExercise(
        exerciseID: exercise.id,
        name: exercise.name,
        group: exercise.group,
        sets: [
          for (var index = 0; index < 3; index++)
            LoggedSet(reps: suggestion.reps.lastOrNull ?? exercise.upperReps, weightKg: suggestion.weight, done: false),
        ],
        restSeconds: gym.rest(exercise.id, compound: exercise.compound),
      ),
    );
    _setActive(session);
  }

  /// Wiederholungen in Reserve für einen Satz. Für den gerade erledigten Satz einer Grundübung mit RIR 0–1
  /// verlängert sich die laufende Pause einmal (`RestAdvisor`).
  void setRIR(int? rir, {required int set, required String of, DateTime? now}) {
    _mutate(of, (exercise) {
      if (set < exercise.sets.length) exercise.sets[set].rir = rir;
    });
    final end = restEndsAt;
    final exercise = active?.exercises.where((exercise) => exercise.id == of).firstOrNull;
    if (lastDone?.exercise != of ||
        lastDone?.set != set ||
        _restExtended ||
        end == null ||
        !end.isAfter(_now(now)) ||
        exercise == null) {
      return;
    }
    final compound = gym.exercise(exercise.exerciseID)?.compound ?? false;
    final extra = RestAdvisor.seconds(base: restSeconds, compound: compound, rir: rir) - restSeconds;
    if (extra <= 0) return;
    _restExtended = true;
    adjustRest(extra, now: now);
  }

  // Ablauf ändern (Gerät belegt, Supersatz, Aufwärmen, Satzart)

  void moveToEnd(String exerciseID) {
    final session = active;
    if (session == null) return;
    WorkoutEdits.moveToEnd(exerciseID, session);
    if (focusExerciseID == exerciseID) focusExerciseID = null;
    _setActive(session);
  }

  void moveExercises({required Set<int> fromOffsets, required int toOffset}) {
    final session = active;
    if (session == null) return;
    WorkoutEdits.move(fromOffsets: fromOffsets, toOffset: toOffset, session: session);
    _setActive(session);
  }

  void toggleSuperset(String exerciseID) {
    final session = active;
    if (session == null) return;
    WorkoutEdits.toggleSuperset(exerciseID, session);
    _setActive(session);
  }

  /// Übung tauschen; das Gewicht kommt aus dem Verlauf der neuen Übung.
  void replace(String exerciseID, ExerciseInfo info) {
    final session = active;
    if (session == null) return;
    _rememberUndo('Übung ersetzt');
    final suggestion = prefillPlanned(info.id);
    WorkoutEdits.replace(exerciseID, info: info, weightKg: suggestion.weight, session: session);
    if (focusExerciseID == exerciseID) {
      focusExerciseID = session.exercises
          .where((exercise) => exercise.exerciseID == info.id && exercise.sets.any((set) => !set.done))
          .firstOrNull
          ?.id;
    }
    _setActive(session);
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

  void insertWarmUp(String exerciseID, {required ExperienceLevel? level}) {
    final session = active;
    final exercise = session?.exercises.where((exercise) => exercise.id == exerciseID).firstOrNull;
    if (session == null || exercise == null) return;
    WorkoutEdits.insertWarmUp(
      warmUpSteps(exercise, level: level),
      exerciseID: exerciseID,
      session: session,
    );
    _setActive(session);
  }

  void setKind(SetKind kind, {required int set, required String of}) => _mutate(of, (exercise) {
    if (set < exercise.sets.length) exercise.sets[set].kind = kind;
  });

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

  // KI-Hinweise

  /// Stillstand, Volumen und Häufigkeit je Muskel aus dem Verlauf (Regeln, ohne KI).
  List<String> get observations => GymCoach.observations(sessions: sessions, today: today);

  /// Hinweise zur Gewichtssteigerung von der KI; ohne Worker bleiben die Regeln stehen.
  Future<void> loadHints(AIClient ai, {required FitnessGoal? goal, AITrigger trigger = AITrigger.user}) async {
    if (!ai.isConfigured || isLoadingHints || progress.isEmpty) return;
    if (!ai.allows('gym_hints', trigger: trigger)) {
      _showFallbackHints();
      notifyListeners();
      return;
    }
    isLoadingHints = true;
    notifyListeners();
    try {
      final response = await ai.run(
        'gym_hints',
        input: GymHints.input(
          progress: progress,
          recovered: recovered,
          volume: volume,
          goal: goal,
          observations: observations,
        ),
        trigger: trigger,
      );
      final points = CoachingNote.points(response.output);
      if (points.isNotEmpty) {
        hints = points;
        hintSource = 'KI · ${response.model}';
        hintEvidence = ['gym.progression', ...CoachingNote.sources(response.output)];
      }
    } on Object {
      _showFallbackHints();
      hintSource = 'Regeln (KI nicht erreichbar)';
    } finally {
      isLoadingHints = false;
      notifyListeners();
    }
  }

  void _showFallbackHints() {
    hints = GymHints.fallback(progress, observations: observations);
    hintSource = 'Regeln (ohne KI)';
    hintEvidence = const ['gym.progression', 'gym.rir'];
  }

  void removeExercise(String id) {
    final session = active;
    final exercise = session?.exercises.where((exercise) => exercise.id == id).firstOrNull;
    if (session == null || exercise == null) return;
    _rememberUndo('${exercise.name} entfernt');
    session.exercises.removeWhere((exercise) => exercise.id == id);
    if (focusExerciseID == id) focusExerciseID = null;
    _setActive(session);
  }

  void addSet(String exerciseID) => _mutate(exerciseID, (exercise) {
    final last = exercise.sets.lastOrNull ?? LoggedSet(reps: 10, weightKg: 0, done: false);
    exercise.sets.add(LoggedSet(reps: last.reps, weightKg: last.weightKg, done: false));
  });

  void removeSet(int index, {required String from}) {
    _rememberUndo('Satz ${index + 1} gelöscht');
    _mutate(from, (exercise) {
      if (index < exercise.sets.length) exercise.sets.removeAt(index);
    });
  }

  void setReps(int reps, {required int set, required String of}) => _mutate(of, (exercise) {
    if (set < exercise.sets.length) exercise.sets[set].reps = math.max(0, reps);
  });

  /// Nur dieser Satz; andere Sätze behalten ihr Gewicht.
  void setWeight(double weight, {required int set, required String of}) {
    final session = active;
    final exercise = session?.exercises.where((exercise) => exercise.id == of).firstOrNull;
    if (session == null || exercise == null) return;
    final assisted = ExerciseUnits.allowsAssistance(gym.exercise(exercise.exerciseID));
    WorkoutEdits.setWeight(weight, set: set, exerciseID: of, allowsNegative: assisted, session: session);
    _setActive(session);
  }

  /// Übung überspringen: Der Ablauf geht weiter zur nächsten; offene Sätze werden nicht gespeichert.
  void skip(String exerciseID) {
    final session = active;
    final exercise = session?.exercises.where((exercise) => exercise.id == exerciseID).firstOrNull;
    if (session == null || exercise == null) return;
    _rememberUndo('${exercise.name} übersprungen');
    WorkoutEdits.setSkipped(true, exerciseID: exerciseID, session: session);
    if (focusExerciseID == exerciseID) focusExerciseID = null;
    if (WorkoutFlow.isComplete(session)) planCompleteCount += 1;
    _setActive(session);
  }

  /// Übersprungene Übung wieder aufnehmen und direkt zeigen.
  void resume(String exerciseID) {
    final session = active;
    if (session == null) return;
    WorkoutEdits.setSkipped(false, exerciseID: exerciseID, session: session);
    focusExerciseID = exerciseID;
    _setActive(session);
  }

  /// Die letzten Leistungen einer Übung als Orientierung unter der Eingabe (neueste zuerst).
  List<GymPerformance> recentPerformances(String exerciseID, {int limit = 5}) =>
      GymStats.recentPerformances(exerciseID, sessions: sessions, limit: limit);

  /// Abhaken startet die Pause; Ent-Haken lässt eine laufende Pause in Ruhe und lässt sich rückgängig machen.
  void toggleDone({required int set, required String of, DateTime? now}) {
    final exercise = active?.exercises.where((exercise) => exercise.id == of).firstOrNull;
    if (exercise == null || set >= exercise.sets.length) return;
    if (exercise.sets[set].done) {
      _rememberUndo('Satz ${set + 1} wieder offen');
      if (lastDone?.exercise == of && lastDone?.set == set) lastDone = null;
      _mutate(of, (exercise) => exercise.sets[set].done = false);
    } else {
      complete(set: set, of: of, now: now);
    }
  }

  /// „Satz erledigt“: abhaken, Pause starten, Fokus bleibt bei der Übung.
  void complete({required int set, required String of, DateTime? now}) {
    final session = active;
    final exerciseIndex = session?.exercises.indexWhere((exercise) => exercise.id == of) ?? -1;
    if (session == null || exerciseIndex < 0) return;
    final exercise = session.exercises[exerciseIndex];
    if (set >= exercise.sets.length || exercise.sets[set].done) return;
    exercise.sets[set].done = true;
    // Nach Aufwärmsätzen die Aufwärmpause aus den Einstellungen, sonst die Pause der Übung.
    final rest = exercise.sets[set].kind == SetKind.warmup ? gym.restWarmup : exercise.restSeconds;
    lastDone = (exercise: of, set: set);
    _restExtended = false;
    // Übung fertig: weiter mit der nächsten offenen ab hier; im Supersatz ohne Pause zur Partnerübung.
    final next = WorkoutFlow.afterCompleting(exerciseIndex, session);
    focusExerciseID = next.focus == null ? null : session.exercises[next.focus!].id;
    restSeconds = rest;
    final time = _now(now);
    // Letzter Satz des Plans: keine Pause, sondern die Frage „beenden oder fortsetzen“.
    if (WorkoutFlow.isComplete(session)) {
      restEndsAt = null;
      pendingRest = null;
      unawaited(_alarm?.schedule(null));
      planCompleteCount += 1;
    } else if (!next.rest || !gym.autoStartsRest) {
      // Ohne automatische Pause startet sie über „Pause starten“ (`startRest`).
      restEndsAt = null;
      unawaited(_alarm?.schedule(null));
      pendingRest = next.rest ? rest : null;
    } else {
      pendingRest = null;
      restEndsAt = time.add(Duration(seconds: rest));
    }
    _setActive(session);
    if (restEndsAt != null) unawaited(_alarm?.schedule(restEndsAt, body: nextText, sound: gym.restSound));
  }

  /// „Weiter mit Schulterdrücken“ bzw. „Weiter mit Satz 3 · Bankdrücken“ – für Pausenende und Sperrbildschirm.
  String? get nextText => switch (active) {
    final session? => WorkoutFlow.nextText(session, focus: focusExerciseID, previous: lastDone?.exercise),
    null => null,
  };

  // Halteübungen (Stoppuhr)

  void startHold({required int set, required String of, DateTime? now}) {
    // Eine laufende Pause endet mit dem Start des nächsten Satzes.
    restEndsAt = null;
    pendingRest = null;
    unawaited(_alarm?.schedule(null));
    hold = (exercise: of, set: set, start: _now(now));
    notifyListeners();
  }

  /// Stopp: gemessene Sekunden übernehmen, Satz abhaken, Pause starten. Korrektur danach über [correctHold].
  void stopHold({DateTime? now}) {
    final current = hold;
    if (current == null) return;
    hold = null;
    final time = _now(now);
    setReps(HoldTimer.seconds(current.start, time), set: current.set, of: current.exercise);
    complete(set: current.set, of: current.exercise, now: time);
  }

  void cancelHold() {
    hold = null;
    notifyListeners();
  }

  /// Zuletzt gestoppte Zeit nachträglich korrigieren (zu spät gestoppt usw.).
  void correctHold(int delta) {
    final last = lastDone;
    final exercise = active?.exercises.where((exercise) => exercise.id == last?.exercise).firstOrNull;
    if (last == null || exercise == null || last.set >= exercise.sets.length) return;
    setReps(HoldTimer.corrected(exercise.sets[last.set].reps, delta), set: last.set, of: last.exercise);
  }

  void startRest({DateTime? now}) {
    final rest = pendingRest;
    if (rest == null) return;
    pendingRest = null;
    restEndsAt = _now(now).add(Duration(seconds: rest));
    unawaited(_alarm?.schedule(restEndsAt, body: nextText, sound: gym.restSound));
    notifyListeners();
  }

  /// Pause einer Übung für diese Einheit und – in den Einstellungen gemerkt – für das nächste Mal.
  ({String exerciseID, int seconds})? setRest(int seconds, {required String of}) {
    final rest = seconds.clamp(15, RestAdvisor.maximumSeconds);
    String? key;
    _mutate(of, (exercise) {
      exercise.restSeconds = rest;
      key = exercise.exerciseID;
    });
    return key == null ? null : (exerciseID: key!, seconds: rest);
  }

  /// Nächster offener Satz wie auf der Fokus-Karte.
  FlowPosition? get currentPosition => switch (active) {
    final session? => WorkoutFlow.current(session, preferring: focusExerciseID),
    null => null,
  };

  /// „Satz erledigt“ aus der Live-Aktivität.
  void completeCurrent({DateTime? now}) {
    final position = currentPosition;
    final session = active;
    if (position == null || session == null) return;
    complete(set: position.set, of: session.exercises[position.exercise].id, now: now);
  }

  /// Gewicht bzw. Wiederholungen des aktuellen Satzes ändern (Knöpfe auf dem Sperrbildschirm).
  void adjustCurrent({int weightBy = 0, int repsBy = 0}) {
    final position = currentPosition;
    final session = active;
    if (position == null || session == null) return;
    final exercise = session.exercises[position.exercise];
    final set = exercise.sets[position.set];
    if (weightBy != 0) {
      final step = ExerciseLibrary.rule(exercise.exerciseID, name: exercise.name, custom: gym.customExercises).step;
      setWeight(set.weightKg + weightBy * step, set: position.set, of: exercise.id);
    }
    if (repsBy != 0) {
      final isTime = gym.exercise(exercise.exerciseID)?.tracking == ExerciseTracking.time;
      setReps(set.reps + repsBy * (isTime ? 5 : 1), set: position.set, of: exercise.id);
    }
  }

  void undo() {
    final session = _undoSession;
    if (session == null) return;
    _undoSession = null;
    undoLabel = null;
    _setActive(session);
  }

  void clearUndo() {
    undoLabel = null;
    _undoSession = null;
    notifyListeners();
  }

  void _rememberUndo(String label) {
    _undoSession = active?.copy();
    undoLabel = label;
  }

  void skipRest() {
    restEndsAt = null;
    unawaited(_alarm?.schedule(null));
    notifyListeners();
  }

  /// Pause bei geöffneter Einheit abgelaufen. Das Signal kommt nur pünktlich: War die App im Hintergrund, hat dort
  /// schon die Mitteilung geklingelt, und beim Zurückkehren soll es nicht noch einmal tönen.
  void restFinished(DateTime end, {DateTime? now}) {
    restEndsAt = null;
    unawaited(_alarm?.schedule(null));
    if (_now(now).difference(end) < const Duration(seconds: 2)) {
      restFinishedCount += 1;
      unawaited(_sound?.play(gym.restSound));
    }
    notifyListeners();
  }

  /// ±15 s während der Pause: gilt für die laufende Pause, die weiteren Sätze dieser Übung und – über den
  /// Rückgabewert, den die Ansicht in den Einstellungen speichert – für das nächste Mal.
  ({String exerciseID, int seconds})? adjustRestAndRemember(int seconds, {DateTime? now}) {
    adjustRest(seconds, now: now);
    final last = lastDone;
    final session = active;
    final index = session?.exercises.indexWhere((exercise) => exercise.id == last?.exercise) ?? -1;
    if (last == null || session == null || index < 0) return null;
    final rest = (session.exercises[index].restSeconds + seconds).clamp(15, RestAdvisor.maximumSeconds);
    session.exercises[index].restSeconds = rest;
    _setActive(session);
    return (exerciseID: session.exercises[index].exerciseID, seconds: rest);
  }

  /// Laufende Pause verlängern oder verkürzen (z. B. ±15 Sekunden).
  void adjustRest(int seconds, {DateTime? now}) {
    final end = restEndsAt;
    if (end == null) return;
    final adjusted = end.add(Duration(seconds: seconds));
    restEndsAt = adjusted.isAfter(_now(now)) ? adjusted : null;
    restSeconds = math.max(0, restSeconds + seconds);
    unawaited(_alarm?.schedule(restEndsAt, body: nextText, sound: gym.restSound));
    notifyListeners();
  }

  void cancelActive() {
    _resetFlow();
    unawaited(_alarm?.schedule(null));
    _setActive(null);
  }

  void _resetFlow() {
    restEndsAt = null;
    pendingRest = null;
    hold = null;
    lastDone = null;
    focusExerciseID = null;
    undoLabel = null;
    _undoSession = null;
  }

  /// Nach dem Abschluss-Bildschirm.
  void dismissFinished() {
    finished = null;
    notifyListeners();
  }

  /// Speichert die Einheit lokal und – wenn möglich – in Apple Health / Health Connect und bei Garmin.
  Future<GymSession?> finish({
    required GymRepository repository,
    required WorkoutSaving writer,
    GarminStrengthService? strength,
    GarminConnectSession? garmin,
    bool completingOpenSets = false,
    DateTime? now,
  }) async {
    final current = active;
    if (current == null) return null;
    final time = _now(now);
    var session = current.copy();
    if (completingOpenSets) session = WorkoutFlow.completingOpenSets(session);
    session.exercises = [
      for (final exercise in session.exercises)
        if (exercise.loggedSets.isNotEmpty) exercise..sets = exercise.loggedSets,
    ];
    if (session.doneSetCount <= 0) {
      message = 'Noch kein Satz abgehakt – nichts zu speichern.';
      notifyListeners();
      return null;
    }
    session.end = time;
    // Garmin: erst die Aufzeichnung der Uhr suchen und dort die Sätze ergänzen (`GarminStrengthService`). Immer
    // vormerken, wenn der Abgleich an ist – auch ohne Anmeldung gerade jetzt; der nächste Abruf holt es nach.
    final syncsGarmin = gym.uploadsToGarmin;
    if (syncsGarmin) session.garmin = GarminLink(status: GarminLinkStatus.pending, updatedAt: time);
    isSaving = true;
    notifyListeners();
    try {
      await repository.save(session);
    } on Object catch (error) {
      message = 'Speichern fehlgeschlagen: $error';
      isSaving = false;
      notifyListeners();
      return null;
    }
    final records = GymStats.newRecords(session, before: sessions);
    // Erst die Zusammenfassung, dann die laufende Einheit leeren: Health und Garmin können Sekunden dauern.
    final summary = FinishedWorkout(
      title: session.title,
      summary: WorkoutFlow.summary(session, now: time),
      records: records,
      status: 'Gespeichert. Apple Health und Garmin werden abgeglichen …',
      exerciseIDs: [for (final exercise in session.exercises) exercise.exerciseID],
      muscles: MuscleLoad.session(session, custom: gym.customExercises),
      volumeChange: SessionComparison.volumeChangePercent(
        session,
        previous: SessionComparison.previous(session, sessions: sessions),
      ),
      share: WorkoutShare.gym(session, records: records, now: time),
      shareKeys: ['g${session.id}'],
    );
    finished = summary;
    _resetFlow();
    unawaited(_alarm?.schedule(null));
    _setActive(null);
    var status = await saveToHealth(session, repository: repository, writer: writer);
    final garminStatus = syncsGarmin && garmin != null && garmin.isLoggedIn && strength != null
        ? await strength.reconcile(garmin: garmin, gym: gym, now: time)
        : null;
    if (garminStatus != null) {
      status += '\n$garminStatus';
    } else if (syncsGarmin && (garmin == null || !garmin.isLoggedIn)) {
      status += '\nGarmin: wird übertragen, sobald du mit dem Garmin-Konto angemeldet bist (Einstellungen).';
    }
    summary.status = status;
    message = records.isEmpty ? status : '🏆 ${records.join('\n🏆 ')}\n\n$status';
    isSaving = false;
    notifyListeners();
    return session;
  }

  /// Gibt eine Meldung für die Anzeige zurück.
  static Future<String> saveToHealth(
    GymSession session, {
    required GymRepository repository,
    required WorkoutSaving writer,
  }) async {
    if (!await writer.isAvailable) return 'Gespeichert. Apple Health ist auf diesem Gerät nicht verfügbar.';
    try {
      await writer.save(session);
      await repository.setSavedToHealth(session.id, value: true);
      return 'Gespeichert und in Apple Health eingetragen.';
    } on Object catch (error) {
      return 'Gespeichert. Apple Health: $error';
    }
  }

  // Hilfen

  void _mutate(String exerciseID, void Function(LoggedExercise exercise) change) {
    final session = active;
    final exercise = session?.exercises.where((exercise) => exercise.id == exerciseID).firstOrNull;
    if (session == null || exercise == null) return;
    change(exercise);
    _setActive(session);
  }

  void _setActive(GymSession? session) {
    active = session;
    unawaited(_store.setJson(activeKey, session?.toJson()));
    notifyListeners();
  }

  /// Verlauf einer Übung je Tag (Höchstgewicht, geschätztes 1RM, Sätze).
  List<GymStatsPoint> history(String exerciseID) => GymStats.history(exerciseID, sessions: sessions);
}
