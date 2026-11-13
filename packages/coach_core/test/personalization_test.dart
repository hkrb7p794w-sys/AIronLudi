// Port von CoachCoreTests/PersonalizationTests.swift. Offen (folgen mit ihren Modulen): Planung
// (SchedulePlanner), Belastungsgrenze (LoadCheck/WeekLoad), Chat-Kontext (ChatContext), Dashboard und Empfehlungen.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 11, 2);

void main() {
  test('Hauptziel nicht unter den Nebenzielen, Anzahl begrenzt', () {
    final goals = PersonalGoals(
      primary: TrainingGoal.muscleGain,
      secondary: const [TrainingGoal.muscleGain, TrainingGoal.fatLoss, TrainingGoal.health, TrainingGoal.endurance],
      priorities: const [FocusArea.muscle, FocusArea.muscle, FocusArea.sleep, FocusArea.nutrition, FocusArea.health],
      since: today,
    );
    expect(goals.secondary, [TrainingGoal.fatLoss, TrainingGoal.health]);
    expect(goals.priorities, [FocusArea.muscle, FocusArea.sleep, FocusArea.nutrition]);
  });

  test('Standard-Prioritäten folgen den Zielen', () {
    final goals = PersonalGoals(
      primary: TrainingGoal.endurance,
      secondary: const [TrainingGoal.recovery],
      since: today,
    );
    expect(goals.effectivePriorities, [FocusArea.endurance, FocusArea.recovery, FocusArea.sleep]);
    final chosen = PersonalGoals(
      primary: TrainingGoal.endurance,
      priorities: const [FocusArea.nutrition],
      since: today,
    );
    expect(chosen.effectivePriorities, [FocusArea.nutrition]);
  });

  test('Ernährungsrichtung aus den Zielen', () {
    expect(
      Personalization.fitnessGoal(PersonalGoals(primary: TrainingGoal.fatLoss, since: today)),
      FitnessGoal.loseWeight,
    );
    final both = PersonalGoals(primary: TrainingGoal.fatLoss, secondary: const [TrainingGoal.strength], since: today);
    expect(Personalization.fitnessGoal(both), FitnessGoal.loseAndBuild);
    expect(
      Personalization.fitnessGoal(PersonalGoals(primary: TrainingGoal.muscleGain, since: today)),
      FitnessGoal.buildMuscle,
    );
    expect(
      Personalization.fitnessGoal(PersonalGoals(primary: TrainingGoal.competition, since: today)),
      FitnessGoal.improveFitness,
    );
    expect(
      Personalization.fitnessGoal(PersonalGoals(primary: TrainingGoal.health, since: today)),
      FitnessGoal.maintain,
    );
  });

  test('abgeleitete Ziele für alte Profile', () {
    expect(Personalization.derived(UserProfile.seasonPlan, since: today).primary, TrainingGoal.competition);
    final profile = UserProfile(goal: FitnessGoal.loseAndBuild);
    expect(Personalization.derived(profile, since: today).all, [TrainingGoal.fatLoss, TrainingGoal.muscleGain]);
    profile.event = EventGoal(name: 'Halbmarathon', date: today.adding(60), kind: EventKind.halfMarathon);
    final withEvent = Personalization.derived(profile, since: today);
    expect(withEvent.primary, TrainingGoal.competition);
    expect(withEvent.secondary.first, TrainingGoal.fatLoss);
  });

  test('Verlauf behält alte Ziele für frühere Tage', () {
    final profile = UserProfile(goal: FitnessGoal.buildMuscle);
    final monday = today.adding(-7);
    profile
      ..updateGoals(
        PersonalGoals(primary: TrainingGoal.muscleGain, since: monday),
        on: monday,
      )
      ..updateGoals(
        PersonalGoals(primary: TrainingGoal.endurance, since: today),
        on: today,
      );
    expect(profile.goalsOn(today).primary, TrainingGoal.endurance);
    expect(profile.goalsOn(today.adding(-3)).primary, TrainingGoal.muscleGain);
    // Vor dem ersten Festlegen: das damals Abgeleitete (Muskelaufbau aus „Muskeln aufbauen“), nicht das neue Ziel.
    expect(profile.goalsOn(today.adding(-30)).primary, TrainingGoal.muscleGain);
    // Zweimal am selben Tag ändern ersetzt, statt den Verlauf zu füllen.
    final count = profile.goalHistory.length;
    profile.updateGoals(
      PersonalGoals(primary: TrainingGoal.health, since: today),
      on: today,
    );
    expect(profile.goalHistory.length, count);
    expect(profile.goal, FitnessGoal.maintain);
  });

  test('erste Änderung behält die abgeleiteten Ziele für die Vergangenheit', () {
    final profile = UserProfile(goal: FitnessGoal.loseWeight)
      ..updateGoals(
        PersonalGoals(primary: TrainingGoal.muscleGain, since: today),
        on: today,
      );
    expect(profile.goalsOn(today.adding(-100)).primary, TrainingGoal.fatLoss);
    expect(profile.goalsOn(today).primary, TrainingGoal.muscleGain);
  });

  test('Profil ohne neue Felder, unbekannte Werte werden übergangen', () {
    final profile = UserProfile.fromJson(
      jsonDecode('{"mode":"personal","onboardingDone":true,"sports":["run"],"goal":"buildMuscle"}'),
    );
    expect(profile.goals, isNull);
    expect(profile.effectiveGoals(today).primary, TrainingGoal.muscleGain);
    final goals = PersonalGoals.fromJson(
      jsonDecode('{"primary":"strength","secondary":["zukunft","health"],"priorities":["laune","sleep"]}'),
    )!;
    expect(goals.secondary, [TrainingGoal.health]);
    expect(goals.priorities, [FocusArea.sleep]);
    expect(goals.since, const CalendarDay(2000, 1, 1));
    final updated = profile.copy()
      ..updateGoals(
        PersonalGoals(primary: TrainingGoal.strength, priorities: const [FocusArea.sleep], since: today),
        on: today,
      )
      ..tracker = const TrackerSetup(usesTracker: true, providers: [DataProvider.garmin, DataProvider.whoop]);
    expect(UserProfile.fromJson(jsonDecode(jsonEncode(updated.toJson()))), updated);
  });

  test('KI-Kontext nennt Ziele, Prioritäten und Ausrichtung', () {
    final profile = UserProfile(sports: const [TrainingSport.strength])
      ..updateGoals(
        PersonalGoals(
          primary: TrainingGoal.muscleGain,
          secondary: const [TrainingGoal.fatLoss],
          priorities: const [FocusArea.muscle],
          since: today,
        ),
        on: today,
      );
    final lines = Personalization.contextLines(profile.effectiveGoals(today)).join('\n');
    expect(lines, contains('Hauptziel: Muskelaufbau; Nebenziele: Fettabbau.'));
    expect(lines, contains('Prioritäten der Person: Muskelaufbau.'));
    expect(lines, contains('Kraftvolumen'));
    final triathlon = UserProfile.seasonPlan..goals = null;
    final season = Personalization.contextLines(triathlon.effectiveGoals(today)).join('\n');
    expect(season, contains('Hauptziel: Wettkampfvorbereitung'));
    expect(season, contains('periodisieren'));
  });
}
