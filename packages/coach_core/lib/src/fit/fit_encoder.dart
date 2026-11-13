import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../gym/exercise_catalog.dart';
import '../gym/exercise_library.dart';
import '../gym/gym_session.dart';

/// FIT-Grundtypen (Nummer, Größe in Byte).
enum FitBaseType {
  enumeration(0x00, 1),
  uint8(0x02, 1),
  uint16(0x84, 2),
  uint32(0x86, 4),
  uint32z(0x8C, 4);

  const FitBaseType(this.rawValue, this.size);

  final int rawValue;
  final int size;
}

/// Ein Feld einer Datennachricht.
final class FitField {
  const FitField(this.number, this.type, this.value);

  final int number;
  final FitBaseType type;

  /// Wert als vorzeichenlose 32-Bit-Zahl.
  final int value;
}

/// Schreibt FIT-Dateien (Protokoll 2.0, Little Endian) – hier für Krafttrainings, die zurück nach Garmin Connect
/// gehen. Feldnummern und Typen laut FIT-SDK-Profil 21.x (`@garmin/fitsdk`, Datei `profile.js`).
final class FitEncoder {
  /// Sekunden zwischen 1970-01-01 und dem FIT-Bezugszeitpunkt 1989-12-31 00:00:00 UTC.
  static const epochOffset = 631065600;

  static int timestamp(DateTime date) =>
      math.max(0.0, date.millisecondsSinceEpoch / 1000 - epochOffset).round() & 0xFFFFFFFF;

  final List<int> _body = [];

  /// Definitionen je lokaler Nummer (globale Nummer und Feldaufbau), damit gleiche Nachrichten sie wiederverwenden.
  final Map<int, ({int global, String layout})> _definitions = {};

  /// Fügt eine Datennachricht hinzu; die Definition wird bei Bedarf vorher geschrieben.
  void add({required int global, required List<FitField> fields}) {
    final layout = fields.map((field) => '${field.number}:${field.type.rawValue}').join(',');
    int? local;
    for (final MapEntry(:key, :value) in _definitions.entries) {
      if (value.global == global && value.layout == layout) {
        local = key;
        break;
      }
    }
    if (local == null) {
      local = _definitions.length % 16;
      _definitions[local] = (global: global, layout: layout);
      _body
        ..add(0x40 | local)
        ..addAll([0, 0]) // reserviert, Little Endian
        ..addAll([global & 0xFF, (global >> 8) & 0xFF])
        ..add(fields.length);
      for (final field in fields) {
        _body.addAll([field.number, field.type.size, field.type.rawValue]);
      }
    }
    _body.add(local);
    for (final field in fields) {
      for (var index = 0; index < field.type.size; index++) {
        _body.add((field.value >> (8 * index)) & 0xFF);
      }
    }
  }

  /// Fertige Datei mit Kopf und Prüfsummen.
  Uint8List data() {
    final size = _body.length;
    final header = <int>[
      14,
      0x20,
      2132 & 0xFF, 2132 >> 8, // Profilversion 21.32
      size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF, (size >> 24) & 0xFF,
      ...ascii.encode('.FIT'),
    ];
    final headerCRC = crc(header);
    header.addAll([headerCRC & 0xFF, headerCRC >> 8]);
    final fileCRC = crc(_body);
    return Uint8List.fromList([...header, ..._body, fileCRC & 0xFF, fileCRC >> 8]);
  }

