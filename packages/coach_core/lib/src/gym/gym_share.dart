import 'dart:convert';
import 'dart:math' as math;

import '../util/german_format.dart';
import '../util/text_prefix.dart';
import 'exercise_library.dart';
import 'gym_session.dart';
import 'routine.dart';
import 'workout_edits.dart';

/// Einheit über das Teilen-Menü des Systems weitergeben: lesbarer Text und ein Link `coach://routine/<daten>`, über den
/// jemand mit AIronLudi die Übungen als eigene Routine übernimmt. Ohne Server, ohne Konto; bewusst ohne Körperwerte
/// (Puls, Gewicht, Kalorien) und ohne RIR.
abstract final class GymShareText {
  /// Abgeschlossene Einheit: Datum, Dauer, je Übung die erledigten Sätze („3 × 8 · 60 kg“).
  static String session(GymSession session, {required List<ExerciseInfo> custom, DateTime? now}) {
    final end = session.end ?? now ?? DateTime.now();
    final minutes = math.max(1, end.difference(session.start).inMinutes);
    final day = session.start.toLocal();
    final title = session.title.isEmpty ? 'Krafttraining' : session.title;
    final lines = <String>[
      '🏋️ $title – ${_date(day)}',
      '$minutes min · ${session.doneSetCount} Sätze'
          '${session.volumeKg > 0 ? ' · ${GermanFormat.number(session.volumeKg.roundToDouble())} kg bewegt' : ''}',
      '',
    ];
    for (final exercise in session.exercises) {
      final sets = exercise.doneSets;
      if (sets.isEmpty) continue;
      lines.add('• ${exercise.name}: ${_sets(sets, exerciseID: exercise.exerciseID, custom: custom)}');
    }
    final link = RoutineLink.fromSession(session);
    if (link != null) lines.addAll(['', 'Als Routine in AIronLudi übernehmen:', link]);
    return lines.join('\n');
  }

  /// Geplante Einheit (Routine): je Übung Sätze, Wiederholungsbereich und – falls hinterlegt – Gewicht.
  static String routine(Routine routine, {required List<ExerciseInfo> custom}) {
    final lines = <String>['🏋️ ${routine.name.isEmpty ? 'Routine' : routine.name}', ''];
    for (final item in routine.items) {
      final info = ExerciseLibrary.info(item.exerciseID, custom: custom);
      final isTime = info?.tracking == ExerciseTracking.time;
      final unit = ExerciseUnits.repsUnit(item.exerciseID, isTime: isTime);
      final reps = item.lowerReps == item.upperReps ? '${item.lowerReps}' : '${item.lowerReps}–${item.upperReps}';
      final weight = switch (item.weightKg) {
        final kg? when kg != 0 => () {
          final text = ExerciseUnits.weightText(kg, info: info);
          return ' · ${text.value}${text.unit.isEmpty ? '' : ' ${text.unit}'}';
        }(),
        _ => '',
      };
      lines.add('• ${item.name}: ${item.sets} × $reps $unit$weight${item.supersetWithNext ? ' (Supersatz)' : ''}');
    }
    lines.addAll(['', 'In AIronLudi übernehmen:', RoutineLink.encode(routine)]);
    return lines.join('\n');
  }

  /// Gleiche Sätze zusammengefasst: „3 × 8 · 60 kg, 1 × 6 · 65 kg“.
  static String _sets(List<LoggedSet> sets, {required String exerciseID, required List<ExerciseInfo> custom}) {
    final info = ExerciseLibrary.info(exerciseID, custom: custom);
    final isTime = info?.tracking == ExerciseTracking.time;
    final unit = isTime ? ' s' : '';
    final groups = <({int reps, double kg, int count})>[];
    for (final set in sets) {
      final last = groups.lastOrNull;
      if (last != null && last.reps == set.reps && last.kg == set.weightKg) {
        groups[groups.length - 1] = (reps: last.reps, kg: last.kg, count: last.count + 1);
      } else {
        groups.add((reps: set.reps, kg: set.weightKg, count: 1));
      }
    }
    return [
      for (final group in groups)
        () {
          final weight = ExerciseUnits.weightText(group.kg, info: info);
          final kg = group.kg == 0 ? '' : ' · ${weight.value}${weight.unit.isEmpty ? '' : ' ${weight.unit}'}';
          return '${group.count} × ${group.reps}$unit$kg';
        }(),
    ].join(', ');
  }

