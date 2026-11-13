import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../nutrition/nutrition_settings.dart';
import '../nutrition/weight_trend.dart';
import 'personalization.dart';
import 'user_profile.dart';

/// Ergebnis der Zielprüfung: was die App daraus für die Ernährung macht und was sie dazu sagt.
final class GoalAssessment {
  const GoalAssessment({
    required this.nutritionGoal,
    required this.weeklyChangePercent,
    required this.notes,
    required this.evidenceIDs,
    required this.blocksWeightChange,
    this.withholdsTargets = false,
  });

  final NutritionGoal nutritionGoal;

  /// Gewichtsänderung in % des Körpergewichts pro Woche (negativ = abnehmen); `null` = Gewicht halten.
  final double? weeklyChangePercent;
  final List<String> notes;
  final List<String> evidenceIDs;

  /// Das gewünschte Gewichtsziel wird nicht umgesetzt (Sicherheit).
  final bool blocksWeightChange;

  /// Schwangerschaft/Stillzeit oder Essstörung: keine Gewichts- oder Kalorienziele, auch keine Vorschläge.
  final bool withholdsTargets;
}

/// Wie weit die App das Körpergewicht beeinflussen darf. Gilt in jedem Pfad, nicht nur beim Speichern des Profils.
enum WeightGoalGuard {
  free,

  /// Unter 18 Jahren oder BMI unter 18,5: kein Defizit.
  noDeficit,

  /// Schwangerschaft/Stillzeit oder Essstörung: keine Ziele und keine Vorschläge.
  noTargets,
}

/// Zielregeln mit Schutzgeländern. Zahlen und Quellen stehen in `docs/decisions.md` von Coach-App.
abstract final class GoalRules {
  /// Obergrenze beim Abnehmen: 1 % des Körpergewichts pro Woche (Garthe et al. 2011 verglichen 0,7 und 1,4 %).
  static const maxLossPercentPerWeek = 1.0;
  static const defaultLossPercentPerWeek = 0.5;

  /// Langsames Tempo beim gleichzeitigen Muskelaufbau.
  static const recompositionLossPercentPerWeek = 0.25;
  static const defaultGainPercentPerWeek = 0.25;
  static const maxGainPercentPerWeek = 0.5;

  /// Ab diesem Tempo hielt in Garthe et al. 2011 die schnelle Gruppe weniger Muskelmasse.
  static const slowLossLimitPercentPerWeek = 0.7;
  static const minimumBMI = 18.5;
  static const minimumAge = 18;

  static double bmi(BodyProfile body) {
    final meters = body.heightCentimeters / 100;
    return meters > 0 ? body.weightKilograms / (meters * meters) : 0;
  }

  /// Ab diesem BMI gelten Bedarfe je kg nicht mehr für das Gesamtgewicht.
  static const obesityBMI = 30.0;

  /// BMI des Referenzgewichts bei Adipositas.
  static const referenceBMI = 25.0;

  /// Gewicht für Protein und Kohlenhydrate je kg: Die Empfehlungen beziehen sich auf die fettfreie Masse (Helms et
  /// al. 2014). Ab BMI 30 rechnet die App deshalb mit dem Gewicht bei BMI 25, als Näherung.
  static double referenceWeightKilograms(BodyProfile body) {
    if (bmi(body) < obesityBMI) return body.weightKilograms;
    final meters = body.heightCentimeters / 100;
    return referenceBMI * meters * meters;
  }

  /// Körperfett in %, wenn keines eingetragen ist. Ab BMI 30 nach Deurenberg et al. 1991; darunter pauschal, weil die
  /// Formel bei Schlanken und Sportlichen zu hoch schätzt und die REDs-Untergrenze dann zu niedrig läge.
  static double estimatedBodyFatPercent(BodyProfile body) {
    final flat = body.isFemale ? 25.0 : 15.0;
    final value = bmi(body);
    if (value < obesityBMI) return flat;
    final deurenberg = 1.2 * value + 0.23 * body.age - (body.isFemale ? 0 : 10.8) - 5.4;
    return math.max(flat, math.min(deurenberg, 60));
  }

