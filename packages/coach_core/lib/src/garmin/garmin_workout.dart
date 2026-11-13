import '../calendar/calendar_day.dart';
import '../json/json_value.dart';
import '../plan/season_schedule.dart';
import '../profile/user_profile.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';

String _prefix(String text, int count) => String.fromCharCodes(text.runes.take(count));

/// Sportart eines Garmin-Workouts.
enum WorkoutSport implements RawEnum {
  run,
  bike,
  swim;

  @override
  String get rawValue => name;

  static WorkoutSport? of(TrainingSport sport) => switch (sport) {
    TrainingSport.run => run,
    TrainingSport.bike => bike,
    TrainingSport.swim => swim,
    TrainingSport.strength || TrainingSport.other => null,
  };

  Map<String, Object?> get json => switch (this) {
    run => {'sportTypeId': 1, 'sportTypeKey': 'running', 'displayOrder': 1},
    bike => {'sportTypeId': 2, 'sportTypeKey': 'cycling', 'displayOrder': 2},
    swim => {'sportTypeId': 4, 'sportTypeKey': 'swimming', 'displayOrder': 3},
  };
}

/// Ende eines Schritts: Zeit, Strecke oder Runden-Taste.
sealed class WorkoutEnd {
  const WorkoutEnd();
}

final class EndSeconds extends WorkoutEnd {
  const EndSeconds(this.seconds);

  final int seconds;

  @override
  bool operator ==(Object other) => other is EndSeconds && other.seconds == seconds;

  @override
  int get hashCode => seconds.hashCode;

  @override
  String toString() => 'EndSeconds($seconds)';
}

final class EndMeters extends WorkoutEnd {
  const EndMeters(this.meters);

  final int meters;

  @override
  bool operator ==(Object other) => other is EndMeters && other.meters == meters;

  @override
  int get hashCode => meters.hashCode;

  @override
  String toString() => 'EndMeters($meters)';
}

final class EndLapButton extends WorkoutEnd {
  const EndLapButton();

  @override
  bool operator ==(Object other) => other is EndLapButton;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'EndLapButton()';
}

/// Art eines ausführbaren Schritts.
enum WorkoutStepKind { warmup, interval, recovery, cooldown }

/// Ein Schritt des Workouts.
sealed class WorkoutStep {
  const WorkoutStep();
}

/// Aufwärmen, Belastung, Erholung oder Ausklang.
final class ExecutableStep extends WorkoutStep {
  const ExecutableStep(this.kind, this.end, {this.note = ''});

  const ExecutableStep.warmup(this.end, {this.note = ''}) : kind = WorkoutStepKind.warmup;
  const ExecutableStep.interval(this.end, {this.note = ''}) : kind = WorkoutStepKind.interval;
  const ExecutableStep.recovery(this.end, {this.note = ''}) : kind = WorkoutStepKind.recovery;
  const ExecutableStep.cooldown(this.end, {this.note = ''}) : kind = WorkoutStepKind.cooldown;

  final WorkoutStepKind kind;
  final WorkoutEnd end;
  final String note;

  @override
  bool operator ==(Object other) =>
      other is ExecutableStep && other.kind == kind && other.end == end && other.note == note;

  @override
  int get hashCode => Object.hash(kind, end, note);

  @override
  String toString() => 'ExecutableStep($kind, $end, $note)';
}

final class RestStep extends WorkoutStep {
  const RestStep(this.seconds);

  final int seconds;

  @override
  bool operator ==(Object other) => other is RestStep && other.seconds == seconds;

  @override
  int get hashCode => seconds.hashCode;

  @override
  String toString() => 'RestStep($seconds)';
}

final class RepeatStep extends WorkoutStep {
  const RepeatStep(this.count, this.steps);

  final int count;
  final List<WorkoutStep> steps;

  @override
  bool operator ==(Object other) =>
      other is RepeatStep &&
      other.count == count &&
      other.steps.length == steps.length &&
      Iterable<int>.generate(steps.length).every((index) => other.steps[index] == steps[index]);

  @override
  int get hashCode => Object.hash(count, Object.hashAll(steps));

  @override
  String toString() => 'RepeatStep($count, $steps)';
}

/// Ein Workout zum Senden an die Uhr.
final class WorkoutPlan {
  const WorkoutPlan({required this.name, required this.sport, required this.description, required this.steps});

