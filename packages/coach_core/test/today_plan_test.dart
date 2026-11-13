// Port von TodayPlanTests.swift und UnitGuideTests.swift.
//
// Vergleich mit `coach_today()` aus dem Altbestand: `fixtures/today-cases.json` wurde mit den Original-Templates
// (`coach_app.jinja`, `coach_plan.jinja`, `coach_days.jinja`) und der Testumgebung von `scripts/check_today.py`
// erzeugt – alle Wochentage × Tagesampel × Erledigt-Zustände × Läufe × HF-Verteilung in fünf Phasen-Wochen.
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

SeasonSchedule loadSchedule() => SeasonSchedule.load(File('assets/season-plan.json').readAsStringSync())!;

const adviceTexts = {
  RecoveryLevel.normal: 'Geplante Einheit wie vorgesehen durchziehen.',
  RecoveryLevel.locker:
      'Einheit machen, aber Intensität raus: harte Intervalle durch lockeres Training ersetzen oder um ein Drittel '
      'kürzen.',
  RecoveryLevel.pause: 'Heute Ruhetag - höchstens 20-30 min sehr locker bewegen.',
};

/// Die App verweist für Wettkampf-Läufe auf den Reiter Plan statt auf den Chat in Home Assistant.
String normalized(String text) => text.replaceAll('im Reiter Chat', 'im Reiter Plan');

/// Eintrag wie `Case.Entry` im Swift-Test; fehlende Schlüssel sind `null`.
String entryKey(Map<String, Object?> entry) =>
    jsonEncode([entry['day'], entry['s'], entry['t'], entry['c'], entry['d'], entry['ok'], entry['a']]);

List<String> entries(
  List<TodayPlanItem> items, {
  required bool withDone,
  required bool withChip,
  required bool withDay,
}) => [
  for (final item in items)
    entryKey({
      'day': withDay ? item.day : null,
      's': item.sport.name,
      't': item.title,
      'c': normalized(item.caption),
      'd': normalized(item.detail),
      'ok': withDone ? item.done : null,
      'a': withChip ? item.chip : null,
    }),
];

List<String> expected(List<Object?> raw, {bool normalize = false}) => [
  for (final item in raw.cast<Map<String, Object?>>())
    entryKey({
      ...item,
      if (normalize) 'c': normalized(item['c']! as String),
      if (normalize && item['d'] != null) 'd': normalized(item['d']! as String),
    }),
];

