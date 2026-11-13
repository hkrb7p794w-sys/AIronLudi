import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../coach/recovery_level.dart';
import '../garmin/garmin_activity.dart';
import '../gym/exercise_catalog.dart';
import '../gym/exercise_library.dart';
import '../gym/gym_session.dart';
import '../gym/muscle_load.dart';
import '../nutrition/meal.dart';
import '../util/enum_codec.dart';

/// Körperregionen für Beweglichkeit. Gröber als `Muscle`, weil Mobility-Übungen Gelenke und Muskelketten
/// ansprechen.
enum MobilityArea implements RawEnum {
  ankles('Sprunggelenke und Waden'),
  hips('Hüfte und Gesäß'),
  hipFlexors('Hüftbeuger und Oberschenkel vorn'),
  hamstrings('Oberschenkel hinten'),
  thoracicSpine('Brustwirbelsäule'),
  shoulders('Schultern und Brust'),
  lowerBack('Unterer Rücken');

  const MobilityArea(this.label);

  final String label;

  @override
  String get rawValue => name;

  String get id => rawValue;

  /// Regionen, die ein Muskel aus dem Krafttraining mitbeansprucht (Praxis-Zuordnung, keine Messung).
  static List<MobilityArea> forMuscle(Muscle muscle) => switch (muscle) {
    Muscle.chest || Muscle.frontDelts => const [shoulders, thoracicSpine],
    Muscle.sideDelts || Muscle.rearDelts || Muscle.traps || Muscle.lats => const [shoulders, thoracicSpine],
    Muscle.lowerBack => const [lowerBack, hamstrings],
    Muscle.glutes || Muscle.adductors => const [hips],
    Muscle.quads => const [hipFlexors, ankles],
    Muscle.hamstrings => const [hamstrings, lowerBack],
    Muscle.calves => const [ankles],
    Muscle.biceps || Muscle.triceps || Muscle.forearms || Muscle.abs || Muscle.obliques => const [],
  };

  /// Regionen, die eine Ausdauersportart besonders fordert.
  static List<MobilityArea> forSport(ActivitySport sport) => switch (sport) {
    ActivitySport.run => const [ankles, hipFlexors, hamstrings, hips],
    ActivitySport.bike => const [hipFlexors, thoracicSpine, hamstrings],
    ActivitySport.swim => const [shoulders, thoracicSpine],
    ActivitySport.strength || ActivitySport.other => const [],
  };
}

/// Körperbereiche mit Beschwerden (Anregung: MCI, Paket 13). Die App stellt keine Diagnose: Sie setzt dort
/// Mobility-Schwerpunkte, weist bei Übungen auf die Belastung hin und gibt die Bereiche an die KI weiter.
enum ComplaintArea implements RawEnum {
  neck('Nacken'),
  shoulder('Schulter'),
  elbowWrist('Ellbogen oder Handgelenk'),
  lowerBack('Unterer Rücken'),
  hip('Hüfte'),
  knee('Knie'),
  ankle('Sprunggelenk oder Achillessehne');

  const ComplaintArea(this.label);

  final String label;

  @override
  String get rawValue => name;

  String get id => rawValue;

  /// Mobility-Regionen, die bei diesen Beschwerden Vorrang bekommen.
  List<MobilityArea> get mobilityAreas => switch (this) {
    neck => const [MobilityArea.thoracicSpine, MobilityArea.shoulders],
    shoulder => const [MobilityArea.shoulders, MobilityArea.thoracicSpine],
    elbowWrist => const [],
    lowerBack => const [MobilityArea.lowerBack, MobilityArea.hips, MobilityArea.hamstrings],
    hip => const [MobilityArea.hips, MobilityArea.hipFlexors],
    knee => const [MobilityArea.hipFlexors, MobilityArea.ankles, MobilityArea.hamstrings],
    ankle => const [MobilityArea.ankles],
  };

  /// Muskeln, deren Übungen den Bereich als Hauptmuskel belasten (Praxis-Zuordnung).
  Set<Muscle> get muscles => switch (this) {
    neck => const {Muscle.traps},
    shoulder => const {Muscle.chest, Muscle.frontDelts, Muscle.sideDelts},
    elbowWrist => const {Muscle.biceps, Muscle.triceps, Muscle.forearms},
    lowerBack => const {Muscle.lowerBack},
    hip => const {Muscle.glutes, Muscle.adductors},
    knee => const {Muscle.quads},
    ankle => const {Muscle.calves},
  };

