import '../util/enum_codec.dart';
import '../util/int_range.dart';

/// Muskelgruppen für das Wochenvolumen (Sätze je Muskel).
enum MuscleGroup implements RawEnum {
  chest('Brust'),
  back('Rücken'),
  shoulders('Schultern'),
  biceps('Bizeps'),
  triceps('Trizeps'),
  legs('Beine'),
  core('Rumpf'),
  forearms('Unterarme'),
  other('Sonstige');

  const MuscleGroup(this.rawValue);

  @override
  final String rawValue;

  static MuscleGroup? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Kanonische Übung mit Wiederholungsbereich und Gewichtssprung (`exercise_names.RULES` im Altbestand).
final class ExerciseRule {
  const ExerciseRule({
    required this.id,
    required this.name,
    required this.group,
    required this.pattern,
    required this.reps,
    required this.compound,
    required this.step,
    required this.percent,
    this.weighted,
    this.assumed = false,
    this.bodyweightReps,
  });

  /// Rückfall für unbekannte Übungen.
  factory ExerciseRule.fallback({required String name}) => ExerciseRule(
    id: ExerciseCatalog.slug(name),
    name: name,
    group: MuscleGroup.other,
    pattern: '',
    reps: const IntRange(8, 12),
    compound: false,
    step: 2.5,
    percent: 2.5,
  );

  final String id;
  final String name;
  final MuscleGroup group;

  /// Regulärer Ausdruck auf den Garmin-Schlüssel („KATEGORIE_ÜBUNG“, z. B. `BENCH_PRESS_BARBELL_BENCH_PRESS`).
  final String pattern;
  final IntRange reps;
  final bool compound;

  /// Kleinster Gewichtssprung am Gerät in kg.
  final double step;

  /// Angestrebte Steigerung in Prozent.
  final double percent;

  /// `true`/`false`: Regel gilt nur mit bzw. ohne Gewicht; `null`: immer.
  final bool? weighted;

  /// Zuordnung ist eine Annahme (z. B. „Row“ ohne genauere Angabe).
  final bool assumed;
  final bool? bodyweightReps;

  ExerciseRule copyWith({String? id, String? name, MuscleGroup? group}) => ExerciseRule(
    id: id ?? this.id,
    name: name ?? this.name,
    group: group ?? this.group,
    pattern: pattern,
    reps: reps,
    compound: compound,
    step: step,
    percent: percent,
    weighted: weighted,
    assumed: assumed,
    bodyweightReps: bodyweightReps,
  );

  @override
  bool operator ==(Object other) =>
      other is ExerciseRule &&
      other.id == id &&
      other.name == name &&
      other.group == group &&
      other.pattern == pattern &&
      other.reps == reps &&
      other.compound == compound &&
      other.step == step &&
      other.percent == percent &&
      other.weighted == weighted &&
      other.assumed == assumed &&
      other.bodyweightReps == bodyweightReps;

  @override
  int get hashCode => Object.hash(id, name, group, pattern, reps, compound, step, percent, weighted, assumed);

