import 'dart:math' as math;

import '../util/enum_codec.dart';
import '../util/int_range.dart';
import 'exercise_catalog.dart';

/// Geräte, mit denen eine Übung ausgeführt wird.
enum Equipment implements RawEnum {
  barbell,
  dumbbell,
  machine,
  cable,
  kettlebell,
  band,
  pullupBar,
  bench,
  bodyweight;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    barbell => 'Langhantel',
    dumbbell => 'Kurzhanteln',
    machine => 'Maschinen',
    cable => 'Kabelzug',
    kettlebell => 'Kettlebell',
    band => 'Widerstandsband',
    pullupBar => 'Klimmzugstange',
    bench => 'Hantelbank',
    bodyweight => 'Körpergewicht',
  };

  /// Typische Ausstattungen für die Auswahl im Profil.
  static final Set<Equipment> gym = values.toSet();
  static const Set<Equipment> homeDumbbells = {dumbbell, bench, band, bodyweight};
  static const Set<Equipment> none = {bodyweight, band};

  static Equipment? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Wie eine Übung erfasst wird.
enum ExerciseTracking implements RawEnum {
  /// Gewicht × Wiederholungen.
  weightReps,

  /// Nur Wiederholungen (Körpergewicht, optional mit Zusatzgewicht).
  reps,

  /// Haltezeit in Sekunden (im Feld „Wiederholungen“).
  time;

  @override
  String get rawValue => name;

  static ExerciseTracking? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Eine Übung der Bibliothek: Muskeln, Geräte, Anleitung und Regeln für die Progression.
final class ExerciseInfo {
  ExerciseInfo({
    required this.id,
    required this.name,
    required this.group,
    this.secondary = const [],
    required this.equipment,
    this.tracking = ExerciseTracking.weightReps,
    required this.compound,
    required this.lowerReps,
    required int upperReps,
    this.step = 2.5,
    this.percent = 2.5,
    this.instructions = const [],
    this.isCustom = false,
  }) : upperReps = math.max(upperReps, lowerReps);

  /// Eigene Übung des Nutzers.
  factory ExerciseInfo.custom({
    required String name,
    required MuscleGroup group,
    required Equipment equipment,
    required ExerciseTracking tracking,
  }) {
    final trimmed = name.trim();
    final isTime = tracking == ExerciseTracking.time;
    return ExerciseInfo(
      id: 'eigen_${ExerciseCatalog.slug(trimmed)}',
      name: trimmed,
      group: group,
      equipment: [equipment],
      tracking: tracking,
      compound: false,
      lowerReps: isTime ? 20 : 8,
      upperReps: isTime ? 60 : 12,
      step: equipment == Equipment.dumbbell ? 1 : 2.5,
      isCustom: true,
    );
  }

  final String id;
  String name;
  MuscleGroup group;
  List<MuscleGroup> secondary;

  /// Eines davon genügt (z. B. Fliegende mit Kurzhanteln oder am Kabel).
  List<Equipment> equipment;
  ExerciseTracking tracking;
  bool compound;
  int lowerReps;
  int upperReps;

  /// Kleinster Gewichtssprung in kg.
  double step;

  /// Angestrebte Steigerung in Prozent.
  double percent;
  List<String> instructions;

  /// Selbst angelegt.
  bool isCustom;

  IntRange get repRange => IntRange(lowerReps, upperReps);

  /// Mit der vorhandenen Ausstattung machbar.
  bool isAvailable(Set<Equipment> available) =>
      equipment.isEmpty || equipment.contains(Equipment.bodyweight) || equipment.any(available.contains);

  /// Regel für die Doppelprogression (`GymProgression`).
  ExerciseRule get rule => ExerciseRule(
    id: id,
    name: name,
    group: group,
    pattern: '',
    reps: repRange,
    compound: compound,
    step: step,
    percent: percent,
    bodyweightReps: tracking == ExerciseTracking.reps ? true : (tracking == ExerciseTracking.time ? false : null),
  );

  ExerciseInfo copy() => ExerciseInfo(
    id: id,
    name: name,
    group: group,
    secondary: [...secondary],
    equipment: [...equipment],
    tracking: tracking,
    compound: compound,
    lowerReps: lowerReps,
    upperReps: upperReps,
    step: step,
    percent: percent,
    instructions: [...instructions],
    isCustom: isCustom,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'group': group.rawValue,
    'secondary': [for (final item in secondary) item.rawValue],
    'equipment': [for (final item in equipment) item.rawValue],
    'tracking': tracking.rawValue,
    'compound': compound,
    'lowerReps': lowerReps,
    'upperReps': upperReps,
    'step': step,
    'percent': percent,
    'instructions': instructions,
    'isCustom': isCustom,
  };