  /// Bereiche aus [complaints], die eine Übung als Hauptmuskel belastet.
  static List<ComplaintArea> loaded(
    String exerciseID, {
    required MuscleGroup group,
    List<ExerciseInfo> custom = const [],
    required List<ComplaintArea> complaints,
  }) {
    if (complaints.isEmpty) return [];
    final main = {
      for (final MapEntry(:key, :value) in MuscleMap.involvement(exerciseID, group: group, custom: custom).entries)
        if (value >= MuscleMap.primary) key,
    };
    return complaints.where((complaint) => complaint.muscles.any(main.contains)).toList();
  }

  /// Hinweis bei einer Übung, die Beschwerdebereiche belastet; `null`, wenn keiner betroffen ist.
  static String? hint(List<ComplaintArea> areas) {
    if (areas.isEmpty) return null;
    return 'Belastet: ${areas.map((area) => area.label).join(', ')}. Gewicht und Bewegungsumfang so wählen, dass es '
        'schmerzfrei bleibt – sonst ersetzen. Bei anhaltenden Schmerzen ärztlich abklären lassen.';
  }
}

/// Wann die Einheit stattfindet. Vor dem Training nur dynamische Übungen: Langes statisches Dehnen direkt davor
/// kann die Leistung kurz mindern (Behm et al. 2016).
enum MobilityContext implements RawEnum {
  preTraining('Vor dem Training'),
  postTraining('Nach dem Training'),
  restDay('Ruhetag oder abends');

  const MobilityContext(this.label);

  final String label;

  @override
  String get rawValue => name;

  String get id => rawValue;

  bool get allowsStatic => this != preTraining;
}

enum DrillStyle {
  /// Bewegung durch den Bewegungsumfang, im Wechsel.
  dynamic,

  /// Position halten.
  hold,
}

final class MobilityDrill {
  const MobilityDrill({
    required this.id,
    required this.name,
    required this.areas,
    required this.style,
    required this.seconds,
    required this.perSide,
    required this.steps,
  });

  final String id;
  final String name;
  final List<MobilityArea> areas;
  final DrillStyle style;

  /// Dauer je Seite bzw. gesamt (ohne Seitenwechsel).
  final int seconds;
  final bool perSide;
  final List<String> steps;

  /// Gesamtdauer inklusive beider Seiten.
  int get totalSeconds => perSide ? seconds * 2 : seconds;

  @override
  bool operator ==(Object other) => other is MobilityDrill && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MobilityDrill($id)';
}

