// „Jetzt dran“ mit dem adaptiven Ausdauerplan (Roast B-01): Einheiten des Ausdauerplans erscheinen, gleiche
// Sportarten aus dem Wochenplan fallen weg, die Ampel warnt auch für sie.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 11, 24);

TodayFocusItem weekly(TrainingSport sport, String title) => TodayFocusItem(
  id: 'woche:$title',
  sport: sport,
  title: title,
  target: 'Soll 45 min · Locker',
  demanding: false,
  status: SessionStatus.open,
  chip: '',
  detail: '',
);

TodayFocus focus({RecoveryLevel? level, List<TodayFocusItem>? items}) => TodayFocus(
  level: level,
  headline: 'Heute',
  detail: '',
  why: null,
  conflict: null,
  items: items ?? [weekly(TrainingSport.run, 'Lockerer Lauf'), weekly(TrainingSport.strength, 'Kraft')],
  progress: const TodayFocusProgress(sessionsDone: 0, sessionsPlanned: 2, minutesDone: 0, minutesPlanned: 90),
  evidenceIDs: const [],
);

PlanSlot slot(EnduranceWorkoutType type, {EnduranceSport sport = EnduranceSport.run, int minutes = 60}) => PlanSlot(
  id: 'w3-${type.name}',
  day: today,
  week: 3,
  phase: EndurancePhase.build,
  baseline: EnduranceWorkout(sport: sport, type: type, title: type.label, minutes: minutes, steps: const [], load: 70),
);

void main() {
  test('Ausdauerplan ersetzt die gleiche Sportart, andere bleiben', () {
    final merged = focus().withEndurance([slot(EnduranceWorkoutType.threshold)]);
    expect(merged.items.map((item) => item.title), ['Kraft', 'Schwelle']);
    final item = merged.items.last;
    expect(item.id, startsWith(TodayFocus.enduranceItemPrefix));
    expect(item.sport, TrainingSport.run);
    expect(item.target, 'Soll 60 min · Schwelle · Ausdauerplan');
    expect(item.demanding, isTrue);
    expect(item.status, SessionStatus.open);
  });

  test('Ruhetag des Ausdauerplans erscheint nicht; ohne Einheiten bleibt alles gleich', () {
    final original = focus();
    expect(identical(original.withEndurance([slot(EnduranceWorkoutType.rest)]), original), isTrue);
    expect(identical(original.withEndurance(const []), original), isTrue);
  });

  test('Ampel „locker“ warnt vor harter Einheit des Ausdauerplans', () {
    final merged = focus(level: RecoveryLevel.locker).withEndurance(
      [slot(EnduranceWorkoutType.vo2max, sport: EnduranceSport.bike)],
      reasons: const ['kurzer Schlaf (5,5 h)'],
    );
    expect(merged.conflict, startsWith('Regel: locker'));
    expect(merged.conflict, contains('VO2max-Intervalle'));
  });
}