  /// Wie das synthetisierte `Decodable`: alle Felder sind Pflicht, ein unbekannter Wert macht den Eintrag ungültig.
  static ExerciseInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final group = MuscleGroup.fromRaw(json['group']);
    final secondary = enumListStrict(MuscleGroup.values, json['secondary']);
    final equipment = enumListStrict(Equipment.values, json['equipment']);
    final tracking = ExerciseTracking.fromRaw(json['tracking']);
    final instructions = json['instructions'];
    final (id, name, compound) = (json['id'], json['name'], json['compound']);
    final (lower, upper) = (json['lowerReps'], json['upperReps']);
    final (step, percent, isCustom) = (jsonDouble(json['step']), jsonDouble(json['percent']), json['isCustom']);
    if (id is! String ||
        name is! String ||
        group == null ||
        secondary == null ||
        equipment == null ||
        tracking == null ||
        compound is! bool ||
        lower is! int ||
        upper is! int ||
        step == null ||
        percent == null ||
        instructions is! List ||
        !instructions.every((item) => item is String) ||
        isCustom is! bool) {
      return null;
    }
    // Wie der Swift-Decoder (memberwise ohne Initialisierer-Logik): Obergrenze wird beim Lesen nicht korrigiert.
    return ExerciseInfo(
      id: id,
      name: name,
      group: group,
      secondary: secondary,
      equipment: equipment,
      tracking: tracking,
      compound: compound,
      lowerReps: lower,
      upperReps: upper,
      step: step,
      percent: percent,
      instructions: instructions.cast<String>(),
      isCustom: isCustom,
    )..upperReps = upper;
  }

  @override
  bool operator ==(Object other) =>
      other is ExerciseInfo &&
      other.id == id &&
      other.name == name &&
      other.group == group &&
      _listEquals(other.secondary, secondary) &&
      _listEquals(other.equipment, equipment) &&
      other.tracking == tracking &&
      other.compound == compound &&
      other.lowerReps == lowerReps &&
      other.upperReps == upperReps &&
      other.step == step &&
      other.percent == percent &&
      _listEquals(other.instructions, instructions) &&
      other.isCustom == isCustom;

  @override
  int get hashCode => Object.hash(id, name, group, tracking, compound, lowerReps, upperReps, step, percent, isCustom);

