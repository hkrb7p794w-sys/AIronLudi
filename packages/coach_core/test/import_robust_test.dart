// Import von Antworten externer KIs, die sich nicht genau ans Format halten (Rückmeldung vom 18.11.2026: ein Plan aus
// Claude kam nicht an). Jede Variante muss ankommen – oder sichtbar sagen, warum nicht.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

ImportPreview check(String text, {ProfileMode mode = ProfileMode.personal}) => CoachImport.preview(
  text,
  profile: UserProfile(mode: mode, sports: const [TrainingSport.strength, TrainingSport.run]),
  equipment: Equipment.gym,
  custom: const [],
);

void main() {
  group('Block finden und lesen', () {
    test('ironludi, json, ohne Sprache, ohne Codeblock, auf einer Zeile, ~~~', () {
      for (final text in [
        '```ironludi\n{"hinweise": ["a"]}\n```',
        '```IronLudi\n{"hinweise": ["a"]}\n```',
        '```json\n{"hinweise": ["a"]}\n```',
        '```\n{"hinweise": ["a"]}\n```',
        '```ironludi {"hinweise": ["a"]}```',
        '~~~ironludi\n{"hinweise": ["a"]}\n~~~',
        '{"hinweise": ["a"]}',
        'Hier ist dein Plan:\n\n{"hinweise": ["a"]}\n\nViel Erfolg!',
      ]) {
        expect(check(text).notes, ['a'], reason: text);
      }
    });

    test('Kommentare, Kommas vor Klammern, typografische Anführungszeichen', () {
      final preview = check('''
```ironludi
{
  // Plan von Claude
  “routinen”: {"liste": [{"name": "A", "uebungen": [{"id": "bankdruecken", "saetze": 3,},],},]},
  /* Hinweise */
  "hinweise": [„Schlaf zählt mit“],
}
```''');
      expect(preview.routines.single.items.single.exerciseID, 'bankdruecken');
      expect(preview.notes, ['Schlaf zählt mit']);
    });

    test('kaputtes JSON im ironludi-Block bleibt ein klarer Fehler, Text ohne Plan auch', () {
      expect(() => check('```ironludi\n{kaputt\n```'), throwsA(ImportError.invalidJSON));
      expect(() => check('Mach einfach drei Mal pro Woche Sport.'), throwsA(ImportError.noBlock));
    });
  });

  group('Schlüssel und Übungen', () {
    test('englische Schlüssel, Wiederholungen als Bereich, Übungen als Text', () {
      final preview = check('''
```json
{"routines": [
  {"title": "Push Day", "exercises": [
    {"name": "Bench Press", "sets": "4", "reps": "6-8", "rest": "120 s", "weight_kg": 60},
    "Lateral Raise",
    {"exercise": "x"}
  ]}
]}
```''');
      final routine = preview.routines.single;
      expect(routine.name, 'Push Day');
      final bench = routine.items.first;
      expect(bench.exerciseID, 'bankdruecken');
      expect((bench.sets, bench.lowerReps, bench.upperReps, bench.restSeconds), (4, 6, 8, 120));
      expect(bench.weightKg, 60);
      expect(routine.items[1].exerciseID, 'seitheben');
      expect(preview.corrections, contains('„Bench Press“ als Bankdrücken übernommen.'));
    });

    test('deutsche Namen mit Klammern, Plural, Bindestrich und Zusatz', () {
      String id(String name) => CoachImport.resolve(name, custom: const []);
      expect(id('Bankdrücken (Langhantel)'), 'bankdruecken');
      expect(id('Kniebeugen'), 'kniebeuge');
      expect(id('kniebeugen'), 'kniebeuge');
      expect(id('Klimmzüge'), 'klimmzug');
      expect(id('Liegestütz'), 'liegestuetze');
      expect(id('Bankdrücken mit Kurzhanteln'), 'kurzhantel_bankdruecken');
      expect(id('Rumänisches Kreuzheben'), 'rumaenisches_kreuzheben');
      expect(id('Kreuzheben'), 'kreuzheben');
      expect(id('Plank'), 'plank');
      expect(id('Unbekanntes Ding'), 'Unbekanntes Ding');
    });

    test('Routine ohne bekannte Übung wird gemeldet statt still verworfen', () {
      final preview = check(
        '```ironludi\n{"routinen": [{"name": "Fantasie", "uebungen": [{"id": "flugrolle"}]}]}\n```',
      );
      expect(preview.routines, isEmpty);
      expect(preview.corrections, contains('Trainingsplan „Fantasie“ nicht übernommen: keine bekannte Übung darin.'));
    });
  });

  group('Wochenplan', () {
    test('Tage als Text, englische Tage, ohne Hülle „tage“, Intensität aus dem Text, Ruhetag', () {
      final preview = check('''
```json
{"weekly_plan": {"applies_to": "next week",
  "monday": "Laufen locker 40 min",
  "wednesday": [{"sport": "Intervalle"}],
  "friday": "Ruhetag",
  "saturday": {"sport": "Lauf", "intensity": "lang"},
  "sunday": ["Ganzkörper Krafttraining"]
}}
```''');
      final schedule = preview.schedule!;
      expect(preview.scheduleScope, ScheduleScope.nextWeek);
      expect(schedule.slots(Weekday.monday), [const SessionSlot(TrainingSport.run)]);
      expect(schedule.slots(Weekday.wednesday), [const SessionSlot(TrainingSport.run, SessionIntensity.hard)]);
      expect(schedule.slots(Weekday.friday), isEmpty);
      expect(schedule.slots(Weekday.saturday), [const SessionSlot(TrainingSport.run, SessionIntensity.long)]);
      expect(schedule.slots(Weekday.sunday).single.sport, TrainingSport.strength);
    });

    test('im Saisonplan sichtbar ignoriert', () {
      final preview = check('```ironludi\n{"wochenplan": {"tage": {"mo": ["Laufen"]}}}\n```', mode: ProfileMode.season);
      expect(preview.schedule, isNull);
      expect(preview.corrections, contains('Wochenplan ignoriert: Im Saisonplan stehen die Tage fest.'));
    });
  });
}