/// Eigene Übungsbeschreibungen (keine Inhalte anderer Apps). Halteübungen 45 s je Seite: unter 60 s je Muskel
/// zeigte sich auch direkt vor Belastung kaum ein Leistungsverlust (Behm et al. 2016).
abstract final class MobilityLibrary {
  // dart format off
  static const drills = [
    MobilityDrill(id: 'knee_to_wall_rocks', name: 'Knie zur Wand', areas: [MobilityArea.ankles], style: DrillStyle.dynamic, seconds: 40, perSide: true, steps: ['Ausfallschritt vor einer Wand, vordere Ferse bleibt am Boden.', 'Knie langsam Richtung Wand schieben und zurück, 10–12 Mal.', 'Knie zeigt über die zweite Zehe.']),
    MobilityDrill(id: 'calf_wall_stretch', name: 'Wadendehnung an der Wand', areas: [MobilityArea.ankles], style: DrillStyle.hold, seconds: 45, perSide: true, steps: ['Hände an die Wand, ein Bein weit nach hinten.', 'Hintere Ferse fest auf den Boden, Knie gestreckt.', 'Ruhig atmen, Zug in der Wade halten.']),
    MobilityDrill(id: 'ankle_circles', name: 'Fußkreisen im Stand', areas: [MobilityArea.ankles], style: DrillStyle.dynamic, seconds: 30, perSide: true, steps: ['Auf einem Bein stehen, wenn nötig festhalten.', 'Den freien Fuß große Kreise ziehen lassen, je Richtung 8 Mal.']),
    MobilityDrill(id: 'world_greatest', name: 'Ausfallschritt mit Rotation', areas: [MobilityArea.hipFlexors, MobilityArea.hips, MobilityArea.thoracicSpine], style: DrillStyle.dynamic, seconds: 45, perSide: true, steps: ['Großer Ausfallschritt, Hände innen neben den vorderen Fuß.', 'Arm auf der Seite des vorderen Beins zur Decke drehen, Blick folgt.', 'Zurück, 5–6 Mal je Seite.']),
    MobilityDrill(id: 'half_kneeling_hip_flexor', name: 'Hüftbeuger im Halbknien', areas: [MobilityArea.hipFlexors], style: DrillStyle.hold, seconds: 45, perSide: true, steps: ['Ein Knie am Boden, das andere Bein vorne aufgestellt.', 'Gesäß anspannen, Becken leicht aufrichten, bis vorne an der Hüfte Zug entsteht.', 'Nicht ins Hohlkreuz fallen.']),
    MobilityDrill(id: 'couch_stretch', name: 'Oberschenkel vorn am Sofa', areas: [MobilityArea.hipFlexors], style: DrillStyle.hold, seconds: 45, perSide: true, steps: ['Knie hinten an Sofa oder Wand, Fußrücken angelehnt.', 'Vorderen Fuß aufstellen, Oberkörper langsam aufrichten.', 'Nur so weit, wie es ohne Schmerz geht.']),
    MobilityDrill(id: 'leg_swings', name: 'Beinpendel', areas: [MobilityArea.hipFlexors, MobilityArea.hamstrings, MobilityArea.hips], style: DrillStyle.dynamic, seconds: 30, perSide: true, steps: ['Seitlich an einer Wand festhalten.', 'Bein locker vor und zurück schwingen, Ausschlag langsam steigern, 12–15 Mal.', 'Danach seitlich vor dem Körper pendeln.']),
    MobilityDrill(id: 'hamstring_sweeps', name: 'Beinrückseite im Gehen', areas: [MobilityArea.hamstrings], style: DrillStyle.dynamic, seconds: 40, perSide: false, steps: ['Eine Ferse vorne aufsetzen, Zehen hoch, Bein fast gestreckt.', 'Hüfte nach hinten schieben und mit den Händen Richtung Boden streichen.', 'Aufrichten, Seite wechseln, 8 Mal je Seite.']),
    MobilityDrill(id: 'seated_hamstring', name: 'Beinrückseite im Sitzen', areas: [MobilityArea.hamstrings, MobilityArea.lowerBack], style: DrillStyle.hold, seconds: 45, perSide: true, steps: ['Ein Bein gestreckt, das andere angewinkelt.', 'Mit langem Rücken aus der Hüfte nach vorne neigen.', 'Zug hinten im Oberschenkel, nicht in der Kniekehle.']),
    MobilityDrill(id: 'ninety_ninety', name: '90/90-Hüftwechsel', areas: [MobilityArea.hips], style: DrillStyle.dynamic, seconds: 45, perSide: false, steps: ['Sitzen, beide Knie 90 Grad gebeugt, eines vorne, eines seitlich.', 'Knie langsam zur anderen Seite kippen, ohne die Hände zu Hilfe zu nehmen, wenn es geht.', '8–10 Wechsel.']),
    MobilityDrill(id: 'pigeon', name: 'Gesäßdehnung in Rückenlage', areas: [MobilityArea.hips, MobilityArea.lowerBack], style: DrillStyle.hold, seconds: 45, perSide: true, steps: ['Rückenlage, einen Knöchel auf das andere Knie legen.', 'Das untere Bein zur Brust ziehen.', 'Kopf und Schultern bleiben entspannt am Boden.']),
    MobilityDrill(id: 'deep_squat_hold', name: 'Tiefe Hocke halten', areas: [MobilityArea.hips, MobilityArea.ankles], style: DrillStyle.hold, seconds: 45, perSide: false, steps: ['Füße etwas breiter als hüftbreit, Fersen am Boden.', 'Tief in die Hocke, Ellbogen schieben die Knie sanft nach außen.', 'Wenn nötig an einem Türrahmen festhalten.']),
    MobilityDrill(id: 'cat_cow', name: 'Katze und Kuh', areas: [MobilityArea.lowerBack, MobilityArea.thoracicSpine], style: DrillStyle.dynamic, seconds: 40, perSide: false, steps: ['Vierfüßlerstand, Hände unter den Schultern.', 'Rücken rund machen, dann langsam ins leichte Hohlkreuz, 8–10 Mal.', 'Bewegung Wirbel für Wirbel.']),
    MobilityDrill(id: 'thread_needle', name: 'Brustwirbelsäule drehen im Vierfüßler', areas: [MobilityArea.thoracicSpine, MobilityArea.shoulders], style: DrillStyle.dynamic, seconds: 40, perSide: true, steps: ['Vierfüßlerstand.', 'Einen Arm unter dem Körper durchschieben, dann zur Decke aufdrehen.', 'Blick folgt der Hand, 6–8 Mal je Seite.']),
    MobilityDrill(id: 'open_book', name: 'Offenes Buch', areas: [MobilityArea.thoracicSpine, MobilityArea.shoulders], style: DrillStyle.dynamic, seconds: 40, perSide: true, steps: ['Seitlage, Knie angewinkelt, Arme vorne aufeinander.', 'Oberen Arm im Bogen zur anderen Seite öffnen, Knie bleiben liegen.', 'Zurück, 6–8 Mal.']),
    MobilityDrill(id: 'doorway_pec', name: 'Brust im Türrahmen', areas: [MobilityArea.shoulders], style: DrillStyle.hold, seconds: 45, perSide: true, steps: ['Unterarm auf Schulterhöhe an den Türrahmen.', 'Mit dem Oberkörper langsam nach vorne drehen, bis vorne an Brust und Schulter Zug entsteht.']),
    MobilityDrill(id: 'wall_slides', name: 'Arme an der Wand hochschieben', areas: [MobilityArea.shoulders, MobilityArea.thoracicSpine], style: DrillStyle.dynamic, seconds: 40, perSide: false, steps: ['Rücken und Unterarme an die Wand.', 'Arme langsam nach oben schieben, ohne dass der untere Rücken abhebt.', '8–10 Mal.']),
    MobilityDrill(id: 'lat_stretch_bench', name: 'Latissimus an Bank oder Stuhl', areas: [MobilityArea.shoulders, MobilityArea.thoracicSpine], style: DrillStyle.hold, seconds: 45, perSide: false, steps: ['Knien vor einer Bank, Ellbogen darauf, Hände zusammen.', 'Gesäß nach hinten zu den Fersen, Brust sinkt nach unten.']),
    MobilityDrill(id: 'child_pose', name: 'Kindhaltung', areas: [MobilityArea.lowerBack, MobilityArea.hips], style: DrillStyle.hold, seconds: 45, perSide: false, steps: ['Aus dem Vierfüßlerstand das Gesäß auf die Fersen.', 'Arme lang nach vorne, Stirn ablegen, ruhig in den Rücken atmen.']),
    MobilityDrill(id: 'hip_hinge_good_morning', name: 'Hüftbeuge ohne Gewicht', areas: [MobilityArea.hamstrings, MobilityArea.lowerBack], style: DrillStyle.dynamic, seconds: 40, perSide: false, steps: ['Hände an die Hüfte, Knie leicht gebeugt.', 'Mit langem Rücken die Hüfte nach hinten schieben, bis hinten Zug entsteht.', 'Aufrichten, 10 Mal.']),
  ];
  // dart format on

