import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import '../mobility/mobility.dart';
import 'muscle_load.dart';

/// Was die Körperkarte zeigt: Sätze aus dem Krafttraining, Minuten Ausdauer oder Minuten Dehnen/Mobility.
enum BodyLoadKind {
  strength('Kraft', 'Sätze'),
  cardio('Kardio', 'min'),
  stretch('Dehnen', 'min');

  const BodyLoadKind(this.label, this.unit);

  final String label;

  /// Einheit der Werte je Muskel.
  final String unit;
}

/// Ausdauerminuten je Muskel: Minuten der Einheit × Anteil des Muskels (Hauptmuskeln 1, mitarbeitende 0,5 – wie
/// beim Krafttraining). Praxis-Zuordnung zur Orientierung, keine Messung der Muskelarbeit.
abstract final class CardioLoad {
  /// Volle Farbe ab so vielen Minuten pro Woche (untere Grenze der WHO-Empfehlung, Bull et al. 2020).
  static const weeklyFull = 150.0;

  static Map<Muscle, double> muscles(ActivitySport sport) => switch (sport) {
    ActivitySport.run => const {
      Muscle.quads: 1,
      Muscle.hamstrings: 1,
      Muscle.glutes: 1,
      Muscle.calves: 1,
      Muscle.adductors: 0.5,
    },
    ActivitySport.bike => const {Muscle.quads: 1, Muscle.glutes: 1, Muscle.hamstrings: 0.5, Muscle.calves: 0.5},
    ActivitySport.swim => const {
      Muscle.lats: 1,
      Muscle.frontDelts: 0.5,
      Muscle.sideDelts: 0.5,
      Muscle.rearDelts: 0.5,
      Muscle.chest: 0.5,
      Muscle.triceps: 0.5,
    },
    ActivitySport.strength || ActivitySport.other => const {},
  };

  /// Gewichtete Minuten je Muskel aus Einheiten von [from] bis [to] (beide eingeschlossen).
  static Map<Muscle, double> minutes(
    List<GarminActivity> activities, {
    required CalendarDay from,
    required CalendarDay to,
  }) {
    final result = <Muscle, double>{};
    for (final activity in activities) {
      final (day, seconds) = (activity.day, activity.durationSeconds);
      if (day == null || seconds == null || seconds <= 0 || day < from || day > to) continue;
      for (final MapEntry(key: muscle, value: share) in muscles(activity.sport).entries) {
        result[muscle] = (result[muscle] ?? 0) + seconds / 60 * share;
      }
    }
    return result;
  }

  /// Minuten je Sportart (nur Sportarten mit Muskelzuordnung), absteigend.
  static List<(ActivitySport, double)> bySport(
    List<GarminActivity> activities, {
    required CalendarDay from,
    required CalendarDay to,
  }) {
    final result = <ActivitySport, double>{};
    for (final activity in activities) {
      final (day, seconds) = (activity.day, activity.durationSeconds);
      if (day == null || seconds == null || seconds <= 0 || day < from || day > to) continue;
      if (muscles(activity.sport).isEmpty) continue;
      result[activity.sport] = (result[activity.sport] ?? 0) + seconds / 60;
    }
    return [for (final entry in result.entries) (entry.key, entry.value)]..sort((a, b) => b.$2.compareTo(a.$2));
  }
}

/// Minuten Dehnen und Mobility je Muskel aus dem Mobility-Protokoll. Die Minuten einer Einheit verteilen sich
/// gleichmäßig auf ihre Schwerpunkte; jeder Muskel eines Schwerpunkts bekommt dessen Anteil.
abstract final class StretchLoad {
  /// Volle Farbe ab so vielen Minuten pro Woche und Muskel (Praxiswert: zwei bis drei Einheiten mit je etwa einer
  /// Minute Halten je Muskel, siehe Regel `mobility.stretching`).
  static const weeklyFull = 5.0;

  /// Muskeln, die ein Schwerpunkt dehnt (Gegenstück zu `MobilityArea.forMuscle`).
  static List<Muscle> muscles(MobilityArea area) => switch (area) {
    MobilityArea.ankles => const [Muscle.calves],
    MobilityArea.hips => const [Muscle.glutes, Muscle.adductors],
    MobilityArea.hipFlexors => const [Muscle.quads],
    MobilityArea.hamstrings => const [Muscle.hamstrings],
    MobilityArea.thoracicSpine => const [Muscle.traps, Muscle.lats],
    MobilityArea.shoulders => const [Muscle.chest, Muscle.frontDelts, Muscle.lats],
    MobilityArea.lowerBack => const [Muscle.lowerBack],
  };

  /// Minuten je Schwerpunkt von [from] bis [to] (beide eingeschlossen).
  static Map<MobilityArea, double> areaMinutes(
    List<MobilityLogEntry> log, {
    required CalendarDay from,
    required CalendarDay to,
  }) {
    final result = <MobilityArea, double>{};
    for (final entry in log) {
      if (entry.day < from || entry.day > to || entry.areas.isEmpty || entry.minutes <= 0) continue;
      final areas = entry.areas.toSet();
      for (final area in areas) {
        result[area] = (result[area] ?? 0) + entry.minutes / areas.length;
      }
    }
    return result;
  }

  /// Minuten je Muskel; ein Muskel in zwei Schwerpunkten (z. B. Latissimus) bekommt beide Anteile.
  static Map<Muscle, double> minutes(List<MobilityLogEntry> log, {required CalendarDay from, required CalendarDay to}) {
    final result = <Muscle, double>{};
    for (final MapEntry(key: area, value: minutes) in areaMinutes(log, from: from, to: to).entries) {
      for (final muscle in muscles(area)) {
        result[muscle] = (result[muscle] ?? 0) + minutes;
      }
    }
    return result;
  }
}