void main() {
  group('Tagesplan im Saisonmodus', () {
    test('stimmt mit den Templates des Altbestands überein', () {
      final schedule = loadSchedule();
      final all = jsonDecode(File('test/fixtures/today-cases.json').readAsStringSync()) as List<Object?>;
      expect(all.length, greaterThan(2000));
      final failures = <String>[];
      for (final raw in all.cast<Map<String, Object?>>()) {
        final today = CalendarDay.tryParse(raw['today']! as String)!;
        final level = enumFromRaw(RecoveryLevel.values, raw['level'])!;
        final zones = switch (raw['zones']) {
          'easy' => IntensityShare.fromSeconds([0, 97, 3, 0, 0]),
          'hard' => IntensityShare.fromSeconds([0, 40, 40, 20, 0]),
          _ => null,
        };
        final done = (raw['done']! as Map).cast<String, int>();
        final plan = TodayPlan(
          schedule: schedule,
          config: SeasonConfig.standard,
          decisions: const {},
          today: today,
          level: level,
          advice: adviceTexts[level] ?? '',
          done: TodayPlanDone(
            swim: done['swim'] ?? 0,
            run: done['run'] ?? 0,
            bike: done['bike'] ?? 0,
            strength: done['strength'] ?? 0,
          ),
          gymDays: (raw['gym']! as List).map((day) => CalendarDay.tryParse(day as String)).nonNulls.toSet(),
          runZones: zones,
        );
        final label = '${raw['today']} ${raw['level']} $done gym=${raw['gym']} zones=${raw['zones'] ?? '-'}';
        void check(String name, Object actual, Object wanted) {
          if (jsonEncode(actual) != jsonEncode(wanted)) failures.add('$name $label');
        }

        check(
          'items',
          entries(plan.items, withDone: true, withChip: true, withDay: false),
          expected(raw['items']! as List, normalize: true),
        );
        check(
          'open',
          entries(plan.open, withDone: false, withChip: true, withDay: false),
          expected(raw['open']! as List, normalize: true),
        );
        check('skip', [for (final item in plan.skipped) item.title], raw['skip']!);
        check(
          'week',
          entries(plan.rest, withDone: false, withChip: false, withDay: true),
          expected(raw['week']! as List),
        );
        check('hint', plan.hint, raw['hint']!);
        check('advice', plan.advice, raw['advice']!);
      }
      expect(failures, isEmpty, reason: '${failures.length} Abweichungen, z. B. ${failures.take(5)}');
    });

    // Regeln aus `check_today.py`: am letzten Tag nie „nicht heute“, Ausfälle nur am letzten Tag, grüne Ampel ohne
    // Hinweise, erledigte Einheiten ohne Hinweis.
    test('Konsistenzregeln des Altbestands', () {
      final schedule = loadSchedule();
      const monday = CalendarDay(2026, 10, 12);
      for (var offset = 0; offset < 7; offset++) {
        for (final level in RecoveryLevel.values) {
          final plan = TodayPlan(
            schedule: schedule,
            config: SeasonConfig.standard,
            decisions: const {},
            today: monday.adding(offset),
            level: level,
            advice: '',
            done: const TodayPlanDone(),
            gymDays: const {},
            runZones: null,
          );
          final chips = [...plan.items, ...plan.open].map((item) => item.chip).where((chip) => chip.isNotEmpty);
          if (offset == 6) expect(chips, isNot(contains('nicht heute')));
          if (offset < 6) expect(plan.skipped, isEmpty);
          if (level == RecoveryLevel.normal) expect(chips.isEmpty && plan.skipped.isEmpty, isTrue);
          expect(plan.items.any((item) => item.done && item.chip.isNotEmpty), isFalse);
          expect(plan.open.any((item) => item.chip == '⅓ weniger Sätze'), isFalse);
          if (offset == 6) expect(plan.rest, isEmpty);
        }
      }
    });
  });

  group('Anleitungen zu Einheiten', () {
    List<PlannedUnit> units() {
      final schedule = loadSchedule();
      return [for (final week in schedule.weeks) ...schedule.units(week, config: SeasonConfig.standard)];
    }

    test('jede Einheit des Saisonplans hat eine vollständige Anleitung', () {
      for (final unit in units()) {
        final guide = UnitGuides.guide(unit);
        expect(guide.purpose, isNotEmpty, reason: '${unit.title} ohne Zweck');
        expect(guide.feel, isNotEmpty);
        expect(guide.steps, isNotEmpty, reason: '${unit.title} ohne Ablauf');
        expect(guide.steps.any((step) => step.contains('§')), isFalse, reason: 'Platzhalter in ${unit.title}');
      }
    });

    test('Schwimmtechnik erklärt Übungen und CSS', () {
      final unit = units().firstWhere((unit) => unit.kind == PlannedUnitKind.swim && unit.title.contains('Technik'));
      final guide = UnitGuides.guide(unit);
      final names = guide.terms.map((term) => term.name).toList();
      expect(names, contains('Abschlag'));
      expect(names, contains('Zipper (Reißverschluss)'));
      expect(names, contains('Seitlage mit 6 Beinschlägen'));
      expect(names, contains('Pull-Buoy'));
      expect(names, contains('CSS (kritische Schwimmgeschwindigkeit)'));
      expect(guide.steps.first, startsWith('Einschwimmen'));
      expect(guide.steps.any((step) => step.contains('etwas langsamer als CSS')), isTrue);
      expect(guide.steps.any((step) => step.startsWith('Pause 30 s')), isTrue);
      expect(guide.steps.last, startsWith('Ausschwimmen'));
    });

    test('Tempo beim Schwimmen in Worten', () {
      expect(UnitGuides.intensity(low: -4, high: -2, note: null), startsWith('schneller als dein CSS-Tempo'));
      expect(UnitGuides.intensity(low: 0, high: 0, note: null), startsWith('im CSS-Tempo'));
      expect(UnitGuides.intensity(low: 4, high: 6, note: null), startsWith('etwas langsamer als CSS'));
      expect(UnitGuides.intensity(low: 12, high: 15, note: null), startsWith('locker'));
      expect(
        UnitGuides.intensity(low: null, high: null, note: 'Technik (z. B. Abschlag)'),
        startsWith('Technikübungen'),
      );
    });

    test('Lauf- und Radanleitungen passen zur Einheit', () {
      final all = units();
      final interval = all.firstWhere((unit) => unit.kind == PlannedUnitKind.quality && unit.title.contains('4×4'));
      expect(UnitGuides.guide(interval).steps.any((step) => step.contains('90–95 % HFmax')), isTrue);
      final runTest = all.firstWhere((unit) => unit.kind == PlannedUnitKind.quality && unit.title.contains('Lauftest'));
      expect(UnitGuides.guide(runTest).purpose, contains('Schwellenpace'));
      final sweetSpot = all.firstWhere((unit) => unit.zwiftCode == 'Z01');
      expect(UnitGuides.guide(sweetSpot).terms.map((term) => term.name), contains('Sweet Spot'));
      final ramp = all.firstWhere((unit) => unit.zwiftCode == 'RAMP');
      expect(UnitGuides.guide(ramp).purpose, contains('FTP'));
    });

    test('eigener Wochenplan ohne Werte des Saisonplans', () {
      for (final sport in TrainingSport.values) {
        for (final intensity in SessionIntensity.values) {
          final guide = UnitGuides.guideForSlot(SessionSlot(sport, intensity));
          expect(guide.purpose, isNotEmpty);
          expect(guide.steps, isNotEmpty);
          // Keine Werte aus dem Saisonplan (CSS, FTP, Schwellenpace) für andere Personen.
          final text = [guide.purpose, guide.feel, ...guide.steps].join(' ');
          expect(text.contains('CSS'), isFalse, reason: '$sport $intensity');
          expect(text.contains('FTP'), isFalse, reason: '$sport $intensity');
        }
      }
      expect(
        UnitGuides.guideForSlot(const SessionSlot(TrainingSport.run, SessionIntensity.hard)).terms
            .map((term) => term.name),
        contains('HFmax'),
      );
    });
  });
}