  static final Map<String, MobilityDrill> byID = {for (final drill in drills) drill.id: drill};
}

/// Ergebnis eines Selbsttests in drei Stufen.
enum MobilityRating implements Comparable<MobilityRating> {
  limited('eingeschränkt'),
  moderate('mittel'),
  good('gut');

  const MobilityRating(this.label);

  final String label;

  int get rawValue => index;

  @override
  int compareTo(MobilityRating other) => index.compareTo(other.index);

  bool operator <(MobilityRating other) => index < other.index;
}

/// Eingabe eines Selbsttests.
sealed class MobilityInput {
  const MobilityInput();
}

/// Messung in cm, mit Grenzen für „mittel“ und „gut“ (jeweils einschließlich).
final class MobilityCentimeters extends MobilityInput {
  const MobilityCentimeters({required this.lower, required this.upper, required this.moderate, required this.good});

  final double lower;
  final double upper;
  final double moderate;
  final double good;
}

/// Direkte Einschätzung in drei Stufen.
final class MobilityLevels extends MobilityInput {
  const MobilityLevels(this.levels);

  final List<String> levels;
}

/// Einfache Selbsttests ohne Kamera. Ergebnis in drei Stufen; die Grenzen sind Praxiswerte zur Orientierung,
/// keine Diagnose.
final class MobilityTest {
  const MobilityTest({
    required this.id,
    required this.name,
    required this.areas,
    required this.steps,
    required this.input,
  });

