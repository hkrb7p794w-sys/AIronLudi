import '../calendar/calendar_day.dart';
import '../coach/recovery_level.dart';
import '../coach/season_plan.dart';
import '../coach/template_item.dart';
import '../garmin/race_predictions.dart';
import '../gym/exercise_library.dart';
import '../gym/routine.dart';
import '../nutrition/nutrient.dart';
import '../nutrition/nutrition_planner.dart';
import '../nutrition/nutrition_settings.dart';
import '../nutrition/recipe_plan.dart';
import '../profile/goal_rules.dart';
import '../profile/input_check.dart';
import '../profile/schedule_advisor.dart';
import '../profile/schedule_check.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import '../util/german_format.dart';

/// Musterperson für den Prüfbericht und die Tests.
final class Persona {
  const Persona({
    required this.name,
    required this.description,
    required this.profile,
    required this.nutrition,
    required this.predictions,
    required this.recipeAllergens,
  });

  final String name;
  final String description;
  final UserProfile profile;
  final NutritionSettings nutrition;
  final RacePredictions? predictions;
  final Set<Allergen> recipeAllergens;

  BodyProfile get body => nutrition.profile(null, on: PersonaReport.monday);
}

/// Ergebnis einer Schutzregel.
final class PersonaCheck {
  const PersonaCheck({required this.rule, required this.passed, required this.detail});

  final String rule;
  final bool passed;
  final String detail;
}

/// Ein Tag der Musterwoche.
typedef PersonaDay = ({Weekday weekday, List<String> sessions, NutritionTargets targets});

final class PersonaResult {
  PersonaResult({
    required this.persona,
    required this.issues,
    required this.assessment,
    required this.week,
    required this.hints,
    required this.adviceNormal,
    required this.advicePause,
    required this.routines,
    this.checks = const [],
  });

  final Persona persona;
  final List<InputIssue> issues;
  final GoalAssessment assessment;
  final List<PersonaDay> week;
  final List<ScheduleHint> hints;
  final ScheduleAdvice? adviceNormal;
  final ScheduleAdvice? advicePause;
  final List<Routine> routines;
  List<PersonaCheck> checks;
}

/// Musterpersonen: Die App rechnet für jede Person alle Empfehlungen durch und prüft feste Regeln (Schutzgrenzen),
/// die nie verletzt werden dürfen.
abstract final class PersonaReport {
  /// Montag, 2.11.2026: fester Bezugstag, damit der Bericht reproduzierbar ist.
  static const monday = CalendarDay(2026, 11, 2);

  static WeekSchedule schedule(Map<Weekday, List<SessionSlot>> plan) {
    var schedule = WeekSchedule();
    for (final MapEntry(key: weekday, value: slots) in plan.entries) {
      schedule = schedule.withSlots(slots, weekday);
    }
    return schedule;
  }

  static NutritionSettings nutrition({
    required double weight,
    required double height,
    required int age,
    required bool female,
    required Diet diet,
  }) => NutritionSettings()
    ..weightKilograms = weight
    ..heightCentimeters = height
    ..age = age
    ..isFemale = female
    ..diet = diet;

