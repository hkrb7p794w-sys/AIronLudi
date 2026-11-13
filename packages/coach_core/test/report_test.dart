// Port von CoachExportImportTests.swift, CoachImportSelectionTests, DataExportTests.swift und PersonaTests
// (SafeguardTests.swift).
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const monday = CalendarDay(2026, 10, 26);

CoachExportInput input({ProfileMode mode = ProfileMode.personal, bool empty = false, bool routines = true}) {
  final week = WeekSchedule().withSlots(const [SessionSlot(TrainingSport.run)], Weekday.tuesday);
  final profile = UserProfile(mode: mode, sports: const [TrainingSport.run, TrainingSport.strength])..schedule = week;
  if (empty) {
    return CoachExportInput(
      profile: UserProfile(mode: ProfileMode.personal, sports: const [TrainingSport.run, TrainingSport.strength]),
      schedule: WeekSchedule(),
      routines: [],
      custom: [],
      equipment: Equipment.gym,
      metrics: [],
      activities: [],
      gym: [],
      meals: [],
      weights: [],
    );
  }
  final metrics = DailyMetrics(monday)
    ..restingHeartRate = 48
    ..sleepSeconds = 7.5 * 3600
    ..steps = 9000;
  final old = DailyMetrics(monday.adding(-40))..restingHeartRate = 99;
  final run = GarminActivity(1)
    ..typeKey = 'running'
    ..startLocal = '2026-10-27 07:00:00'
    ..durationSeconds = 2700
    ..distanceMeters = 8420;
  final strength = GarminActivity(2)
    ..typeKey = 'strength_training'
    ..startLocal = '2026-10-26 18:00:00';
  final start = monday.referenceDate;
  final session = GymSession(
    workoutKey: null,
    title: routines ? 'Push A' : 'Push, A',
    start: start,
    end: start.add(const Duration(seconds: 3000)),
    exercises: [
      LoggedExercise(
        exerciseID: 'bankdruecken',
        name: 'Bankdrücken',
        group: MuscleGroup.chest,
        sets: [LoggedSet(reps: 10, weightKg: 52.5), LoggedSet(reps: 9, weightKg: 52.5, rir: 1)],
      ),
    ],
  );
  final item = MealItem(
    name: 'Haferflocken',
    grams: 80,
    source: MealItemSource.manual,
    per100g: NutrientValues({Nutrient.kcal: 370, Nutrient.protein: 13}),
  );
  return CoachExportInput(
    profile: profile,
    schedule: routines ? week : WeekSchedule(),
    routines: routines ? RoutineTemplates.gymBook : [],
    custom: [],
    equipment: Equipment.gym,
    metrics: [metrics, old],
    activities: [run, strength],
    gym: [session],
    meals: [
      ExportMeal(day: monday, category: 'Frühstück', title: 'Porridge', items: [item]),
    ],
    weights: [const WeightEntry(day: monday, kilograms: 80.4, source: WeightSource.manual)],
  );
}

Routine routine(String name) => Routine(
  name: name,
  items: [
    RoutineItem(
      exerciseID: 'bankdruecken',
      name: 'Bankdrücken',
      sets: 3,
      lowerReps: 6,
      upperReps: 10,
      restSeconds: 120,
    ),
  ],
);