  final String id;
  final String name;
  final List<MobilityArea> areas;
  final List<String> steps;
  final MobilityInput input;

  MobilityRating rating(double value) => switch (input) {
    MobilityCentimeters(:final moderate, :final good) =>
      value >= good
          ? MobilityRating.good
          : value >= moderate
          ? MobilityRating.moderate
          : MobilityRating.limited,
    MobilityLevels() => MobilityRating.values[value.round().clamp(0, 2)],
  };

  // dart format off
  static const all = [
    MobilityTest(id: 'knee_to_wall', name: 'Knie zur Wand', areas: [MobilityArea.ankles], steps: ['Barfuß vor eine Wand, Ausfallschritt.', 'Knie berührt die Wand, Ferse bleibt am Boden.', 'Fuß so weit wie möglich zurücksetzen und den Abstand große Zehe – Wand messen.', 'Schlechtere Seite eintragen.'], input: MobilityCentimeters(lower: 0.0, upper: 20.0, moderate: 6.0, good: 10.0)),
    MobilityTest(id: 'toe_touch', name: 'Zehen berühren', areas: [MobilityArea.hamstrings, MobilityArea.lowerBack], steps: ['Aufrecht stehen, Beine gestreckt, Füße zusammen.', 'Langsam nach vorne beugen, nicht wippen.', 'Abstand Fingerspitzen – Boden messen: über den Zehen negativ, Zehen erreicht 0, darüber hinaus positiv.'], input: MobilityCentimeters(lower: -40.0, upper: 20.0, moderate: -10.0, good: 0.0)),
    MobilityTest(id: 'shoulder_wall', name: 'Arme über Kopf an der Wand', areas: [MobilityArea.shoulders, MobilityArea.thoracicSpine], steps: ['Rücken, Hinterkopf und Gesäß an die Wand, Knie leicht gebeugt.', 'Gestreckte Arme vor dem Körper nach oben führen.', 'Unterer Rücken bleibt an der Wand.'], input: MobilityLevels(['Hände erreichen die Wand nicht', 'Wand nur mit Hohlkreuz erreicht', 'Daumen an der Wand, Rücken bleibt angelehnt'])),
    MobilityTest(id: 'deep_squat', name: 'Tiefe Hocke', areas: [MobilityArea.hips, MobilityArea.ankles], steps: ['Füße hüft- bis schulterbreit.', 'Ohne Halt so tief wie möglich in die Hocke und 30 Sekunden bleiben.'], input: MobilityLevels(['Nur mit Festhalten oder Fersen heben', 'Tief, aber unsicher oder Rücken stark rund', 'Tief und stabil, Fersen am Boden'])),
  ];
  // dart format on

  static final Map<String, MobilityTest> byID = {for (final test in all) test.id: test};
}

/// Ein gespeichertes Testergebnis.
final class MobilityTestResult {
  MobilityTestResult({String? id, required this.testID, required this.day, required this.value}) : id = id ?? newUuid();

  final String id;
  final String testID;
  final CalendarDay day;
  final double value;

  /// Letztes Ergebnis je Test.
  static Map<String, MobilityTestResult> latest(List<MobilityTestResult> results) {
    final latest = <String, MobilityTestResult>{};
    for (final result in results) {
      if ((latest[result.testID]?.day ?? const CalendarDay(1, 1, 1)) <= result.day) latest[result.testID] = result;
    }
    return latest;
  }

  Map<String, Object?> toJson() => {'id': id, 'testID': testID, 'day': day.toJson(), 'value': value};

  static MobilityTestResult? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, testID, rawDay, value) = (json['id'], json['testID'], json['day'], json['value']);
    if (id is! String || testID is! String || rawDay is! Map || value is! num) return null;
    try {
      return MobilityTestResult(
        id: id,
        testID: testID,
        day: CalendarDay.fromJson(rawDay.cast<String, Object?>()),
        value: value.toDouble(),
      );
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MobilityTestResult &&
      other.id == id &&
      other.testID == testID &&
      other.day == day &&
      other.value == value;

  @override
  int get hashCode => Object.hash(id, testID, day, value);
}

