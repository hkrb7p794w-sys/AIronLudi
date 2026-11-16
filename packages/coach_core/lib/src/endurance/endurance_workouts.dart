import 'dart:math' as math;

import '../garmin/garmin_workout.dart';
import 'endurance_plan.dart';
import 'training_load.dart';

/// Baut strukturierte Einheiten (Aufwärmen, Hauptteil bzw. Intervalle mit Ziel-Pace/-Watt/-Puls, Ausklang) aus Art,
/// Disziplin und Dauer. Deterministisch: gleiche Eingaben ergeben dieselbe Einheit.
abstract final class EnduranceWorkouts {
  static EnduranceWorkout build({
    required EnduranceSport sport,
    required EnduranceWorkoutType type,
    required int minutes,
    required AthleteThresholds thresholds,
    EndurancePhase phase = EndurancePhase.base,
    EnduranceEvent? event,
    String note = '',
  }) {
    if (type == EnduranceWorkoutType.rest) {
      return EnduranceWorkout(
        sport: sport,
        type: type,
        title: 'Ruhetag',
        minutes: 0,
        steps: const [],
        load: 0,
        note: note,
      );
    }
    final steps = sport == EnduranceSport.swim
        ? _swim(type, minutes, thresholds, event)
        : _timed(sport, type, minutes, thresholds, phase, event);
    final seconds = _totalSeconds(steps, sport, thresholds);
    final meters = sport == EnduranceSport.swim ? _totalMeters(steps) : null;
    return EnduranceWorkout(
      sport: sport,
      type: type,
      title: _title(sport, type, steps, event),
      minutes: (seconds / 60).round(),
      meters: meters,
      steps: steps,
      load: TrainingLoad.planned(steps, sport, thresholds),
      note: note,
    );
  }

  static EnduranceStep _step(
    WorkoutStepKind kind,
    IntensityZone zone,
    EnduranceSport sport,
    AthleteThresholds thresholds, {
    int? seconds,
    int? meters,
    String note = '',
  }) => EnduranceStep(
    kind: kind,
    zone: zone,
    seconds: seconds,
    meters: meters,
    target: EnduranceZones.target(sport, zone, thresholds),
    note: note,
  );

  static int _round5(double minutes) => math.max(5, (minutes / 5).round() * 5);

  /// Rennzone nach Wettkampfdauer: kurz an der Schwelle, mittel im Tempobereich, lang in der Grundlage.
  static IntensityZone raceZone(EnduranceEvent? event, int minutes) {
    if (minutes <= 60) return IntensityZone.threshold;
    if (minutes <= 150) return IntensityZone.tempo;
    return IntensityZone.endurance;
  }

