import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../coach/recovery_level.dart';
import '../coach/template_item.dart';
import '../garmin/garmin_activity.dart';
import '../garmin/garmin_profile.dart';
import '../garmin/strength_duplicates.dart';
import '../profile/goal_rules.dart';
import 'nutrient.dart';
import 'nutrition_settings.dart';

final class DayClassification {
  const DayClassification({
    required this.type,
    required this.enduranceMinutes,
    required this.trainingMinutes,
    required this.trainingLoad,
  });

  final DayType type;
  final double enduranceMinutes;
  final double trainingMinutes;
  final double trainingLoad;
}

enum TargetsSource {
  garmin('Garmin'),
  planned('Wochenplan'),
  none('keine Daten');

  const TargetsSource(this.rawValue);

  final String rawValue;
}

final class NutritionTargets {
  const NutritionTargets({
    required this.values,
    required this.dayType,
    required this.source,
    required this.classification,
    required this.profile,
    required this.basalMetabolicRate,
    required this.exerciseKilocalories,
    required this.proteinPerKilogram,
    required this.referenceWeightKilograms,
    required this.energyAvailabilityFloorApplied,
  });

  final NutrientValues values;
  final DayType dayType;
  final TargetsSource source;
  final DayClassification classification;
  final BodyProfile profile;
  final double basalMetabolicRate;
  final double exerciseKilocalories;
  final double proteinPerKilogram;

  /// Gewicht, auf das sich Protein und Kohlenhydrate beziehen (ab BMI 30 weniger als das Körpergewicht).
  final double referenceWeightKilograms;

  /// `true`, wenn die Energie auf 30 kcal/kg fettfreie Masse angehoben wurde (REDs-Schwelle).
  final bool energyAvailabilityFloorApplied;
}

/// Tagesziele der Ernährung (Port von `NutritionPlanner`, ursprünglich `ernaehrung/app/targets.py`).
///
/// - Energie: Grundumsatz nach Mifflin-St Jeor (1990) × PAL ohne Sport + Netto-kcal der Aktivitäten.
/// - Kohlenhydrate je kg nach Tagestyp (Thomas, Erdman & Burke 2016), Protein je Ziel, Fett als Rest (20–35 % der
///   Energie, ACSM 2016).
/// - Mikronährstoffe, Ballaststoffe: DGE-Referenzwerte 25 bis < 51 Jahre; Jod 150 µg (DGE/ÖGE 2025); Omega-3
///   EPA+DHA 250 mg (EFSA 2012).
/// - Flüssigkeit ~35 ml/kg + ~0,6 l je Stunde Ausdauer (ACSM 2016).
abstract final class NutritionPlanner {
  static const enduranceKeys = [
    'running', 'cycling', 'swimming', 'lap_swimming', 'open_water', 'trail', 'treadmill', 'virtual_ride', //
    'indoor_cycling', 'rowing', 'elliptical', 'cross_country', 'hiking', 'multi_sport', 'triathlon', 'road_biking', //
    'mountain_biking', 'gravel',
  ];
  static const strengthKeys = ['strength', 'fitness_equipment', 'hiit', 'yoga', 'pilates', 'training'];

  static Map<Nutrient, double> micro({required bool isFemale, required int age}) => {
    Nutrient.sodium: 1500,
    Nutrient.potassium: 4000,
    Nutrient.magnesium: isFemale ? 300 : 350,
    Nutrient.calcium: age < 19 ? 1200 : 1000,
    Nutrient.iron: isFemale ? 16 : 11,
    Nutrient.zinc: isFemale ? 8 : 14,
    Nutrient.vitaminD: 20,
    Nutrient.vitaminB12: 4,
    Nutrient.vitaminC: isFemale ? 95 : 110,
    Nutrient.fiber: 30,
    Nutrient.iodine: 150,
    Nutrient.omega3: 250,
  };

  static double mifflinStJeor(BodyProfile profile) {
    final base = 10 * profile.weightKilograms + 6.25 * profile.heightCentimeters - 5 * profile.age;
    return base + (profile.isFemale ? -161 : 5);
  }

  static bool isEndurance(String? typeKey) {
    final key = typeKey?.toLowerCase() ?? '';
    return enduranceKeys.any(key.contains) && !key.contains('walking');
  }

  static bool isStrength(String? typeKey) {
    final key = typeKey?.toLowerCase() ?? '';
    return strengthKeys.any(key.contains);
  }