  static String _date(DateTime day) =>
      '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
}

/// Routine als Link `coach://routine/<base64url(JSON)>`. Kurzes JSON (`n` Name, `i` Übungen als Liste
/// `[exerciseID, Name, Sätze, untere Wdh., obere Wdh., Pause s, Gewicht kg?, Supersatz?]`), damit der Link in eine
/// Nachricht passt. Beim Übernehmen bekommt alles neue Kennungen.
abstract final class RoutineLink {
  static const prefix = 'coach://routine/';

  /// Mehr Übungen nimmt der Link nicht auf (Länge bleibt unter etwa 2000 Zeichen).
  static const maxItems = 20;

  static String encode(Routine routine) {
    final json = {
      'n': textPrefix(routine.name, 60),
      'i': [
        for (final item in routine.items.take(maxItems))
          [
            item.exerciseID,
            textPrefix(item.name, 60),
            item.sets,
            item.lowerReps,
            item.upperReps,
            item.restSeconds,
            item.weightKg,
            if (item.supersetWithNext) 1,
          ],
      ],
    };
    return '$prefix${base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '')}';
  }

  /// Routine aus einer Einheit: Übungen mit erledigten Sätzen, Wiederholungsbereich aus den Sätzen, Gewicht des
  /// schwersten Satzes. `null` ohne erledigte Sätze.
  static String? fromSession(GymSession session) {
    final items = <RoutineItem>[];
    for (final exercise in session.exercises) {
      final sets = exercise.doneSets;
      if (sets.isEmpty) continue;
      final reps = [for (final set in sets) set.reps];
      final heaviest = sets.map((set) => set.weightKg).reduce(math.max);
      items.add(
        RoutineItem(
          exerciseID: exercise.exerciseID,
          name: exercise.name,
          sets: sets.length,
          lowerReps: reps.reduce(math.min),
          upperReps: reps.reduce(math.max),
          restSeconds: exercise.restSeconds,
          weightKg: heaviest == 0 ? null : heaviest,
        ),
      );
    }
    if (items.isEmpty) return null;
    return encode(Routine(name: session.title.isEmpty ? 'Krafttraining' : session.title, items: items));
  }

  /// Routine aus `coach://routine/<daten>`; `null` bei allem Unlesbaren. Werte werden begrenzt.
  static Routine? decode(String link) {
    final trimmed = link.trim();
    if (!trimmed.startsWith(prefix)) return null;
    var data = trimmed.substring(prefix.length);
    final end = data.indexOf(RegExp('[?#/]'));
    if (end >= 0) data = data.substring(0, end);
    if (data.isEmpty || data.length > 8000) return null;
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(data))));
      if (json is! Map || json['i'] is! List) return null;
      final name = json['n'] is String ? textPrefix((json['n'] as String).trim(), 60) : '';
      final items = <RoutineItem>[];
      for (final raw in (json['i'] as List).take(maxItems)) {
        if (raw is! List || raw.length < 6) return null;
        final [id, title, sets, lower, upper, rest, ...more] = raw;
        if (id is! String || title is! String || sets is! int || lower is! int || upper is! int || rest is! int) {
          return null;
        }
        if (id.isEmpty || id.length > 80 || title.trim().isEmpty) return null;
        final weight = more.isNotEmpty && more.first is num ? (more.first as num).toDouble() : null;
        items.add(
          RoutineItem(
            exerciseID: id,
            name: textPrefix(title.trim(), 60),
            sets: sets.clamp(1, 20),
            lowerReps: lower.clamp(1, 600),
            upperReps: upper.clamp(1, 600),
            restSeconds: rest.clamp(0, 900),
            weightKg: weight != null && weight.isFinite && weight.abs() <= 1000 ? weight : null,
            supersetWithNext: more.length > 1 && more[1] == 1,
          ),
        );
      }
      if (items.isEmpty) return null;
      return Routine(name: name.isEmpty ? 'Geteilte Routine' : name, items: items);
    } on Object {
      return null;
    }
  }
}
