import 'dart:convert';

import 'package:collection/collection.dart';

import '../gym/exercise_library.dart';
import '../gym/gym_coach.dart';
import '../gym/routine.dart';
import '../json/json_value.dart';
import '../profile/schedule_check.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import '../util/enum_codec.dart';
import '../util/text_prefix.dart';

enum RoutineMode implements RawEnum {
  add('ergaenzen'),
  replace('ersetzen');

  const RoutineMode(this.rawValue);

  @override
  final String rawValue;
}

enum ScheduleScope implements RawEnum {
  permanent('dauerhaft'),
  nextWeek('naechste_woche');

  const ScheduleScope(this.rawValue);

  @override
  final String rawValue;
}

/// Vorschau eines Imports, bevor etwas übernommen wird.
final class ImportPreview {
  ImportPreview();

  List<Routine> routines = [];
  RoutineMode routineMode = RoutineMode.add;
  WeekSchedule? schedule;
  ScheduleScope scheduleScope = ScheduleScope.permanent;
  List<String> notes = [];

  /// Was die Regeln geändert oder verworfen haben.
  List<String> corrections = [];

  /// Hinweise der Regeln zum Ergebnis (z. B. Wochenvolumen, Plan-Prüfung).
  List<String> ruleNotes = [];

  bool get isEmpty => routines.isEmpty && schedule == null && notes.isEmpty;
}

/// Fehler beim Lesen der KI-Antwort.
enum ImportError implements Exception {
  noBlock(
    'Kein Block ```ironludi … ``` gefunden. Bitte die ganze Antwort der KI einfügen; das Format steht oben in der '
    'Export-Datei.',
  ),
  invalidJSON('Der ironludi-Block ist kein gültiges JSON.');

  const ImportError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Was mit einer vorgeschlagenen Routine passiert.
enum RoutineChoice implements RawEnum {
  /// Gleichnamige bestehende Routine überschreiben.
  replace('Bestehende ersetzen'),

  /// Zusätzlich anlegen; bestehende bleiben unverändert.
  add('Zusätzlich anlegen'),

  /// Nicht übernehmen.
  skip('Nicht übernehmen');

  const RoutineChoice(this.label);

  final String label;

  @override
  String get rawValue => name;

  String get id => rawValue;
}

/// Entscheidung der Person, was aus dem Vorschlag übernommen wird.
final class ImportSelection {
  ImportSelection();

  Map<String, RoutineChoice> routines = {};

  /// Alle bisherigen Routinen löschen und nur die übernommenen behalten.
  bool replaceAllRoutines = false;
  bool schedule = true;
  ScheduleScope scheduleScope = ScheduleScope.permanent;

  /// Tage, deren Vorschlag übernommen wird (die anderen bleiben wie bisher).
  Set<Weekday> scheduleDays = {};

  /// Indizes der übernommenen Hinweise.
  Set<int> notes = {};

  /// Vorschlag: gleichnamige Routinen ersetzen, neue hinzufügen; Wochenplan und Hinweise wie von der KI.
  static ImportSelection defaults(
    ImportPreview preview, {
    required List<Routine> existing,
    WeekSchedule? currentSchedule,
  }) {
    final selection = ImportSelection();
    final names = {for (final routine in existing) routine.name};
    for (final routine in preview.routines) {
      selection.routines[routine.id] = names.contains(routine.name) ? RoutineChoice.replace : RoutineChoice.add;
    }
    selection
      ..replaceAllRoutines = preview.routineMode == RoutineMode.replace
      ..schedule = preview.schedule != null
      ..scheduleScope = preview.scheduleScope;
    if (preview.schedule case final schedule?) {
      selection.scheduleDays = CoachImport.changedDays(schedule, from: currentSchedule ?? WeekSchedule()).toSet();
    }
    selection.notes = {for (var index = 0; index < preview.notes.length; index++) index};
    return selection;
  }

