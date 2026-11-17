// Adaptiver Ausdauerplan (neu in AIronLudi, keine Swift-Vorlage): Periodisierung, Verteilung, Anpassung, Exporte.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const thresholds = AthleteThresholds(
  runThresholdPace: 270, // 4:30 /km
  ftpWatts: 250,
  swimCss: 110, // 1:50 /100 m
  runThresholdHeartRate: 170,
);

final monday = CalendarDay(2026, 11, 16);
final now = DateTime.utc(2026, 11, 16, 6);

TrainingPlanRequest triRequest({int weeks = 12}) => TrainingPlanRequest(
  username: 'anna',
  mode: PlanningMode.goal,
  sports: const [],
  start: monday,
  weeklyMinutes: 480,
  days: const [Weekday.monday, Weekday.tuesday, Weekday.wednesday, Weekday.thursday, Weekday.saturday, Weekday.sunday],
  longDay: Weekday.saturday,
  event: EnduranceEvent.triOlympic,
  eventDay: monday.adding(7 * (weeks - 1) + 6),
  targetMinutes: 150,
  thresholds: thresholds,
);

TrainingPlanRequest runPeriod({int weeks = 8}) => TrainingPlanRequest(
  username: 'anna',
  mode: PlanningMode.period,
  sports: const [EnduranceSport.run, EnduranceSport.bike],
  start: monday,
  weeklyMinutes: 300,
  days: const [Weekday.tuesday, Weekday.thursday, Weekday.saturday, Weekday.sunday],
  longDay: Weekday.sunday,
  weeks: weeks,
  thresholds: thresholds,
);

GarminActivity activity(
  int id,
  CalendarDay day,
  String type, {
  required int minutes,
  double? power,
  double? speed,
  double? heartRate,
}) => GarminActivity(id)
  ..typeKey = type
  ..startLocal = '${day.iso} 07:00:00'
  ..durationSeconds = minutes * 60.0
  ..normalizedPower = power
  ..averageSpeed = speed
  ..averageHeartRate = heartRate;

DailyMetrics metrics(CalendarDay day, {double? sleepHours, String? hrv, double? battery, double? restingHeartRate}) =>
    DailyMetrics(day)
      ..sleepSeconds = sleepHours == null ? null : sleepHours * 3600
      ..hrvStatus = hrv
      ..bodyBatteryAtWake = battery
      ..restingHeartRate = restingHeartRate;

