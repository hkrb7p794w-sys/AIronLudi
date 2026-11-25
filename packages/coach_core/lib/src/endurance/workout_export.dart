import 'dart:convert';
import 'dart:typed_data';

import '../calendar/calendar_day.dart';
import '../fit/fit_encoder.dart';
import '../garmin/garmin_workout.dart';
import '../util/fnv.dart';
import 'endurance_plan.dart';
import 'training_load.dart';

/// Gemeinsame Hilfen der Exporte.
abstract final class WorkoutExport {
  /// Fingerabdruck des Inhalts: ändert er sich, wird das Workout im Garmin-Kalender ersetzt.
  static String fingerprint(EnduranceWorkout workout, CalendarDay day) =>
      fnv1a64Text('${day.iso}|${jsonEncode(workout.toJson())}').toRadixString(16);

  /// Dateiname ohne Endung („2026-11-20-rad-schwelle-4x10-min“).
  static String fileName(EnduranceWorkout workout, CalendarDay day) {
    final base = '${day.iso}-${workout.title}'
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss')
        .replaceAll('×', 'x')
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    return base.length > 60 ? base.substring(0, 60) : base;
  }

  /// Ausführbare Schritte in Reihenfolge, Wiederholungen ausgeschrieben (für die Vorschau).
  static List<String> summary(EnduranceWorkout workout) {
    String size(EnduranceStep step) {
      if (step.meters case final meters?) return '$meters m';
      final seconds = step.seconds ?? 0;
      return seconds % 60 == 0 ? '${seconds ~/ 60} min' : '$seconds s';
    }

    String target(EnduranceStep step) => switch (step.target.kind) {
      TargetKind.pace =>
        workout.sport == EnduranceSport.swim
            ? '${_clock(step.target.low)}–${_clock(step.target.high)} /100 m'
            : '${_clock(step.target.low)}–${_clock(step.target.high)} /km',
      TargetKind.power => '${step.target.low}–${step.target.high} W',
      TargetKind.heartRate => '${step.target.low}–${step.target.high} bpm',
      TargetKind.open => step.zone.label,
    };

    String label(EnduranceStep step) {
      final kind = switch (step.kind) {
        WorkoutStepKind.warmup => 'Aufwärmen',
        WorkoutStepKind.interval => 'Belastung',
        WorkoutStepKind.recovery => 'Erholung',
        WorkoutStepKind.cooldown => 'Ausklang',
      };
      return '$kind ${size(step)} · ${target(step)}';
    }

    return [
      for (final block in workout.steps)
        switch (block) {
          EnduranceStep() => label(block),
          EnduranceRepeat(:final count, :final steps) => '$count × (${steps.map(label).join(' / ')})',
        },
    ];
  }

  static String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Rad-Workout für Zwift (`.zwo`, Zwift Workout XML). Leistung als Anteil der FTP, daher auch ohne bekannte FTP
/// richtig: Zwift setzt die eigene FTP ein. Die Datei kommt in `Dokumente/Zwift/Workouts/<Zwift-ID>/` – eine
/// offizielle Schnittstelle zum direkten Übertragen bietet Zwift nicht.
abstract final class ZwiftWorkoutFile {
  static bool supports(EnduranceWorkout workout) => workout.sport == EnduranceSport.bike && !workout.isRest;