/// Erledigte Mobility-Einheit (für Verlauf und Wochenzählung).
final class MobilityLogEntry {
  const MobilityLogEntry({required this.day, required this.minutes, required this.areas});

  final CalendarDay day;
  final int minutes;
  final List<MobilityArea> areas;

  Map<String, Object?> toJson() => {
    'day': day.toJson(),
    'minutes': minutes,
    'areas': [for (final area in areas) area.rawValue],
  };

  static MobilityLogEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final (rawDay, minutes) = (json['day'], json['minutes']);
    final areas = enumListStrict(MobilityArea.values, json['areas']);
    if (rawDay is! Map || minutes is! int || areas == null) return null;
    try {
      return MobilityLogEntry(
        day: CalendarDay.fromJson(rawDay.cast<String, Object?>()),
        minutes: minutes,
        areas: areas,
      );
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MobilityLogEntry &&
      other.day == day &&
      other.minutes == minutes &&
      const ListEquality<MobilityArea>().equals(other.areas, areas);

  @override
  int get hashCode => Object.hash(day, minutes, Object.hashAll(areas));
}

/// Einstellungen und Verlauf (in der App gespeichert).
final class MobilitySettings {
  MobilitySettings();

  int minutes = 10;
  List<MobilityTestResult> results = [];
  List<MobilityLogEntry> log = [];

  /// Bereiche mit Beschwerden (selbst angegeben).
  List<ComplaintArea> complaints = [];

  Map<String, Object?> toJson() => {
    'minutes': minutes,
    'results': [for (final result in results) result.toJson()],
    'log': [for (final entry in log) entry.toJson()],
    'complaints': [for (final complaint in complaints) complaint.rawValue],
  };

  /// Tolerant: unlesbare Teile fallen auf ihren Standard zurück (wie in Swift).
  static MobilitySettings fromJson(Object? json) {
    final settings = MobilitySettings();
    if (json is! Map) return settings;
    final minutes = json['minutes'];
    if (minutes is int) settings.minutes = minutes;
    settings
      ..results = listStrict(json['results'], MobilityTestResult.fromJson) ?? []
      ..log = listStrict(json['log'], MobilityLogEntry.fromJson) ?? []
      ..complaints = enumListStrict(ComplaintArea.values, json['complaints']) ?? [];
    return settings;
  }

  /// Eine Zeile für Chat und KI-Analyse: Wochenzahl und Einstufung der Selbsttests (keine Rohwerte).
  String? contextLine(CalendarDay today) {
    final latest = MobilityTestResult.latest(results);
    final tests = [
      for (final test in MobilityTest.all)
        if (latest[test.id] case final result?) '${test.name} ${test.rating(result.value).label}',
    ];
    final count = sessions(inWeekEnding: today);
    if (count == 0 && tests.isEmpty && complaints.isEmpty) return null;
    var line = 'Mobility: $count Einheiten in den letzten 7 Tagen';
    if (tests.isNotEmpty) line += '; Selbsttests: ${tests.join(', ')}';
    line += '.';
    if (complaints.isNotEmpty) {
      line +=
          ' Angegebene Beschwerden: ${complaints.map((complaint) => complaint.label).join(', ')} – keine Diagnose '
          'stellen, Übungen schmerzfrei wählen und bei anhaltenden Schmerzen ärztliche Abklärung empfehlen.';
    }
    return line;
  }

  /// Einheiten in den sieben Tagen bis [inWeekEnding] (einschließlich).
  int sessions({required CalendarDay inWeekEnding}) {
    final start = inWeekEnding.adding(-6);
    return {
      for (final entry in log)
        if (entry.day >= start && entry.day <= inWeekEnding) entry.day,
    }.length;
  }
}

/// Ein Block der Einheit.
final class MobilityBlock {
  const MobilityBlock({required this.drill, required this.area});

  final MobilityDrill drill;
  final MobilityArea area;

  String get id => drill.id;
}

final class MobilityRoutine {
  const MobilityRoutine({
    required this.context,
    required this.minutes,
    required this.focus,
    required this.reasons,
    required this.blocks,
  });

  final MobilityContext context;
  final int minutes;
  final List<MobilityArea> focus;

