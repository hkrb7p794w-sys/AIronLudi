import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../endurance/endurance_plan.dart';
import '../endurance/training_load.dart';
import '../garmin/garmin_activity.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import 'recommendation.dart';
import 'recovery_level.dart';

/// Wie stark der Tag fordert, verglichen mit dem üblichen Tag der letzten Wochen.
enum StrainLevel {
  rest('Ruhig'),
  light('Leicht'),
  moderate('Mittel'),
  high('Hoch'),
  veryHigh('Sehr hoch');

  const StrainLevel(this.label);

  final String label;
}

/// „Meine Belastung heute“: erledigte und noch geplante Belastung (Training-Stress-Punkte), der übliche Tag (Fitness,
/// CTL) und die Erholungsampel. Regeln, keine KI.
final class DailyStrain {
  const DailyStrain({
    required this.done,
    required this.planned,
    required this.typical,
    required this.fatigue,
    required this.level,
    required this.recovery,
    required this.headline,
    required this.advice,
    required this.week,
  });

  /// Heute schon trainiert (Punkte).
  final double done;

  /// Heute noch geplant (Punkte, geschätzt).
  final double planned;

  /// Üblicher Tag: Fitness (CTL, 42 Tage) – mindestens [DailyStrainRules.minimumTypical].
  final double typical;

  /// Ermüdung (ATL, 7 Tage).
  final double fatigue;
  final StrainLevel level;
  final RecoveryLevel? recovery;
  final String headline;
  final String advice;

  /// Belastung der letzten 7 Tage (ältester zuerst, heute zuletzt) für das Mini-Diagramm.
  final List<double> week;

  double get total => done + planned;

  /// Anteil am üblichen Tag (1 = so viel wie sonst im Schnitt).
  double get ratio => typical <= 0 ? 0 : total / typical;

  /// Form (Fitness − Ermüdung).
  double get form => typical - fatigue;
}

abstract final class DailyStrainRules {
  /// Untergrenze für den üblichen Tag, damit wenige Wochen Daten keine Riesenausschläge ergeben.
  static const minimumTypical = 25.0;

  /// Geschätzte Punkte einer geplanten Einheit (Sportart × Intensität) – Mittelwerte für 45–100 min.
  static double plannedLoad(SessionSlot slot) => switch ((slot.sport, slot.intensity)) {
    (TrainingSport.run, SessionIntensity.easy) => 45,
    (TrainingSport.run, SessionIntensity.hard) => 70,
    (TrainingSport.run, SessionIntensity.long) => 100,
    (TrainingSport.bike, SessionIntensity.easy) => 40,
    (TrainingSport.bike, SessionIntensity.hard) => 65,
    (TrainingSport.bike, SessionIntensity.long) => 110,
    (TrainingSport.swim, SessionIntensity.easy) => 35,
    (TrainingSport.swim, SessionIntensity.hard) => 50,
    (TrainingSport.swim, SessionIntensity.long) => 60,
    (TrainingSport.strength, SessionIntensity.easy) => 30,
    (TrainingSport.strength, _) => 45,
    (TrainingSport.other, _) => 20,
  };

  static ActivitySport _activitySport(TrainingSport sport) => sport.garminSport;

