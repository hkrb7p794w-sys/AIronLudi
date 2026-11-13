// Port von MobilityTests.swift und GameTests.swift.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  group('Mobilität', () {
    const today = CalendarDay(2026, 11, 9);
    List<MobilityScore> scores({
      Map<Muscle, double> sets = const {},
      Map<ActivitySport, double> minutes = const {},
      List<MobilityTestResult> results = const [],
      List<ComplaintArea> complaints = const [],
    }) => MobilityPlanner.scores(recentSets: sets, enduranceMinutes: minutes, results: results, complaints: complaints);

    test('Bibliothek deckt jede Region für jeden Zeitpunkt ab', () {
      for (final area in MobilityArea.values) {
        final drills = MobilityLibrary.drills.where((drill) => drill.areas.contains(area));
        expect(drills.any((drill) => drill.style == DrillStyle.dynamic), isTrue, reason: '$area ohne dynamische Übung');
        expect(drills.any((drill) => drill.style == DrillStyle.hold), isTrue, reason: '$area ohne Halteübung');
      }
      expect({for (final drill in MobilityLibrary.drills) drill.id}.length, MobilityLibrary.drills.length);
      // Halten unter 60 s je Seite (Behm et al. 2016).
      expect(MobilityLibrary.drills.where((d) => d.style == DrillStyle.hold).every((d) => d.seconds < 60), isTrue);
    });

    test('Einstufung nach Grenzen', () {
      final knee = MobilityTest.byID['knee_to_wall']!;
      expect(knee.rating(4), MobilityRating.limited);
      expect(knee.rating(6), MobilityRating.moderate);
      expect(knee.rating(12), MobilityRating.good);
      final toes = MobilityTest.byID['toe_touch']!;
      expect(toes.rating(-15), MobilityRating.limited);
      expect(toes.rating(-5), MobilityRating.moderate);
      expect(toes.rating(0), MobilityRating.good);
      final squat = MobilityTest.byID['deep_squat']!;
      expect(squat.rating(2), MobilityRating.good);
      expect(squat.rating(7), MobilityRating.good);
      expect(squat.rating(-1), MobilityRating.limited);
    });

    test('Laufen setzt Beine und Hüfte in den Fokus', () {
      final result = scores(minutes: {ActivitySport.run: 60});
      expect(result.take(4).map((score) => score.area).toSet(), {
        MobilityArea.ankles,
        MobilityArea.hipFlexors,
        MobilityArea.hamstrings,
        MobilityArea.hips,
      });
      expect(result[0].reasons.first, 'Laufen 60 min seit gestern');
    });

    test('kurze Einheiten zählen nicht', () {
      expect(scores(minutes: {ActivitySport.swim: 10}).every((score) => score.points == 0), isTrue);
    });

    test('Oberkörpertag: Schultern im Fokus', () {
      final result = scores(sets: {Muscle.chest: 9, Muscle.lats: 9, Muscle.triceps: 6});
      expect(result.take(2).map((score) => score.area).toSet(), {MobilityArea.shoulders, MobilityArea.thoracicSpine});
    });

    test('eingeschränkter Test vor Training', () {
      final result = scores(
        sets: {Muscle.chest: 12},
        results: [MobilityTestResult(testID: 'knee_to_wall', day: today, value: 3)],
      );
      expect(result[0].area, MobilityArea.ankles);
      expect(result[0].reasons, contains('Test „Knie zur Wand“: eingeschränkt'));
    });

    test('das letzte Ergebnis zählt', () {
      final results = [
        MobilityTestResult(testID: 'knee_to_wall', day: today.adding(-30), value: 3),
        MobilityTestResult(testID: 'knee_to_wall', day: today, value: 12),
      ];
      expect(MobilityTestResult.latest(results)['knee_to_wall']?.value, 12);
      expect(scores(results: results).every((score) => score.points == 0), isTrue);
    });

    MobilityRoutine routine(
      MobilityContext context,
      int minutes, {
      Map<Muscle, double> sets = const {},
      Map<ActivitySport, double> endurance = const {},
    }) => MobilityPlanner.routine(
      context: context,
      minutes: minutes,
      recentSets: sets,
      enduranceMinutes: endurance,
      results: const [],
    );

    test('vor dem Training nur dynamisch', () {
      for (final minutes in MobilityPlanner.durations) {
        final result = routine(
          MobilityContext.preTraining,
          minutes,
          sets: {Muscle.quads: 10},
          endurance: {ActivitySport.run: 40},
        );
        expect(result.blocks, isNotEmpty);
        expect(result.blocks.every((block) => block.drill.style == DrillStyle.dynamic), isTrue);
      }
    });

    test('Ruhetag beginnt mit Halten', () {
      final result = routine(MobilityContext.restDay, 10, endurance: {ActivitySport.run: 60});
      expect(result.blocks.first.drill.style, DrillStyle.hold);
      expect(result.focus.length, 3);
    });

    test('Einheit hält die Dauer ein, ohne Doppelte', () {
      for (final context in MobilityContext.values) {
        for (final minutes in MobilityPlanner.durations) {
          final result = routine(
            context,
            minutes,
            sets: {Muscle.hamstrings: 8, Muscle.glutes: 8},
            endurance: {ActivitySport.bike: 90},
          );
          expect(result.totalSeconds, lessThanOrEqualTo(minutes * 60 + 30), reason: '$context $minutes min zu lang');
          // Vor dem Training reichen die dynamischen Übungen nicht für 20 Minuten; das zeigt die App ehrlich an.
          if (context != MobilityContext.preTraining || minutes <= 10) {
            expect(
              result.totalSeconds,
              greaterThanOrEqualTo(minutes * 60 ~/ 2),
              reason: '$context $minutes min zu kurz',
            );
          }
          expect({for (final block in result.blocks) block.id}.length, result.blocks.length);
          expect(result.blocks.every((block) => result.focus.contains(block.area)), isTrue);
        }
      }
    });

    test('ohne Daten eine ausgewogene Einheit', () {
      final result = routine(MobilityContext.restDay, 5);
      expect(result.reasons, [MobilityPlanner.balancedReason]);
      expect(result.blocks, isNotEmpty);
    });

    test('Eingaben aus Einheiten und Aktivitäten', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1793500000 * 1000, isUtc: true);
      LoggedExercise squat() => LoggedExercise(
        exerciseID: 'kniebeuge',
        name: 'Kniebeuge',
        group: MuscleGroup.legs,
        sets: [for (var index = 0; index < 4; index++) LoggedSet(reps: 8, weightKg: 100)],
      );
      GymSession session(int hoursAgo) => GymSession(
        workoutKey: null,
        title: 'Beine',
        start: now.subtract(Duration(hours: hoursAgo)),
        end: now.subtract(Duration(hours: hoursAgo - 1)),
        exercises: [squat()],
      );
      final sets = MobilityPlanner.recentSets([session(20), session(80)], now: now);
      expect(sets[Muscle.quads] ?? 0, greaterThan(0));
      expect(sets[Muscle.quads] ?? 0, lessThanOrEqualTo(4));
      final run = GarminActivity(1)
        ..typeKey = 'running'
        ..startLocal = '2026-11-08 07:00:00'
        ..durationSeconds = 3000;
      final oldRide = GarminActivity(2)
        ..typeKey = 'cycling'
        ..startLocal = '2026-11-05 07:00:00'
        ..durationSeconds = 3600;
      final minutes = MobilityPlanner.enduranceMinutes([run, oldRide], today: today);
      expect(minutes[ActivitySport.run], 50);
      expect(minutes[ActivitySport.bike], isNull);
    });

    test('Wochenzahl zählt verschiedene Tage', () {
      final settings = MobilitySettings()
        ..log = [
          MobilityLogEntry(day: today, minutes: 10, areas: const [MobilityArea.hips]),
          MobilityLogEntry(day: today, minutes: 5, areas: const [MobilityArea.ankles]),
          MobilityLogEntry(day: today.adding(-3), minutes: 10, areas: const [MobilityArea.hips]),
          MobilityLogEntry(day: today.adding(-8), minutes: 10, areas: const [MobilityArea.hips]),
        ];
      expect(settings.sessions(inWeekEnding: today), 2);
      final text = jsonEncode(settings.toJson());
      expect(jsonEncode(MobilitySettings.fromJson(jsonDecode(text)).toJson()), text);
      expect(MobilitySettings.fromJson(<String, Object?>{}).minutes, 10);
    });

    test('Evidenz-Regeln vorhanden', () {
      expect(Evidence.rulesByID['mobility.stretching']?.studies.length, 3);
      expect(Evidence.rulesByID['mobility.focus'], isNotNull);
    });

    test('Vorschlag an Ruhe- und Erholungstagen', () {
      bool suggest(bool training, RecoveryLevel? recovery, bool done) =>
          MobilityPlanner.suggestToday(hasTraining: training, recovery: recovery, doneToday: done);
      expect(suggest(false, RecoveryLevel.normal, false), isTrue);
      expect(suggest(true, RecoveryLevel.normal, false), isFalse);
      expect(suggest(true, RecoveryLevel.locker, false), isTrue);
      expect(suggest(true, RecoveryLevel.pause, false), isTrue);
      expect(suggest(false, null, true), isFalse);
    });

    test('Kontextzeile ohne Rohwerte', () {
      final settings = MobilitySettings();
      expect(settings.contextLine(today), isNull);
      settings
        ..log = [
          MobilityLogEntry(day: today, minutes: 10, areas: const [MobilityArea.hips]),
        ]
        ..results = [MobilityTestResult(testID: 'knee_to_wall', day: today, value: 4)];
      expect(
        settings.contextLine(today),
        'Mobility: 1 Einheiten in den letzten 7 Tagen; Selbsttests: Knie zur Wand eingeschränkt.',
      );
      final facts = ChatFacts(profile: UserProfile(), privacy: PrivacyMode.reduced)
        ..mobilityLine = settings.contextLine(today);
      expect(ChatContext.lines(facts).any((line) => line.startsWith('Mobility: 1 Einheiten')), isTrue);
    });

    test('Beschwerden setzen Schwerpunkte und markieren Übungen', () {
      final result = scores(complaints: [ComplaintArea.knee]);
      expect(result.take(3).map((score) => score.area).toSet(), {
        MobilityArea.hipFlexors,
        MobilityArea.ankles,
        MobilityArea.hamstrings,
      });
      expect(result[0].reasons.first, 'Beschwerden: Knie – nur schmerzfrei bewegen');
      // Kniebeuge belastet das Knie (Oberschenkel vorn als Hauptmuskel), Bankdrücken nicht.
      expect(
        ComplaintArea.loaded(
          'kniebeuge',
          group: MuscleGroup.legs,
          complaints: [ComplaintArea.knee, ComplaintArea.shoulder],
        ),
        [ComplaintArea.knee],
      );
      expect(ComplaintArea.loaded('bankdruecken', group: MuscleGroup.chest, complaints: [ComplaintArea.knee]), isEmpty);
      expect(ComplaintArea.loaded('bankdruecken', group: MuscleGroup.chest, complaints: [ComplaintArea.shoulder]), [
        ComplaintArea.shoulder,
      ]);
      expect(ComplaintArea.hint([]), isNull);
      expect(ComplaintArea.hint([ComplaintArea.knee])!.startsWith('Belastet: Knie.'), isTrue);
    });

    test('Beschwerden erreichen den Coach ohne Diagnose', () {
      final settings = MobilitySettings()..complaints = [ComplaintArea.lowerBack];
      final line = settings.contextLine(today);
      expect(line, contains('Angegebene Beschwerden: Unterer Rücken'));
      expect(line, contains('keine Diagnose'));
      expect(MobilitySettings.fromJson(jsonDecode(jsonEncode(settings.toJson()))).complaints, [
        ComplaintArea.lowerBack,
      ]);
    });
  });

  group('Spiel', () {
    const today = CalendarDay(2026, 11, 11); // Mittwoch
    CalendarDay november(int day) => CalendarDay(2026, 11, day);

    test('Serie bis gestern, solange heute offen ist', () {
      final days = {for (var back = 1; back <= 5; back++) today.adding(-back)};
      final streak = DailyStreak.compute(activeDays: days, today: today);
      expect(streak.current, 5);
      expect(streak.activeToday, isFalse);
      final withToday = DailyStreak.compute(activeDays: {...days, today}, today: today);
      expect(withToday.current, 6);
      expect(withToday.activeToday, isTrue);
    });

    test('ein Joker je Woche überbrückt eine Lücke', () {
      // Mo 09., Di 10. aktiv; So 08. fehlt (Joker der Vorwoche), Sa 07., Fr 06. aktiv.
      final streak = DailyStreak.compute(
        activeDays: {
          for (final d in [9, 10, 7, 6]) november(d),
        },
        today: today,
      );
      expect(streak.current, 5);
      expect(streak.jokerDays, [november(8)]);
      // Je Woche ein Joker: 09.11. (diese Woche) und 07.11. (Vorwoche); die zweite Lücke der Vorwoche beendet die Serie.
      final bridged = DailyStreak.compute(
        activeDays: {
          for (final d in [10, 8, 6, 4]) november(d),
        },
        today: today,
      );
      expect(bridged.current, 5);
      expect(bridged.jokerDays, [november(9), november(7)]);
    });

    test('ohne Joker nur lückenlose Tage', () {
      // Di 10. und Mo 09. aktiv, So 08. fehlt: ohne Joker endet die Serie dort.
      final days = {
        for (final d in [10, 9, 7, 6]) november(d),
      };
      final strict = DailyStreak.compute(activeDays: days, today: today, jokers: 0);
      expect(strict.current, 2);
      expect(strict.jokerDays, isEmpty);
      expect(DailyStreak.compute(activeDays: days, today: today).current, 5);
      // Vorgestern zuletzt eingetragen: keine Serie mehr.
      expect(DailyStreak.compute(activeDays: {today.adding(-2)}, today: today, jokers: 0).current, 0);
    });

    test('keine Serie ohne Aktivität', () {
      final streak = DailyStreak.compute(activeDays: {}, today: today);
      expect(streak.current, 0);
      expect(streak.best, 0);
      final old = DailyStreak.compute(
        activeDays: {for (var back = 20; back <= 29; back++) today.adding(-back)},
        today: today,
      );
      expect(old.current, 0);
      expect(old.best, 10);
    });

    test('Abzeichen belohnen Beständigkeit, nicht Menge', () {
      final stats = GameStats()
        ..workouts = 12
        ..bestDayStreak = 8
        ..friends = 1;
      expect(
        {for (final badge in BadgeRules.earned(stats)) badge.id},
        {'workout.1', 'workout.10', 'streak.7', 'friends.1'},
      );
      expect(BadgeRules.next(stats), isNotNull);
      expect({for (final badge in BadgeRules.all) badge.id}.length, BadgeRules.all.length);
    });

    test('Challenge-Werte sind gedeckelt', () {
      final monday = november(9);
      final minutes = {monday: 200, monday.adding(1): 45, monday.adding(5): 60};
      final meals = {monday, monday.adding(2)};
      int value(ChallengeMetric metric) =>
          metric.value(monday: monday, today: today, minutesByDay: minutes, mealDays: meals, adherence: null);
      // Samstag liegt nach heute (Mittwoch) und zählt noch nicht.
      expect(value(ChallengeMetric.minutes), 90 + 45);
      expect(value(ChallengeMetric.sessions), 2);
      expect(value(ChallengeMetric.meals), 2);
      expect(value(ChallengeMetric.plan), 0);
      expect(ChallengeMetric.minutes.max, 630);
    });

    test('Challenge des Workers wird gelesen', () {
      const json = '''
        {"id": "c1", "title": "Minuten-Duell", "metric": "minutes", "metricTitle": "Trainingsminuten", "max": 630,
         "week": "2026-11-09", "finished": true, "status": "joined", "mineCreated": false,
         "members": [{"username": "lena", "displayName": "Lena", "status": "joined", "progress": 240, "me": true,
                      "winner": true}]}''';
      final challenge = Challenge.fromJson(jsonDecode(json))!;
      expect(challenge.kind, ChallengeMetric.minutes);
      expect(challenge.iWon, isTrue);
      expect(challenge.monday, november(9));
    });

    test('Fortschritt in der Stufe', () {
      final progress = GameLevel.progress(345);
      expect(progress.inLevel, 45);
      expect(progress.level, ScoreRules.level(345));
    });
  });
}