  RoutineChoice choice(Routine routine) => routines[routine.id] ?? RoutineChoice.add;
}

/// Import der Antwort einer externen KI (ChatGPT, Gemini, Claude) aus dem Format, das `CoachExport` vorgibt: ein
/// Codeblock ```ironludi … ``` mit JSON. Die KI schlägt vor, die Regeln prüfen: nur bekannte Übungen der eigenen
/// Ausstattung, Grenzen für Sätze, Wiederholungen, Pausen und Gewicht, Wochenvolumen; Wochenplan nur im eigenen
/// Plan. Nichts wird übernommen, bevor die Vorschau bestätigt ist.
abstract final class CoachImport {
  static JsonValue? _parse(String text) {
    try {
      return JsonValue(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  /// JSON aus dem ersten ```ironludi-Block, sonst aus einem ```json- oder unbenannten Block mit passenden Schlüsseln.
  /// Wirft [ImportError].
  static JsonValue block(String text) {
    final blocks = <({String tag, String body})>[];
    var rest = text.replaceAll('\r\n', '\n');
    while (true) {
      final open = rest.indexOf('```');
      if (open < 0) break;
      final afterFence = rest.substring(open + 3);
      final lineEnd = afterFence.indexOf('\n');
      if (lineEnd < 0) break;
      final body = afterFence.substring(lineEnd + 1);
      final close = body.indexOf('```');
      if (close < 0) break;
      blocks.add((tag: afterFence.substring(0, lineEnd).trim().toLowerCase(), body: body.substring(0, close)));
      rest = body.substring(close + 3);
    }
    final tagged = blocks.firstWhereOrNull((block) => block.tag == 'ironludi');
    if (tagged != null) return _parse(tagged.body) ?? (throw ImportError.invalidJSON);
    for (final block in blocks) {
      if (block.tag != 'json' && block.tag.isNotEmpty) continue;
      final json = _parse(block.body);
      if (json != null && (json['routinen'] != null || json['wochenplan'] != null || json['hinweise'] != null)) {
        return json;
      }
    }
    throw ImportError.noBlock;
  }

  /// Wirft [ImportError].
  static ImportPreview preview(
    String text, {
    required UserProfile profile,
    required Set<Equipment> equipment,
    required List<ExerciseInfo> custom,
  }) {
    final json = block(text);
    final preview = ImportPreview();

    final routines = json['routinen'];
    if (routines != null) {
      preview.routineMode = enumFromRaw(RoutineMode.values, routines['modus']?.stringValue ?? '') ?? RoutineMode.add;
      final list = routines['liste']?.arrayValue ?? routines.arrayValue ?? const <JsonValue>[];
      final weights = <String, double>{};
      final normalized = [
        for (final raw in list)
          if (raw.raw case final Map<dynamic, dynamic> routine)
            {
              ...routine.cast<String, Object?>(),
              'uebungen': [
                for (final entry in raw['uebungen']?.arrayValue ?? const <JsonValue>[])
                  if (entry.raw case final Map<dynamic, dynamic> item)
                    () {
                      final id = resolve(entry['id']?.stringValue ?? entry['name']?.stringValue ?? '', custom: custom);
                      final weight = entry['gewicht']?.doubleValue;
                      if (weight != null && weight >= 0 && weight <= 500) weights[id] = weight;
                      return {...item.cast<String, Object?>(), 'id': id};
                    }()
                  else
                    entry.raw,
              ],
            }
          else
            raw.raw,
      ];
      final request = PlanRequest()
        ..daysPerWeek = 10
        ..minutesPerSession = 120;
      final checked = GymCoach.validatePlan(
        JsonValue({'routinen': normalized}),
        request: request,
        equipment: equipment,
        custom: custom,
        lastWeights: weights,
      );
      preview
        ..routines = checked.routines
        ..corrections.addAll(checked.corrections)
        ..ruleNotes.addAll(checked.notes);
    }

    final plan = json['wochenplan'];
    if (plan != null) {
      if (profile.mode == ProfileMode.season) {
        preview.corrections.add('Wochenplan ignoriert: Im Saisonplan stehen die Tage fest.');
      } else {
        preview.scheduleScope =
            enumFromRaw(ScheduleScope.values, plan['gilt_fuer']?.stringValue ?? '') ?? ScheduleScope.permanent;
        var schedule = profile.schedule;
        const keys = ['mo', 'di', 'mi', 'do', 'fr', 'sa', 'so'];
        for (var index = 0; index < keys.length; index++) {
          final entries = plan['tage']?[keys[index]]?.arrayValue;
          if (entries == null) continue;
          final weekday = Weekday.values[index];
          final slots = <SessionSlot>[];
          for (final entry in entries.take(3)) {
            final sport = _sport(entry['sport']?.stringValue);
            if (sport == null) {
              preview.corrections.add('${weekday.long}: Sportart „${entry['sport']?.stringValue ?? '?'}“ unbekannt.');
              continue;
            }
            slots.add(SessionSlot(sport, _intensity(entry['intensitaet']?.stringValue)));
          }
          schedule = schedule.withSlots(slots, weekday);
        }
        preview.schedule = schedule;
        final planned = {
          for (final weekday in Weekday.values)
            for (final slot in schedule.slots(weekday)) slot.sport,
        };
        final missing = planned.difference(profile.sports.toSet()).toList()
          ..sort((a, b) => a.rawValue.compareTo(b.rawValue));
        for (final sport in missing) {
          preview.ruleNotes.add('${sport.label} steht im Plan, ist aber nicht in deinem Profil gewählt.');
        }
        preview.ruleNotes.addAll(ScheduleCheck.hints(schedule, profile).map((hint) => hint.message));
      }
    }

    preview.notes = [for (final note in json['hinweise']?.arrayValue ?? const <JsonValue>[]) ?note.stringValue]
        .take(10)
        .map((note) => textPrefix(note, 400))
        .toList();
    return preview;
  }

  /// ID aus der Bibliothek; sonst Übung gleichen Namens (Groß-/Kleinschreibung egal).
  static String resolve(String text, {required List<ExerciseInfo> custom}) {
    final trimmed = text.trim();
    if (ExerciseLibrary.info(trimmed, custom: custom) != null) return trimmed;
    final lower = trimmed.toLowerCase();
    return [
          ...ExerciseLibrary.all,
          ...custom,
        ].firstWhereOrNull((exercise) => exercise.name.toLowerCase() == lower)?.id ??
        trimmed;
  }

  static TrainingSport? _sport(String? text) => switch (text?.toLowerCase() ?? '') {
    'run' || 'laufen' || 'lauf' => TrainingSport.run,
    'bike' || 'rad' || 'radfahren' => TrainingSport.bike,
    'swim' || 'schwimmen' => TrainingSport.swim,
    'strength' || 'kraft' || 'krafttraining' || 'gym' => TrainingSport.strength,
    'other' || 'anderes' || 'yoga' || 'mobilität' => TrainingSport.other,
    _ => null,
  };

  static SessionIntensity _intensity(String? text) => switch (text?.toLowerCase() ?? '') {
    'hard' || 'intensiv' || 'hart' => SessionIntensity.hard,
    'long' || 'lang' => SessionIntensity.long,
    _ => SessionIntensity.easy,
  };

  // Auswahl

  /// Routinen nach der Auswahl. Beim Hinzufügen bekommt ein schon vorhandener Name den Zusatz „(KI)“.
  static List<Routine> routines(
    ImportPreview preview, {
    required ImportSelection selection,
    required List<Routine> existing,
  }) {
    final result = selection.replaceAllRoutines ? <Routine>[] : [...existing];
    for (final routine in preview.routines) {
      switch (selection.choice(routine)) {
        case RoutineChoice.skip:
          continue;
        case RoutineChoice.replace:
          final index = result.indexWhere((item) => item.name == routine.name);
          if (index >= 0) {
            result[index] = routine;
          } else {
            result.add(routine);
          }
        case RoutineChoice.add:
          final copy = routine.copy();
          final names = {for (final item in result) item.name};
          if (names.contains(copy.name)) {
            var counter = 1;
            var name = '${routine.name} (KI)';
            while (names.contains(name)) {
              counter += 1;
              name = '${routine.name} (KI $counter)';
            }
            copy.name = name;
          }
          result.add(copy);
      }
    }
    return result;
  }

  /// Tage, an denen der Vorschlag vom bisherigen Plan abweicht.
  static List<Weekday> changedDays(WeekSchedule proposal, {required WeekSchedule from}) => [
    for (final weekday in Weekday.values)
      if (!const ListEquality<SessionSlot>().equals(proposal.slots(weekday), from.slots(weekday))) weekday,
  ];

  /// Wochenplan nach der Auswahl: gewählte Tage aus dem Vorschlag, die anderen wie bisher.
  static WeekSchedule? schedule(
    ImportPreview preview, {
    required ImportSelection selection,
    required WeekSchedule current,
  }) {
    final proposal = preview.schedule;
    if (!selection.schedule || proposal == null) return null;
    var result = current;
    for (final weekday in selection.scheduleDays) {
      result = result.withSlots(proposal.slots(weekday), weekday);
    }
    return result == current ? null : result;
  }

  /// Übernommene Hinweise in der Reihenfolge der KI.
  static List<String> notes(ImportPreview preview, {required ImportSelection selection}) => [
    for (var index = 0; index < preview.notes.length; index++)
      if (selection.notes.contains(index)) preview.notes[index],
  ];

  /// Gibt es überhaupt etwas zu übernehmen?
  static bool hasChanges(ImportPreview preview, {required ImportSelection selection}) =>
      selection.replaceAllRoutines ||
      preview.routines.any((routine) => selection.choice(routine) != RoutineChoice.skip) ||
      (selection.schedule && preview.schedule != null && selection.scheduleDays.isNotEmpty) ||
      selection.notes.isNotEmpty;
}
