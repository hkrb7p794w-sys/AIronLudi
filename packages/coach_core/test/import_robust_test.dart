// Import von Antworten externer KIs, die sich nicht genau ans Format halten (Rückmeldung vom 18.11.2026: ein Plan aus
// Claude kam nicht an). Jede Variante muss ankommen – oder sichtbar sagen, warum nicht.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

ImportPreview check(String text, {ProfileMode mode = ProfileMode.personal, WeekSchedule? schedule}) =>
    CoachImport.preview(
      text,
      profile: UserProfile(mode: mode, sports: const [TrainingSport.strength, TrainingSport.run])
        ..schedule = schedule ?? WeekSchedule(),
      equipment: Equipment.gym,
      custom: const [],
      // Mittwoch
      now: DateTime(2026, 11, 18, 9),
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

  group('Wochenplan als Markdown-Tabelle', () {
    test('dauerhafter Plan, diese Woche und Hinweise', () {
      // Bisheriger Plan: Donnerstag und Freitag Lauf – die Tabelle nennt beide nicht, also werden sie frei.
      final old = WeekSchedule().withSlots(const [SessionSlot(TrainingSport.run)], Weekday.thursday).withSlots(const [
        SessionSlot(TrainingSport.run),
      ], Weekday.friday);
      final preview = check(markdownPlan, schedule: old);
      expect(preview.scheduleScope, ScheduleScope.permanent);
      expect(preview.schedule!.slots(Weekday.thursday), isEmpty);
      expect(preview.schedule!.slots(Weekday.friday), isEmpty);
      final schedule = preview.schedule!;
      expect(schedule.slots(Weekday.monday), [const SessionSlot(TrainingSport.swim)]);
      expect(schedule.slots(Weekday.tuesday), isEmpty);
      expect(schedule.slots(Weekday.wednesday), [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)]);
      expect(schedule.slots(Weekday.saturday), [const SessionSlot(TrainingSport.bike)]);
      expect(schedule.slots(Weekday.sunday), [const SessionSlot(TrainingSport.run, SessionIntensity.long)]);
      // Ab heute (Mittwoch) vollständig: nicht genannte Tage frei, Montag und Dienstag bleiben, wie sie waren.
      expect(preview.currentWeek.keys, [
        Weekday.wednesday,
        Weekday.thursday,
        Weekday.friday,
        Weekday.saturday,
        Weekday.sunday,
      ]);
      expect(preview.currentWeek[Weekday.friday], isEmpty);
      expect(preview.currentWeek[Weekday.wednesday], [const SessionSlot(TrainingSport.swim)]);
      expect(preview.currentWeek[Weekday.thursday], [const SessionSlot(TrainingSport.strength, SessionIntensity.hard)]);
      expect(preview.currentWeek[Weekday.sunday], [const SessionSlot(TrainingSport.run)]);
      expect(preview.corrections, isEmpty);
      expect(preview.notes, contains('Kein Rad diese Woche.'));
      expect(preview.notes, contains('Phase: Grundlage (4 Wochen), nur locker'));
      expect(preview.notes, contains('Diese Woche, Mittwoch: Nur Technik'));
      expect(preview.notes, contains('Samstag: Zone 2'));

      final selection = ImportSelection.defaults(preview, existing: const [], currentSchedule: old);
      expect(selection.scheduleDays, containsAll([Weekday.thursday, Weekday.friday, Weekday.monday]));
      expect(selection.currentWeek, isTrue);
      expect(CoachImport.hasChanges(preview, selection: selection), isTrue);
      final week = CoachImport.currentWeekSchedule(preview, selection: selection, base: schedule)!;
      expect(week.slots(Weekday.monday), schedule.slots(Weekday.monday));
      expect(week.slots(Weekday.wednesday), [const SessionSlot(TrainingSport.swim)]);
      expect(week.slots(Weekday.saturday), isEmpty);
    });

    test('nur eine Tabelle ohne Überschrift: dauerhaft; mehrere Einheiten an einem Tag', () {
      final preview = check('''
| Tag | Training |
|:--|:--|
| Mo | Schwimmen + Kraft |
| Mi | Intervalle |
| Fr | Ruhetag |
''');
      expect(preview.schedule!.slots(Weekday.monday), [
        const SessionSlot(TrainingSport.swim),
        const SessionSlot(TrainingSport.strength, SessionIntensity.hard),
      ]);
      expect(preview.schedule!.slots(Weekday.wednesday), [const SessionSlot(TrainingSport.run, SessionIntensity.hard)]);
      expect(preview.schedule!.slots(Weekday.friday), isEmpty);
      expect(preview.currentWeek, isEmpty);
    });

    test('nächste Woche, unbekannte Einheit sichtbar, Saisonplan ignoriert', () {
      final next = check('''
### Plan für nächste Woche
| Tag | Einheit |
|---|---|
| Dienstag | Lauf locker |
| Donnerstag | Tischtennis |
''');
      expect(next.scheduleScope, ScheduleScope.nextWeek);
      expect(next.corrections, ['Donnerstag: Einheit „Tischtennis“ nicht erkannt.']);
      final season = check(markdownPlan, mode: ProfileMode.season);
      expect(season.schedule, isNull);
      expect(season.currentWeek, isEmpty);
      expect(season.corrections, ['Wochenplan ignoriert: Im Saisonplan stehen die Tage fest.']);
    });

    test('JSON-Block hat Vorrang vor Tabellen; diese_woche im JSON', () {
      final preview = check('''
| Tag | Einheit |
|---|---|
| Montag | Schwimmen |

```ironludi
{"wochenplan": {"gilt_fuer": "diese_woche", "tage": {"fr": "Lauf locker"}}}
```
''');
      expect(preview.schedule, isNull);
      expect(preview.currentWeek, {
        Weekday.friday: [const SessionSlot(TrainingSport.run)],
      });
    });

    test('Text ohne Tabelle und ohne JSON bleibt ein Fehler', () {
      expect(() => check('# Plan\n\nMontag Schwimmen, Dienstag frei.'), throwsA(ImportError.noBlock));
    });
  });
}

// Rückmeldung vom 18.11.2026: Plan als .md-Datei mit Tabellen statt JSON (Inhalt verfremdet).
const markdownPlan = '''
# Wochenplan – Halbmarathon im Frühjahr

Phase: Grundlage (4 Wochen), nur locker

## Diese Woche

| Tag | Einheit | Hinweis |
|---|---|---|
| Mittwoch | Lockeres Schwimmen, 45 min | Nur Technik |
| **Donnerstag** | Krafttraining | – |
| Sonntag | Lockerer Lauf, 30–40 min | Zone 2 |

Kein Rad diese Woche.

## Dauerhafter Wochenplan ab Montag

| Tag | Einheit | Hinweis |
|---|---|---|
| Montag | Lockeres Schwimmen, 45 min | Technik |
| Dienstag | Dehnen und Regeneration | Frei |
| Mittwoch | Krafttraining | – |
| Samstag | Lockere Radfahrt (Rolle), 75 min | Zone 2 |
| Sonntag | Langer Lauf, 60 min | – |

## Verlauf

| Woche | Schwimmen (min) | Lauf So (min) |
|---|---|---|
| 1 | 45 | 30–40 |
| 2 | 60 | 45 |

Danach: Test auf der Rolle, neuer Export.
''';