  static List<EnduranceBlock> _timed(
    EnduranceSport sport,
    EnduranceWorkoutType type,
    int minutes,
    AthleteThresholds thresholds,
    EndurancePhase phase,
    EnduranceEvent? event,
  ) {
    EnduranceStep step(WorkoutStepKind kind, IntensityZone zone, int minutes, {String note = ''}) =>
        _step(kind, zone, sport, thresholds, seconds: minutes * 60, note: note);
    final warmup = sport == EnduranceSport.bike ? 15 : 12;
    switch (type) {
      case EnduranceWorkoutType.rest:
        return const [];
      case EnduranceWorkoutType.recovery:
        return [step(WorkoutStepKind.interval, IntensityZone.recovery, math.max(15, minutes), note: 'Ganz locker')];
      case EnduranceWorkoutType.endurance:
        if (minutes < 30) return [step(WorkoutStepKind.interval, IntensityZone.endurance, minutes)];
        return [
          step(WorkoutStepKind.warmup, IntensityZone.recovery, 10),
          step(WorkoutStepKind.interval, IntensityZone.endurance, minutes - 15, note: 'Gleichmäßig, Nasenatmung'),
          step(WorkoutStepKind.cooldown, IntensityZone.recovery, 5),
        ];
      case EnduranceWorkoutType.long:
        final main = math.max(20, minutes - 15);
        // In der Spitzenphase das letzte Drittel im Wettkampftempo (Lauf-Halbmarathon/Marathon, Langdistanz).
        final specific = phase == EndurancePhase.peak && main >= 60;
        return [
          step(WorkoutStepKind.warmup, IntensityZone.recovery, 10),
          if (specific) ...[
            step(WorkoutStepKind.interval, IntensityZone.endurance, _round5(main * 2 / 3)),
            step(
              WorkoutStepKind.interval,
              IntensityZone.tempo,
              main - _round5(main * 2 / 3),
              note: 'Im Wettkampftempo',
            ),
          ] else
            step(WorkoutStepKind.interval, IntensityZone.endurance, main, note: 'Gleichmäßig, Verpflegung üben'),
          step(WorkoutStepKind.cooldown, IntensityZone.recovery, 5),
        ];
      case EnduranceWorkoutType.tempo:
        final work = math.max(10, minutes - warmup - 10);
        final count = ((work + 3) ~/ 13).clamp(2, 4);
        final block = ((work + 3) ~/ count - 3).clamp(5, 10);
        return [
          step(WorkoutStepKind.warmup, IntensityZone.endurance, warmup),
          EnduranceRepeat(count, [
            step(WorkoutStepKind.interval, IntensityZone.tempo, block, note: 'Kontrolliert zügig'),
            step(WorkoutStepKind.recovery, IntensityZone.recovery, 3),
          ]),
          step(WorkoutStepKind.cooldown, IntensityZone.recovery, 10),
        ];
      case EnduranceWorkoutType.threshold:
        final (on, off) = sport == EnduranceSport.bike ? (10, 3) : (8, 2);
        final work = math.max(on + off, minutes - warmup - 10);
        final count = (work ~/ (on + off)).clamp(2, 6);
        return [
          step(WorkoutStepKind.warmup, IntensityZone.endurance, warmup),
          EnduranceRepeat(count, [
            step(WorkoutStepKind.interval, IntensityZone.threshold, on, note: 'An der Schwelle'),
            step(WorkoutStepKind.recovery, IntensityZone.recovery, off),
          ]),
          step(WorkoutStepKind.cooldown, IntensityZone.recovery, 10),
        ];
      case EnduranceWorkoutType.vo2max:
        final work = math.max(6, minutes - warmup - 10);
        final count = (work ~/ 6).clamp(3, 8);
        return [
          step(WorkoutStepKind.warmup, IntensityZone.endurance, warmup),
          EnduranceRepeat(count, [
            step(WorkoutStepKind.interval, IntensityZone.vo2max, 3, note: 'Hart, aber gleichmäßig'),
            step(WorkoutStepKind.recovery, IntensityZone.recovery, 3),
          ]),
          step(WorkoutStepKind.cooldown, IntensityZone.recovery, 10),
        ];
      case EnduranceWorkoutType.race:
        return [step(WorkoutStepKind.interval, raceZone(event, minutes), math.max(10, minutes), note: 'Wettkampf')];
    }
  }

  static int _meters(double meters) => math.max(50, (meters / 50).round() * 50);

