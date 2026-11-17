// „Meine Belastung heute“ (neu in AIronLudi, Rückmeldung vom 17.11.2026).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

final today = CalendarDay(2026, 11, 17);

GarminActivity activity(int id, CalendarDay day, String type, int minutes) => GarminActivity(id)
  ..typeKey = type
  ..startLocal = '${day.iso} 07:00:00'
  ..durationSeconds = minutes * 60.0;

/// Sechs Wochen täglich 45 min Laufen (45 Punkte ohne Messwerte): üblicher Tag etwa 28 Punkte.
List<GarminActivity> history() => [
  for (var offset = 1; offset <= 42; offset++) activity(offset, today.adding(-offset), 'running', 45),
];

const normal = Recommendation(level: RecoveryLevel.normal, reasons: []);

void main() {
  test('Ruhiger Tag ohne Plan und Training', () {
    final strain = DailyStrainRules.compute(
      activities: history(),
      plannedToday: const [],
      recovery: normal,
      today: today,
    );
    expect(strain.level, StrainLevel.rest);
    expect(strain.headline, 'Heute ruhig');
    expect(strain.week, hasLength(7));
    expect(strain.typical, greaterThan(DailyStrainRules.minimumTypical));
  });

  test('Geplant, aber noch nicht erledigt; erledigte Einheit zählt nicht doppelt', () {
    const easy = [SessionSlot(TrainingSport.run)];
    final open = DailyStrainRules.compute(activities: history(), plannedToday: easy, recovery: normal, today: today);
    expect(open.done, 0);
    expect(open.planned, 45);
    expect(open.headline, endsWith('geplant'));
    expect(open.advice, 'Noch nichts erledigt, 45 Punkte geplant.');
    const slots = [SessionSlot(TrainingSport.run, SessionIntensity.long)];
    final long = DailyStrainRules.compute(activities: history(), plannedToday: slots, recovery: normal, today: today);
    expect(long.level, StrainLevel.veryHigh);
    expect(long.advice, startsWith('Geplant sind 100 Punkte'));
    final done = DailyStrainRules.compute(
      activities: [...history(), activity(99, today, 'running', 120)],
      plannedToday: slots,
      recovery: normal,
      today: today,
    );
    expect(done.planned, 0);
    expect(done.done, 120);
    expect(done.level, StrainLevel.veryHigh);
    expect(done.headline, 'Sehr hoch belastet');
  });

  test('Erholungsampel: Pause streicht Geplantes, locker warnt bei hoher Belastung', () {
    const slots = [SessionSlot(TrainingSport.run, SessionIntensity.hard)];
    final pause = DailyStrainRules.compute(
      activities: history(),
      plannedToday: slots,
      recovery: const Recommendation(level: RecoveryLevel.pause, reasons: ['nur 4 h Schlaf']),
      today: today,
    );
    expect(pause.planned, 0);
    expect(pause.advice, contains('Pause'));
    final locker = DailyStrainRules.compute(
      activities: [...history(), activity(98, today, 'cycling', 45)],
      plannedToday: const [],
      recovery: const Recommendation(level: RecoveryLevel.locker, reasons: []),
      today: today,
    );
    expect(locker.level, StrainLevel.high);
    expect(locker.advice, contains('eingeschränkter Erholung'));
  });

  test('Ausdauerplan hat Vorrang, App-Krafttraining zählt mit', () {
    final plan = TrainingPlanEngine.generate(
      TrainingPlanRequest(
        username: 'anna',
        mode: PlanningMode.period,
        sports: const [EnduranceSport.bike],
        start: today,
        weeklyMinutes: 300,
        days: Weekday.values,
        longDay: Weekday.sunday,
        weeks: 2,
      ),
      now: DateTime.utc(2026, 11, 17),
      id: 'S',
    );
    final slot = plan.slotsOn(today).single;
    final strain = DailyStrainRules.compute(
      activities: history(),
      plannedToday: const [SessionSlot(TrainingSport.bike), SessionSlot(TrainingSport.strength)],
      enduranceToday: [slot],
      recovery: normal,
      today: today,
      gymMinutesToday: 60,
    );
    expect(strain.planned, slot.current.load); // Rad aus dem Plan, Kraft schon erledigt
    expect(strain.done, 35);
  });

  test('Ohne Verlauf: feste Stufen statt „sehr hoch“ gegen einen unbekannten Alltag', () {
    final strain = DailyStrainRules.compute(
      activities: const [],
      plannedToday: const [SessionSlot(TrainingSport.run, SessionIntensity.hard)],
      recovery: null,
      today: today,
    );
    expect(strain.level, StrainLevel.moderate);
    expect(strain.advice, contains('Noch kein Verlauf'));
  });
}
