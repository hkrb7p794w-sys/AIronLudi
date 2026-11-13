// Port von SeasonPlanTests aus CoachCoreTests/CoachTests.swift.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

CalendarDay day(int year, int month, int dayOfMonth) => CalendarDay(year, month, dayOfMonth);

GarminActivity activity(int id, String typeKey, CalendarDay on, {double km = 5}) => GarminActivity(id)
  ..typeKey = typeKey
  ..startLocal = '${on.iso} 07:00:00'
  ..distanceMeters = km * 1000
  ..durationSeconds = 1800;

void main() {
  final config = SeasonConfig.standard;

  test('Phasengrenzen wie im Altbestand', () {
    final bounds = SeasonPlan.phaseBounds(config);
    expect(bounds.map((span) => span.phase), TrainingPhase.values);
    expect(bounds[1].end, day(2027, 4, 11)); // Marathon-Aufbau bis 11.04.
    expect(bounds[2].start, day(2027, 4, 12));
    expect(bounds[3], PhaseSpan(phase: TrainingPhase.regeneration, start: day(2027, 5, 3), end: day(2027, 5, 16)));
    expect(bounds[4].start, day(2027, 5, 17)); // Almere-Aufbau 17.05.–08.08.
    expect(bounds[4].end, day(2027, 8, 8));
    expect(bounds[5].start, day(2027, 8, 9)); // Almere-Peak 09.08.–29.08.
    expect(bounds[6].start, day(2027, 8, 30)); // Taper ab Mo 30.08.
    expect(bounds[6].end, day(2027, 9, 11));
  });

  test('Phase eines Tages', () {
    expect(SeasonPlan.phase(day(2026, 10, 23), config), TrainingPhase.grundlage);
    expect(SeasonPlan.phase(day(2027, 2, 1), config), TrainingPhase.marathonAufbau);
    expect(SeasonPlan.phase(day(2027, 9, 20), config), TrainingPhase.almereTaper);
    expect(SeasonPlan.phase(day(2026, 1, 1), config), TrainingPhase.grundlage);
  });

  test('Wochentag beginnt am Montag', () {
    expect(day(2026, 10, 19).weekdayIndex, 0); // Montag
    expect(day(2026, 10, 25).weekdayIndex, 6); // Sonntag
    expect(day(2027, 9, 11).weekdayIndex, 5); // Samstag
  });

  test('Wochenvolumen zählt die Kalenderwoche und übergeht Rad ohne Distanz', () {
    final week = WeeklyVolume.from([
      activity(1, 'running', day(2026, 10, 19), km: 8),
      activity(2, 'running', day(2026, 10, 18)), // Sonntag davor
      activity(3, 'virtual_ride', day(2026, 10, 20), km: 30),
      activity(4, 'indoor_cycling', day(2026, 10, 20), km: 0), // Zweitaufzeichnung der Uhr
      activity(5, 'strength_training', day(2026, 10, 21), km: 0),
      activity(6, 'lap_swimming', day(2026, 10, 22), km: 2),
    ], weekContaining: day(2026, 10, 23));
    expect(week.sessions, {
      ActivitySport.run: 1,
      ActivitySport.bike: 1,
      ActivitySport.strength: 1,
      ActivitySport.swim: 1,
    });
    expect(week.kilometers[ActivitySport.run], 8);
    expect(week.minutes[ActivitySport.bike], 30);
  });

  test('Gym-Einheiten der App zählen, außer an Tagen mit Kraft-Aufzeichnung der Uhr', () {
    final week = WeeklyVolume.from(
      [activity(5, 'strength_training', day(2026, 10, 21), km: 0)],
      weekContaining: day(2026, 10, 23),
      gymDays: [day(2026, 10, 21), day(2026, 10, 22), day(2026, 10, 12)],
    );
    expect(week.sessions[ActivitySport.strength], 2);
  });

  test('Planzustand nennt Offenes und die heutigen Fixpunkte', () {
    final friday = day(2026, 10, 23);
    final week = WeeklyVolume()..sessions = {ActivitySport.run: 1, ActivitySport.strength: 4};
    final state = SeasonPlan.state(today: friday, config: config, week: week);
    expect(state.weekday, 'Freitag');
    expect(state.phase, TrainingPhase.grundlage);
    expect(state.daysLeftInWeek, 2);
    expect(state.todayFixed.map((item) => item.text), ['Push + Pull kombiniert (Home-Gym)']);
    expect(state.weekOpen, ['1× Schwimmen', '1× Laufen (1x Zone 2, 1x Schwelle/Intervall im Wechsel)', '1× Rad']);
    expect(state.targets.firstWhere((item) => item.target.sport == ActivitySport.run).percent, 50);
    expect(state.daysToRace, friday.daysUntil(day(2027, 9, 11)));
  });

  test('Rad am Wochenende gilt als erledigt, wenn das Soll erreicht ist', () {
    final week = WeeklyVolume()..sessions = {ActivitySport.bike: 1};
    final state = SeasonPlan.state(today: day(2026, 10, 25), config: config, week: week);
    expect(state.todayFixed.first.done, isTrue);
    expect(state.todayFixed.first.text, endsWith('diese Woche schon erledigt'));
    // Die Musterwoche selbst bleibt unverändert.
    expect(SeasonPlan.template(TrainingPhase.grundlage, 6).first.done, isFalse);
  });

  test('Plantexte nutzen die Testwerte', () {
    final custom = config.copy()..ftpWatts = 200;
    expect(SeasonPlan.planText(TrainingPhase.almerePeak, custom).bike, contains('150–156 W'));
    expect(SeasonPlan.testValuesText(config), contains('CSS 2:10 /100 m'));
    expect(SeasonPlan.testValuesText(config), contains('Lauf-Schwellenpace 4:55 /km'));
  });

  test('liest ältere gespeicherte Stände', () {
    final decoded = SeasonConfig.fromJson(jsonDecode('{"mainRaceName": "Test", "ftpWatts": 190}'))!;
    expect(decoded.mainRaceName, 'Test');
    expect(decoded.ftpWatts, 190);
    expect(decoded.marathonDate, SeasonConfig.standard.marathonDate);
    expect(SeasonConfig.fromJson(jsonDecode(jsonEncode(config.toJson()))), config);
    expect(SeasonConfig.fromJson(jsonDecode('{"ftpWatts": "viel"}')), isNull);
  });

  test('Entwurf beim Wechsel vom Saisonplan zum persönlichen Profil', () {
    final draft = UserProfile.personalDraft(config);
    expect(draft.mode, ProfileMode.personal);
    expect(draft.onboardingDone, isFalse);
    expect(draft.event?.name, 'Challenge Almere');
    expect(draft.event?.kind, EventKind.triathlon);
    expect(draft.trains(TrainingSport.swim), isTrue);
  });
}