  static List<EnduranceBlock> _swim(
    EnduranceWorkoutType type,
    int minutes,
    AthleteThresholds thresholds,
    EnduranceEvent? event,
  ) {
    const sport = EnduranceSport.swim;
    double metersFor(IntensityZone zone, double minutes) =>
        minutes * 60 / EnduranceZones.pace(sport, zone, thresholds) * 100;
    EnduranceStep swim(WorkoutStepKind kind, IntensityZone zone, int meters, {String note = ''}) =>
        _step(kind, zone, sport, thresholds, meters: meters, note: note);
    EnduranceStep pause(int seconds) => _step(
      WorkoutStepKind.recovery,
      IntensityZone.recovery,
      sport,
      thresholds,
      seconds: seconds,
      note: EnduranceStep.pauseNote,
    );
    final warmup = swim(WorkoutStepKind.warmup, IntensityZone.recovery, 300, note: 'Einschwimmen, gemischt');
    final cooldown = swim(WorkoutStepKind.cooldown, IntensityZone.recovery, 200, note: 'Ausschwimmen');
    final mainMinutes = math.max(10.0, minutes - 12.0);
    switch (type) {
      case EnduranceWorkoutType.rest:
        return const [];
      case EnduranceWorkoutType.recovery:
        return [
          swim(
            WorkoutStepKind.interval,
            IntensityZone.recovery,
            _meters(metersFor(IntensityZone.recovery, minutes.toDouble())),
            note: 'Technik, locker',
          ),
        ];
      case EnduranceWorkoutType.endurance || EnduranceWorkoutType.long:
        final total = metersFor(IntensityZone.endurance, mainMinutes);
        final count = math.max(1, (total / 400).round());
        return [
          warmup,
          EnduranceRepeat(count, [
            swim(WorkoutStepKind.interval, IntensityZone.endurance, 400, note: 'Gleichmäßig'),
            pause(20),
          ]),
          cooldown,
        ];
      case EnduranceWorkoutType.tempo:
        final count = math.max(2, (metersFor(IntensityZone.tempo, mainMinutes) / 300).round().clamp(2, 8));
        return [
          warmup,
          EnduranceRepeat(count, [swim(WorkoutStepKind.interval, IntensityZone.tempo, 300), pause(30)]),
          cooldown,
        ];
      case EnduranceWorkoutType.threshold:
        final count = (metersFor(IntensityZone.threshold, mainMinutes * 0.85) / 200).round().clamp(3, 12);
        return [
          warmup,
          EnduranceRepeat(count, [
            swim(WorkoutStepKind.interval, IntensityZone.threshold, 200, note: 'CSS-Tempo'),
            pause(20),
          ]),
          cooldown,
        ];
      case EnduranceWorkoutType.vo2max:
        final count = (metersFor(IntensityZone.vo2max, mainMinutes * 0.7) / 100).round().clamp(4, 16);
        return [
          warmup,
          EnduranceRepeat(count, [
            swim(WorkoutStepKind.interval, IntensityZone.vo2max, 100, note: 'Schnell'),
            pause(20),
          ]),
          cooldown,
        ];
      case EnduranceWorkoutType.race:
        final zone = raceZone(event, minutes);
        return [swim(WorkoutStepKind.interval, zone, _meters(metersFor(zone, minutes.toDouble())), note: 'Wettkampf')];
    }
  }

  static int _totalSeconds(List<EnduranceBlock> steps, EnduranceSport sport, AthleteThresholds thresholds) {
    var total = 0;
    for (final block in steps) {
      total += switch (block) {
        EnduranceStep() => EnduranceZones.seconds(block, sport, thresholds),
        EnduranceRepeat(:final count, steps: final inner) =>
          count * inner.fold(0, (sum, step) => sum + EnduranceZones.seconds(step, sport, thresholds)),
      };
    }
    return total;
  }

  static int _totalMeters(List<EnduranceBlock> steps) {
    var total = 0;
    for (final block in steps) {
      total += switch (block) {
        EnduranceStep(:final meters) => meters ?? 0,
        EnduranceRepeat(:final count, steps: final inner) =>
          count * inner.fold(0, (sum, step) => sum + (step.meters ?? 0)),
      };
    }
    return total;
  }

  static String _title(
    EnduranceSport sport,
    EnduranceWorkoutType type,
    List<EnduranceBlock> steps,
    EnduranceEvent? event,
  ) {
    if (type == EnduranceWorkoutType.race) return event?.label ?? 'Wettkampf';
    final repeat = steps.whereType<EnduranceRepeat>().firstOrNull;
    if (repeat != null && type.isHard) {
      final work = repeat.steps.first;
      final size = work.meters != null ? '${work.meters} m' : '${(work.seconds ?? 0) ~/ 60} min';
      return '${sport.label} ${type.label} ${repeat.count}×$size';
    }
    return '${sport.label} ${type.label}';
  }
}