  /// Begründung je Schwerpunkt, z. B. „Laufen gestern 50 min“.
  final List<String> reasons;
  final List<MobilityBlock> blocks;

  int get totalSeconds =>
      blocks.fold(0, (sum, block) => sum + block.drill.totalSeconds + MobilityPlanner.transitionSeconds);
}

/// Bedarf einer Region.
final class MobilityScore {
  const MobilityScore({required this.area, required this.points, required this.reasons});

  final MobilityArea area;
  final double points;
  final List<String> reasons;
}

/// Regeln entscheiden: Schwerpunkte aus Krafttraining (Sätze je Muskel), Ausdauer (Minuten je Sportart) und den
/// eigenen Testergebnissen. Kein KI-Aufruf.
abstract final class MobilityPlanner {
  static const transitionSeconds = 10;
  static const balancedReason = 'Keine Belastung oder Testergebnisse – ausgewogene Einheit für den ganzen Körper.';
  static const durations = [5, 10, 20];

  /// Belastung, ab der eine Region voll zählt.
  static const fullSets = 6.0;
  static const fullMinutes = 60.0;

  /// [recentSets]: effektive Sätze je Muskel der letzten 48 Stunden. [enduranceMinutes]: Minuten je Sportart
  /// gestern und heute.
  static List<MobilityScore> scores({
    required Map<Muscle, double> recentSets,
    required Map<ActivitySport, double> enduranceMinutes,
    required List<MobilityTestResult> results,
    List<ComplaintArea> complaints = const [],
  }) {
    final points = <MobilityArea, double>{};
    final reasons = <MobilityArea, List<String>>{};
    void add(MobilityArea area, double value, String reason) {
      points[area] = (points[area] ?? 0) + value;
      (reasons[area] ??= []).add(reason);
    }

    final gymByArea = <MobilityArea, double>{};
    for (final muscle in Muscle.values) {
      final sets = recentSets[muscle] ?? 0;
      if (sets <= 0) continue;
      for (final area in MobilityArea.forMuscle(muscle)) {
        gymByArea[area] = (gymByArea[area] ?? 0) + sets;
      }
    }
    for (final area in MobilityArea.values) {
      final sets = gymByArea[area];
      if (sets == null) continue;
      add(area, (sets / fullSets).clamp(0, 1) * 2, 'Krafttraining: ${sets.round()} Sätze in den letzten 2 Tagen');
    }

    for (final sport in const [ActivitySport.run, ActivitySport.bike, ActivitySport.swim]) {
      final minutes = enduranceMinutes[sport];
      if (minutes == null || minutes < 15) continue;
      for (final area in MobilityArea.forSport(sport)) {
        add(area, (minutes / fullMinutes).clamp(0, 1) * 2, '${sportLabel(sport)} ${minutes.round()} min seit gestern');
      }
    }

    // Swift durchläuft hier ein Dictionary (Reihenfolge zufällig); Dart nimmt die Reihenfolge der Tests.
    final latest = MobilityTestResult.latest(results);
    for (final test in MobilityTest.all) {
      final result = latest[test.id];
      if (result == null) continue;
      final rating = test.rating(result.value);
      if (!(rating < MobilityRating.good)) continue;
      for (final area in test.areas) {
        add(area, rating == MobilityRating.limited ? 3 : 1.5, 'Test „${test.name}“: ${rating.label}');
      }
    }

    for (final complaint in complaints) {
      for (final area in complaint.mobilityAreas) {
        add(area, 2, 'Beschwerden: ${complaint.label} – nur schmerzfrei bewegen');
      }
    }

    // Stabile Reihenfolge: Punkte absteigend, bei Gleichstand die Reihenfolge der Regionen.
    final ranked = [
      for (final area in MobilityArea.values)
        MobilityScore(area: area, points: points[area] ?? 0, reasons: reasons[area] ?? const []),
    ];
    mergeSort(ranked, compare: (a, b) => b.points.compareTo(a.points));
    return ranked;
  }

  static String sportLabel(ActivitySport sport) => switch (sport) {
    ActivitySport.run => 'Laufen',
    ActivitySport.bike => 'Radfahren',
    ActivitySport.swim => 'Schwimmen',
    ActivitySport.strength => 'Krafttraining',
    ActivitySport.other => 'Training',
  };

