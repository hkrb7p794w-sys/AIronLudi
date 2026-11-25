// Zeitrechner für die Regler auf den Seiten „Almere“ und „Marathon“ sowie einheitliche Namen der Krafteinheiten.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  group('Zeitrechner 70.3', () {
    test('Ausgangswerte ergeben dieselbe Zeit wie die Schätzung', () {
      final config = SeasonConfig.standard;
      final estimate = RaceEstimate(config: config, tests: const [], today: CalendarDay(2026, 11, 25));
      final times = TriathlonTimes.season(config);
      expect(times.totalMinutes, closeTo(estimate.totalMinutes, 1e-9));
      expect(times.transitionMinutes, RaceEstimate.transition1 + RaceEstimate.transition2);
    });

    test('Regler ändern die Abschnitte wie die Tabelle der Hebel', () {
      final config = SeasonConfig.standard;
      final estimate = RaceEstimate(config: config, tests: const [], today: CalendarDay(2026, 11, 25));
      final base = TriathlonTimes.season(config);
      final faster = base.copyWith(
        swimSecondsPer100m: base.swimSecondsPer100m - 5,
        bikeKmh: base.bikeKmh + 1,
        runSecondsPerKm: base.runSecondsPerKm - 10,
      );
      expect(base.swimMinutes - faster.swimMinutes, closeTo(estimate.savings.swim, 1e-9));
      expect(base.bikeMinutes - faster.bikeMinutes, closeTo(estimate.savings.bike, 1e-9));
      expect(base.runMinutes - faster.runMinutes, closeTo(estimate.savings.run, 1e-9));
      // 30 km/h über 94 km: 3:08 h.
      expect(RaceEstimate.hoursMinutes(base.copyWith(bikeKmh: 30).bikeMinutes), '3:08');
    });

    test('Werte außerhalb der Regler werden hineingezogen', () {
      final times = TriathlonTimes(swimSecondsPer100m: 30, bikeKmh: 80, runSecondsPerKm: 900, transitionMinutes: 0);
      expect(times.swimSecondsPer100m, TriathlonTimes.swimMin);
      expect(times.bikeKmh, TriathlonTimes.bikeMax);
      expect(times.runSecondsPerKm, TriathlonTimes.runMax);
      expect(times.transitionMinutes, TriathlonTimes.transitionMin);
    });
  });

  group('Zeitrechner Marathon', () {
    test('Endzeit und Zwischenzeiten aus der Pace', () {
      expect(MarathonTimes.seconds(290), 12237);
      expect(TimeText.hms(MarathonTimes.seconds(290)), '3:23:57');
      expect(MarathonTimes.seconds(300, kilometers: 10), 3000);
      expect(MarathonTimes.seconds(300, kilometers: 21.0975), 6329);
    });

    test('realistische Spanne aus dem Halbmarathon', () {
      final range = MarathonTimes.fromHalf(6300);
      expect((range.low, range.high), (13545, 13860));
      expect(MarathonTimes.clampHalf(100), MarathonTimes.halfMin);
      expect(MarathonTimes.clampPace(1000), MarathonTimes.paceMax);
    });
  });

  group('Namen der Krafteinheiten', () {
    test('ältere Namen heißen wie heute, andere bleiben', () {
      expect(WorkoutNames.canonical('Push A'), 'Push');
      expect(WorkoutNames.canonical('Pull A'), 'Pull');
      expect(WorkoutNames.canonical('Push & Pull B'), 'Pull & Push');
      expect(WorkoutNames.canonical('Push + Pull'), 'Pull & Push');
      expect(WorkoutNames.canonical('Beine'), 'Lower');
      expect(WorkoutNames.canonical('Ganzkörper A'), 'Ganzkörper A');
    });

    test('Plan, gespeicherte Einheiten und Routinen nutzen die neuen Namen', () {
      expect(GymPlan.standard.workouts.map((workout) => workout.name), ['Push', 'Pull', 'Pull & Push', 'Lower']);
      final old = GymSession(
        workoutKey: 'gymbook:2026-10-23:Push & Pull B',
        title: 'Push & Pull B',
        start: DateTime.utc(2026, 10, 23, 17),
        end: DateTime.utc(2026, 10, 23, 18),
        exercises: [],
      );
      final normalized = ExerciseAliases.normalized(old);
      expect(normalized.title, 'Pull & Push');
      expect(normalized.workoutKey, 'gymbook:2026-10-23:Push & Pull B');
      expect(old.title, 'Push & Pull B');
      final settings = GymSettings.fromJson({
        'routines': [for (final name in ['Push A', 'Lower', 'Eigene']) Routine(name: name, items: const []).toJson()],
      });
      expect(settings.routines.map((routine) => routine.name), ['Push', 'Lower', 'Eigene']);
    });
  });
}