  /// Schutzstufe für die aktuellen Körperwerte.
  static WeightGoalGuard weightGuard(NutritionSettings settings, BodyProfile body) {
    if (settings.weightTargetsWithheld) return WeightGoalGuard.noTargets;
    final value = bmi(body);
    if (body.age < minimumAge || (value > 0 && value < minimumBMI)) return WeightGoalGuard.noDeficit;
    return WeightGoalGuard.free;
  }

  /// Schwangerschaft/Stillzeit oder Essstörung angegeben.
  static bool withholdsTargets(UserProfile profile) =>
      profile.health.contains(HealthFlag.pregnantOrPostpartum) || profile.health.contains(HealthFlag.eatingDisorder);

  /// Wochentempo, um das Zielgewicht in [weeks] Wochen zu erreichen, begrenzt auf den sicheren Bereich.
  static ({double percent, bool capped}) weeklyLossPercent({
    required double currentKilograms,
    required double targetKilograms,
    required int weeks,
  }) {
    if (currentKilograms <= 0 || targetKilograms >= currentKilograms || weeks <= 0) {
      return (percent: defaultLossPercentPerWeek, capped: false);
    }
    final perWeek = (currentKilograms - targetKilograms) / currentKilograms * 100 / weeks;
    return (
      percent: math.min(math.max(perWeek, recompositionLossPercentPerWeek), maxLossPercentPerWeek),
      capped: perWeek > maxLossPercentPerWeek,
    );
  }

  static ({double percent, bool capped}) weeklyGainPercent({
    required double currentKilograms,
    required double targetKilograms,
    required int weeks,
  }) {
    if (currentKilograms <= 0 || targetKilograms <= currentKilograms || weeks <= 0) {
      return (percent: defaultGainPercentPerWeek, capped: false);
    }
    final perWeek = (targetKilograms - currentKilograms) / currentKilograms * 100 / weeks;
    return (percent: math.min(math.max(perWeek, 0.1), maxGainPercentPerWeek), capped: perWeek > maxGainPercentPerWeek);
  }