  static DayClassification classify(List<GarminActivity> activities) {
    double minutes(GarminActivity activity) => (activity.durationSeconds ?? 0) / 60;
    final endurance = activities.where((activity) => isEndurance(activity.typeKey)).map(minutes).sum;
    final total = activities
        .where((activity) => isEndurance(activity.typeKey) || isStrength(activity.typeKey))
        .map(minutes)
        .sum;
    final load = activities.map((activity) => activity.trainingLoad).nonNulls.sum;
    final DayType type;
    if (endurance >= 240) {
      type = DayType.veryHard;
    } else if (endurance >= 90 || load >= 150) {
      type = DayType.hard;
    } else if (endurance >= 45 || total >= 75 || load >= 80) {
      type = DayType.moderate;
    } else if (total >= 20) {
      type = DayType.light;
    } else {
      type = DayType.restDay;
    }
    return DayClassification(
      type: type,
      enduranceMinutes: endurance.roundToDouble(),
      trainingMinutes: total.roundToDouble(),
      trainingLoad: load.roundToDouble(),
    );
  }

  /// Erwarteter Tagestyp aus dem Wochenplan, solange noch keine Aktivität aufgezeichnet ist – Kohlenhydrate gehören
  /// vor die Einheit (Impey et al. 2018).
  static DayType? plannedDayType(List<TemplateItem> items) {
    final types = items.map((item) {
      if (item.plannedType != null) return item.plannedType;
      final text = item.text.toLowerCase();
      if (['lange', 'longrun', 'koppel', 'renn'].any(text.contains)) return DayType.hard;
      return switch (item.kind) {
        TemplateItemKind.bike || TemplateItemKind.run => DayType.moderate,
        TemplateItemKind.strength || TemplateItemKind.swimOrLegs => DayType.light,
        TemplateItemKind.optional => null,
      };
    }).nonNulls;
    return maxBy(types, (DayType type) => type.index);
  }