  /// [activities]: alle Aktivitäten (für heute und den Verlauf). [plannedToday]: Einheiten laut Wochenplan heute;
  /// eine schon aufgezeichnete Einheit derselben Sportart zählt als erledigt. [enduranceToday]: Einheiten des
  /// Ausdauerplans heute (haben Vorrang vor geschätzten Wochenplan-Einheiten derselben Sportart).
  /// [gymMinutesToday]: Krafttraining der App ohne Aufzeichnung der Uhr (35 Punkte je Stunde).
  static DailyStrain compute({
    required List<GarminActivity> activities,
    required List<SessionSlot> plannedToday,
    required Recommendation? recovery,
    required CalendarDay today,
    List<PlanSlot> enduranceToday = const [],
    double gymMinutesToday = 0,
    AthleteThresholds thresholds = const AthleteThresholds(),
  }) {
    final daily = TrainingLoad.daily(activities, thresholds);
    if (gymMinutesToday > 0) daily[today] = (daily[today] ?? 0) + gymMinutesToday / 60 * 35;
    final state = TrainingLoad.state(daily, day: today);
    final done = daily[today] ?? 0;

    // Noch offen: geplante Einheiten, für die heute keine Aufzeichnung derselben Sportart vorliegt.
    final recorded = <ActivitySport, int>{};
    for (final activity in activities.where((activity) => activity.day == today)) {
      recorded[activity.sport] = (recorded[activity.sport] ?? 0) + 1;
    }
    if (gymMinutesToday > 0) recorded[ActivitySport.strength] = (recorded[ActivitySport.strength] ?? 0) + 1;
    double planned = 0;
    final enduranceSports = <ActivitySport>{};
    for (final slot in enduranceToday) {
      if (slot.status != SlotStatus.planned || slot.current.isRest) continue;
      final sport = slot.current.sport.activitySport;
      enduranceSports.add(sport);
      if ((recorded[sport] ?? 0) > 0) {
        recorded[sport] = recorded[sport]! - 1;
        continue;
      }
      planned += slot.current.load;
    }
    for (final slot in plannedToday) {
      final sport = _activitySport(slot.sport);
      if (enduranceSports.contains(sport)) continue;
      if ((recorded[sport] ?? 0) > 0) {
        recorded[sport] = recorded[sport]! - 1;
        continue;
      }
      planned += plannedLoad(slot);
    }
    if (recovery?.level == RecoveryLevel.pause) planned = 0;

    // Ohne Training in den letzten sechs Wochen gibt es keinen „üblichen Tag“: dann feste Stufen (40/80/120 Punkte).
    final hasHistory = daily.entries.any(
      (entry) => entry.key < today && entry.key >= today.adding(-42) && entry.value > 0,
    );
    final typical = hasHistory ? math.max(state.fitness, minimumTypical) : 60.0;
    final total = done + planned;
    final ratio = total / typical;
    final level = total < 5
        ? StrainLevel.rest
        : hasHistory
        ? (ratio < 0.6
              ? StrainLevel.light
              : ratio < 1.1
              ? StrainLevel.moderate
              : ratio < 1.6
              ? StrainLevel.high
              : StrainLevel.veryHigh)
        : (total < 40
              ? StrainLevel.light
              : total < 80
              ? StrainLevel.moderate
              : total < 120
              ? StrainLevel.high
              : StrainLevel.veryHigh);
    final recoveryLevel = recovery?.level;
    final headline = switch (level) {
      StrainLevel.rest => 'Heute ruhig',
      _ when done < 5 => '${level.label} geplant',
      _ => '${level.label} belastet',
    };
    final advice = switch ((recoveryLevel, level)) {
      (RecoveryLevel.pause, _) when done >= 5 =>
        'Deine Erholung sagt Pause – heute nichts mehr, morgen locker beginnen.',
      (RecoveryLevel.pause, _) => 'Deine Erholung sagt Pause – die geplante Einheit zählt heute nicht.',
      (RecoveryLevel.locker, StrainLevel.high || StrainLevel.veryHigh) =>
        'Viel für einen Tag mit eingeschränkter Erholung – heute nichts Intensives mehr.',
      _ when !hasHistory && planned > 0 =>
        '${planned.round()} Punkte geplant. Noch kein Verlauf – eingeordnet nach festen Werten, bis Trainings da sind.',
      _ when !hasHistory => 'Noch kein Verlauf – eingeordnet nach festen Werten, bis Trainings da sind.',
      (_, StrainLevel.veryHigh) when done < 5 =>
        'Geplant sind ${planned.round()} Punkte – deutlich mehr als dein üblicher Tag, danach bewusst erholen.',
      (_, StrainLevel.veryHigh) => 'Deutlich mehr als dein üblicher Tag – danach bewusst erholen.',
      (_, StrainLevel.rest) => 'Kein Training geplant oder aufgezeichnet.',
      _ when planned > 0 && done < 5 => 'Noch nichts erledigt, ${planned.round()} Punkte geplant.',
      _ when planned > 0 => 'Noch ${planned.round()} Punkte geplant.',
      _ => 'Im Rahmen deines üblichen Trainings.',
    };
    return DailyStrain(
      done: (done * 10).roundToDouble() / 10,
      planned: planned,
      typical: (typical * 10).roundToDouble() / 10,
      fatigue: (state.fatigue * 10).roundToDouble() / 10,
      level: level,
      recovery: recoveryLevel,
      headline: headline,
      advice: advice,
      week: [for (var offset = 6; offset >= 0; offset--) daily[today.adding(-offset)] ?? 0],
    );
  }
}