  /// Zahl der Schwerpunkte je Dauer.
  static int focusCount(int minutes) => minutes <= 5
      ? 2
      : minutes <= 10
      ? 3
      : 5;

  static MobilityRoutine routine({
    required MobilityContext context,
    required int minutes,
    required Map<Muscle, double> recentSets,
    required Map<ActivitySport, double> enduranceMinutes,
    required List<MobilityTestResult> results,
    List<ComplaintArea> complaints = const [],
  }) {
    final ranked = scores(
      recentSets: recentSets,
      enduranceMinutes: enduranceMinutes,
      results: results,
      complaints: complaints,
    );
    final focus = ranked.take(focusCount(minutes)).toList();
    final budget = minutes * 60;
    final used = <String>{};
    final blocks = <MobilityBlock>[];
    var spent = 0;

    List<MobilityDrill> candidates(MobilityArea area) {
      final fitting = MobilityLibrary.drills.where((drill) => drill.areas.contains(area) && !used.contains(drill.id));
      final allowed = (context.allowsStatic ? fitting : fitting.where((drill) => drill.style == DrillStyle.dynamic))
          .toList();
      // Nach dem Training und am Ruhetag zuerst halten (größere Wirkung auf die Beweglichkeit, Konrad et al.
      // 2023), vor dem Training nur dynamisch. Dann Hauptregion zuerst, sonst Bibliotheksreihenfolge.
      int rank(MobilityDrill drill) {
        final first = context.allowsStatic ? drill.style == DrillStyle.hold : drill.style == DrillStyle.dynamic;
        final main = drill.areas.first == area;
        return (first ? 0 : 2) + (main ? 0 : 1);
      }

      mergeSort(allowed, compare: (a, b) => rank(a).compareTo(rank(b)));
      return allowed;
    }

    var progress = true;
    while (progress) {
      progress = false;
      for (final score in focus) {
        // Höchstens 30 Sekunden über der gewählten Dauer.
        final drill = candidates(score.area)
            .firstWhereOrNull((drill) => spent + drill.totalSeconds + transitionSeconds <= budget + 30);
        if (drill == null) continue;
        used.add(drill.id);
        blocks.add(MobilityBlock(drill: drill, area: score.area));
        spent += drill.totalSeconds + transitionSeconds;
        progress = true;
      }
    }

    final reasons = [
      for (final score in focus)
        if (score.reasons.isNotEmpty) '${score.area.label}: ${score.reasons.first}',
    ];
    return MobilityRoutine(
      context: context,
      minutes: minutes,
      focus: [for (final score in focus) score.area],
      reasons: reasons.isEmpty ? const [balancedReason] : reasons,
      blocks: blocks,
    );
  }

  /// Mobility auf „Heute“ vorschlagen: an Tagen ohne Training und bei gelber oder roter Ampel (dann ersetzt eine
  /// ruhige Einheit das harte Training), sofern heute noch keine eingetragen ist.
  static bool suggestToday({required bool hasTraining, required RecoveryLevel? recovery, required bool doneToday}) {
    if (doneToday) return false;
    if (!hasTraining) return true;
    return recovery == RecoveryLevel.locker || recovery == RecoveryLevel.pause;
  }

  /// Effektive Sätze je Muskel in den 48 Stunden vor [now].
  static Map<Muscle, double> recentSets(
    List<GymSession> sessions, {
    required DateTime now,
    List<ExerciseInfo> custom = const [],
  }) {
    final since = now.subtract(const Duration(hours: 48));
    final result = <Muscle, double>{};
    for (final session in sessions) {
      if (session.start.isBefore(since) || session.start.isAfter(now)) continue;
      for (final MapEntry(key: muscle, value: sets) in MuscleLoad.session(session, custom: custom).entries) {
        result[muscle] = (result[muscle] ?? 0) + sets;
      }
    }
    return result;
  }

  /// Minuten je Sportart gestern und heute.
  static Map<ActivitySport, double> enduranceMinutes(List<GarminActivity> activities, {required CalendarDay today}) {
    final yesterday = today.adding(-1);
    final result = <ActivitySport, double>{};
    for (final activity in activities) {
      final day = activity.day;
      final seconds = activity.durationSeconds;
      if (day == null || day < yesterday || day > today || seconds == null) continue;
      result[activity.sport] = (result[activity.sport] ?? 0) + seconds / 60;
    }
    return result;
  }
}