  static GoalAssessment assess(UserProfile profile, BodyProfile body) {
    final goal = profile.goal;
    final notes = <String>[];
    final evidence = <String>[];
    GoalAssessment hold(List<String> reasons, [List<String> ids = const []]) => GoalAssessment(
      nutritionGoal: NutritionGoal.maintain,
      weeklyChangePercent: null,
      notes: reasons,
      evidenceIDs: ids,
      blocksWeightChange: true,
      withholdsTargets: withholdsTargets(profile),
    );
    GoalAssessment reachedTarget() => GoalAssessment(
      nutritionGoal: NutritionGoal.maintain,
      weeklyChangePercent: null,
      notes: [...notes, 'Du hast dein Zielgewicht erreicht. Die App hält jetzt dein Gewicht.'],
      evidenceIDs: evidence,
      blocksWeightChange: false,
    );

    final wantsChange = goal.losesWeight || goal.gainsWeight;
    if (profile.health.contains(HealthFlag.pregnantOrPostpartum)) {
      return hold(
        [
          'In Schwangerschaft und Stillzeit gibt die App keine Gewichtsziele vor. Sprich Ernährung und Training '
              'mit deiner Ärztin oder Hebamme ab; die WHO hat dafür eigene Empfehlungen.',
        ],
        ['activity.who'],
      );
    }
    if (profile.health.contains(HealthFlag.eatingDisorder)) {
      return hold(
        [
          'Wegen einer Essstörung gibt die App keine Gewichts- oder Kalorienziele vor. Bitte lass Training und '
              'Ernährung mit deinem Behandlungsteam abstimmen.',
        ],
        ['nutrition.reds'],
      );
    }
    if (wantsChange && body.age < minimumAge) {
      return hold([
        'Für unter 18-Jährige gibt die App keine Gewichtsziele vor. Sie hält dein Gewicht und unterstützt das Training.',
      ]);
    }
    if (goal.losesWeight && bmi(body) < minimumBMI) {
      return hold(
        [
          'Dein BMI liegt unter 18,5. Abnehmen ist dann nicht sinnvoll: Die App hält dein Gewicht und baut mit dem '
              'Training Kraft auf.',
        ],
        ['nutrition.reds'],
      );
    }
    if (profile.health.contains(HealthFlag.medicalCondition) || profile.health.contains(HealthFlag.injury)) {
      notes.add(
        'Du hast eine Erkrankung oder Verletzung angegeben. Lass dir vom Arzt bestätigen, welches Training für dich '
        'passt, und passe den Plan an.',
      );
      evidence.add('activity.who');
    }

    final target = profile.targets.targetWeightKilograms;
    final weeks = profile.targets.weeksToTargetWeight;
    switch (goal) {
      case FitnessGoal.loseWeight:
        if (target != null && target >= body.weightKilograms) return reachedTarget();
        var rate = defaultLossPercentPerWeek;
        if (target != null && weeks != null) {
          final targetBody = BodyProfile(
            weightKilograms: target,
            heightCentimeters: body.heightCentimeters,
            age: body.age,
            isFemale: body.isFemale,
          );
          if (bmi(targetBody) < minimumBMI) {
            notes.add(
              'Dein Zielgewicht läge unter BMI 18,5. Die App plant daher mit dem Standardtempo und stoppt bei BMI 18,5.',
            );
          } else {
            final result = weeklyLossPercent(
              currentKilograms: body.weightKilograms,
              targetKilograms: target,
              weeks: weeks,
            );
            rate = result.percent;
            if (result.capped) {
              notes.add(
                'Dein Wunschtempo wäre schneller als ${maxLossPercentPerWeek.toInt()} % des Körpergewichts pro Woche. '
                'Die App begrenzt darauf; das Ziel dauert entsprechend länger.',
              );
            }
          }
        }
        if (rate > slowLossLimitPercentPerWeek) {
          notes.add(
            'Ab etwa 0,7 % pro Woche behielten Athleten in einer Studie weniger Muskelmasse als bei langsamerem Tempo. '
            'Etwa 0,5 % pro Woche sind ein guter Standard.',
          );
        }
        evidence.addAll(['weightloss.rate', 'weightloss.protein', 'weightloss.exercise']);
        return GoalAssessment(
          nutritionGoal: NutritionGoal.lose,
          weeklyChangePercent: -rate,
          notes: notes,
          evidenceIDs: evidence,
          blocksWeightChange: false,
        );
      case FitnessGoal.loseAndBuild:
        notes.add(
          'Fett abbauen und Muskeln aufbauen gelingt am besten mit kleinem Defizit, viel Protein und regelmäßigem '
          'Krafttraining. Der Fortschritt ist langsamer als bei nur einem der beiden Ziele.',
        );
        evidence.addAll(['weightloss.protein', 'weightloss.exercise']);
        return GoalAssessment(
          nutritionGoal: NutritionGoal.recomposition,
          weeklyChangePercent: -recompositionLossPercentPerWeek,
          notes: notes,
          evidenceIDs: evidence,
          blocksWeightChange: false,
        );
      case FitnessGoal.buildMuscle || FitnessGoal.gainWeight:
        if (target != null && target <= body.weightKilograms) return reachedTarget();
        var rate = goal == FitnessGoal.gainWeight ? maxGainPercentPerWeek : defaultGainPercentPerWeek;
        if (target != null && weeks != null) {
          final result = weeklyGainPercent(
            currentKilograms: body.weightKilograms,
            targetKilograms: target,
            weeks: weeks,
          );
          rate = result.percent;
          if (result.capped) {
            notes.add(
              'Dein Wunschtempo ist schneller, als der Körper Muskeln aufbaut. Die App begrenzt auf höchstens 0,5 % '
              'pro Woche.',
            );
          }
        }
        notes.add('Ein kleiner Überschuss genügt: etwa 300–500 kcal pro Tag zusammen mit konsequentem Krafttraining.');
        evidence.addAll(['gain.surplus', 'weightloss.protein']);
        return GoalAssessment(
          nutritionGoal: NutritionGoal.gain,
          weeklyChangePercent: rate,
          notes: notes,
          evidenceIDs: evidence,
          blocksWeightChange: false,
        );
      case FitnessGoal.improveFitness || FitnessGoal.maintain:
        return GoalAssessment(
          nutritionGoal: NutritionGoal.maintain,
          weeklyChangePercent: null,
          notes: notes,
          evidenceIDs: evidence,
          blocksWeightChange: false,
        );
    }
  }