  static String xml(EnduranceWorkout workout, {String author = 'AIronLudi'}) {
    if (!supports(workout)) throw ArgumentError('Zwift-Export gibt es nur für Rad-Einheiten.');
    final buffer = StringBuffer()
      ..writeln('<workout_file>')
      ..writeln('    <author>${_escape(author)}</author>')
      ..writeln('    <name>${_escape(workout.title)}</name>')
      ..writeln('    <description>${_escape(_description(workout))}</description>')
      ..writeln('    <sportType>bike</sportType>')
      ..writeln('    <tags>')
      ..writeln('        <tag name="${_escape(workout.type.label)}"/>')
      ..writeln('    </tags>')
      ..writeln('    <workout>');
    for (final block in workout.steps) {
      switch (block) {
        case EnduranceStep():
          buffer.writeln('        ${_step(block)}');
        case EnduranceRepeat(:final count, :final steps):
          if (steps.length == 2 && steps.every((step) => step.seconds != null)) {
            final on = steps[0];
            final off = steps[1];
            buffer.writeln(
              '        <IntervalsT Repeat="$count" OnDuration="${on.seconds}" OffDuration="${off.seconds}" '
              'OnPower="${_power(on.zone)}" OffPower="${_power(off.zone)}"/>',
            );
          } else {
            for (var index = 0; index < count; index++) {
              for (final step in steps) {
                buffer.writeln('        ${_step(step)}');
              }
            }
          }
      }
    }
    buffer
      ..writeln('    </workout>')
      ..writeln('</workout_file>');
    return buffer.toString();
  }

  static String _description(EnduranceWorkout workout) =>
      [workout.summary, if (workout.note.isNotEmpty) workout.note].join(' – ');

  static String _step(EnduranceStep step) {
    final seconds = step.seconds ?? 0;
    return switch (step.kind) {
      WorkoutStepKind.warmup =>
        '<Warmup Duration="$seconds" PowerLow="0.45" PowerHigh="${_power(step.zone, high: true)}"/>',
      WorkoutStepKind.cooldown =>
        '<Cooldown Duration="$seconds" PowerLow="${_power(step.zone, high: true)}" PowerHigh="0.45"/>',
      _ => '<SteadyState Duration="$seconds" Power="${_power(step.zone)}"/>',
    };
  }

