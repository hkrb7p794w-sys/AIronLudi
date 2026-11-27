// Krafttraining von Screenshots (WHOOP Strength Trainer u. a.): Antwort der KI prüfen, Einheit bauen.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

/// Antwort von `gym_import` zum WHOOP-Screenshot „Oberkörper, 19. Nov. 07:16 bis 08:09“.
final _output = JsonValue(
  jsonDecode('''
{"titel": "Oberkörper", "tag": 19, "monat": 11, "jahr": null, "start": "07:16", "ende": "08:09",
 "uebungen": [
  {"name": "Bankdrücken", "id": "bankdruecken", "gruppe": null,
   "saetze": [{"wdh": 10, "kg": 60, "sekunden": null}, {"wdh": 8, "kg": 62.5, "sekunden": null}]},
  {"name": "Butterfly-Maschine", "id": null, "gruppe": "Brust",
   "saetze": [{"wdh": 12, "kg": 45, "sekunden": null}, {"wdh": 12, "kg": 45, "sekunden": null}]},
  {"name": "Unterarmstütz", "id": null, "gruppe": "Rumpf", "saetze": [{"wdh": null, "kg": 0, "sekunden": 60}]},
  {"name": "Klimmzüge", "id": null, "gruppe": "Rücken", "saetze": [{"wdh": 8, "kg": 0, "sekunden": null}]},
  {"name": "Bankdrücken", "id": "bankdruecken", "saetze": [{"wdh": 6, "kg": 65, "sekunden": null}]},
  {"name": "Leer", "saetze": [{"wdh": 0, "kg": 50}]},
  {"name": "", "saetze": [{"wdh": 5, "kg": 10}]}
 ]}
'''),
);

void main() {
  test('Antwort lesen: Sätze, Zeitübungen, Datum und Uhrzeit', () {
    final workout = ImportedWorkout.fromOutput(_output)!;
    expect(workout.title, 'Oberkörper');
    expect(workout.exercises.map((exercise) => exercise.name), [
      'Bankdrücken',
      'Butterfly-Maschine',
      'Unterarmstütz',
      'Klimmzüge',
      'Bankdrücken',
    ]);
    expect(workout.setCount, 7);
    expect(workout.exercises[2].sets.single.isTimed, isTrue);
    expect(workout.startMinutes, 7 * 60 + 16);
    expect(workout.endMinutes, 8 * 60 + 9);
    expect(ImportedWorkout.fromOutput(JsonValue(jsonDecode('{"uebungen": []}'))), isNull);
  });

  test('Tag ohne Jahr: der letzte solche Tag bis heute', () {
    final workout = ImportedWorkout.fromOutput(_output)!;
    expect(workout.dayIn(const CalendarDay(2026, 11, 27)), const CalendarDay(2026, 11, 19));
    // Im Januar ist der 19. November der des Vorjahres.
    expect(workout.dayIn(const CalendarDay(2027, 1, 5)), const CalendarDay(2026, 11, 19));
    const noDate = ImportedWorkout(exercises: []);
    expect(noDate.dayIn(const CalendarDay(2026, 11, 27)), isNull);
    const invalid = ImportedWorkout(day: 31, month: 2, year: 2026, exercises: []);
    expect(invalid.dayIn(const CalendarDay(2026, 11, 27)), isNull);
  });

  test('Einheit: Bibliothek zugeordnet, Unbekanntes als eigene Übung, gleiche Übung zusammengeführt', () {
    final workout = ImportedWorkout.fromOutput(_output)!;
    final times = GymScreenshotImport.times(workout, day: const CalendarDay(2026, 11, 19));
    expect(times.start, DateTime(2026, 11, 19, 7, 16));
    expect(times.end, DateTime(2026, 11, 19, 8, 9));
    final result = GymScreenshotImport.session(workout, start: times.start, end: times.end, custom: const []);
    final session = result.session;
    expect(session.title, 'Oberkörper');
    expect(session.workoutKey, 'import:2026-11-19:07:16');
    expect(session.id, GymBookImport.stableID('import:2026-11-19:07:16'));
    expect(session.day, const CalendarDay(2026, 11, 19));
    final bench = session.exercises.first;
    expect(bench.exerciseID, 'bankdruecken');
    expect(bench.sets.map((set) => (set.reps, set.weightKg)), [(10, 60.0), (8, 62.5), (6, 65.0)]);
    expect(session.exercises, hasLength(4));
    expect(session.doneSetCount, 7);
    expect(session.volumeKg, 10 * 60 + 8 * 62.5 + 6 * 65 + 2 * 12 * 45);
    expect(result.newCustom.map((info) => (info.name, info.group, info.tracking)), [
      ('Butterfly-Maschine', MuscleGroup.chest, ExerciseTracking.weightReps),
      ('Unterarmstütz', MuscleGroup.core, ExerciseTracking.time),
      ('Klimmzüge', MuscleGroup.back, ExerciseTracking.reps),
    ]);
    // Haltezeit im Feld der Wiederholungen.
    expect(session.exercises[2].sets.single.reps, 60);
    // Schon angelegte eigene Übung wird wiederverwendet.
    final again = GymScreenshotImport.session(workout, start: times.start, end: times.end, custom: result.newCustom);
    expect(again.newCustom, isEmpty);
    expect(again.session.id, session.id);
  });

  test('ohne Uhrzeit: Aufzeichnung des Tages, sonst 18 Uhr für eine Stunde', () {
    const workout = ImportedWorkout(exercises: []);
    const day = CalendarDay(2026, 11, 19);
    final fallback = GymScreenshotImport.times(
      workout,
      day: day,
      fallbackStart: DateTime(2026, 11, 19, 7, 16),
      fallbackEnd: DateTime(2026, 11, 19, 8, 9),
    );
    expect((fallback.start, fallback.end), (DateTime(2026, 11, 19, 7, 16), DateTime(2026, 11, 19, 8, 9)));
    final none = GymScreenshotImport.times(workout, day: day);
    expect((none.start, none.end), (DateTime(2026, 11, 19, 18), DateTime(2026, 11, 19, 19)));
  });

  test('Bibliothek für die KI und Einordnung als Erfassen', () {
    final library = GymScreenshotImport.library();
    expect(library, contains('bankdruecken | Bankdrücken'));
    expect(library, hasLength(ExerciseLibrary.all.length));
    expect(AIPolicy.allows(AIMode.captureOnly, task: 'gym_import', trigger: AITrigger.user), isTrue);
  });
}