void main() {
  group('Coach-Export und Import', () {
    test('Export enthält Zeitraum und Anleitung', () {
      final text = CoachExport.markdown(input(), from: monday.adding(-6), to: monday.adding(1));
      expect(text, contains('```ironludi'));
      expect(text, contains('| 2026-10-26 | 48 | – | 7.5 |'));
      expect(text, isNot(contains('| 99 |')));
      expect(text, contains('| 2026-10-27 07:00:00 | running | – | 45 | 8.4 |'));
      expect(text, contains('- Bankdrücken [bankdruecken]: 52.5×10, 52.5×9 (RIR 1)'));
      expect(text, contains('### 2026-10-26: 296 kcal, Protein 10 g'));
      expect(text, contains('- 2026-10-26: 80.4 kg'));
      expect(text, contains('- Dienstag: Lockerer Lauf'));
      expect(text, contains('- dips_barren – Dips am Barren – Trizeps'));
      expect(text, contains('"wochenplan"'));
      expect(
        CoachExport.markdown(
          input(mode: ProfileMode.season),
          from: monday,
          to: monday,
        ),
        isNot(contains('"wochenplan"')),
      );
    });

    const answer = '''
Hier meine Analyse … Dein Ruhepuls ist stabil.
```ironludi
{
  "routinen": {"modus": "ersetzen", "liste": [
    {"name": "Push neu", "uebungen": [
      {"id": "bankdruecken", "saetze": 8, "wdh_min": 6, "wdh_max": 10, "pause": 120, "gewicht": 55},
      {"name": "Dips am Barren", "saetze": 3},
      {"id": "fantasie", "saetze": 3}
    ]}
  ]},
  "wochenplan": {"gilt_fuer": "naechste_woche", "tage": {
    "mo": [{"sport": "kraft", "intensitaet": "intensiv"}], "di": [], "mi": [{"sport": "tanzen"}]
  }},
  "hinweise": ["Schlaf vor harten Tagen priorisieren."]
}
```
''';

    test('Import prüft Routinen und Wochenplan', () {
      final preview = CoachImport.preview(answer, profile: input().profile, equipment: Equipment.gym, custom: []);
      expect(preview.routineMode, RoutineMode.replace);
      expect(preview.routines.first.items.map((item) => item.exerciseID), ['bankdruecken', 'dips_barren']);
      expect(preview.routines.first.items.first.sets, 5);
      expect(preview.routines.first.items.first.weightKg, 55);
      expect(preview.corrections, contains('Unbekannte Übung „fantasie“ entfernt.'));
      expect(preview.corrections.any((note) => note.startsWith('Mittwoch: Sportart „tanzen“')), isTrue);
      expect(preview.scheduleScope, ScheduleScope.nextWeek);
      expect(preview.schedule?.slots(Weekday.monday), [
        const SessionSlot(TrainingSport.strength, SessionIntensity.hard),
      ]);
      expect(preview.schedule?.slots(Weekday.tuesday), isEmpty);
      expect(preview.notes, ['Schlaf vor harten Tagen priorisieren.']);
      // Saisonplan: Wochenplan wird nicht übernommen.
      final season = CoachImport.preview(
        answer,
        profile: input(mode: ProfileMode.season).profile,
        equipment: Equipment.gym,
        custom: [],
      );
      expect(season.schedule, isNull);
    });

    test('Import braucht einen Block', () {
      expect(
        () => CoachImport.preview('Nur Text', profile: UserProfile(), equipment: Equipment.gym, custom: []),
        throwsA(ImportError.noBlock),
      );
      expect(
        () => CoachImport.preview('```ironludi\n{kaputt\n```', profile: UserProfile(), equipment: {}, custom: []),
        throwsA(ImportError.invalidJSON),
      );
      const plain = '```json\n{"hinweise": ["Mehr trinken"]}\n```';
      expect(CoachImport.preview(plain, profile: UserProfile(), equipment: {}, custom: []).notes, ['Mehr trinken']);
    });
  });

  group('Auswahl beim Import', () {
    test('Standard: Gleichnamige ersetzen, Neue hinzufügen', () {
      final existing = [routine('Push A'), routine('Lower')];
      final preview = ImportPreview()
        ..routines = [routine('Push A'), routine('Ganzkörper')]
        ..notes = ['a', 'b'];
      final selection = ImportSelection.defaults(preview, existing: existing);
      expect(selection.choice(preview.routines[0]), RoutineChoice.replace);
      expect(selection.choice(preview.routines[1]), RoutineChoice.add);
      final result = CoachImport.routines(preview, selection: selection, existing: existing);
      expect(result.map((item) => item.name), ['Push A', 'Lower', 'Ganzkörper']);
      expect(result[0].id, preview.routines[0].id);
      expect(CoachImport.notes(preview, selection: selection), ['a', 'b']);
    });

    test('Die Person entscheidet je Eintrag', () {
      final existing = [routine('Push A'), routine('Lower')];
      final preview = ImportPreview()
        ..routines = [routine('Push A'), routine('Ganzkörper')]
        ..notes = ['a', 'b'];
      final selection = ImportSelection.defaults(preview, existing: existing);
      selection.routines[preview.routines[0].id] = RoutineChoice.add;
      selection.routines[preview.routines[1].id] = RoutineChoice.skip;
      selection.notes = {1};
      final result = CoachImport.routines(preview, selection: selection, existing: existing);
      expect(result.map((item) => item.name), ['Push A', 'Lower', 'Push A (KI)']);
      expect(result[0].id, existing[0].id);
      expect(CoachImport.notes(preview, selection: selection), ['b']);
      selection.replaceAllRoutines = true;
      expect(CoachImport.routines(preview, selection: selection, existing: existing).map((item) => item.name), [
        'Push A',
      ]);
      final nothing = ImportSelection()..schedule = false;
      for (final item in preview.routines) {
        nothing.routines[item.id] = RoutineChoice.skip;
      }
      expect(CoachImport.hasChanges(preview, selection: nothing), isFalse);
    });

    test('Wochenplan nur an gewählten Tagen', () {
      final current = WeekSchedule().withSlots(const [SessionSlot(TrainingSport.run)], Weekday.tuesday).withSlots(
        const [SessionSlot(TrainingSport.strength)],
        Weekday.thursday,
      );
      final proposal = current
          .withSlots(const [SessionSlot(TrainingSport.run, SessionIntensity.hard)], Weekday.tuesday)
          .withSlots(const [], Weekday.thursday);
      final preview = ImportPreview()..schedule = proposal;
      final selection = ImportSelection.defaults(preview, existing: [], currentSchedule: current);
      expect(selection.scheduleDays, {Weekday.tuesday, Weekday.thursday});
      selection.scheduleDays = {Weekday.tuesday};
      final result = CoachImport.schedule(preview, selection: selection, current: current);
      expect(result?.slots(Weekday.tuesday), [const SessionSlot(TrainingSport.run, SessionIntensity.hard)]);
      expect(result?.slots(Weekday.thursday), [const SessionSlot(TrainingSport.strength)]);
      selection.scheduleDays = {};
      expect(CoachImport.schedule(preview, selection: selection, current: current), isNull);
    });
  });

  group('Datenexport', () {
    final (from, to) = (monday.adding(-6), monday.adding(1));
    CoachExportInput data({bool empty = false}) => input(empty: empty, routines: false);

    test('Markdown nur mit den gewählten Kategorien', () {
      final text = DataExport.markdown(
        data(),
        from: from,
        to: to,
        categories: {ExportCategory.recovery, ExportCategory.gym},
      );
      expect(text, contains('## Erholung'));
      expect(text, contains('| 2026-10-26 | 48 | – | – | – | – |'));
      expect(text, contains('Bankdrücken'));
      expect(text, isNot(contains('## Schlaf')));
      expect(text, isNot(contains('Haferflocken')));
      expect(text, isNot(contains('```ironludi')));
      final withImport = DataExport.markdown(
        data(),
        from: from,
        to: to,
        categories: {ExportCategory.gym},
        withImportFormat: true,
      );
      expect(withImport, contains('```ironludi'));
    });

    test('JSON kennzeichnet Fehlendes als null', () {
      final text = DataExport.json(data(), from: from, to: to, categories: ExportCategory.values.toSet());
      final value = JsonValue(jsonDecode(text));
      expect(value['erholung']?.arrayValue?.first['ruhepuls']?.doubleValue, 48);
      expect(value['erholung']?.arrayValue?.first['hrv_ms']?.isNull, isTrue);
      // Krafttraining der Uhr steht nicht unter Ausdauer.
      expect(value['ausdauer']?.arrayValue?.length, 1);
      expect(value['ausdauer']?.arrayValue?.first['distanz_km']?.doubleValue, 8.42);
      expect(value['gym']?.arrayValue?.first['uebungen']?.arrayValue?.first['saetze']?.arrayValue?.length, 2);
      expect(value['ernaehrung']?.arrayValue?.first['kcal']?.doubleValue, 296);
      expect(value['verlauf_wochen']?.arrayValue, isNotEmpty);
      expect(value['export']?['kategorien']?.arrayValue?.length, 8);
      // Formatiert wie `JSONEncoder` mit `.prettyPrinted` und `.sortedKeys`.
      expect(text.startsWith('{\n  "ausdauer" : [\n'), isTrue);
    });

    test('CSV: eine Datei je Kategorie, mit Anführungszeichen', () {
      final files = DataExport.csv(
        data(),
        from: from,
        to: to,
        categories: {ExportCategory.gym, ExportCategory.weight, ExportCategory.sleep},
      );
      expect(files.length, 3);
      final gym = files.firstWhere((file) => file.name.contains('-gym-'));
      expect(gym.content.startsWith('datum,einheit,uebung_id'), isTrue);
      expect(gym.content, contains('"Push, A"'));
      expect(gym.content, contains(',52.5,9,1,'));
      final sleep = files.firstWhere((file) => file.name.contains('-schlaf-'));
      expect(sleep.content, contains('2026-10-26,7.5,,,,'));
    });

    test('ohne Daten trotzdem ein Export', () {
      final all = ExportCategory.values.toSet();
      final text = DataExport.markdown(data(empty: true), from: from, to: to, categories: all);
      expect(text, contains('# AIronLudi'));
      expect(text, isNot(contains('## Erholung')));
      final json = JsonValue(jsonDecode(DataExport.json(data(empty: true), from: from, to: to, categories: all)));
      expect(json['gym']?.arrayValue, isEmpty);
      expect(DataExport.counts(data(empty: true), from: from, to: to).values.every((count) => count == 0), isTrue);
      expect(DataExport.counts(data(), from: from, to: to)[ExportCategory.endurance], 1);
    });

    test('Prompts setzen Platzhalter ein und hängen Daten an', () {
      final template = PromptLibrary.builtIn[0];
      final text = PromptLibrary.compose(template, input: data(), from: from, to: to);
      expect(text.startsWith('Analysiere meine Trainingsdaten der letzten 8 Tage'), isTrue);
      expect(text, isNot(contains('{')));
      expect(text, contains('Arbeitsweise:'));
      expect(text, contains('Bankdrücken'));
      expect(
        PromptLibrary.compose(template, input: data(), from: from, to: to, format: ExportFormat.json),
        contains('```json'),
      );
      expect({for (final prompt in PromptLibrary.builtIn) prompt.id}.length, PromptLibrary.builtIn.length);
      expect(PromptLibrary.builtIn.every((prompt) => prompt.categories.isNotEmpty && !prompt.isCustom), isTrue);
      final custom = PromptTemplate(
        title: 'Eigen',
        text: 'Ziel {ziel}',
        categories: [ExportCategory.weight],
        days: 999,
      );
      expect(custom.days, 365);
      expect(PromptLibrary.filled(custom, profile: data().profile, from: from, to: to).startsWith('Ziel '), isTrue);
      expect(PromptTemplate.fromJson(jsonDecode(jsonEncode(custom.toJson()))), custom);
    });
  });

  group('Musterpersonen', () {
    test('alle Personen halten jede Schutzregel ein', () {
      for (final persona in PersonaReport.personas) {
        final result = PersonaReport.evaluate(persona);
        for (final check in result.checks) {
          expect(check.passed, isTrue, reason: '${persona.name}: ${check.rule} – ${check.detail}');
        }
        expect(result.checks.length, greaterThanOrEqualTo(4));
      }
    });

    test('der Bericht nennt jede Person', () {
      final report = PersonaReport.run();
      expect(report, contains('Alle Schutzregeln eingehalten.'));
      for (final persona in PersonaReport.personas) {
        expect(report, contains('## ${persona.name}'));
      }
      expect(report, contains('💡'));
    });
  });
}