  /// Einschätzung eines Ruhepuls-Ziels. Nach einem Jahr Laufen sank der Ruhepuls bei Inaktiven im Schnitt um etwa 7
  /// Schläge pro Minute (Hespanhol Junior et al. 2015).
  static String restingHeartRateOutlook({required double? current, required int target}) {
    if (current == null) return 'Sobald Garmin deinen Ruhepuls liefert, zeigt die App den Verlauf zu deinem Ziel.';
    final difference = current - target;
    if (difference <= 0) return 'Du liegst schon bei oder unter deinem Ziel. Ziel ist jetzt, den Wert zu halten.';
    if (difference <= 7) {
      return 'Realistisch: In Studien sank der Ruhepuls nach einem Jahr regelmäßigem Ausdauertraining im Schnitt um '
          'etwa 7 Schläge pro Minute.';
    }
    return 'Dein Ziel liegt ${difference.round()} Schläge unter deinem Wert. Das ist mehr als der Durchschnitt aus '
        'Studien nach einem Jahr (etwa 7). Es ist ambitioniert; die App zeigt dir den Fortschritt.';
  }

  /// Überträgt das Ergebnis in die Ernährungseinstellungen.
  static void apply(GoalAssessment assessment, NutritionSettings settings) {
    settings
      ..goal = assessment.nutritionGoal
      ..weeklyWeightChangePercent = assessment.weeklyChangePercent
      ..weightTargetsWithheld = assessment.withholdsTargets;
    if (assessment.withholdsTargets) {
      settings.energyAdjustmentKilocalories = 0;
    } else if (assessment.blocksWeightChange) {
      settings.energyAdjustmentKilocalories = math.max(settings.energyAdjustmentKilocalories, 0);
    }
  }

  /// Übernimmt die neueste Wägung als aktuelles Körpergewicht. Eine Eingabe in den Einstellungen bleibt gültig, bis
  /// eine neuere Wägung kommt. `true`, wenn sich etwas geändert hat.
  static bool updateWeight(NutritionSettings settings, Iterable<WeightEntry> entries, {required CalendarDay today}) {
    final recent = WeightTrend.merged(entries).where((entry) => entry.day <= today && entry.day >= today.adding(-30));
    if (recent.isEmpty) return false;
    final latest = recent.last;
    final applied = settings.lastAppliedWeighInDay;
    if (applied != null && latest.day <= applied) return false;
    settings
      ..lastAppliedWeighInDay = latest.day
      ..weightKilograms = (latest.kilograms * 10).roundToDouble() / 10;
    return true;
  }

  /// Hat sich geändert, ob das Gewicht gehalten wird (Grenze oder Zielgewicht erreicht bzw. wieder verlassen)? Ein
  /// laufendes Tempo bleibt sonst unangetastet: Neu berechnet würde es mit jedem Kilo langsamer.
  static bool holdChanged(GoalAssessment assessment, NutritionSettings settings) =>
      (assessment.weeklyChangePercent == null) != (settings.weeklyWeightChangePercent == null);

  /// Profil für KI, Export und Anzeige: Ist das Gewichtsziel gesperrt oder erreicht, darf nirgends mehr „Abnehmen“
  /// oder „Überschuss“ als Auftrag stehen.
  static UserProfile coachingProfile(UserProfile profile, NutritionSettings nutrition) {
    final changesWeight = profile.goal.losesWeight || profile.goal.gainsWeight;
    final held =
        profile.mode == ProfileMode.personal &&
        changesWeight &&
        nutrition.goal == NutritionGoal.maintain &&
        nutrition.weeklyWeightChangePercent == null;
    if (!nutrition.weightTargetsWithheld && !held) return profile;
    final result = profile.copy()..goal = FitnessGoal.maintain;
    final goals = result.goals;
    if (goals != null) {
      var primary = goals.primary;
      if (primary == TrainingGoal.fatLoss) {
        primary = TrainingGoal.health;
      } else if (primary == TrainingGoal.muscleGain) {
        primary = TrainingGoal.strength;
      }
      result.goals = goals.copyWith(
        primary: primary,
        secondary: goals.secondary.where((goal) => goal != TrainingGoal.fatLoss && goal != primary).toList(),
      );
    }
    return result;
  }
}