  /// CRC-16 des FIT-Protokolls.
  static int crc(List<int> bytes) {
    const table = [
      0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, //
      0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ];
    var crc = 0;
    for (final byte in bytes) {
      var tmp = table[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ table[byte & 0xF];
      tmp = table[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ table[(byte >> 4) & 0xF];
    }
    return crc;
  }
}

/// Krafttraining als FIT-Aktivität für Garmin Connect: je Satz Übung (Kategorie und Unterart aus dem FIT-Profil),
/// Wiederholungen und Gewicht, dazwischen Pausen. Garmin zeigt die Einheit danach wie eine Uhr-Aufzeichnung.
abstract final class StrengthFitExport {
  static Uint8List fit(GymSession session, {DateTime? end}) {
    final start = session.start;
    final candidate = end ?? session.end ?? start.add(const Duration(hours: 1));
    final minimum = start.add(const Duration(minutes: 1));
    final finish = candidate.isAfter(minimum) ? candidate : minimum;
    final sets = [
      for (final exercise in session.exercises)
        for (final set in exercise.doneSets) (exercise, set),
    ];
    final encoder = FitEncoder();
    final startStamp = FitEncoder.timestamp(start);
    final endStamp = FitEncoder.timestamp(finish);
    final total = (endStamp - startStamp).toDouble();
    int u32(double value) => value.toInt() & 0xFFFFFFFF;

    encoder
      ..add(
        global: 0,
        fields: [
          const FitField(0, FitBaseType.enumeration, 4), // Typ: Aktivität
          const FitField(1, FitBaseType.uint16, 255), // Hersteller: development
          const FitField(2, FitBaseType.uint16, 1),
          const FitField(3, FitBaseType.uint32z, 20261027),
          FitField(4, FitBaseType.uint32, startStamp),
        ],
      )
      ..add(
        global: 21,
        fields: [
          FitField(253, FitBaseType.uint32, startStamp),
          const FitField(0, FitBaseType.enumeration, 0),
          const FitField(1, FitBaseType.enumeration, 0),
        ],
      );

    bool isTime(LoggedExercise exercise) =>
        ExerciseLibrary.info(exercise.exerciseID)?.tracking == ExerciseTracking.time;
    // Dauer je Satz: gezeitete Sätze mit ihrer Zeit, sonst 3 s je Wiederholung (mind. 20 s); der Rest sind Pausen.
    final active = [
      for (final (exercise, set) in sets) isTime(exercise) ? set.reps.toDouble() : math.max(set.reps * 3.0, 20.0),
    ];
    final pause = sets.isEmpty
        ? 0.0
        : math.max(0.0, (total - active.fold(0.0, (sum, value) => sum + value)) / sets.length);
    var clock = startStamp.toDouble();
    var index = 0;
    for (var offset = 0; offset < sets.length; offset++) {
      final (exercise, set) = sets[offset];
      final mapping = GarminExerciseMapping.code(exercise.exerciseID, name: exercise.name, group: exercise.group);
      final duration = active[offset];
      encoder.add(
        global: 225,
        fields: [
          FitField(254, FitBaseType.uint32, u32(clock + duration)),
          FitField(0, FitBaseType.uint32, u32(duration * 1000)),
          const FitField(5, FitBaseType.uint8, 1), // aktiver Satz
          FitField(6, FitBaseType.uint32, u32(clock)),
          FitField(7, FitBaseType.uint16, mapping.category),
          FitField(8, FitBaseType.uint16, mapping.subtype ?? 0xFFFF),
          FitField(10, FitBaseType.uint16, index),
          if (!isTime(exercise)) FitField(3, FitBaseType.uint16, math.max(set.reps, 0)),
          if (set.weightKg > 0) FitField(4, FitBaseType.uint16, (set.weightKg * 16).round()),
        ],
      );
      clock += duration;
      index += 1;
      if (offset < sets.length - 1 && pause > 0) {
        encoder.add(
          global: 225,
          fields: [
            FitField(254, FitBaseType.uint32, u32(clock + pause)),
            FitField(0, FitBaseType.uint32, u32(pause * 1000)),
            const FitField(5, FitBaseType.uint8, 0), // Pause
            FitField(6, FitBaseType.uint32, u32(clock)),
            const FitField(7, FitBaseType.uint16, 0xFFFF),
            const FitField(8, FitBaseType.uint16, 0xFFFF),
            FitField(10, FitBaseType.uint16, index),
          ],
        );
        clock += pause;
        index += 1;
      }
    }

    final elapsed = u32(total * 1000);
    final zoneOffset = finish.toLocal().timeZoneOffset.inSeconds;
    encoder
      ..add(
        global: 21,
        fields: [
          FitField(253, FitBaseType.uint32, endStamp),
          const FitField(0, FitBaseType.enumeration, 0),
          const FitField(1, FitBaseType.enumeration, 4),
        ],
      )
      ..add(
        global: 19,
        fields: [
          FitField(253, FitBaseType.uint32, endStamp),
          const FitField(0, FitBaseType.enumeration, 9),
          const FitField(1, FitBaseType.enumeration, 1),
          FitField(2, FitBaseType.uint32, startStamp),
          FitField(7, FitBaseType.uint32, elapsed),
          FitField(8, FitBaseType.uint32, elapsed),
        ],
      )
      ..add(
        global: 18,
        fields: [
          FitField(253, FitBaseType.uint32, endStamp),
          const FitField(0, FitBaseType.enumeration, 8),
          const FitField(1, FitBaseType.enumeration, 1),
          FitField(2, FitBaseType.uint32, startStamp),
          const FitField(5, FitBaseType.enumeration, 10),
          const FitField(6, FitBaseType.enumeration, 20),
          FitField(7, FitBaseType.uint32, elapsed),
          FitField(8, FitBaseType.uint32, elapsed),
          const FitField(25, FitBaseType.uint16, 0),
          const FitField(26, FitBaseType.uint16, 1),
        ],
      )
      ..add(
        global: 34,
        fields: [
          FitField(253, FitBaseType.uint32, endStamp),
          FitField(0, FitBaseType.uint32, elapsed),
          const FitField(1, FitBaseType.uint16, 1),
          const FitField(2, FitBaseType.enumeration, 0),
          const FitField(3, FitBaseType.enumeration, 26),
          const FitField(4, FitBaseType.enumeration, 1),
          FitField(5, FitBaseType.uint32, (endStamp + zoneOffset) & 0xFFFFFFFF),
        ],
      );
    return encoder.data();
  }
}

/// Kategorie und Unterart im Übungskatalog von Garmin.
final class GarminExerciseCode {
  const GarminExerciseCode(this.category, this.subtype);

  final int category;
  final int? subtype;

  @override
  bool operator ==(Object other) =>
      other is GarminExerciseCode && other.category == category && other.subtype == subtype;

  @override
  int get hashCode => Object.hash(category, subtype);

  @override
  String toString() => 'GarminExerciseCode($category, $subtype)';
}

/// Zuordnung der Übungen zu Garmins Übungskatalog (FIT `exercise_category` und `*_exercise_name`).
abstract final class GarminExerciseMapping {
  // Kategorien laut FIT-Profil.
  static const benchPress = 0, calfRaise = 1, core = 5, crunch = 6, curl = 7;
  static const deadlift = 8, flye = 9, hipRaise = 10, hipStability = 11;
  static const hyperextension = 13, lateralRaise = 14, legCurl = 15, legRaise = 16;
  static const lunge = 17, plank = 19, pullUp = 21, pushUp = 22, row = 23;
  static const shoulderPress = 24, shrug = 26, squat = 28, tricepsExtension = 30;
  static const banded = 37;
  static const unknown = 65534;

  // dart format off
  static const Map<String, GarminExerciseCode> table = {
    'bankdruecken': GarminExerciseCode(benchPress, 1),
    'kurzhantel_bankdruecken': GarminExerciseCode(benchPress, 6),
    'schraegbankdruecken': GarminExerciseCode(benchPress, 8),
    'kurzhantel_schraegbankdruecken': GarminExerciseCode(benchPress, 9),
    'brustpresse': GarminExerciseCode(banded, 5),
    'fliegende': GarminExerciseCode(flye, 2),
    'fliegende_kabel_hoch': GarminExerciseCode(flye, 0),
    'liegestuetze': GarminExerciseCode(pushUp, 77),
    'klimmzug': GarminExerciseCode(pullUp, 38),
    'latziehen': GarminExerciseCode(pullUp, 25),
    'latziehen_einarmig': GarminExerciseCode(pullUp, 13),
    'kabel_pullover': GarminExerciseCode(pullUp, 19),
    'rudern_langhantel': GarminExerciseCode(row, 46),
    'rudern_kurzhantel': GarminExerciseCode(row, 2),
    'rudern_kabel': GarminExerciseCode(row, 18),
    'rudern_koerpergewicht': GarminExerciseCode(row, 35),
    'face_pull': GarminExerciseCode(row, 5),
    'rueckenstrecker': GarminExerciseCode(hyperextension, null),
    'schulterdruecken': GarminExerciseCode(shoulderPress, 14),
    'kurzhantel_schulterdruecken': GarminExerciseCode(shoulderPress, 17),
    'seitheben': GarminExerciseCode(lateralRaise, 34),
    'seitheben_kabel': GarminExerciseCode(lateralRaise, 14),
    'frontheben': GarminExerciseCode(lateralRaise, 10),
    'reverse_fly': GarminExerciseCode(flye, 11),
    'reverse_fly_kabel': GarminExerciseCode(flye, 6),
    'aufrechtes_rudern': GarminExerciseCode(shrug, 24),
    'shrugs': GarminExerciseCode(shrug, 1),
    'bizeps_curl': GarminExerciseCode(curl, 3),
    'kurzhantel_curl': GarminExerciseCode(curl, null),
    'hammer_curl': GarminExerciseCode(curl, 16),
    'hammer_curl_kabel': GarminExerciseCode(curl, 9),
    'kabel_curl_liegend': GarminExerciseCode(curl, 8),
    'trizeps_pushdown': GarminExerciseCode(tricepsExtension, 39),
    'trizepsstrecken': GarminExerciseCode(tricepsExtension, 15),
    'trizeps_kabel_schraegbank': GarminExerciseCode(tricepsExtension, 5),
    'dips': GarminExerciseCode(tricepsExtension, 2),
    'dips_barren': GarminExerciseCode(tricepsExtension, 40),
    'kniebeuge': GarminExerciseCode(squat, 6),
    'goblet_squat': GarminExerciseCode(squat, 37),
    'beinpresse': GarminExerciseCode(squat, 0),
    'ausfallschritt': GarminExerciseCode(lunge, 21),
    'bulgarische_kniebeuge': GarminExerciseCode(lunge, null),
    'rumaenisches_kreuzheben': GarminExerciseCode(deadlift, 23),
    'kreuzheben': GarminExerciseCode(deadlift, 0),
    'hueftstoss': GarminExerciseCode(hipRaise, null),
    'kettlebell_swing': GarminExerciseCode(hipRaise, 23),
    'beinstrecken': GarminExerciseCode(banded, 29),
    'beinbeugen': GarminExerciseCode(legCurl, 0),
    'wadenheben': GarminExerciseCode(calfRaise, 18),
    'plank': GarminExerciseCode(plank, 43),
    'seitstuetz': GarminExerciseCode(plank, 66),
    'dead_bug': GarminExerciseCode(hipStability, 1),
    'crunch': GarminExerciseCode(crunch, 83),
    'crunch_geraet': GarminExerciseCode(crunch, 79),
    'crunch_kabel': GarminExerciseCode(crunch, 1),
    'beinheben': GarminExerciseCode(legRaise, 1),
    'pallof': GarminExerciseCode(core, null),
    'rotation': GarminExerciseCode(core, 46),
  };
  // dart format on

  /// Unbekannte oder eigene Übungen (`eigen_…`, auch aus dem GymBook-Import) erst über den Namen
  /// („Schulterdrücken Maschine“ → Schulterdrücken), dann über die Muskelgruppe einer passenden Kategorie zuordnen.
  /// Name und Gruppe stehen an jeder geloggten Übung – auch wenn die eigene Übung inzwischen gelöscht ist.
  static GarminExerciseCode code(String exerciseID, {String name = '', MuscleGroup? group}) {
    if (table[exerciseID] case final code?) return code;
    if (libraryID(name) case final key?) {
      if (table[key] case final code?) return code;
    }
    return switch (ExerciseLibrary.info(exerciseID)?.group ?? group) {
      MuscleGroup.chest => const GarminExerciseCode(benchPress, null),
      MuscleGroup.back => const GarminExerciseCode(row, null),
      MuscleGroup.shoulders => const GarminExerciseCode(shoulderPress, null),
      MuscleGroup.biceps || MuscleGroup.forearms => const GarminExerciseCode(curl, null),
      MuscleGroup.triceps => const GarminExerciseCode(tricepsExtension, null),
      MuscleGroup.legs => const GarminExerciseCode(squat, null),
      MuscleGroup.core => const GarminExerciseCode(core, null),
      _ => const GarminExerciseCode(unknown, null),
    };
  }

  /// Stichwörter im Namen → Übung der Bibliothek. Genauere zuerst (Schrägbank vor Bank, Hammer-Curl vor Curl).
  // dart format off
  static const List<({List<String> words, String id})> keywords = [
    (words: ['dips'], id: 'dips'),
    (words: ['schraegbankdr', 'schraegbank dr', 'incline bench', 'incline press'], id: 'schraegbankdruecken'),
    (words: ['bankdr', 'bench press'], id: 'bankdruecken'),
    (words: ['brustpresse', 'chest press', 'chestpress'], id: 'brustpresse'),
    (words: ['butterfly reverse', 'reverse butterfly', 'reverse fly', 'reverse flys', 'rear delt'], id: 'reverse_fly'),
    (words: ['butterfly', 'fliegende', 'flys', 'flye', 'cable cross', 'kabelzug brust'], id: 'fliegende'),
    (words: ['liegestue', 'push up', 'pushup', 'push-up'], id: 'liegestuetze'),
    (words: ['face pull', 'facepull'], id: 'face_pull'),
    (words: ['latzug', 'latzieh', 'lat pull', 'pulldown'], id: 'latziehen'),
    (words: ['klimmz', 'pull up', 'pullup', 'chin up', 'chinup'], id: 'klimmzug'),
    (words: ['pullover'], id: 'kabel_pullover'),
    (words: ['aufrechtes rudern', 'upright row'], id: 'aufrechtes_rudern'),
    (words: ['rudern', 'row'], id: 'rudern_kabel'),
    (words: ['schulterdr', 'shoulder press', 'overhead press', 'military', 'nackendr'], id: 'schulterdruecken'),
    (words: ['seitheb', 'lateral raise', 'seitlich'], id: 'seitheben'),
    (words: ['frontheb', 'front raise'], id: 'frontheben'),
    (words: ['shrug', 'schulterheb'], id: 'shrugs'),
    (words: ['beinbeug', 'leg curl', 'beincurl'], id: 'beinbeugen'),
    (words: ['beinstreck', 'leg extension'], id: 'beinstrecken'),
    (words: ['hammer'], id: 'hammer_curl'),
    (words: ['handgelenk', 'wrist'], id: 'handgelenk_curl'),
    (words: ['trizeps', 'triceps', 'pushdown', 'french press', 'skull'], id: 'trizeps_pushdown'),
    (words: ['curl', 'bizeps', 'biceps'], id: 'bizeps_curl'),
    (words: ['beinpresse', 'leg press'], id: 'beinpresse'),
    (words: ['bulgar', 'split squat'], id: 'bulgarische_kniebeuge'),
    (words: ['ausfall', 'lunge'], id: 'ausfallschritt'),
    (words: ['goblet'], id: 'goblet_squat'),
    (words: ['kniebeug', 'squat', 'hackenschmidt'], id: 'kniebeuge'),
    (words: ['rumaen', 'romanian', 'rdl', 'gestreckt'], id: 'rumaenisches_kreuzheben'),
    (words: ['kreuzheb', 'deadlift'], id: 'kreuzheben'),
    (words: ['hip thrust', 'hueftstoss', 'hueftheb', 'glute bridge', 'beckenheb'], id: 'hueftstoss'),
    (words: ['kettlebell swing'], id: 'kettlebell_swing'),
    (words: ['waden', 'calf'], id: 'wadenheben'),
    (words: ['rueckenstreck', 'hyperext', 'back extension'], id: 'rueckenstrecker'),
    (words: ['seitstuetz', 'side plank'], id: 'seitstuetz'),
    (words: ['plank', 'unterarmstuetz'], id: 'plank'),
    (words: ['beinheb', 'leg raise', 'knee raise', 'knieheb'], id: 'beinheben'),
    (words: ['crunch', 'bauchpresse', 'sit up', 'situp'], id: 'crunch'),
    (words: ['russian twist', 'rotation', 'woodchop', 'holzhack'], id: 'rotation'),
  ];
  // dart format on

  /// Übung der Bibliothek zu einem frei eingegebenen Namen; `null`, wenn kein Stichwort passt. Stichwörter gelten am
  /// Wortanfang („Kabelrudern“ passt nicht auf „row“ in „Arrow“, aber auch nicht auf „rudern“).
  static String? libraryID(String name) {
    final text = ' ${ExerciseCatalog.slug(name).replaceAll('_', ' ')} ';
    if (text.length <= 2) return null;
    for (final entry in keywords) {
      if (entry.words.any((word) => text.contains(' $word'))) return entry.id;
    }
    return null;
  }
}