  static NutritionTargets compute({
    required List<GarminActivity> activities,
    required List<TemplateItem> planItems,
    required NutritionSettings settings,
    required GarminProfile? garminProfile,
    required CalendarDay day,
    required bool hasGarminData,
    RecoveryLevel? recovery,
  }) {
    final profile = settings.profile(garminProfile, on: day);
    final weight = profile.weightKilograms;
    // Schutzgrenzen gelten hier, damit kein Pfad sie umgeht (Wägung, Anpassung, Saisonmodus, Altdaten).
    var goal = settings.goal;
    var weeklyChange = settings.weeklyWeightChangePercent;
    var adjustment = settings.energyAdjustmentKilocalories;
    switch (GoalRules.weightGuard(settings, profile)) {
      case WeightGoalGuard.free:
        break;
      case WeightGoalGuard.noTargets:
        goal = NutritionGoal.maintain;
        weeklyChange = null;
        adjustment = 0;
      case WeightGoalGuard.noDeficit:
        if (profile.age < GoalRules.minimumAge || goal.adjustPercent < 0 || (weeklyChange ?? 0) < 0) {
          goal = NutritionGoal.maintain;
          weeklyChange = null;
        }
        adjustment = math.max(adjustment, 0);
    }
    final classification = classify(activities);
    var dayType = classification.type;
    var source = hasGarminData ? TargetsSource.garmin : TargetsSource.none;
    // Sagt die Ampel „Pause“, wird die geplante Einheit nicht mitgegessen; bei „locker“ höchstens ein leichter Tag.
    var plannedType = plannedDayType(planItems);
    if (recovery == RecoveryLevel.pause) plannedType = null;
    if (recovery == RecoveryLevel.locker && plannedType != null && plannedType > DayType.light) {
      plannedType = DayType.light;
    }
    if (activities.isEmpty && plannedType != null && plannedType > dayType) {
      dayType = plannedType;
      source = TargetsSource.planned;
    }
    final bmr = mifflinStJeor(profile);
    final baseKcal = bmr * settings.activityFactor;
    // Ein Krafttraining, das als Export und als Aufzeichnung der Uhr vorliegt, zählt nur einmal.
    var exerciseKcal = StrengthDuplicates.removing(activities).fold<double>(0, (sum, activity) {
      final minutes = (activity.durationSeconds ?? 0) / 60;
      return sum + math.max(0, (activity.calories ?? 0) - bmr / 1440 * minutes);
    });
    if (source == TargetsSource.planned) {
      // Netto-Verbrauch der geplanten Einheit: (MET − 1) × kg × Stunden.
      final timed = recovery == RecoveryLevel.locker
          ? <TemplateItem>[]
          : planItems.where((item) => item.minutes != null);
      if (timed.isEmpty) {
        exerciseKcal = (dayType.plannedMET - 1) * weight * dayType.plannedMinutes / 60;
      } else {
        exerciseKcal = timed.fold<double>(0, (sum, item) {
          final met = item.kind == TemplateItemKind.strength ? DayType.light.plannedMET : DayType.moderate.plannedMET;
          return sum + (met - 1) * weight * (item.minutes ?? 0) / 60;
        });
      }
    }
    final dayEnergy = baseKcal + exerciseKcal;
    var adjustPercent = goal.adjustPercent;
    if (weeklyChange != null && dayEnergy > 0) {
      // 7.700 kcal je kg Körpergewicht; Grenzen: höchstens 25 % Defizit bzw. 15 % Überschuss.
      final dailyKilocalories = weeklyChange / 100 * weight * 7700 / 7;
      adjustPercent = math.max(-25, math.min(15, dailyKilocalories / dayEnergy * 100));
    }
    final goalPercent = adjustPercent * dayType.goalScale;
    var energy = dayEnergy * (1 + goalPercent / 100) + adjustment;
    // Höchstens ein Viertel Defizit, auch zusammen mit der Anpassung aus dem Gewichtsverlauf.
    energy = math.max(energy, 0.75 * dayEnergy);
    // Energieverfügbarkeit nie unter 30 kcal/kg fettfreie Masse (IOC-Konsensus REDs 2023), aber nie über dem Bedarf.
    final bodyFat = settings.bodyFatPercent ?? GoalRules.estimatedBodyFatPercent(profile);
    final fatFreeMass = weight * (1 - bodyFat / 100);
    final energyFloor = math.min(30 * fatFreeMass + exerciseKcal, dayEnergy);
    var floorApplied = false;
    if (energy < energyFloor) {
      energy = energyFloor;
      floorApplied = true;
    }
    final proteinPerKilogram = goal.proteinPerKilogram;
    final referenceWeight = GoalRules.referenceWeightKilograms(profile);
    var protein = proteinPerKilogram * referenceWeight;
    // Die Energie entscheidet: Kohlenhydrate nach Tagestyp, aber nur so viele, dass Fett mindestens 20 % behält
    // (ACSM 2016); höchstens bis zur Untergrenze der Spanne gekürzt.
    final fatMinimum = 0.20 * energy / 9;
    final fatMaximum = 0.35 * energy / 9;
    final carbRoom = (energy - 4 * protein - 9 * fatMinimum) / 4;
    var carbs = math.min(
      dayType.carbsPerKilogram * referenceWeight,
      math.max(carbRoom, dayType.minimumCarbsPerKilogram * referenceWeight),
    );
    final rest = energy - 4 * protein - 4 * carbs;
    var fat = math.min(math.max(rest / 9, fatMinimum), fatMaximum);
    if (rest / 9 > fatMaximum) carbs += (rest - fat * 9) / 4;
    // Auch wenn die Untergrenze der Kohlenhydrate die Energie übersteigt, bleibt Fett bei mindestens 20 %.
    fat = math.max(fat, (protein + carbs) / 9);
    var total = 4 * protein + 4 * carbs + 9 * fat;
    // Bei einem Defizit dürfen die Mindestmengen das Ziel nicht über den Bedarf heben: Kohlenhydrate zuerst kürzen,
    // Protein nur, wenn das nicht reicht. Bei Fett = (P + K) / 9 ist die Summe 5 × (P + K).
    if (energy < dayEnergy && total > dayEnergy) {
      protein = math.min(protein, dayEnergy / 5);
      carbs = math.max(0, dayEnergy / 5 - protein);
      fat = (protein + carbs) / 9;
      total = 4 * protein + 4 * carbs + 9 * fat;
    }
    final water =
        35 * weight +
        10 * classification.enduranceMinutes +
        5 * math.max(0, classification.trainingMinutes - classification.enduranceMinutes);
    final values = NutrientValues(micro(isFemale: profile.isFemale, age: profile.age))
      ..[Nutrient.kcal] = total.roundToDouble()
      ..[Nutrient.protein] = protein.roundToDouble()
      ..[Nutrient.carbs] = carbs.roundToDouble()
      ..[Nutrient.fat] = fat.roundToDouble()
      ..[Nutrient.sugar] = (0.10 * total / 4).roundToDouble()
      ..[Nutrient.saturatedFat] = (0.10 * total / 9).roundToDouble()
      ..[Nutrient.water] = (water / 50).roundToDouble() * 50;
    return NutritionTargets(
      values: values,
      dayType: dayType,
      source: source,
      classification: classification,
      profile: profile,
      basalMetabolicRate: bmr.roundToDouble(),
      exerciseKilocalories: exerciseKcal.roundToDouble(),
      proteinPerKilogram: proteinPerKilogram,
      referenceWeightKilograms: referenceWeight,
      energyAvailabilityFloorApplied: floorApplied,
    );
  }
}