  /// Mitte (bzw. Obergrenze) der Zone als Anteil der FTP mit zwei Nachkommastellen.
  static String _power(IntensityZone zone, {bool high = false}) {
    final (low, top) = EnduranceZones.bikePower[zone]!;
    final value = high ? top : (low + top) / 2;
    return value.toStringAsFixed(2);
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Workout als FIT-Datei (Dateityp „workout“, FIT-SDK-Profil 21.x: `file_id` 0, `workout` 26, `workout_step` 27).
/// Kompatible Uhren übernehmen sie per USB in `GARMIN/NEWFILES` bzw. über Apps, die FIT-Workouts importieren.
abstract final class FitWorkoutFile {
  static const fileTypeWorkout = 5;

  static int sport(EnduranceSport sport) => switch (sport) {
    EnduranceSport.run => 1,
    EnduranceSport.bike => 2,
    EnduranceSport.swim => 5,
  };

  static Uint8List bytes(EnduranceWorkout workout, {required DateTime created}) {
    if (workout.isRest) throw ArgumentError('Ein Ruhetag lässt sich nicht als Einheit exportieren.');
    final encoder = FitEncoder();
    final stamp = FitEncoder.timestamp(created);
    encoder.add(
      global: 0,
      fields: [
        const FitField(0, FitBaseType.enumeration, fileTypeWorkout),
        const FitField(1, FitBaseType.uint16, 255), // Hersteller: development
        const FitField(2, FitBaseType.uint16, 1),
        FitField(3, FitBaseType.uint32z, stamp == 0 ? 1 : stamp),
        FitField(4, FitBaseType.uint32, stamp),
      ],
    );
    final steps = <List<FitField>>[];
    void addStep(EnduranceStep step) {
      final index = steps.length;
      final (durationType, durationValue) = switch ((step.seconds, step.meters)) {
        (_, final int meters) => (1, meters * 100), // Strecke in cm
        (final int seconds, _) => (0, seconds * 1000), // Zeit in ms
        _ => (5, 0), // offen (Runden-Taste)
      };
      final intensity = switch (step.kind) {
        WorkoutStepKind.warmup => 2,
        WorkoutStepKind.cooldown => 3,
        WorkoutStepKind.recovery => step.isPause ? 1 : 4,
        WorkoutStepKind.interval => 0,
      };
      final (targetType, low, high) = switch (step.target.kind) {
        TargetKind.pace => (0, _speed(workout.sport, step.target.high), _speed(workout.sport, step.target.low)),
        TargetKind.heartRate => (1, step.target.low + 100, step.target.high + 100),
        TargetKind.power => (4, step.target.low + 1000, step.target.high + 1000),
        TargetKind.open => (2, 0, 0),
      };
      steps.add([
        FitField(254, FitBaseType.uint16, index),
        FitField(1, FitBaseType.enumeration, durationType),
        FitField(2, FitBaseType.uint32, durationValue),
        FitField(3, FitBaseType.enumeration, targetType),
        const FitField(4, FitBaseType.uint32, 0),
        FitField(5, FitBaseType.uint32, low),
        FitField(6, FitBaseType.uint32, high),
        FitField(7, FitBaseType.enumeration, intensity),
        if (step.note.isNotEmpty) FitField.text(8, step.note, size: 48),
      ]);
    }

    for (final block in workout.steps) {
      switch (block) {
        case EnduranceStep():
          addStep(block);
        case EnduranceRepeat(:final count, steps: final inner):
          final first = steps.length;
          inner.forEach(addStep);
          steps.add([
            FitField(254, FitBaseType.uint16, steps.length),
            const FitField(1, FitBaseType.enumeration, 6), // repeat_until_steps_cmplt
            FitField(2, FitBaseType.uint32, first),
            FitField(4, FitBaseType.uint32, count),
          ]);
      }
    }
    encoder.add(
      global: 26,
      fields: [
        FitField(4, FitBaseType.enumeration, sport(workout.sport)),
        FitField(6, FitBaseType.uint16, steps.length),
        FitField.text(8, workout.title, size: 32),
        if (workout.sport == EnduranceSport.swim) ...[
          const FitField(14, FitBaseType.uint16, GarminWorkout.poolLengthMeters * 100),
          const FitField(15, FitBaseType.enumeration, 0),
        ],
      ],
    );
    for (final fields in steps) {
      encoder.add(global: 27, fields: fields);
    }
    return encoder.data();
  }

  /// Geschwindigkeit in mm/s (FIT-Skala 1000) aus der Pace (s/km bzw. s/100 m).
  static int _speed(EnduranceSport sport, int pace) {
    if (pace <= 0) return 0;
    final metersPerSecond = (sport == EnduranceSport.swim ? 100 : 1000) / pace;
    return (metersPerSecond * 1000).round();
  }
}

/// Workout für den Garmin-Connect-Kalender (`workout-service`, Format wie [GarminWorkout.payload]) – mit Zielen je
/// Schritt: Pace (m/s), Leistung (W) oder Puls (bpm). Schwimmziele stehen als Notiz am Schritt.
abstract final class GarminEnduranceWorkout {
  static Map<String, Object?> payload(EnduranceWorkout workout) {
    if (workout.isRest) throw ArgumentError('Ein Ruhetag lässt sich nicht senden.');
    final sport = workout.sport.workoutSport;
    var order = 0;
    var groups = 0;

    Map<String, Object?> executable(EnduranceStep step, int? child) {
      order += 1;
      final type = switch (step.kind) {
        WorkoutStepKind.warmup => GarminWorkout.stepType(1, 'warmup'),
        WorkoutStepKind.cooldown => GarminWorkout.stepType(2, 'cooldown'),
        WorkoutStepKind.interval => GarminWorkout.stepType(3, 'interval'),
        WorkoutStepKind.recovery =>
          step.isPause ? GarminWorkout.stepType(5, 'rest') : GarminWorkout.stepType(4, 'recovery'),
      };
      final note = [
        if (step.note.isNotEmpty) step.note,
        if (workout.sport == EnduranceSport.swim || step.target.kind == TargetKind.open) step.zone.label,
        if (workout.sport == EnduranceSport.swim && step.target.kind == TargetKind.pace)
          'Pace ${_clock(step.target.low)}–${_clock(step.target.high)} /100 m',
      ].join(' · ');
      final result = <String, Object?>{
        'type': 'ExecutableStepDTO',
        'stepOrder': order,
        'stepType': type,
        'childStepId': ?child,
        if (note.isNotEmpty) 'description': note.length > 250 ? note.substring(0, 250) : note,
      };
      if (step.meters case final meters?) {
        result['endCondition'] = GarminWorkout.condition(3, 'distance');
        result['endConditionValue'] = meters;
        result['preferredEndConditionUnit'] = GarminWorkout.meter;
      } else if (step.seconds case final seconds?) {
        result['endCondition'] = GarminWorkout.condition(2, 'time');
        result['endConditionValue'] = seconds;
      } else {
        result['endCondition'] = GarminWorkout.condition(1, 'lap.button');
      }
      final target = workout.sport == EnduranceSport.swim ? const StepTarget.open() : step.target;
      switch (target.kind) {
        case TargetKind.pace:
          result['targetType'] = _targetType(6, 'pace.zone');
          result['targetValueOne'] = _metersPerSecond(target.high);
          result['targetValueTwo'] = _metersPerSecond(target.low);
        case TargetKind.power:
          result['targetType'] = _targetType(2, 'power.zone');
          result['targetValueOne'] = target.low;
          result['targetValueTwo'] = target.high;
        case TargetKind.heartRate:
          result['targetType'] = _targetType(4, 'heart.rate.zone');
          result['targetValueOne'] = target.low;
          result['targetValueTwo'] = target.high;
        case TargetKind.open:
          result['targetType'] = GarminWorkout.noTarget;
      }
      return result;
    }

    final steps = <Map<String, Object?>>[];
    for (final block in workout.steps) {
      switch (block) {
        case EnduranceStep():
          steps.add(executable(block, null));
        case EnduranceRepeat(:final count, steps: final inner):
          order += 1;
          final current = order;
          groups += 1;
          final group = groups;
          steps.add({
            'type': 'RepeatGroupDTO',
            'stepOrder': current,
            'stepType': GarminWorkout.stepType(6, 'repeat'),
            'childStepId': group,
            'numberOfIterations': count,
            'endCondition': GarminWorkout.condition(7, 'iterations', displayable: false),
            'endConditionValue': count,
            'smartRepeat': false,
            'skipLastRestStep': true,
            'workoutSteps': [for (final step in inner) executable(step, group)],
          });
      }
    }
    final description = [workout.summary, if (workout.note.isNotEmpty) workout.note].join(' – ');
    final segment = <String, Object?>{'segmentOrder': 1, 'sportType': sport.json, 'workoutSteps': steps};
    final root = <String, Object?>{
      'workoutName': workout.title.length > 80 ? workout.title.substring(0, 80) : workout.title,
      'description': description.length > 1000 ? description.substring(0, 1000) : description,
      'sportType': sport.json,
    };
    if (workout.sport == EnduranceSport.swim) {
      segment['poolLength'] = GarminWorkout.poolLengthMeters;
      root['poolLength'] = GarminWorkout.poolLengthMeters;
      segment['poolLengthUnit'] = GarminWorkout.meter;
      root['poolLengthUnit'] = GarminWorkout.meter;
    }
    root['workoutSegments'] = [segment];
    return root;
  }

  static Map<String, Object?> _targetType(int id, String key) => {
    'workoutTargetTypeId': id,
    'workoutTargetTypeKey': key,
    'displayOrder': id,
  };

  /// Pace (s/km) als Geschwindigkeit in m/s mit drei Nachkommastellen.
  static double _metersPerSecond(int pace) => pace <= 0 ? 0 : (1000 / pace * 1000).round() / 1000;

  static String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