void main() {
  group('Periodisierung', () {
    test('Marathon über 16 Wochen: Grundlage, Aufbau, Spitze, Tapering, Wettkampfwoche', () {
      final phases = TrainingPlanEngine.periodize(mode: PlanningMode.goal, weeks: 16, event: EnduranceEvent.marathon);
      expect(phases.length, 16);
      expect(phases.last, EndurancePhase.race);
      expect(phases[14], EndurancePhase.taper);
      expect(phases.sublist(12, 14), [EndurancePhase.peak, EndurancePhase.peak]);
      expect(phases.first, EndurancePhase.base);
      expect(phases.contains(EndurancePhase.build), isTrue);
      // 3:1 – jede vierte Woche Entlastung.
      expect(phases[3], EndurancePhase.recovery);
      expect(phases[7], EndurancePhase.recovery);
      expect(phases[11], EndurancePhase.recovery);
    });

    test('Langdistanz tapert drei Wochen, 5 km nur die Wettkampfwoche', () {
      final full = TrainingPlanEngine.periodize(mode: PlanningMode.goal, weeks: 20, event: EnduranceEvent.triFull);
      expect(full.sublist(17), [EndurancePhase.taper, EndurancePhase.taper, EndurancePhase.race]);
      final short = TrainingPlanEngine.periodize(mode: PlanningMode.goal, weeks: 6, event: EnduranceEvent.run5k);
      expect(short.last, EndurancePhase.race);
      expect(short.where((phase) => phase == EndurancePhase.taper), isEmpty);
    });

    test('Kurzer Zielplan und Zeitraum-Pläne', () {
      expect(TrainingPlanEngine.periodize(mode: PlanningMode.goal, weeks: 2, event: EnduranceEvent.halfMarathon), [
        EndurancePhase.taper,
        EndurancePhase.race,
      ]);
      final base = TrainingPlanEngine.periodize(mode: PlanningMode.period, weeks: 8, focus: PeriodFocus.base);
      expect(base.toSet(), {EndurancePhase.base, EndurancePhase.recovery});
      final fitness = TrainingPlanEngine.periodize(mode: PlanningMode.period, weeks: 12);
      expect(fitness.first, EndurancePhase.base);
      expect(fitness.last, isNot(EndurancePhase.race));
      expect(fitness.sublist(6).where((phase) => phase == EndurancePhase.build), isNotEmpty);
    });

    test('Umfang steigt höchstens 10 % je Woche, Entlastung und Tapering deutlich weniger', () {
      final phases = TrainingPlanEngine.periodize(mode: PlanningMode.goal, weeks: 16, event: EnduranceEvent.marathon);
      final factors = TrainingPlanEngine.volumeFactors(phases);
      // Höchstens 10 % mehr als die letzte Belastungswoche (Entlastungswochen zählen nicht als Bezug).
      double? last;
      for (var index = 0; index < factors.length; index++) {
        if (phases[index] == EndurancePhase.recovery) continue;
        if (last != null) expect(factors[index], lessThanOrEqualTo(last * 1.1 + 0.001), reason: 'Woche $index');
        last = factors[index];
      }
      expect(factors[3], lessThan(factors[2] * 0.7));
      expect(factors.last, 0.45);
      expect(factors.every((value) => value <= 1.0), isTrue);
    });

    test('Eingabeprüfung', () {
      expect(TrainingPlanEngine.validate(triRequest()), isNull);
      final past = TrainingPlanRequest(
        username: 'anna',
        mode: PlanningMode.goal,
        sports: const [],
        start: monday,
        weeklyMinutes: 300,
        days: const [Weekday.monday],
        longDay: Weekday.monday,
        event: EnduranceEvent.run10k,
        eventDay: monday.adding(-3),
      );
      expect(TrainingPlanEngine.validate(past), 'Der Wettkampf liegt vor dem Planbeginn.');
      expect(() => TrainingPlanEngine.generate(past, now: now), throwsArgumentError);
    });
  });

  group('Gesamtplan', () {
    final plan = TrainingPlanEngine.generate(triRequest(), now: now, id: 'P1');

    test('Makrozyklus für den ganzen Zeitraum, nur an Trainingstagen, Wettkampf am Zieltag', () {
      expect(plan.username, 'anna');
      expect(plan.weeks.length, 12);
      expect(plan.weeks.first.monday, monday);
      final allowed = {0, 1, 2, 3, 5, 6};
      final eventDay = triRequest().eventDay!;
      for (final slot in plan.slots) {
        if (slot.baseline.type == EnduranceWorkoutType.race) {
          expect(slot.day, eventDay);
        } else {
          expect(allowed.contains(slot.day.weekdayIndex), isTrue, reason: slot.id);
          expect(slot.day < eventDay, isTrue);
        }
      }
      final races = plan.slots.where((slot) => slot.baseline.type == EnduranceWorkoutType.race).toList();
      expect(races.map((slot) => slot.baseline.sport).toSet(), EnduranceSport.values.toSet());
      expect(races.fold(0, (sum, slot) => sum + slot.baseline.minutes), closeTo(150, 10));
      expect(plan.slots.map((slot) => slot.id).toSet().length, plan.slots.length);
    });

    test('Alle drei Disziplinen jede Woche, lange Rad-Einheit am Samstag, keine zwei harten Tage hintereinander', () {
      for (final week in plan.weeks.where((week) => week.phase != EndurancePhase.race)) {
        final slots = plan.slotsInWeek(week.index);
        expect(slots.map((slot) => slot.baseline.sport).toSet(), EnduranceSport.values.toSet(), reason: '$week');
        final long = slots.where((slot) => slot.baseline.type == EnduranceWorkoutType.long).single;
        expect(long.baseline.sport, EnduranceSport.bike);
        expect(long.day.weekdayIndex, Weekday.saturday.index);
        final hardDays = [
          for (final slot in slots)
            if (slot.baseline.type.isHard || slot.baseline.type == EnduranceWorkoutType.long) slot.day,
        ];
        for (final day in hardDays) {
          expect(hardDays.contains(day.adding(1)), isFalse, reason: 'Woche ${week.index}: $day');
        }
      }
    });

    test('Aufbauwochen haben Schwelle und VO2max, Entlastung keine harten Einheiten', () {
      final build = plan.weeks.firstWhere((week) => week.phase == EndurancePhase.build);
      final types = plan.slotsInWeek(build.index).map((slot) => slot.baseline.type).toSet();
      expect(types, containsAll([EnduranceWorkoutType.threshold, EnduranceWorkoutType.vo2max]));
      final recovery = plan.weeks.firstWhere((week) => week.phase == EndurancePhase.recovery);
      expect(plan.slotsInWeek(recovery.index).any((slot) => slot.baseline.type.isHard), isFalse);
      final minutes = [
        for (final week in plan.weeks) plan.slotsInWeek(week.index).fold(0, (sum, slot) => sum + slot.baseline.minutes),
      ];
      expect(minutes[recovery.index], lessThan(minutes[recovery.index - 1]));
    });

    test('JSON hin und zurück; fremder Benutzer bekommt den Plan nicht', () {
      final json = jsonDecode(jsonEncode(plan.toJson()));
      final restored = EndurancePlan.fromJson(json, username: 'anna')!;
      expect(restored.slots.length, plan.slots.length);
      expect(restored.weeks.last.phase, EndurancePhase.race);
      for (var index = 0; index < plan.slots.length; index++) {
        expect(restored.slots[index].baseline.sameContent(plan.slots[index].baseline), isTrue);
      }
      expect(restored.request.event, EnduranceEvent.triOlympic);
      expect(EndurancePlan.fromJson(json, username: 'ben'), isNull);
      final tampered = jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>;
      (tampered['request']! as Map)['username'] = 'ben';
      expect(EndurancePlan.fromJson(tampered, username: 'anna'), isNull);
    });

    test('Zeitraum-Plan mit vier Tagen', () {
      final period = TrainingPlanEngine.generate(runPeriod(), now: now, id: 'P2');
      expect(period.weeks.length, 8);
      for (final week in period.weeks) {
        final slots = period.slotsInWeek(week.index);
        expect(slots.length, 4);
        expect(slots.where((slot) => slot.baseline.type.isHard).length, lessThanOrEqualTo(1));
        expect(slots.where((slot) => slot.baseline.type == EnduranceWorkoutType.long).single.day.weekdayIndex, 6);
      }
      expect(period.slots.first.baseline.type, isNot(EnduranceWorkoutType.tempo)); // erste Woche ohne Intensität
    });
  });

  group('Einheiten', () {
    test('Lauf-Schwelle mit Pace-Zielen', () {
      final workout = EnduranceWorkouts.build(
        sport: EnduranceSport.run,
        type: EnduranceWorkoutType.threshold,
        minutes: 60,
        thresholds: thresholds,
      );
      expect(workout.steps.first, isA<EnduranceStep>());
      final repeat = workout.steps[1] as EnduranceRepeat;
      expect(repeat.count, 3);
      expect(repeat.steps.first.seconds, 480);
      expect(repeat.steps.first.target, const StepTarget(TargetKind.pace, low: 262, high: 278));
      expect(workout.title, 'Laufen Schwelle 3×8 min');
      expect(workout.minutes, 52);
    });

    test('Rad mit Watt, ohne FTP mit Puls, ohne beides offen', () {
      final bike = EnduranceWorkouts.build(
        sport: EnduranceSport.bike,
        type: EnduranceWorkoutType.vo2max,
        minutes: 60,
        thresholds: thresholds,
      );
      final repeat = bike.steps[1] as EnduranceRepeat;
      expect(repeat.steps.first.target, const StepTarget(TargetKind.power, low: 265, high: 300));
      final heart = EnduranceWorkouts.build(
        sport: EnduranceSport.bike,
        type: EnduranceWorkoutType.endurance,
        minutes: 60,
        thresholds: const AthleteThresholds(runThresholdHeartRate: 170),
      );
      expect((heart.steps[1] as EnduranceStep).target, const StepTarget(TargetKind.heartRate, low: 134, high: 147));
      final open = EnduranceWorkouts.build(
        sport: EnduranceSport.run,
        type: EnduranceWorkoutType.endurance,
        minutes: 45,
        thresholds: const AthleteThresholds(),
      );
      expect((open.steps[1] as EnduranceStep).target.kind, TargetKind.open);
    });

    test('Schwimmen in Metern mit Pausen am Rand', () {
      final swim = EnduranceWorkouts.build(
        sport: EnduranceSport.swim,
        type: EnduranceWorkoutType.threshold,
        minutes: 50,
        thresholds: thresholds,
      );
      final repeat = swim.steps[1] as EnduranceRepeat;
      expect(repeat.steps.first.meters, 200);
      expect(repeat.steps.last.isPause, isTrue);
      expect(swim.meters, 300 + repeat.count * 200 + 200);
      expect(swim.minutes, inInclusiveRange(30, 60));
    });

    test('Belastungspunkte: eine Stunde an der FTP sind 100', () {
      final hour = activity(1, monday, 'cycling', minutes: 60, power: 250);
      expect(TrainingLoad.actual(hour, thresholds), 100);
      final run = activity(2, monday, 'running', minutes: 60, speed: 1000 / 270 * 0.8);
      expect(TrainingLoad.actual(run, thresholds), 64);
      final unknown = activity(3, monday, 'running', minutes: 30);
      expect(TrainingLoad.actual(unknown, const AthleteThresholds()), 30);
      final state = TrainingLoad.state({for (var i = 1; i <= 7; i++) monday.adding(-i): 150}, day: monday);
      expect(state.form, lessThan(-50));
    });
  });

  group('Anpassung', () {
    // Zeitraum-Plan: Woche 2 (Aufbau ab Woche 5) – wir nehmen Woche 2 (Grundlage mit Tempo).
    EndurancePlan basePlan() => TrainingPlanEngine.generate(runPeriod(), now: now, id: 'P3');

    PlanSlot slotOn(EndurancePlan plan, CalendarDay day) => plan.slotsOn(day).single;

    test('Erledigt und ausgefallen werden zugeordnet', () {
      final plan = basePlan();
      final tuesday = monday.adding(1);
      final thursday = monday.adding(3);
      final result = TrainingPlanEngine.adapt(
        plan,
        activities: [
          activity(
            10,
            tuesday,
            slotOn(plan, tuesday).baseline.sport == EnduranceSport.run ? 'running' : 'cycling',
            minutes: 50,
          ),
        ],
        metrics: const [],
        today: monday.adding(4),
        now: now,
      );
      expect(slotOn(result.plan, tuesday).status, SlotStatus.completed);
      expect(slotOn(result.plan, tuesday).actualLoad, isNotNull);
      expect(slotOn(result.plan, thursday).status, SlotStatus.missed);
      expect(result.plan.lastAdapted, monday.adding(4));
    });

    test('Rad deutlich härter als geplant entschärft den nächsten Lauf (disziplinübergreifend)', () {
      final plan = TrainingPlanEngine.generate(triRequest(), now: now, id: 'P4');
      // Woche mit Aufbau: harte Lauf-Einheit suchen, deren Vortag eine Rad-Einheit ist.
      final target = plan.slots.firstWhere((slot) {
        if (slot.baseline.sport != EnduranceSport.run || !slot.baseline.type.isHard) return false;
        final before = plan.slotsOn(slot.day.adding(-1));
        return before.length == 1 && before.single.baseline.sport == EnduranceSport.bike;
      });
      final rideDay = target.day.adding(-1);
      final ride = plan.slotsOn(rideDay).single;
      final hard = activity(20, rideDay, 'cycling', minutes: 150, power: 230);
      final result = TrainingPlanEngine.adapt(plan, activities: [hard], metrics: const [], today: target.day, now: now);
      final adapted = result.plan.slot(target.id)!;
      expect(adapted.current.type, EnduranceWorkoutType.endurance);
      expect(adapted.current.sport, EnduranceSport.run);
      expect(adapted.current.note, contains('Rad am'));
      expect(adapted.current.note, contains('statt ${ride.baseline.load.round()}'));
      final entry = result.changes.singleWhere((change) => change.slotID == target.id);
      expect(entry.cause, AdjustmentCause.load);
      expect(result.plan.revision, plan.revision + 1);
    });

    test('Ausgefallene Schlüsseleinheit wird einmal in der Woche nachgeholt', () {
      final plan = basePlan();
      // Woche 2: Di Lauf-Tempo, Do und Sa Rad-Grundlage, So langer Lauf.
      final week = plan.slotsInWeek(1);
      final tempo = week.firstWhere((slot) => slot.baseline.type == EnduranceWorkoutType.tempo);
      expect(tempo.day.weekdayIndex, Weekday.tuesday.index);
      final result = TrainingPlanEngine.adapt(
        plan,
        activities: const [],
        metrics: const [],
        today: tempo.day.adding(1),
        now: now,
      );
      expect(result.plan.slot(tempo.id)!.status, SlotStatus.missed);
      final makeup = result.changes.single;
      expect(makeup.cause, AdjustmentCause.missed);
      expect(makeup.reason, startsWith('Nachgeholt: Laufen Tempo'));
      final target = result.plan.slot(makeup.slotID)!;
      expect(target.day.weekdayIndex, Weekday.thursday.index); // nicht Sa: Tag vor der langen Einheit
      expect(target.current.type, EnduranceWorkoutType.tempo);
      // Am Tag danach bleibt es bei der einen Ersatz-Einheit.
      final later = TrainingPlanEngine.adapt(
        result.plan,
        activities: const [],
        metrics: const [],
        today: tempo.day.adding(2),
        now: now,
      );
      expect(later.changes, isEmpty);
    });

    test(
      'Schlechte Erholung: locker statt Intervall, Ruhetag bei sehr schlechten Werten, danach wieder wie geplant',
      () {
        final plan = TrainingPlanEngine.generate(triRequest(), now: now, id: 'P5');
        final hard = plan.slots.firstWhere((slot) => slot.baseline.type == EnduranceWorkoutType.threshold);
        final day = hard.day;
        final locker = TrainingPlanEngine.adapt(
          plan,
          activities: const [],
          metrics: [metrics(day, sleepHours: 5.5)],
          today: day,
          now: now,
        );
        final easy = locker.plan.slot(hard.id)!;
        expect(easy.current.type, EnduranceWorkoutType.endurance);
        expect(easy.current.note, contains('kurzer Schlaf'));
        expect(easy.current.steps.whereType<EnduranceRepeat>(), isEmpty);

        final pause = TrainingPlanEngine.adapt(
          plan,
          activities: const [],
          metrics: [metrics(day, hrv: 'LOW', battery: 20)],
          today: day,
          now: now,
        );
        expect(pause.plan.slot(hard.id)!.current.type, EnduranceWorkoutType.rest);
        expect(pause.plan.slot(hard.id)!.current.note, contains('Body Battery 20'));

        // Am nächsten Morgen gute Werte: die Einheit von heute bleibt wie geplant, nichts hängt nach.
        final again = TrainingPlanEngine.adapt(
          locker.plan,
          activities: const [],
          metrics: [metrics(day, sleepHours: 8, hrv: 'BALANCED', battery: 80)],
          today: day,
          now: now,
        );
        final restored = again.plan.slot(hard.id)!;
        expect(restored.current.sameContent(restored.baseline), isTrue);
        expect(again.changes.single.cause, AdjustmentCause.restored);
      },
    );

    test('Ohne Health-Daten keine Änderung; zweiter Lauf ändert nichts mehr', () {
      final plan = TrainingPlanEngine.generate(triRequest(), now: now, id: 'P6');
      final first = TrainingPlanEngine.adapt(plan, activities: const [], metrics: const [], today: monday, now: now);
      expect(first.changes, isEmpty);
      expect(first.plan.revision, plan.revision);
      final hard = plan.slots.firstWhere((slot) => slot.baseline.type == EnduranceWorkoutType.vo2max);
      final once = TrainingPlanEngine.adapt(
        plan,
        activities: const [],
        metrics: [metrics(hard.day, sleepHours: 4)],
        today: hard.day,
        now: now,
      );
      final twice = TrainingPlanEngine.adapt(
        once.plan,
        activities: const [],
        metrics: [metrics(hard.day, sleepHours: 4)],
        today: hard.day,
        now: now,
      );
      expect(once.changes, isNotEmpty);
      expect(twice.changes, isEmpty);
    });

    test('Hohe Ermüdung nimmt die Intensität heute und morgen heraus, Wettkampf bleibt', () {
      final plan = TrainingPlanEngine.generate(triRequest(), now: now, id: 'P7');
      final hard = plan.slots.firstWhere((slot) => slot.baseline.type.isHard && slot.week > 2);
      final heavy = [
        for (var i = 1; i <= 10; i++) activity(100 + i, hard.day.adding(-i - 2), 'cycling', minutes: 150, power: 240),
      ];
      final result = TrainingPlanEngine.adapt(plan, activities: heavy, metrics: const [], today: hard.day, now: now);
      expect(result.plan.slot(hard.id)!.current.type, EnduranceWorkoutType.endurance);
      expect(result.changes.any((change) => change.cause == AdjustmentCause.fatigue), isTrue);

      final race = plan.slots.firstWhere((slot) => slot.baseline.type == EnduranceWorkoutType.race);
      final raceDay = TrainingPlanEngine.adapt(
        plan,
        activities: const [],
        metrics: [metrics(race.day, hrv: 'POOR')],
        today: race.day,
        now: now,
      );
      expect(raceDay.plan.slot(race.id)!.current.type, EnduranceWorkoutType.race);
    });
  });

  group('Exporte', () {
    final bike = EnduranceWorkouts.build(
      sport: EnduranceSport.bike,
      type: EnduranceWorkoutType.threshold,
      minutes: 75,
      thresholds: thresholds,
    );

    test('Zwift-Workout (.zwo)', () {
      final xml = ZwiftWorkoutFile.xml(bike);
      expect(xml, startsWith('<workout_file>'));
      expect(xml, contains('<sportType>bike</sportType>'));
      expect(xml, contains('<Warmup Duration="900" PowerLow="0.45" PowerHigh="0.75"/>'));
      expect(
        xml,
        contains('<IntervalsT Repeat="3" OnDuration="600" OffDuration="180" OnPower="1.00" OffPower="0.50"/>'),
      );
      expect(xml, contains('<Cooldown Duration="600" PowerLow="0.55" PowerHigh="0.45"/>'));
      expect(
        ZwiftWorkoutFile.supports(
          EnduranceWorkouts.build(
            sport: EnduranceSport.run,
            type: EnduranceWorkoutType.endurance,
            minutes: 40,
            thresholds: thresholds,
          ),
        ),
        isFalse,
      );
      final escaped = ZwiftWorkoutFile.xml(
        EnduranceWorkout(
          sport: EnduranceSport.bike,
          type: EnduranceWorkoutType.endurance,
          title: 'A & B <C>',
          minutes: 10,
          steps: bike.steps,
          load: 1,
        ),
      );
      expect(escaped, contains('<name>A &amp; B &lt;C&gt;</name>'));
    });

    test('FIT-Workout mit gültigen Prüfsummen, Schritten und Wiederholung', () {
      final bytes = FitWorkoutFile.bytes(bike, created: now);
      expect(bytes[0], 14);
      expect(ascii.decode(bytes.sublist(8, 12)), '.FIT');
      final size = bytes[4] | bytes[5] << 8 | bytes[6] << 16 | bytes[7] << 24;
      expect(bytes.length, 14 + size + 2);
      expect(FitEncoder.crc(bytes.sublist(0, 12)), bytes[12] | bytes[13] << 8);
      expect(FitEncoder.crc(bytes.sublist(14, 14 + size)), bytes[14 + size] | bytes[15 + size] << 8);
      final messages = _fitMessages(bytes);
      expect(messages.where((message) => message.global == 0).single.fields[0], [5]); // Dateityp workout
      final workout = messages.where((message) => message.global == 26).single;
      expect(workout.fields[4], [2]); // Rad
      expect(utf8.decode(workout.fields[8]!.takeWhile((byte) => byte != 0).toList()), bike.title);
      final steps = messages.where((message) => message.global == 27).toList();
      expect(steps.length, 5); // Aufwärmen, Belastung, Erholung, Wiederholung, Ausklang
      expect(_int(workout.fields[6]!), 5);
      final repeat = steps[3];
      expect(repeat.fields[1], [6]);
      expect(_int(repeat.fields[2]!), 1); // ab Schritt 1
      expect(_int(repeat.fields[4]!), 3);
      final interval = steps[1];
      expect(interval.fields[3], [4]); // Leistung
      expect(_int(interval.fields[5]!), 1000 + 238);
      expect(_int(interval.fields[6]!), 1000 + 263);
      expect(_int(interval.fields[2]!), 600000);
    });

    test('FIT-Workout Laufen mit Pace als Geschwindigkeit', () {
      final run = EnduranceWorkouts.build(
        sport: EnduranceSport.run,
        type: EnduranceWorkoutType.recovery,
        minutes: 30,
        thresholds: thresholds,
      );
      final step = _fitMessages(FitWorkoutFile.bytes(run, created: now)).where((m) => m.global == 27).single;
      expect(step.fields[3], [0]);
      expect(_int(step.fields[5]!), (1000 / 386 * 1000).round()); // langsamere Grenze zuerst
      expect(_int(step.fields[6]!), (1000 / 346 * 1000).round());
    });

    test('Garmin-Connect-Workout mit Zielen', () {
      final run = EnduranceWorkouts.build(
        sport: EnduranceSport.run,
        type: EnduranceWorkoutType.threshold,
        minutes: 60,
        thresholds: thresholds,
      );
      final payload = GarminEnduranceWorkout.payload(run);
      final steps = ((payload['workoutSegments']! as List).single as Map)['workoutSteps'] as List;
      expect(steps.length, 3);
      final group = steps[1] as Map;
      expect(group['type'], 'RepeatGroupDTO');
      expect(group['numberOfIterations'], 3);
      final interval = (group['workoutSteps'] as List).first as Map;
      expect((interval['targetType'] as Map)['workoutTargetTypeKey'], 'pace.zone');
      expect(interval['targetValueOne'], (1000 / 278 * 1000).round() / 1000);
      expect(interval['targetValueTwo'], (1000 / 262 * 1000).round() / 1000);
      expect(interval['endConditionValue'], 480);
      final watts = GarminEnduranceWorkout.payload(bike);
      final bikeInterval =
          ((((watts['workoutSegments']! as List).single as Map)['workoutSteps'] as List)[1] as Map)['workoutSteps']
              as List;
      expect(((bikeInterval.first as Map)['targetType'] as Map)['workoutTargetTypeKey'], 'power.zone');
      expect(
        () => GarminEnduranceWorkout.payload(
          EnduranceWorkouts.build(
            sport: EnduranceSport.run,
            type: EnduranceWorkoutType.rest,
            minutes: 0,
            thresholds: thresholds,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('Fingerabdruck und Dateiname', () {
      final day = CalendarDay(2026, 11, 20);
      expect(WorkoutExport.fingerprint(bike, day), WorkoutExport.fingerprint(bike, day));
      expect(WorkoutExport.fingerprint(bike, day), isNot(WorkoutExport.fingerprint(bike, day.adding(1))));
      expect(WorkoutExport.fileName(bike, day), '2026-11-20-rad-schwelle-3x10-min');
      expect(WorkoutExport.summary(bike)[1], '3 × (Belastung 10 min · 238–263 W / Erholung 3 min · 113–138 W)');
    });
  });

  group('Ziele aus der App', () {
    final today = CalendarDay(2026, 11, 17);

    test('Wettkampf aus der Einrichtung mit Zielzeit, Tage und Zeit aus dem Wochenplan', () {
      final schedule = WeekSchedule()
          .withSlots(const [SessionSlot(TrainingSport.run)], Weekday.tuesday)
          .withSlots(const [SessionSlot(TrainingSport.strength)], Weekday.wednesday)
          .withSlots(const [SessionSlot(TrainingSport.run, SessionIntensity.hard)], Weekday.thursday)
          .withSlots(const [SessionSlot(TrainingSport.run, SessionIntensity.long)], Weekday.saturday);
      final profile = UserProfile(
        sports: const [TrainingSport.run, TrainingSport.strength],
        event: EventGoal(
          name: 'Berlin-Halbmarathon',
          date: CalendarDay(2027, 4, 4),
          kind: EventKind.halfMarathon,
          targetSeconds: 6300,
        ),
        schedule: schedule,
      );
      final known = EnduranceGoals.known(profile, SeasonConfig.standard, today: today);
      expect(known.single.name, 'Berlin-Halbmarathon');
      expect(known.single.event, EnduranceEvent.halfMarathon);
      expect(known.single.targetMinutes, 105);
      expect(known.single.source, 'Deine Ziele');
      final request = EnduranceGoals.suggestion(profile, SeasonConfig.standard, username: 'anna', today: today);
      expect(request.mode, PlanningMode.goal);
      expect(request.event, EnduranceEvent.halfMarathon);
      expect(request.eventDay, CalendarDay(2027, 4, 4));
      expect(request.eventName, 'Berlin-Halbmarathon');
      expect(request.targetMinutes, 105);
      expect(request.sports, [EnduranceSport.run]);
      expect(request.days, [Weekday.tuesday, Weekday.thursday, Weekday.saturday]);
      expect(request.longDay, Weekday.saturday);
      expect(request.weeklyMinutes, 210); // 45 + 60 + 100 → auf halbe Stunden
      expect(TrainingPlanEngine.validate(request), isNull);
      final plan = TrainingPlanEngine.generate(request, now: now, id: 'G');
      final restored = EndurancePlan.fromJson(jsonDecode(jsonEncode(plan.toJson())), username: 'anna')!;
      expect(restored.request.eventName, 'Berlin-Halbmarathon');
    });

    test('Saisonplan: Marathon und Almere nur im Saisonmodus, vergangene fallen weg', () {
      final season = SeasonConfig.standard;
      final own = EnduranceGoals.known(UserProfile.seasonPlan, season, today: today);
      expect(own.map((goal) => goal.name), ['Marathon', 'Challenge Almere']);
      expect(own.first.event, EnduranceEvent.marathon);
      expect(own.first.targetMinutes, (325 * 42.195 / 60).round());
      expect(own.last.event, EnduranceEvent.triMiddle);
      expect(own.last.targetMinutes, 330);
      expect(
        EnduranceGoals.known(UserProfile.seasonPlan, season, today: CalendarDay(2027, 6, 1)).single.name,
        'Challenge Almere',
      );
      expect(EnduranceGoals.known(UserProfile(), season, today: today), isEmpty);
    });

    test('Triathlon nach Name, anderer Wettkampf nach Sportart, ohne Wettkampf Zeitraum nach Ziel', () {
      EnduranceEvent? kind(String name, {EventKind type = EventKind.triathlon, List<TrainingSport>? sports}) =>
          EnduranceGoals.eventOf(
            EventGoal(name: name, date: CalendarDay(2027, 6, 1), kind: type),
            UserProfile(sports: sports ?? const [TrainingSport.run]),
          );
      expect(kind('Ironman 70.3 Zell am See'), EnduranceEvent.triMiddle);
      expect(kind('Ironman Frankfurt'), EnduranceEvent.triFull);
      expect(kind('Stadttriathlon Sprint'), EnduranceEvent.triSprint);
      expect(kind('Kölner Triathlon'), EnduranceEvent.triOlympic);
      expect(kind('Ötztaler', type: EventKind.other, sports: const [TrainingSport.bike]), EnduranceEvent.bikeEvent);
      expect(kind('Irgendwas', type: EventKind.other, sports: const [TrainingSport.bike, TrainingSport.run]), isNull);

      final health = UserProfile(
        sports: const [TrainingSport.bike, TrainingSport.swim],
        goals: PersonalGoals(primary: TrainingGoal.health, since: today),
      );
      final request = EnduranceGoals.suggestion(health, SeasonConfig.standard, username: 'anna', today: today);
      expect(request.mode, PlanningMode.period);
      expect(request.focus, PeriodFocus.base);
      expect(request.sports, [EnduranceSport.bike, EnduranceSport.swim]);
      expect(request.days, [Weekday.tuesday, Weekday.thursday, Weekday.saturday, Weekday.sunday]);
      expect(request.weeklyMinutes, 180);
      expect(EnduranceGoals.firstClock('Finish in 5:30–6:00 h'), 330);
    });

    test('Ziel in der App geändert: Hinweis auf den neuen Wettkampf', () {
      final first = UserProfile(
        event: EventGoal(name: '10 km Stadtlauf', date: CalendarDay(2027, 3, 1), kind: EventKind.run10k),
      );
      final plan = TrainingPlanEngine.generate(
        EnduranceGoals.suggestion(first, SeasonConfig.standard, username: 'anna', today: today),
        now: now,
        id: 'C',
      );
      expect(
        EnduranceGoals.changedGoal(plan, EnduranceGoals.known(first, SeasonConfig.standard, today: today)),
        isNull,
      );
      final changed = UserProfile(
        event: EventGoal(name: 'Marathon Hamburg', date: CalendarDay(2027, 4, 25), kind: EventKind.marathon),
      );
      expect(
        EnduranceGoals.changedGoal(plan, EnduranceGoals.known(changed, SeasonConfig.standard, today: today))?.name,
        'Marathon Hamburg',
      );
    });
  });
}

int _int(List<int> bytes) {
  var value = 0;
  for (var index = bytes.length - 1; index >= 0; index--) {
    value = value << 8 | bytes[index];
  }
  return value;
}

final class _FitMessage {
  _FitMessage(this.global, this.fields);

  final int global;
  final Map<int, List<int>> fields;
}

/// Minimaler Leser für die eigenen FIT-Dateien (normale Köpfe, Little Endian).
List<_FitMessage> _fitMessages(List<int> bytes) {
  final size = bytes[4] | bytes[5] << 8 | bytes[6] << 16 | bytes[7] << 24;
  final definitions = <int, (int, List<(int, int)>)>{};
  final result = <_FitMessage>[];
  var position = 14;
  while (position < 14 + size) {
    final header = bytes[position++];
    final local = header & 0x0F;
    if (header & 0x40 != 0) {
      position += 2;
      final global = bytes[position] | bytes[position + 1] << 8;
      position += 2;
      final count = bytes[position++];
      final fields = <(int, int)>[];
      for (var index = 0; index < count; index++) {
        fields.add((bytes[position], bytes[position + 1]));
        position += 3;
      }
      definitions[local] = (global, fields);
    } else {
      final (global, fields) = definitions[local]!;
      final values = <int, List<int>>{};
      for (final (number, length) in fields) {
        values[number] = bytes.sublist(position, position + length);
        position += length;
      }
      result.add(_FitMessage(global, values));
    }
  }
  return result;
}