  final String name;
  final WorkoutSport sport;
  final String description;
  final List<WorkoutStep> steps;
}

/// Wiederholungen aus dem Plantext.
final class WorkoutRepeats {
  const WorkoutRepeats({required this.count, required this.work, this.recoverySeconds});

  final int count;
  final WorkoutEnd work;
  final int? recoverySeconds;

  @override
  bool operator ==(Object other) =>
      other is WorkoutRepeats && other.count == count && other.work == work && other.recoverySeconds == recoverySeconds;

  @override
  int get hashCode => Object.hash(count, work, recoverySeconds);
}

/// Einheit als strukturiertes Garmin-Workout für die Uhr – auf Wunsch je Einheit, nie automatisch. Gleiches Format
/// wie die Schwimm-Workouts des Home-Assistant-Add-ons (`garmin_swim.py`, Feldnamen von Garmin Connect,
/// `workout-service`): anlegen (`POST /workout-service/workout`), dann im Kalender einplanen
/// (`POST /workout-service/schedule/{id}`). Inoffizielle Schnittstelle: Garmin kann sie jederzeit ändern.
abstract final class GarminWorkout {
  static const poolLengthMeters = 25;
  static const createPath = '/workout-service/workout';

  static String schedulePath(int workoutID) => '/workout-service/schedule/$workoutID';

  static String workoutPath(int workoutID) => '/workout-service/workout/$workoutID';

  // Aus dem Plantext

  /// Liest den Plantext („4×2 km @ 4:20 /km, 90 s Trab“, „50 min Zone 2“, „16 km locker“) in Schritte. Was sich
  /// nicht lesen lässt, wird ein Schritt bis zur Runden-Taste mit dem Text als Notiz – die Uhr zeigt ihn an.
  static WorkoutPlan plan({required String name, required WorkoutSport sport, required String text}) {
    final note = _prefix(text, 250);
    final description = _prefix(text, 1000);
    if (repeatsPattern(text) case final repeats?) {
      return WorkoutPlan(
        name: name,
        sport: sport,
        description: description,
        steps: [
          const ExecutableStep.warmup(EndLapButton(), note: 'Einlaufen bzw. Einrollen'),
          RepeatStep(repeats.count, [
            ExecutableStep.interval(repeats.work, note: note),
            if (repeats.recoverySeconds case final recovery?) ExecutableStep.recovery(EndSeconds(recovery)),
          ]),
          const ExecutableStep.cooldown(EndLapButton(), note: 'Auslaufen'),
        ],
      );
    }
    if (firstNumber(text, unit: 'min') case final minutes?) {
      return WorkoutPlan(
        name: name,
        sport: sport,
        description: description,
        steps: [ExecutableStep.interval(EndSeconds((minutes * 60).round()), note: note)],
      );
    }
    if (firstNumber(text, unit: 'km') case final kilometers?) {
      return WorkoutPlan(
        name: name,
        sport: sport,
        description: description,
        steps: [ExecutableStep.interval(EndMeters((kilometers * 1000).round()), note: note)],
      );
    }
    return WorkoutPlan(
      name: name,
      sport: sport,
      description: description,
      steps: [ExecutableStep.interval(const EndLapButton(), note: note)],
    );
  }

  static double? _number(String text) => double.tryParse(text.replaceAll(',', '.'));

  /// „N×M km|min|m|s“ und optional „, P s|min Trab/locker/Pause“ danach.
  static WorkoutRepeats? repeatsPattern(String text) {
    final match = RegExp(r'(\d+)\s*[×x]\s*(\d+(?:[.,]\d+)?)\s*(km|min|m|s)\b').firstMatch(text);
    if (match == null) return null;
    final count = int.tryParse(match.group(1)!);
    final value = _number(match.group(2)!);
    if (count == null || count <= 1 || count > 50 || value == null) return null;
    final WorkoutEnd work = switch (match.group(3)) {
      'km' => EndMeters((value * 1000).round()),
      'm' => EndMeters(value.round()),
      'min' => EndSeconds((value * 60).round()),
      _ => EndSeconds(value.round()),
    };
    final rest = text.substring(match.end);
    int? recovery;
    final pause = RegExp(r'(\d+(?:[.,]\d+)?)\s*(s|min)\s*(Trab|locker|Pause|Gehpause|lockeres)').firstMatch(rest);
    if (pause != null) {
      if (_number(pause.group(1)!) case final number?) {
        recovery = (pause.group(2) == 'min' ? number * 60 : number).round();
      }
    }
    return WorkoutRepeats(count: count, work: work, recoverySeconds: recovery);
  }