  @override
  String toString() => 'ExerciseInfo($id)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Übungsbibliothek mit kurzer Technikanleitung. Übungen aus dem Garmin-Katalog (`ExerciseCatalog`) behalten ihre
/// IDs, damit Verlauf und Progression aus Garmin-Importen weiter zusammenpassen.
abstract final class ExerciseLibrary {
  // dart format off
  static final List<ExerciseInfo> all = List.unmodifiable([
    // Brust
    _item('bankdruecken', 'Bankdrücken', MuscleGroup.chest, [MuscleGroup.triceps, MuscleGroup.shoulders], [Equipment.barbell], 6, 10, compound: true, ['Auf der Bank liegen, Füße fest am Boden, Schulterblätter zusammen und nach unten ziehen.', 'Stange kontrolliert zur unteren Brust senken, Ellbogen etwa 45–70° vom Körper.', 'Gerade nach oben drücken, ohne das Gesäß von der Bank zu heben.']),
    _item('kurzhantel_bankdruecken', 'Kurzhantel-Bankdrücken', MuscleGroup.chest, [MuscleGroup.triceps, MuscleGroup.shoulders], [Equipment.dumbbell], 6, 10, compound: true, ['Hanteln auf Brusthöhe, Handflächen zeigen Richtung Füße.', 'Hanteln über der Brust zusammenführen, ohne sie anzuschlagen.', 'Langsam senken, bis eine leichte Dehnung in der Brust spürbar ist.']),
    _item('schraegbankdruecken', 'Schrägbankdrücken', MuscleGroup.chest, [MuscleGroup.shoulders, MuscleGroup.triceps], [Equipment.barbell], 6, 10, compound: true, ['Bank auf etwa 30° stellen.', 'Stange zur oberen Brust senken, Schulterblätter bleiben zurückgezogen.', 'Kontrolliert nach oben drücken.']),
    _item('kurzhantel_schraegbankdruecken', 'Kurzhantel-Schrägbankdrücken', MuscleGroup.chest, [MuscleGroup.shoulders, MuscleGroup.triceps], [Equipment.dumbbell], 6, 10, compound: true, ['Bank auf etwa 30° stellen, Hanteln neben der oberen Brust.', 'Über der Brust zusammendrücken, Ellbogen leicht angewinkelt lassen.', 'Langsam und kontrolliert senken.']),
    _item('brustpresse', 'Brustpresse', MuscleGroup.chest, [MuscleGroup.triceps, MuscleGroup.shoulders], [Equipment.machine], 8, 12, compound: true, step: 5, ['Sitz so einstellen, dass die Griffe auf Höhe der mittleren Brust sind.', 'Nach vorn drücken, ohne die Ellbogen ganz durchzustrecken.', 'Langsam zurückführen, Rücken bleibt an der Lehne.']),
    _item('fliegende', 'Fliegende (Brust)', MuscleGroup.chest, [MuscleGroup.shoulders], [Equipment.dumbbell, Equipment.cable, Equipment.machine], 10, 15, compound: false, step: 1.25, ['Arme leicht gebeugt, Ellbogen bleiben während der Bewegung im gleichen Winkel.', 'In einem weiten Bogen öffnen, bis die Brust gedehnt ist.', 'Im selben Bogen zusammenführen und die Brust anspannen.']),
    _item('liegestuetze', 'Liegestütze', MuscleGroup.chest, [MuscleGroup.triceps, MuscleGroup.shoulders, MuscleGroup.core], [Equipment.bodyweight], 8, 20, tracking: ExerciseTracking.reps, compound: true, ['Hände etwas breiter als schulterbreit, Körper bildet eine gerade Linie.', 'Brust bis knapp über den Boden senken, Ellbogen etwa 45° vom Körper.', 'Kräftig hochdrücken. Leichter: Hände erhöht auf einer Bank.']),
    // Rücken
    _item('klimmzug', 'Klimmzug', MuscleGroup.back, [MuscleGroup.biceps], [Equipment.pullupBar], 5, 10, tracking: ExerciseTracking.reps, compound: true, ['Stange etwas breiter als schulterbreit greifen, aus dem Hang starten.', 'Schulterblätter nach unten ziehen und das Kinn über die Stange ziehen.', 'Kontrolliert ganz absenken. Leichter: mit Widerstandsband.']),
    _item('latziehen', 'Latziehen', MuscleGroup.back, [MuscleGroup.biceps], [Equipment.cable, Equipment.machine], 6, 10, compound: true, ['Oberschenkel unter dem Polster fixieren, Stange breit greifen.', 'Stange zur oberen Brust ziehen, Ellbogen nach unten und hinten.', 'Langsam nach oben führen, bis die Arme gestreckt sind.']),
    _item('latziehen_einarmig', 'Latziehen einarmig', MuscleGroup.back, [MuscleGroup.biceps], [Equipment.cable], 8, 12, compound: false, ['Griff mit einer Hand fassen, leicht zur Seite lehnen.', 'Ellbogen Richtung Hüfte ziehen.', 'Langsam strecken und die Dehnung im Rücken spüren.']),
    _item('rudern_langhantel', 'Langhantelrudern', MuscleGroup.back, [MuscleGroup.biceps, MuscleGroup.legs], [Equipment.barbell], 6, 10, compound: true, ['Hüfte beugen, Oberkörper etwa 45° nach vorn, Rücken gerade.', 'Stange zum Bauchnabel ziehen, Schulterblätter zusammen.', 'Kontrolliert senken, Rücken bleibt neutral.']),
    _item('rudern_kurzhantel', 'Kurzhantelrudern', MuscleGroup.back, [MuscleGroup.biceps], [Equipment.dumbbell], 8, 12, compound: true, ['Eine Hand und ein Knie auf der Bank, Rücken gerade.', 'Hantel zur Hüfte ziehen, Ellbogen nah am Körper.', 'Langsam strecken, ohne den Oberkörper zu drehen.']),
    _item('rudern_kabel', 'Rudern am Kabel', MuscleGroup.back, [MuscleGroup.biceps], [Equipment.cable, Equipment.machine], 6, 10, compound: true, ['Aufrecht sitzen, Knie leicht gebeugt.', 'Griff zum Bauch ziehen, Schulterblätter zusammen, Brust raus.', 'Arme kontrolliert strecken, ohne nach vorn zu kippen.']),
    _item('rudern_koerpergewicht', 'Rudern mit Körpergewicht', MuscleGroup.back, [MuscleGroup.biceps], [Equipment.bodyweight, Equipment.barbell, Equipment.band], 8, 15, tracking: ExerciseTracking.reps, compound: true, ['Unter eine Stange (z. B. im Rack) legen und sie greifen, Körper gestreckt.', 'Brust zur Stange ziehen, Schulterblätter zusammen.', 'Langsam senken. Leichter: Füße näher, Körper aufrechter.']),
    _item('kabel_pullover', 'Kabel-Pullover', MuscleGroup.back, [], [Equipment.cable], 10, 15, compound: false, ['Vor dem Kabelzug stehen, Stange oder Seil mit gestreckten Armen fassen.', 'Mit fast gestreckten Armen im Bogen bis zu den Oberschenkeln ziehen.', 'Langsam zurück, bis die Arme über Kopfhöhe sind.']),
    _item('rueckenstrecker', 'Rückenstrecker (Hyperextension)', MuscleGroup.back, [MuscleGroup.legs], [Equipment.bench, Equipment.machine, Equipment.bodyweight], 10, 15, tracking: ExerciseTracking.reps, compound: false, ['Hüfte am Polster, Füße fixiert, Rücken gerade.', 'Oberkörper aus der Hüfte senken.', 'Bis zur geraden Linie aufrichten, nicht ins Hohlkreuz gehen.']),
    // Schultern
    _item('schulterdruecken', 'Schulterdrücken', MuscleGroup.shoulders, [MuscleGroup.triceps], [Equipment.barbell], 6, 10, compound: true, ['Stehen, Stange auf Höhe der Schlüsselbeine, Bauch und Gesäß fest.', 'Stange senkrecht über den Kopf drücken, Kopf leicht zurück.', 'Kontrolliert zurück zur Startposition.']),
    _item('kurzhantel_schulterdruecken', 'Kurzhantel-Schulterdrücken', MuscleGroup.shoulders, [MuscleGroup.triceps], [Equipment.dumbbell], 6, 10, compound: true, ['Sitzend oder stehend, Hanteln auf Schulterhöhe.', 'Über den Kopf drücken, ohne die Hanteln anzuschlagen.', 'Langsam bis auf Schulterhöhe senken.']),
    _item('seitheben', 'Seitheben', MuscleGroup.shoulders, [], [Equipment.dumbbell, Equipment.cable, Equipment.band], 10, 15, compound: false, step: 1, ['Leicht nach vorn geneigt stehen, Arme minimal gebeugt.', 'Arme seitlich bis auf Schulterhöhe heben, Ellbogen führen.', 'Langsam senken, ohne Schwung.']),
    _item('frontheben', 'Frontheben', MuscleGroup.shoulders, [], [Equipment.dumbbell, Equipment.cable, Equipment.barbell], 8, 12, compound: false, step: 1, ['Aufrecht stehen, Gewicht vor den Oberschenkeln.', 'Mit fast gestreckten Armen bis auf Schulterhöhe heben.', 'Kontrolliert senken.']),
    _item('reverse_fly', 'Reverse Fly', MuscleGroup.shoulders, [MuscleGroup.back], [Equipment.dumbbell, Equipment.cable, Equipment.machine], 10, 15, compound: false, step: 1, ['Oberkörper nach vorn geneigt, Rücken gerade.', 'Arme seitlich nach hinten öffnen, Schulterblätter zusammen.', 'Langsam zurückführen.']),
    _item('face_pull', 'Face Pull', MuscleGroup.shoulders, [MuscleGroup.back], [Equipment.cable, Equipment.band], 10, 15, compound: false, ['Seil auf Augenhöhe, mit beiden Händen greifen.', 'Zum Gesicht ziehen, Hände auseinander, Ellbogen hoch.', 'Kurz halten, dann kontrolliert strecken.']),
    _item('aufrechtes_rudern', 'Aufrechtes Rudern', MuscleGroup.shoulders, [], [Equipment.barbell, Equipment.dumbbell, Equipment.cable], 8, 12, compound: false, ['Gewicht vor dem Körper, Griff etwa schulterbreit.', 'Ellbogen seitlich bis knapp unter Schulterhöhe ziehen.', 'Langsam senken; bei Schulterbeschwerden lieber Seitheben.']),
    _item('shrugs', 'Shrugs', MuscleGroup.shoulders, [MuscleGroup.back], [Equipment.barbell, Equipment.dumbbell], 8, 12, compound: false, ['Aufrecht stehen, Gewicht an gestreckten Armen.', 'Schultern senkrecht zu den Ohren ziehen.', 'Kurz halten und langsam senken.']),
    // Bizeps, Trizeps, Unterarme
    _item('bizeps_curl', 'Bizeps-Curl', MuscleGroup.biceps, [MuscleGroup.forearms], [Equipment.barbell, Equipment.cable], 8, 12, compound: false, ['Aufrecht stehen, Ellbogen am Körper.', 'Gewicht ohne Schwung zur Schulter beugen.', 'Langsam strecken, bis die Arme fast gerade sind.']),
    _item('kurzhantel_curl', 'Kurzhantel-Curl', MuscleGroup.biceps, [MuscleGroup.forearms], [Equipment.dumbbell], 8, 12, compound: false, step: 1, ['Hanteln seitlich, Handflächen nach vorn.', 'Abwechselnd oder gleichzeitig beugen, Ellbogen bleiben am Körper.', 'Kontrolliert senken.']),
    _item('hammer_curl', 'Hammer Curl', MuscleGroup.biceps, [MuscleGroup.forearms], [Equipment.dumbbell, Equipment.cable], 8, 12, compound: false, ['Handflächen zeigen zueinander.', 'Hanteln zur Schulter beugen, Ellbogen fest am Körper.', 'Langsam senken.']),
    _item('trizeps_pushdown', 'Trizeps-Pushdown', MuscleGroup.triceps, [], [Equipment.cable, Equipment.band], 8, 12, compound: false, ['Am Kabelzug stehen, Ellbogen fest an den Seiten.', 'Griff nach unten drücken, bis die Arme gestreckt sind.', 'Langsam bis etwa 90° zurück, Ellbogen bleiben ruhig.']),
    _item('trizepsstrecken', 'Trizepsstrecken', MuscleGroup.triceps, [], [Equipment.dumbbell, Equipment.cable, Equipment.barbell], 8, 12, compound: false, ['Gewicht über dem Kopf oder liegend über der Stirn halten.', 'Nur im Ellbogen beugen und das Gewicht hinter den Kopf senken.', 'Strecken, Oberarme bleiben ruhig.']),
    _item('dips', 'Dips', MuscleGroup.triceps, [MuscleGroup.chest, MuscleGroup.shoulders], [Equipment.bodyweight], 6, 12, tracking: ExerciseTracking.reps, compound: true, ['An parallelen Holmen oder einer Bank abstützen.', 'Senken, bis die Oberarme etwa parallel zum Boden sind.', 'Kräftig hochdrücken. Bei Schulterbeschwerden auslassen.']),
    _item('handgelenk_curl', 'Handgelenk-Curl', MuscleGroup.forearms, [], [Equipment.dumbbell, Equipment.barbell], 10, 15, compound: false, step: 1, ['Unterarme auf den Oberschenkeln, Handgelenke über dem Knie.', 'Gewicht nur im Handgelenk anheben.', 'Langsam senken.']),
    // Beine
    _item('kniebeuge', 'Kniebeuge', MuscleGroup.legs, [MuscleGroup.core], [Equipment.barbell], 6, 10, compound: true, ['Stange auf dem oberen Rücken, Füße etwa schulterbreit, Zehen leicht nach außen.', 'Hüfte nach hinten und unten, Knie folgen den Zehen, Rücken bleibt gerade.', 'So tief wie sauber möglich, dann kraftvoll aufstehen.']),
    _item('goblet_squat', 'Goblet Squat', MuscleGroup.legs, [MuscleGroup.core], [Equipment.dumbbell, Equipment.kettlebell], 8, 12, compound: true, ['Hantel vor der Brust halten, Füße schulterbreit.', 'Tief in die Hocke gehen, Ellbogen zwischen den Knien.', 'Aufrecht aufstehen. Gut zum Lernen der Kniebeuge.']),
    _item('beinpresse', 'Beinpresse', MuscleGroup.legs, [], [Equipment.machine], 6, 12, compound: true, step: 5, ['Füße schulterbreit mittig auf der Platte.', 'Schlitten senken, bis die Knie etwa 90° gebeugt sind, Gesäß bleibt am Polster.', 'Drücken, ohne die Knie ganz durchzustrecken.']),
    _item('ausfallschritt', 'Ausfallschritte', MuscleGroup.legs, [MuscleGroup.core], [Equipment.dumbbell, Equipment.bodyweight, Equipment.barbell], 8, 12, compound: true, ['Großer Schritt nach vorn, Oberkörper aufrecht.', 'Hinteres Knie Richtung Boden senken, vorderes Knie über dem Fuß.', 'Über die Ferse zurückdrücken; Seiten wechseln.']),
    _item('bulgarische_kniebeuge', 'Bulgarische Kniebeuge', MuscleGroup.legs, [MuscleGroup.core], [Equipment.dumbbell, Equipment.bodyweight, Equipment.bench], 8, 12, compound: true, ['Hinterer Fuß auf der Bank, vorderer Fuß weit genug vorn.', 'Senkrecht nach unten gehen, bis der vordere Oberschenkel etwa waagerecht ist.', 'Über die vordere Ferse hochdrücken.']),
    _item('rumaenisches_kreuzheben', 'Rumänisches Kreuzheben', MuscleGroup.legs, [MuscleGroup.back], [Equipment.barbell, Equipment.dumbbell], 6, 10, compound: true, ['Gewicht vor den Oberschenkeln, Knie leicht gebeugt.', 'Hüfte weit nach hinten schieben, Gewicht nah an den Beinen, Rücken gerade.', 'Bei Dehnung der Oberschenkelrückseite die Hüfte nach vorn bringen.']),
    _item('kreuzheben', 'Kreuzheben', MuscleGroup.legs, [MuscleGroup.back, MuscleGroup.forearms], [Equipment.barbell], 5, 8, compound: true, step: 5, ['Füße hüftbreit, Stange über der Fußmitte, schulterbreit greifen.', 'Rücken gerade, Brust raus, Stange vom Boden drücken und nah am Körper führen.', 'Oben aufrecht stehen, kontrolliert ablegen.']),
    _item('hueftstoss', 'Hüftstoß', MuscleGroup.legs, [], [Equipment.barbell, Equipment.dumbbell, Equipment.machine, Equipment.bodyweight], 8, 12, compound: true, step: 5, ['Oberer Rücken an der Bank, Gewicht auf der Hüfte, Füße hüftbreit.', 'Hüfte hochdrücken, bis Oberkörper und Oberschenkel eine Linie bilden.', 'Gesäß oben anspannen, langsam senken.']),
    _item('beinstrecken', 'Beinstrecken', MuscleGroup.legs, [], [Equipment.machine], 10, 15, compound: false, step: 2.5, percent: 5, ['Knie auf Höhe der Drehachse, Polster über den Knöcheln.', 'Beine strecken und kurz halten.', 'Langsam senken.']),
    _item('beinbeugen', 'Beinbeugen', MuscleGroup.legs, [], [Equipment.machine], 8, 12, compound: false, step: 2.5, percent: 5, ['Polster knapp über den Fersen.', 'Beine gegen den Widerstand beugen.', 'Kontrolliert strecken.']),
    _item('wadenheben', 'Wadenheben', MuscleGroup.legs, [], [Equipment.machine, Equipment.dumbbell, Equipment.bodyweight], 10, 15, compound: false, ['Fußballen auf einer Kante, Fersen frei.', 'So hoch wie möglich auf die Zehen.', 'Langsam senken, bis die Waden gedehnt sind.']),
    _item('kettlebell_swing', 'Kettlebell Swing', MuscleGroup.legs, [MuscleGroup.back, MuscleGroup.core], [Equipment.kettlebell], 10, 20, compound: true, step: 4, ['Kettlebell zwischen den Beinen nach hinten schwingen, Rücken gerade.', 'Hüfte explosiv nach vorn strecken, die Arme führen nur.', 'Kettlebell bis Brusthöhe schwingen lassen.']),
    // Rumpf
    _item('plank', 'Plank (Unterarmstütz)', MuscleGroup.core, [], [Equipment.bodyweight], 20, 60, tracking: ExerciseTracking.time, compound: false, ['Auf Unterarmen und Zehen, Körper bildet eine gerade Linie.', 'Bauch und Gesäß anspannen, Hüfte weder durchhängen noch hochstrecken.', 'Ruhig weiteratmen.']),
    _item('seitstuetz', 'Seitstütz', MuscleGroup.core, [], [Equipment.bodyweight], 20, 45, tracking: ExerciseTracking.time, compound: false, ['Auf einem Unterarm, Füße übereinander.', 'Hüfte heben, bis der Körper gerade ist.', 'Halten, dann Seite wechseln.']),
    _item('dead_bug', 'Dead Bug', MuscleGroup.core, [], [Equipment.bodyweight], 8, 15, tracking: ExerciseTracking.reps, compound: false, ['Rückenlage, Arme nach oben, Beine im 90°-Winkel.', 'Gegengleich einen Arm und ein Bein strecken, unterer Rücken bleibt am Boden.', 'Zurück und Seite wechseln.']),
    _item('crunch', 'Crunch', MuscleGroup.core, [], [Equipment.bodyweight], 10, 15, tracking: ExerciseTracking.reps, compound: false, ['Rückenlage, Knie gebeugt.', 'Oberkörper einrollen, bis die Schulterblätter abheben.', 'Langsam ablegen.']),
    _item('crunch_geraet', 'Crunch am Gerät', MuscleGroup.core, [], [Equipment.machine, Equipment.cable], 10, 15, compound: false, ['Am Gerät oder kniend am Kabel mit Seil.', 'Oberkörper einrollen, Bewegung aus dem Bauch.', 'Kontrolliert zurück.']),
    _item('beinheben', 'Beinheben', MuscleGroup.core, [], [Equipment.pullupBar, Equipment.bodyweight], 10, 15, tracking: ExerciseTracking.reps, compound: false, ['Hängend oder liegend, Beine gestreckt oder angewinkelt.', 'Beine heben, ohne zu schwingen.', 'Langsam senken.']),
    _item('pallof', 'Pallof Press', MuscleGroup.core, [], [Equipment.cable, Equipment.band], 10, 15, compound: false, ['Seitlich zum Kabel stehen, Griff vor der Brust.', 'Arme nach vorn strecken und der Drehung widerstehen.', 'Kurz halten, zurück; Seite wechseln.']),
    _item('rotation', 'Rumpfrotation', MuscleGroup.core, [], [Equipment.cable, Equipment.band, Equipment.dumbbell], 10, 15, compound: false, ['Seitlich zum Kabel, Arme gestreckt.', 'Oberkörper kontrolliert drehen, Hüfte bleibt stabil.', 'Langsam zurück; Seite wechseln.']),
    // Varianten aus GymBook (Kabel- und Geräteübungen), damit Verlauf und Progression je Variante getrennt bleiben.
    _item('fliegende_kabel_hoch', 'Flyings am hohen Kabel', MuscleGroup.chest, [MuscleGroup.shoulders], [Equipment.cable], 10, 15, compound: false, step: 1.25, ['Zwischen den Kabeltürmen stehen, Griffe von oben, Arme leicht gebeugt.', 'In einem Bogen vor dem Körper nach unten zusammenführen.', 'Kontrolliert öffnen, bis die Brust gedehnt ist.']),
    _item('reverse_fly_kabel', 'Reverse Flyings am hohen Kabel', MuscleGroup.shoulders, [MuscleGroup.back], [Equipment.cable], 10, 15, compound: false, step: 1.25, ['Kabel über Kreuz auf Schulterhöhe greifen.', 'Arme seitlich nach hinten öffnen, Schulterblätter zusammen.', 'Langsam zurückführen.']),
    _item('seitheben_kabel', 'Einarmiges Seitheben am tiefen Kabel', MuscleGroup.shoulders, [], [Equipment.cable], 10, 15, compound: false, step: 1.25, ['Seitlich zum Kabelzug stehen, Griff mit der äußeren Hand von unten.', 'Arm seitlich bis Schulterhöhe heben.', 'Langsam senken, ohne Schwung.']),
    _item('hammer_curl_kabel', 'Curls in Hammerhaltung am Kabel', MuscleGroup.biceps, [MuscleGroup.forearms], [Equipment.cable], 8, 12, compound: false, ['Seil am tiefen Kabel, Handflächen zueinander.', 'Zur Schulter beugen, Ellbogen bleiben am Körper.', 'Langsam strecken.']),
    _item('kabel_curl_liegend', 'Curls am Kabel liegend', MuscleGroup.biceps, [], [Equipment.cable, Equipment.bench], 8, 12, compound: false, ['Rücklings vor dem Kabelzug liegen, Stange am tiefen Kabel.', 'Unterarme zur Schulter beugen, Oberarme bleiben am Boden.', 'Kontrolliert strecken.']),
    _item('trizeps_kabel_schraegbank', 'Armstrecken am tiefen Kabel auf Schrägbank', MuscleGroup.triceps, [], [Equipment.cable, Equipment.bench], 10, 15, compound: false, ['Auf der Schrägbank mit dem Rücken zum tiefen Kabel, Seil über dem Kopf.', 'Unterarme nach oben strecken, Ellbogen zeigen nach vorn.', 'Langsam beugen, bis der Trizeps gedehnt ist.']),
    _item('crunch_kabel', 'Crunches am Kabel kniend', MuscleGroup.core, [], [Equipment.cable], 10, 15, compound: false, ['Vor dem hohen Kabel knien, Seil neben dem Kopf halten.', 'Oberkörper einrollen, Ellbogen Richtung Knie.', 'Langsam aufrichten, Hüfte bleibt ruhig.']),
    _item('dips_barren', 'Dips am Barren', MuscleGroup.triceps, [MuscleGroup.chest, MuscleGroup.shoulders], [Equipment.bodyweight, Equipment.machine], 6, 12, compound: true, ['Wie in GymBook mit Gewichtsangabe (Zusatzgewicht bzw. Unterstützung am Gerät).', 'Senken, bis die Oberarme etwa waagerecht sind.', 'Kräftig hochdrücken, Schultern bleiben unten.']),
    // Für Übungen aus dem Garmin-Katalog gelten dessen Sprünge, damit sich die Progression nicht ändert.
  ]);
  // dart format on

