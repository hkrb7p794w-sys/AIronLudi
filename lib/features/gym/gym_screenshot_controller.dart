import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/settings/coach_settings.dart';
import '../../services/ai/ai_client.dart';

/// Krafttraining von Screenshots übernehmen (WHOOP Strength Trainer, Hevy, Strong …): Bilder an die KI (Aufgabe
/// `gym_import`), Ergebnis als Gym-Einheit zum Prüfen, dann sichern. WHOOP gibt Übungen, Sätze und Gewichte über
/// seine Schnittstelle nicht heraus – das ist der Weg, sie trotzdem in die App zu bekommen.
final class GymScreenshotController extends ChangeNotifier {
  GymScreenshotController({
    required this._ai,
    required this._gym,
    required this._settings,
    required this._activities,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AIClient _ai;
  final GymRepository _gym;
  final CoachSettings _settings;
  final Future<List<GarminActivity>> Function() _activities;
  final DateTime Function() _clock;

  static const task = 'gym_import';

  /// Höchstens so viele Bilder je Anfrage (Grenze des Workers).
  static const maxImages = 4;

  bool isWorking = false;
  String? errorMessage;

  /// Abgelesene Einheit zum Prüfen; `null` vor der Auswertung.
  GymSession? session;

  /// Übungen, die beim Sichern neu als eigene Übungen angelegt werden.
  List<ExerciseInfo> newCustom = [];

  /// Tag und Uhrzeit standen nicht auf den Bildern: bitte prüfen.
  bool guessedDate = false;

  /// Schon gespeicherte Einheiten am selben Tag (Hinweis, nichts wird überschrieben außer demselben Import).
  List<String> sameDay = [];

  List<Uint8List> _images = [];

  bool get isAvailable => _ai.allows(task);

  /// Bilder auswerten; [images] sind schon verkleinert (ohne Metadaten).
  Future<void> analyze(List<Uint8List> images) async {
    if (images.isEmpty || isWorking) return;
    _images = images.take(maxImages).toList();
    await retry();
  }

  /// Dieselben Bilder noch einmal auswerten (KI überlastet o. Ä.).
  Future<void> retry() async {
    if (_images.isEmpty || isWorking) return;
    isWorking = true;
    errorMessage = null;
    notifyListeners();
    try {
      final custom = _settings.gym.customExercises;
      final response = await _ai.run(
        task,
        input: {'library': GymScreenshotImport.library(custom: custom)},
        images: [for (final image in _images) AIImage(mimeType: 'image/jpeg', data: image)],
      );
      final workout = ImportedWorkout.fromOutput(response.output);
      if (workout == null) throw const AIClientError.http(200, 'Auf den Bildern wurden keine Übungen erkannt.');
      final today = CalendarDay.fromDate(_clock());
      final day = workout.dayIn(today);
      guessedDate = day == null || workout.startMinutes == null;
      final resolved = day ?? today;
      final recorded = await _strengthActivity(resolved);
      final times = GymScreenshotImport.times(
        workout,
        day: resolved,
        fallbackStart: recorded?.start,
        fallbackEnd: recorded?.end,
      );
      final result = GymScreenshotImport.session(workout, start: times.start, end: times.end, custom: custom);
      session = result.session;
      newCustom = result.newCustom;
      await _checkSameDay();
    } on Object catch (error) {
      errorMessage = error is AIClientError ? error.message : '$error';
    } finally {
      isWorking = false;
      notifyListeners();
    }
  }

  /// Krafttraining derselben Tages aus WHOOP, Garmin oder Health: liefert Beginn und Ende, wenn der Screenshot keine
  /// Uhrzeit zeigt.
  Future<({DateTime start, DateTime end})?> _strengthActivity(CalendarDay day) async {
    final candidates = [
      for (final activity in await _activities())
        if (activity.day == day && activity.sport == ActivitySport.strength) activity,
    ];
    for (final activity in candidates) {
      final start = HealthImport.date(activity.startLocal ?? '');
      final seconds = activity.durationSeconds ?? activity.elapsedSeconds;
      if (start != null && seconds != null && seconds > 0) {
        return (start: start, end: start.add(Duration(seconds: seconds.round())));
      }
    }
    return null;
  }

  Future<void> _checkSameDay() async {
    final current = session;
    if (current == null) return;
    sameDay = [
      for (final stored in await _gym.all())
        if (stored.session.day == current.day && stored.session.id != current.id) stored.session.title,
    ];
  }

  /// Anderer Tag oder Beginn; die Dauer bleibt.
  Future<void> moveTo(DateTime start) async {
    final current = session;
    if (current == null) return;
    final duration = (current.end ?? current.start.add(const Duration(hours: 1))).difference(current.start);
    current
      ..start = start
      ..end = start.add(duration);
    guessedDate = false;
    await _checkSameDay();
    notifyListeners();
  }

  void rename(String title) {
    session?.title = title.trim().isEmpty ? 'Krafttraining' : title.trim();
  }

  void removeExercise(LoggedExercise exercise) {
    session?.exercises.remove(exercise);
    notifyListeners();
  }

  void removeSet(LoggedExercise exercise, LoggedSet set) {
    exercise.sets.remove(set);
    if (exercise.sets.isEmpty) session?.exercises.remove(exercise);
    notifyListeners();
  }

  void updateSet(LoggedSet set, {required int reps, required double weightKg}) {
    set
      ..reps = reps
      ..weightKg = weightKg;
    notifyListeners();
  }

  /// Sichern: Kennung aus dem Beginn (derselbe Import ersetzt sich), neue Übungen nur, wenn sie noch vorkommen.
  /// Liefert eine kurze Bestätigung.
  Future<String?> save() async {
    final current = session;
    if (current == null || current.exercises.isEmpty) return null;
    final key = GymScreenshotImport.workoutKey(current.start);
    current
      ..workoutKey = key
      ..id = GymBookImport.stableID(key);
    final used = {for (final exercise in current.exercises) exercise.exerciseID};
    final added = [
      for (final info in newCustom)
        if (used.contains(info.id) && !_settings.gym.customExercises.any((known) => known.id == info.id)) info,
    ];
    if (added.isNotEmpty) {
      _settings.gym = _settings.gym..customExercises = [..._settings.gym.customExercises, ...added];
    }
    await _gym.save(current);
    return '${current.title} übernommen: ${current.exercises.length} Übungen, ${current.doneSetCount} Sätze.';
  }
}