  /// Erste Zahl vor der Einheit („50 min“, „16 km“); Bereiche wie „60–75 min“ ergeben die untere Grenze.
  static double? firstNumber(String text, {required String unit}) {
    final match = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:[–-]\s*\d+(?:[.,]\d+)?\s*)?'
      '$unit'
      r'\b',
    ).firstMatch(text);
    return match == null ? null : _number(match.group(1)!);
  }

  /// Schwimmeinheit aus den Schritten des Saisonplans (Strecke, Pause, Erholung bis zur Taste, Wiederholung).
  static WorkoutPlan swimPlan({required String name, required String text, required List<SwimStep> steps}) {
    List<WorkoutStep> convert(List<SwimStep> steps) => [
      for (final step in steps)
        switch (step.t) {
          'rep' => RepeatStep(step.n ?? 1, convert(step.steps ?? const [])),
          'rest' => RestStep(step.s ?? 0),
          'rec' => ExecutableStep.recovery(const EndLapButton(), note: step.note ?? ''),
          'warmup' => ExecutableStep.warmup(_meters(step.m), note: step.note ?? ''),
          'cool' => ExecutableStep.cooldown(_meters(step.m), note: step.note ?? ''),
          _ => ExecutableStep.interval(_meters(step.m), note: step.note ?? ''),
        },
    ];
    return WorkoutPlan(name: name, sport: WorkoutSport.swim, description: _prefix(text, 1000), steps: convert(steps));
  }

  static WorkoutEnd _meters(int? meters) => meters == null ? const EndLapButton() : EndMeters(meters);

  /// Kurzfassung der Schritte für die Vorschau vor dem Senden.
  static List<String> summary(List<WorkoutStep> steps) {
    String end(WorkoutEnd end) => switch (end) {
      EndSeconds(:final seconds) => seconds % 60 == 0 ? '${seconds ~/ 60} min' : '$seconds s',
      EndMeters(:final meters) =>
        meters >= 1000 && meters % 100 == 0 ? '${GermanFormat.decimal(meters / 1000)} km' : '$meters m',
      EndLapButton() => 'bis Runden-Taste',
    };
    return [
      for (final step in steps)
        switch (step) {
          ExecutableStep(kind: WorkoutStepKind.warmup, end: final value) => 'Aufwärmen: ${end(value)}',
          ExecutableStep(kind: WorkoutStepKind.cooldown, end: final value) => 'Ausklang: ${end(value)}',
          ExecutableStep(kind: WorkoutStepKind.interval, end: final value) => 'Belastung: ${end(value)}',
          ExecutableStep(kind: WorkoutStepKind.recovery, end: final value) => 'Erholung: ${end(value)}',
          RestStep(:final seconds) => 'Pause: $seconds s',
          RepeatStep(:final count, steps: final inner) => '$count × (${summary(inner).join(', ')})',
        },
    ];
  }

  // Garmin-JSON (Zahlen als ganze Zahlen, wo Swift ganzzahlige `Double` als `1` statt `1.0` schreibt)

  static Map<String, Object?> payload(WorkoutPlan plan) {
    var order = 0;
    var groups = 0;
    List<Map<String, Object?>> encode(List<WorkoutStep> steps, int? child) {
      final result = <Map<String, Object?>>[];
      for (final step in steps) {
        order += 1;
        final current = order;
        switch (step) {
          case RepeatStep(:final count, steps: final inner):
            groups += 1;
            final group = groups;
            final children = encode(inner, group);
            result.add({
              'type': 'RepeatGroupDTO',
              'stepOrder': current,
              'stepType': stepType(6, 'repeat'),
              'childStepId': group,
              'numberOfIterations': count,
              'endCondition': condition(7, 'iterations', displayable: false),
              'endConditionValue': count,
              'smartRepeat': false,
              'skipLastRestStep': true,
              'workoutSteps': children,
            });
          case RestStep(:final seconds):
            result.add(
              executable(order: current, child: child, type: stepType(5, 'rest'), end: null, restSeconds: seconds),
            );
          case ExecutableStep(:final kind, :final end, :final note):
            final type = switch (kind) {
              WorkoutStepKind.warmup => stepType(1, 'warmup'),
              WorkoutStepKind.cooldown => stepType(2, 'cooldown'),
              WorkoutStepKind.interval => stepType(3, 'interval'),
              WorkoutStepKind.recovery => stepType(4, 'recovery'),
            };
            result.add(executable(order: current, child: child, type: type, end: end, note: note));
        }
      }
      return result;
    }

    final steps = encode(plan.steps, null);
    final segment = <String, Object?>{'segmentOrder': 1, 'sportType': plan.sport.json, 'workoutSteps': steps};
    final root = <String, Object?>{
      'workoutName': _prefix(plan.name, 80),
      'description': plan.description,
      'sportType': plan.sport.json,
    };
    if (plan.sport == WorkoutSport.swim) {
      segment['poolLength'] = poolLengthMeters;
      root['poolLength'] = poolLengthMeters;
      segment['poolLengthUnit'] = meter;
      root['poolLengthUnit'] = meter;
    }
    root['workoutSegments'] = [segment];
    return root;
  }

  static const Map<String, Object?> meter = {'unitId': 1, 'unitKey': 'meter', 'factor': 100};
  static const Map<String, Object?> noTarget = {
    'workoutTargetTypeId': 1,
    'workoutTargetTypeKey': 'no.target',
    'displayOrder': 1,
  };

  static Map<String, Object?> stepType(int id, String key) => {
    'stepTypeId': id,
    'stepTypeKey': key,
    'displayOrder': id,
  };

  static Map<String, Object?> condition(int id, String key, {bool displayable = true}) => {
    'conditionTypeId': id,
    'conditionTypeKey': key,
    'displayOrder': id,
    'displayable': displayable,
  };

  static Map<String, Object?> executable({
    required int order,
    required int? child,
    required Map<String, Object?> type,
    required WorkoutEnd? end,
    int? restSeconds,
    String note = '',
  }) {
    final step = <String, Object?>{
      'type': 'ExecutableStepDTO',
      'stepOrder': order,
      'stepType': type,
      'targetType': noTarget,
      'childStepId': ?child,
      if (note.isNotEmpty) 'description': _prefix(note, 250),
    };
    if (restSeconds != null) {
      step['endCondition'] = condition(8, 'fixed.rest');
      step['endConditionValue'] = restSeconds;
    } else {
      switch (end ?? const EndLapButton()) {
        case EndSeconds(:final seconds):
          step['endCondition'] = condition(2, 'time');
          step['endConditionValue'] = seconds;
        case EndMeters(:final meters):
          step['endCondition'] = condition(3, 'distance');
          step['endConditionValue'] = meters;
          step['preferredEndConditionUnit'] = meter;
        case EndLapButton():
          step['endCondition'] = condition(1, 'lap.button');
      }
    }
    return step;
  }

  /// `workoutId` aus der Antwort von Garmin.
  static int? workoutID(JsonValue response) => response['workoutId']?.doubleValue?.toInt();

  static Map<String, Object?> scheduleBody(CalendarDay day) => {'date': day.iso};
}

/// Gesendete Workouts (je Einheit und Tag), damit erneutes Senden das alte Workout ersetzt statt zu verdoppeln.
final class SentWorkouts {
  SentWorkouts({Map<String, int>? ids}) : ids = ids ?? {};

  Map<String, int> ids;

  static String key({required String name, required CalendarDay day}) => '${day.iso}|$name';

  /// Einträge älter als 60 Tage fallen weg.
  void prune(CalendarDay today) {
    final cutoff = today.adding(-60).iso;
    ids = {
      for (final entry in ids.entries)
        if (_prefix(entry.key, 10).compareTo(cutoff) >= 0) entry.key: entry.value,
    };
  }

  Map<String, Object?> toJson() => {'ids': ids};

  static SentWorkouts? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['ids'];
    if (raw is! Map) return null;
    final ids = <String, int>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! num) return null;
      ids[entry.key as String] = value.toInt();
    }
    return SentWorkouts(ids: ids);
  }
}