  static final Map<String, ExerciseInfo> byID = () {
    final result = <String, ExerciseInfo>{};
    for (final item in all) {
      result.putIfAbsent(item.id, () => item);
    }
    return result;
  }();

  /// Übung zur ID: Bibliothek, dann eigene Übungen, dann Garmin-Katalog.
  static ExerciseInfo? info(String id, {List<ExerciseInfo> custom = const []}) {
    if (byID[id] case final known?) return known;
    for (final own in custom) {
      if (own.id == id) return own;
    }
    final rule = ExerciseCatalog.rulesByID[id];
    if (rule == null) return null;
    return ExerciseInfo(
      id: rule.id,
      name: rule.name,
      group: rule.group,
      equipment: const [],
      compound: rule.compound,
      lowerReps: rule.reps.lower,
      upperReps: rule.reps.upper,
      step: rule.step,
      percent: rule.percent,
    );
  }

  /// Regel für die Progression: Garmin-Katalog bevorzugt (gleiche Werte wie bisher), sonst Bibliothek.
  static ExerciseRule rule(String id, {required String name, List<ExerciseInfo> custom = const []}) {
    if (ExerciseCatalog.rulesByID[id] case final rule?) return rule;
    if (info(id, custom: custom) case final info?) return info.rule;
    return ExerciseRule.fallback(name: name);
  }