  @override
  String toString() => 'ExerciseRule($id)';
}

/// Zuordnung von Garmin-Übungsnamen zu kanonischen Übungen.
///
/// Reihenfolge und Muster unverändert aus dem Altbestand (`exercise_names.py`): Beine zuerst (Garmin-Kategorien sind
/// dort oft falsch), Spezialfälle vor allgemeinen Regeln.
abstract final class ExerciseCatalog {
  // dart format off
  static final List<ExerciseRule> rules = [
    _rule('beinpresse', 'Beinpresse', MuscleGroup.legs, r'LEG_PRESS', IntRange(6, 12), compound: true, step: 5, percent: 5),
    _rule('beinstrecken', 'Beinstrecken', MuscleGroup.legs, r'LEG_EXTENSION', IntRange(10, 15), compound: false, step: 2.5, percent: 5),
    _rule('beinbeugen', 'Beinbeugen', MuscleGroup.legs, r'LEG_CURL', IntRange(8, 12), compound: false, step: 2.5, percent: 5),
    _rule('rumaenisches_kreuzheben', 'Rumänisches Kreuzheben', MuscleGroup.legs, r'ROMANIAN|STIFF_LEG', IntRange(6, 10), compound: true, step: 2.5, percent: 5),
    _rule('kreuzheben', 'Kreuzheben', MuscleGroup.legs, r'DEADLIFT', IntRange(5, 8), compound: true, step: 5, percent: 5),
    _rule('ausfallschritt', 'Ausfallschritte', MuscleGroup.legs, r'LUNGE|SPLIT_SQUAT|STEP_UP', IntRange(8, 12), compound: true, step: 2.5, percent: 5),
    _rule('kniebeuge', 'Kniebeuge', MuscleGroup.legs, r'SQUAT', IntRange(6, 10), compound: true, step: 2.5, percent: 5),
    _rule('wadenheben', 'Wadenheben', MuscleGroup.legs, r'CALF', IntRange(10, 15), compound: false, step: 2.5, percent: 5),
    _rule('hueftstoss', 'Hüftstoß', MuscleGroup.legs, r'HIP_THRUST|GLUTE_BRIDGE|HIP_RAISE', IntRange(8, 12), compound: true, step: 5, percent: 5),
    _rule('plank', 'Plank', MuscleGroup.core, r'PLANK', IntRange(1, 1), compound: false, step: 2.5, percent: 0, bodyweightReps: false),
    _rule('pallof', 'Pallof Press', MuscleGroup.core, r'PALLOF', IntRange(10, 15), compound: false, step: 2.5, percent: 2.5),
    _rule('rotation', 'Rumpfrotation', MuscleGroup.core, r'RUSSIAN_TWIST|WOOD_?CHOP|ROTATION', IntRange(10, 15), compound: false, step: 2.5, percent: 2.5),
    _rule('beinheben', 'Beinheben', MuscleGroup.core, r'LEG_RAISE|KNEE_RAISE|HANGING', IntRange(10, 15), compound: false, step: 2.5, percent: 2.5),
    // Vor dem allgemeinen Crunch: Am Kabel ist das Gewicht normales Gerätegewicht, kein Zusatz zum Körpergewicht.
    _rule('crunch_kabel', 'Crunches am Kabel kniend', MuscleGroup.core, r'CABLE_CRUNCH', IntRange(10, 15), compound: false, step: 2.5, percent: 2.5),
    _rule('crunch_geraet', 'Crunch am Gerät', MuscleGroup.core, r'(^|_)WEIGHTED_CRUNCH$', IntRange(10, 15), compound: false, step: 2.5, percent: 2.5),
    _rule('crunch', 'Crunch', MuscleGroup.core, r'CRUNCH|SIT_UP', IntRange(10, 15), compound: false, step: 2.5, percent: 2.5),
    _rule('reverse_fly', 'Reverse Fly', MuscleGroup.shoulders, r'REVERSE_FL|REAR_DELT', IntRange(10, 15), compound: false, step: 1, percent: 2.5),
    _rule('face_pull', 'Face Pull', MuscleGroup.shoulders, r'FACE_PULL', IntRange(10, 15), compound: false, step: 2.5, percent: 2.5),
    _rule('frontheben', 'Frontheben', MuscleGroup.shoulders, r'FRONT_RAISE', IntRange(8, 12), compound: false, step: 1, percent: 2.5),
    _rule('seitheben', 'Seitheben', MuscleGroup.shoulders, r'LATERAL_RAISE', IntRange(10, 15), compound: false, step: 1, percent: 2.5),
    _rule('aufrechtes_rudern', 'Aufrechtes Rudern', MuscleGroup.shoulders, r'UPRIGHT_ROW', IntRange(8, 12), compound: false, step: 2.5, percent: 2.5),
    _rule('kurzhantel_schulterdruecken', 'Kurzhantel-Schulterdrücken', MuscleGroup.shoulders, r'DUMBBELL.*(SHOULDER_PRESS|OVERHEAD_PRESS)|ARNOLD', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('schulterdruecken', 'Schulterdrücken', MuscleGroup.shoulders, r'OVERHEAD_PRESS|SHOULDER_PRESS|MILITARY', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('shrugs', 'Shrugs', MuscleGroup.shoulders, r'SHRUG', IntRange(8, 12), compound: false, step: 2.5, percent: 2.5),
    _rule('dips', 'Dips', MuscleGroup.triceps, r'(^|_)DIPS?($|_)', IntRange(6, 12), compound: true, step: 2.5, percent: 2.5),
    _rule('trizeps_pushdown', 'Trizeps-Pushdown', MuscleGroup.triceps, r'PUSHDOWN|PRESSDOWN|PRESS_DOWN', IntRange(8, 12), compound: false, step: 2.5, percent: 2.5),
    _rule('trizepsstrecken', 'Trizepsstrecken', MuscleGroup.triceps, r'TRICEPS|SKULL|KICKBACK', IntRange(8, 12), compound: false, step: 2.5, percent: 2.5),
    _rule('handgelenk_curl', 'Handgelenk-Curl', MuscleGroup.forearms, r'WRIST_CURL', IntRange(10, 15), compound: false, step: 1, percent: 2.5),
    _rule('hammer_curl', 'Hammer Curl', MuscleGroup.biceps, r'HAMMER_CURL', IntRange(8, 12), compound: false, step: 2.5, percent: 2.5),
    _rule('kurzhantel_curl', 'Kurzhantel-Curl', MuscleGroup.biceps, r'DUMBBELL.*CURL|CURL.*DUMBBELL', IntRange(8, 12), compound: false, step: 1, percent: 2.5),
    _rule('bizeps_curl', 'Bizeps-Curl', MuscleGroup.biceps, r'CURL', IntRange(8, 12), compound: false, step: 2.5, percent: 2.5),
    _rule('kurzhantel_schraegbankdruecken', 'Kurzhantel-Schrägbankdrücken', MuscleGroup.chest, r'INCLINE.*DUMBBELL|DUMBBELL.*INCLINE', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('schraegbankdruecken', 'Schrägbankdrücken', MuscleGroup.chest, r'INCLINE.*(BENCH|PRESS)', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('kurzhantel_bankdruecken', 'Kurzhantel-Bankdrücken', MuscleGroup.chest, r'DUMBBELL_(BENCH|CHEST|PRESS)|DUMBBELL.*BENCH_PRESS', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('brustpresse', 'Brustpresse', MuscleGroup.chest, r'CHEST_PRESS|MACHINE_PRESS', IntRange(8, 12), compound: true, step: 5, percent: 2.5),
    _rule('bankdruecken', 'Bankdrücken', MuscleGroup.chest, r'BENCH_PRESS|BENCH$', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('liegestuetze', 'Liegestütze', MuscleGroup.chest, r'PUSH_UP|PUSHUP', IntRange(8, 20), compound: false, step: 2.5, percent: 2.5, bodyweightReps: true),
    _rule('fliegende', 'Fliegende (Brust)', MuscleGroup.chest, r'(^|_)FLY(E|ES)?($|_)|PEC_DECK|CROSSOVER', IntRange(10, 15), compound: false, step: 1.25, percent: 2.5),
    _rule('kabel_pullover', 'Kabel-Pullover', MuscleGroup.back, r'PULLOVER', IntRange(10, 15), compound: false, step: 2.5, percent: 2.5),
    _rule('latziehen_einarmig', 'Latziehen einarmig', MuscleGroup.back, r'_30_DEGREE_LAT_PULLDOWN|KNEELING(_UNDERHAND_GRIP)?_LAT_PULLDOWN|SINGLE_ARM.*PULLDOWN', IntRange(8, 12), compound: false, step: 2.5, percent: 2.5),
    _rule('latziehen', 'Latziehen', MuscleGroup.back, r'PULLDOWN|PULL_DOWN', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('latziehen', 'Latziehen', MuscleGroup.back, r'^(PULL_UP|CHIN_UP)$', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5, weighted: true, assumed: true),
    _rule('klimmzug', 'Klimmzug', MuscleGroup.back, r'PULL_UP|CHIN_UP', IntRange(5, 10), compound: true, step: 2.5, percent: 2.5, bodyweightReps: true),
    _rule('rudern_kurzhantel', 'Kurzhantelrudern', MuscleGroup.back, r'DUMBBELL_ROW|ONE_ARM_ROW|SINGLE_ARM_ROW', IntRange(8, 12), compound: true, step: 2.5, percent: 2.5),
    _rule('rudern_langhantel', 'Langhantelrudern', MuscleGroup.back, r'BARBELL_ROW|BENT_OVER|T_BAR|PENDLAY', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('rudern_kabel', 'Rudern am Kabel', MuscleGroup.back, r'SEATED_CABLE_ROW|CABLE_ROW|SEATED_ROW|MACHINE_ROW', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5),
    _rule('rudern_kabel', 'Rudern am Kabel', MuscleGroup.back, r'(^|_)ROW($|_)', IntRange(6, 10), compound: true, step: 2.5, percent: 2.5, assumed: true),
  ];
  // dart format on

  static final Map<String, ExerciseRule> rulesByID = () {
    final result = <String, ExerciseRule>{};
    for (final rule in rules) {
      result.putIfAbsent(rule.id, () => rule);
    }
    return result;
  }();

  static final Map<String, RegExp> _patterns = {};

  static ExerciseRule _rule(
    String id,
    String name,
    MuscleGroup group,
    String pattern,
    IntRange reps, {
    required bool compound,
    required double step,
    required double percent,
    bool? weighted,
    bool assumed = false,
    bool? bodyweightReps,
  }) => ExerciseRule(
    id: id,
    name: name,
    group: group,
    pattern: pattern,
    reps: reps,
    compound: compound,
    step: step,
    percent: percent,
    weighted: weighted,
    assumed: assumed,
    bodyweightReps: bodyweightReps,
  );

  /// „Row (SEATED_CABLE_ROW)“ → „ROW_SEATED_CABLE_ROW“.
  static String key(String label) {
    final spaced = label.toUpperCase().split('').map((character) => '()-/,'.contains(character) ? ' ' : character);
    return spaced.join().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).join('_');
  }

  static String slug(String text) {
    final replaced = text
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    final result = StringBuffer();
    var lastWasSeparator = false;
    for (final rune in replaced.runes) {
      final isAsciiAlnum =
          (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7A) || (rune >= 0x41 && rune <= 0x5A);
      if (isAsciiAlnum) {
        result.writeCharCode(rune);
        lastWasSeparator = false;
      } else if (!lastWasSeparator) {
        result.write('_');
        lastWasSeparator = true;
      }
    }
    final trimmed = result.toString().replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'uebung' : trimmed;
  }

  /// Ordnet einen Garmin-Namen einer Regel zu. [hasWeight]: ob die Sätze Gewicht haben (`null` = unbekannt).
  static ExerciseRule classify(String label, {bool? hasWeight}) {
    final key = ExerciseCatalog.key(label);
    for (final rule in rules) {
      if (rule.weighted case final weighted?) {
        if (hasWeight == null || hasWeight != weighted) continue;
      }
      final pattern = _patterns.putIfAbsent(rule.pattern, () => RegExp(rule.pattern));
      if (pattern.hasMatch(key)) return rule;
    }
    final name = label.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).join(' ');
    return ExerciseRule.fallback(name: name);
  }
}