  static List<Persona> get personas {
    const run = SessionSlot(TrainingSport.run);
    const hardRun = SessionSlot(TrainingSport.run, SessionIntensity.hard);
    const longRun = SessionSlot(TrainingSport.run, SessionIntensity.long);
    const hardStrength = SessionSlot(TrainingSport.strength, SessionIntensity.hard);

    final runner =
        UserProfile(
            mode: ProfileMode.personal,
            onboardingDone: true,
            sports: const [TrainingSport.run, TrainingSport.strength],
            goal: FitnessGoal.loseWeight,
            targets: const ImprovementTargets(targetWeightKilograms: 65, weeksToTargetWeight: 20),
          )
          ..setLevel(ExperienceLevel.beginner, TrainingSport.run)
          ..setLevel(ExperienceLevel.beginner, TrainingSport.strength);
    runner.schedule = schedule({
      Weekday.tuesday: const [run],
      Weekday.thursday: const [hardStrength],
      Weekday.saturday: const [longRun],
    });

    final season = UserProfile.seasonPlan..onboardingDone = true;

    final beginner = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.run],
      goal: FitnessGoal.improveFitness,
      targets: const ImprovementTargets(restingHeartRate: 60),
    )..setLevel(ExperienceLevel.beginner, TrainingSport.run);
    beginner.schedule = schedule({
      Weekday.wednesday: const [run],
      Weekday.sunday: const [run],
    });

    final muscle = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.strength],
      goal: FitnessGoal.buildMuscle,
    )..setLevel(ExperienceLevel.intermediate, TrainingSport.strength);
    muscle.schedule = schedule({
      Weekday.monday: const [hardStrength],
      Weekday.tuesday: const [hardStrength],
      Weekday.thursday: const [hardStrength],
      Weekday.friday: const [hardStrength],
    });

    final vegan =
        UserProfile(
            mode: ProfileMode.personal,
            onboardingDone: true,
            sports: const [TrainingSport.run, TrainingSport.bike],
            goal: FitnessGoal.improveFitness,
            event: EventGoal(
              name: 'Stadtlauf Halbmarathon',
              date: monday.adding(84),
              kind: EventKind.halfMarathon,
              targetSeconds: 6600,
            ),
          )
          ..setLevel(ExperienceLevel.intermediate, TrainingSport.run)
          ..setLevel(ExperienceLevel.intermediate, TrainingSport.bike);
    vegan.schedule = schedule({
      Weekday.tuesday: const [hardRun],
      Weekday.wednesday: const [SessionSlot(TrainingSport.bike)],
      Weekday.thursday: const [run],
      Weekday.sunday: const [longRun],
    });
    final veganPredictions = RacePredictions(tenK: 3240, halfMarathon: 7080);

    final underweight = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.run],
      goal: FitnessGoal.loseWeight,
    )..setLevel(ExperienceLevel.beginner, TrainingSport.run);
    underweight.schedule = schedule({
      Weekday.monday: const [run],
      Weekday.tuesday: const [hardRun],
      Weekday.wednesday: const [hardRun],
      Weekday.thursday: const [run],
      Weekday.friday: const [run],
      Weekday.saturday: const [longRun],
      Weekday.sunday: const [run],
    });

    return [
      Persona(
        name: 'Läuferin, möchte abnehmen',
        description: '30 Jahre, 170 cm, 72 kg, Laufen + Gym, Einsteigerin',
        profile: runner,
        nutrition: nutrition(weight: 72, height: 170, age: 30, female: true, diet: Diet.omnivore),
        predictions: null,
        recipeAllergens: const {},
      ),
      Persona(
        name: 'Saisonplan (Triathlon)',
        description: '35 Jahre, 180 cm, 78 kg, Saisonplan Marathon und Almere',
        profile: season,
        nutrition: nutrition(weight: 78, height: 180, age: 35, female: false, diet: Diet.pescetarian),
        predictions: null,
        recipeAllergens: const {},
      ),
      Persona(
        name: 'Einsteiger Fitness',
        description: '45 Jahre, 178 cm, 90 kg, 2× Laufen, Ruhepuls-Ziel 60',
        profile: beginner,
        nutrition: nutrition(weight: 90, height: 178, age: 45, female: false, diet: Diet.omnivore),
        predictions: null,
        recipeAllergens: const {},
      ),
      Persona(
        name: 'Muskelaufbau',
        description: '25 Jahre, 180 cm, 70 kg, 4× Kraft, Fortgeschritten',
        profile: muscle,
        nutrition: nutrition(weight: 70, height: 180, age: 25, female: false, diet: Diet.omnivore),
        predictions: null,
        recipeAllergens: const {},
      ),
      Persona(
        name: 'Vegane Halbmarathonläuferin',
        description: '28 Jahre, 165 cm, 58 kg, Ziel 1:50 h, Nussallergie',
        profile: vegan,
        nutrition: nutrition(weight: 58, height: 165, age: 28, female: true, diet: Diet.vegan),
        predictions: veganPredictions,
        recipeAllergens: const {Allergen.nuts},
      ),
      Persona(
        name: 'Untergewicht will abnehmen',
        description: '22 Jahre, 172 cm, 52 kg (BMI 17,6), 7 Lauftage',
        profile: underweight,
        nutrition: nutrition(weight: 52, height: 172, age: 22, female: true, diet: Diet.vegetarian),
        predictions: null,
        recipeAllergens: const {},
      ),
    ];
  }

  static PersonaResult evaluate(Persona persona) {
    final profile = persona.profile;
    final body = persona.body;
    // Kopie wie bei einer Swift-Struktur: Die Einstellungen der Person bleiben unverändert.
    final settings = persona.nutrition.copy();
    final assessment = GoalRules.assess(profile, body);
    if (profile.mode == ProfileMode.personal) GoalRules.apply(assessment, settings);
    final issues = [
      ...InputCheck.body(body),
      ...InputCheck.goals(profile: profile, body: body, predictions: persona.predictions, today: monday),
    ];

    final week = <PersonaDay>[
      for (final weekday in Weekday.values)
        () {
          final day = monday.adding(weekday.rawValue);
          final List<TemplateItem> items;
          final List<String> sessions;
          if (profile.mode == ProfileMode.season) {
            items = SeasonPlan.state(today: day, config: SeasonConfig.standard, week: WeeklyVolume()).todayFixed;
            sessions = [for (final item in items) item.text];
          } else {
            items = profile.schedule.templateItems(weekday);
            sessions = [for (final slot in profile.schedule.slots(weekday)) slot.title];
          }
          final targets = NutritionPlanner.compute(
            activities: const [],
            planItems: items,
            settings: settings,
            garminProfile: null,
            day: day,
            hasGarminData: false,
          );
          return (weekday: weekday, sessions: sessions, targets: targets);
        }(),
    ];

    var hints = <ScheduleHint>[];
    ScheduleAdvice? normal;
    ScheduleAdvice? pause;
    var routines = <Routine>[];
    if (profile.mode == ProfileMode.personal) {
      hints = ScheduleCheck.hints(profile.schedule, profile);
      final trainingDays = profile.schedule.trainingDays;
      final day = monday.adding(trainingDays.isEmpty ? 0 : trainingDays.first.rawValue);
      normal = ScheduleAdvisor.advice(profile: profile, day: day, recovery: RecoveryLevel.normal, trainedToday: false);
      pause = ScheduleAdvisor.advice(profile: profile, day: day, recovery: RecoveryLevel.pause, trainedToday: false);
      if (profile.trains(TrainingSport.strength)) {
        routines = RoutineTemplates.suggest(profile: profile, equipment: Equipment.gym);
      }
    }

    final result = PersonaResult(
      persona: persona,
      issues: issues,
      assessment: assessment,
      week: week,
      hints: hints,
      adviceNormal: normal,
      advicePause: pause,
      routines: routines,
    );
    return result..checks = checks(result, settings: settings);
  }

  /// Schutzregeln, die für jede Person gelten müssen.
  static List<PersonaCheck> checks(PersonaResult result, {required NutritionSettings settings}) {
    final persona = result.persona;
    final body = persona.body;
    final checks = <PersonaCheck>[];
    final bodyFat = settings.bodyFatPercent ?? (body.isFemale ? 25 : 15);
    final floor = 30 * body.weightKilograms * (1 - bodyFat / 100);
    final kilocalories = [for (final day in result.week) day.targets.values[Nutrient.kcal] ?? 0];
    final lowest = kilocalories.isEmpty ? 0.0 : kilocalories.reduce((a, b) => a < b ? a : b);
    checks.add(
      PersonaCheck(
        rule: 'Energie nie unter der REDs-Untergrenze (30 kcal/kg fettfreie Masse)',
        passed: lowest >= floor - 1,
        detail: 'niedrigster Tag ${lowest.truncate()} kcal, Untergrenze ${floor.round()} kcal',
      ),
    );

    final rate = result.assessment.weeklyChangePercent ?? 0;
    checks.add(
      PersonaCheck(
        rule: 'Abnehmen höchstens 1 % pro Woche, Zunehmen höchstens 0,5 %',
        passed: rate >= -GoalRules.maxLossPercentPerWeek && rate <= GoalRules.maxGainPercentPerWeek,
        detail: 'geplant ${GermanFormat.number(rate)} % pro Woche',
      ),
    );

    final proteins = [
      for (final day in result.week) (day.targets.values[Nutrient.protein] ?? 0) / body.weightKilograms,
    ];
    checks.add(
      PersonaCheck(
        rule: 'Protein 1,4–2,2 g je kg',
        passed: proteins.every((value) => value >= 1.39 && value <= 2.21),
        detail: '${GermanFormat.number(((proteins.isEmpty ? 0 : proteins.first) * 10).roundToDouble() / 10)} g/kg',
      ),
    );

    // Makros müssen zur Energie passen und Fett im Bereich 20–35 % liegen (ACSM 2016).
    final shares = [
      for (final day in result.week)
        () {
          final values = day.targets.values;
          final kcal = (values[Nutrient.kcal] ?? 1) < 1 ? 1.0 : (values[Nutrient.kcal] ?? 1);
          final fromMacros =
              4 * (values[Nutrient.protein] ?? 0) + 4 * (values[Nutrient.carbs] ?? 0) + 9 * (values[Nutrient.fat] ?? 0);
          return (fat: 9 * (values[Nutrient.fat] ?? 0) / kcal, gap: (fromMacros - kcal).abs());
        }(),
    ];
    final lowestFat = shares.isEmpty ? 0.0 : shares.map((share) => share.fat).reduce((a, b) => a < b ? a : b);
    checks.add(
      PersonaCheck(
        rule: 'Fett 20–35 % der Energie, Makros ergeben die Tagesenergie',
        passed: shares.every((share) => share.fat >= 0.195 && share.fat <= 0.355 && share.gap <= 15),
        detail: 'niedrigster Fettanteil ${(lowestFat * 100).round()} %',
      ),
    );

    if (GoalRules.bmi(body) < GoalRules.minimumBMI && persona.profile.goal.losesWeight) {
      checks.add(
        PersonaCheck(
          rule: 'Kein Abnehmziel bei BMI unter 18,5',
          passed: result.assessment.blocksWeightChange,
          detail: result.assessment.blocksWeightChange ? 'Ziel wird gehalten statt umgesetzt' : 'Ziel wird umgesetzt',
        ),
      );
    }

    if (persona.profile.mode == ProfileMode.personal) {
      final schedule = persona.profile.schedule;
      final restOK =
          schedule.restDays.isNotEmpty ||
          result.hints.any((hint) => hint.id == 'rest' && hint.severity == HintSeverity.warning);
      checks.add(
        PersonaCheck(
          rule: 'Mindestens ein Ruhetag oder eine deutliche Warnung',
          passed: restOK,
          detail: '${schedule.restDays.length} Ruhetage',
        ),
      );
      if (result.advicePause case final pause?) {
        checks.add(
          PersonaCheck(
            rule: 'Bei schlechter Erholung keine harte Einheit empfehlen',
            passed: pause.mode == ScheduleAdviceMode.rest || pause.mode == ScheduleAdviceMode.restDay,
            detail: pause.headline,
          ),
        );
      }
      final hardDays = schedule.demandingEnduranceDays;
      final backToBack = hardDays.any((day) => hardDays.contains(day.next));
      checks.add(
        PersonaCheck(
          rule: 'Zwei harte Ausdauertage hintereinander werden gemeldet',
          passed: !backToBack || result.hints.any((hint) => hint.id.startsWith('back-to-back')),
          detail: backToBack ? 'kommt vor' : 'kommt nicht vor',
        ),
      );
    }

    final samples = [
      ('Hähnchenbrust', persona.nutrition.diet != Diet.omnivore),
      ('Basilikumpesto', persona.nutrition.diet == Diet.vegan || persona.recipeAllergens.contains(Allergen.nuts)),
      ('Walnusskerne', persona.recipeAllergens.contains(Allergen.nuts)),
    ];
    final recipeOK = samples.every(
      (sample) =>
          RecipePlanner.violations(
            sample.$1,
            diet: persona.nutrition.diet,
            allergens: persona.recipeAllergens,
          ).isEmpty !=
          sample.$2,
    );
    checks.add(
      PersonaCheck(
        rule: 'Rezept-Prüfung erkennt Ernährungsweise und Allergene (auch versteckte)',
        passed: recipeOK,
        detail: samples.map((sample) => sample.$1).join(', '),
      ),
    );
    return checks;
  }

  // Markdown

  static String markdown(List<PersonaResult> results) {
    final lines = [
      '# Prüfbericht: Musterpersonen',
      '',
      'Woche ab ${Weekday.monday.long}, ${monday.iso}. Alle Werte stammen aus denselben Regeln wie die App.',
      '',
    ];
    final failed = results.expand((result) => result.checks).where((check) => !check.passed).length;
    lines.add(failed == 0 ? '**Alle Schutzregeln eingehalten.**' : '**$failed Schutzregeln verletzt!**');
    for (final result in results) {
      final persona = result.persona;
      lines
        ..addAll(['', '## ${persona.name}', '', '_${persona.description}_', ''])
        ..add('### Schutzregeln')
        ..addAll([for (final check in result.checks) '- ${check.passed ? '✅' : '❌'} ${check.rule} – ${check.detail}']);
      if (result.issues.isNotEmpty) {
        lines
          ..addAll(['', '### Eingaben'])
          ..addAll([for (final issue in result.issues) '- ${symbol(issue.severity)} ${issue.message}']);
      }
      lines.addAll(['', '### Ziel', '']);
      final assessment = result.assessment;
      final rate = assessment.weeklyChangePercent == null
          ? ''
          : ', ${GermanFormat.number(assessment.weeklyChangePercent!)} % pro Woche';
      lines
        ..add('- Ernährung: ${assessment.nutritionGoal.label}$rate')
        ..addAll([for (final note in assessment.notes) '- $note'])
        ..addAll([
          '',
          '### Woche',
          '',
          '| Tag | Einheiten | Tagestyp | kcal | Protein | KH | Fett |',
          '|---|---|---|---|---|---|---|',
        ]);
      for (final day in result.week) {
        final values = day.targets.values;
        String value(Nutrient nutrient) => '${(values[nutrient] ?? 0).truncate()}';
        final sessions = day.sessions.isEmpty ? 'frei' : day.sessions.join(' + ');
        lines.add(
          '| ${day.weekday.short} | $sessions | ${day.targets.dayType.label} | ${value(Nutrient.kcal)} | '
          '${value(Nutrient.protein)} g | ${value(Nutrient.carbs)} g | ${value(Nutrient.fat)} g |',
        );
      }
      if (result.hints.isNotEmpty) {
        lines
          ..addAll(['', '### Hinweise zum Wochenplan'])
          ..addAll([
            for (final hint in result.hints) '- ${hint.severity == HintSeverity.warning ? '⚠️' : '💡'} ${hint.message}',
          ]);
      }
      if ((result.adviceNormal, result.advicePause) case (final normal?, final pause?)) {
        lines.addAll([
          '',
          '### Tagesempfehlung (erster Trainingstag)',
          '- Erholung gut: **${normal.headline}** – ${normal.detail}',
          '- Erholung schlecht: **${pause.headline}** – ${pause.detail}',
        ]);
      }
      if (result.routines.isNotEmpty) {
        lines
          ..addAll(['', '### Vorgeschlagene Routinen'])
          ..addAll([
            for (final routine in result.routines)
              '- ${routine.name}: ${routine.items.map((item) => '${item.name} ${item.sets}×${item.lowerReps}–${item.upperReps}').join(', ')}',
          ]);
      }
    }
    return '${lines.join('\n')}\n';
  }

  static String symbol(InputSeverity severity) => switch (severity) {
    InputSeverity.warning => '⚠️',
    InputSeverity.tip => '💡',
    InputSeverity.info => 'ℹ️',
  };

  static String run() => markdown([for (final persona in personas) evaluate(persona)]);
}