  /// Suche über Name und Muskel, nach Muskelgruppe sortiert.
  static List<ExerciseInfo> search(String text, {List<ExerciseInfo> custom = const [], Set<Equipment>? available}) {
    final query = text.trim().toLowerCase();
    return [...all, ...custom]
        .where(
          (item) =>
              (available == null || item.isAvailable(available)) &&
              (query.isEmpty ||
                  item.name.toLowerCase().contains(query) ||
                  item.group.rawValue.toLowerCase().contains(query)),
        )
        .toList();
  }

  static ExerciseInfo _item(
    String id,
    String name,
    MuscleGroup group,
    List<MuscleGroup> secondary,
    List<Equipment> equipment,
    int lower,
    int upper,
    List<String> instructions, {
    ExerciseTracking tracking = ExerciseTracking.weightReps,
    required bool compound,
    double? step,
    double? percent,
  }) {
    // Für Übungen aus dem Garmin-Katalog gelten dessen Sprünge, damit sich die Progression nicht ändert.
    final catalog = ExerciseCatalog.rulesByID[id];
    return ExerciseInfo(
      id: id,
      name: name,
      group: group,
      secondary: secondary,
      equipment: equipment,
      tracking: tracking,
      compound: compound,
      lowerReps: lower,
      upperReps: upper,
      step: step ?? catalog?.step ?? 2.5,
      percent: percent ?? catalog?.percent ?? 2.5,
      instructions: instructions,
    );
  }
}
