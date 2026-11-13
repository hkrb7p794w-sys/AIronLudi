import '../calendar/calendar_day.dart';
import '../coach/recovery_level.dart';
import '../util/enum_codec.dart';
import 'adherence.dart';

enum CompanionKind implements RawEnum {
  dog,
  cat,
  coach,

  /// Gezeichnete, animierte Daisy (`DaisyGeometry`).
  daisy;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    daisy => 'Daisy (animiert)',
    dog => 'Hund',
    cat => 'Katze',
    coach => 'Trainer:in',
  };

  String get symbol => switch (this) {
    dog || daisy => 'dog.fill',
    cat => 'cat.fill',
    coach => 'figure.strengthtraining.functional',
  };
}

/// Optionaler Begleiter (z. B. der eigene Hund), der den Tag in freundlichen Worten kommentiert. Er sagt nichts,
/// was nicht auch die Regeln sagen: Die Stimmung folgt aus Plan, Erholung und Erledigtem. Kein Druck, keine
/// Schuldgefühle – bei schlechter Erholung lobt er das Ausruhen.
final class CompanionSettings {
  CompanionSettings({this.enabled = false, this.name = '', this.kind = CompanionKind.dog});

  bool enabled;
  String name;
  CompanionKind kind;

  /// Anzeigename; ohne Eingabe ein Standardname.
  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return switch (kind) {
      CompanionKind.dog || CompanionKind.daisy => 'Daisy',
      CompanionKind.cat => 'Mimi',
      CompanionKind.coach => 'Coach',
    };
  }

  bool get isActive => enabled;

  /// Hund-Sätze gelten auch für Daisy.
  CompanionKind get voice => kind == CompanionKind.daisy ? CompanionKind.dog : kind;

  Map<String, Object?> toJson() => {'enabled': enabled, 'name': name, 'kind': kind.rawValue};

  /// Tolerant: unbekannte oder fehlende Felder bekommen ihren Standard.
  static CompanionSettings fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    final (enabled, name) = (map['enabled'], map['name']);
    return CompanionSettings(
      enabled: enabled is bool ? enabled : false,
      name: name is String ? name : '',
      kind: enumFromRaw(CompanionKind.values, map['kind']) ?? CompanionKind.dog,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CompanionSettings && other.enabled == enabled && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(enabled, name, kind);
}

enum CompanionMood implements RawEnum {
  /// Heute trainiert.
  happy,

  /// Woche komplett.
  proud,

  /// Einheit steht heute an.
  excited,

  /// Ruhetag.
  resting,

  /// Erholung niedrig: lieber kuscheln und ausruhen.
  cozy,

  /// Gestern etwas verpasst – heute ist ein neuer Tag.
  hopeful;

  @override
  String get rawValue => name;

  /// Symbol für die Stimmung (neben dem Begleiter).
  String get symbol => switch (this) {
    happy => 'heart.fill',
    proud => 'star.fill',
    excited => 'sparkles',
    resting => 'moon.zzz.fill',
    cozy => 'cup.and.saucer.fill',
    hopeful => 'sun.max.fill',
  };
}

final class CompanionMessage {
  const CompanionMessage({required this.mood, required this.text});

  final CompanionMood mood;
  final String text;
}

final class CompanionContext {
  const CompanionContext({
    required this.plannedToday,
    required this.trainedToday,
    required this.recovery,
    required this.week,
    required this.missedYesterday,
  });

  final List<String> plannedToday;
  final bool trainedToday;
  final RecoveryLevel? recovery;
  final WeekAdherence week;
  final bool missedYesterday;
}

abstract final class CompanionVoice {
  static CompanionMood mood(CompanionContext context) {
    if (context.trainedToday) return context.week.isComplete ? CompanionMood.proud : CompanionMood.happy;
    if (context.recovery == RecoveryLevel.pause) return CompanionMood.cozy;
    if (context.plannedToday.isEmpty) return context.week.isComplete ? CompanionMood.proud : CompanionMood.resting;
    if (context.missedYesterday) return CompanionMood.hopeful;
    return CompanionMood.excited;
  }

  /// Fester Satz je Stimmung und Begleiter. [day] wählt zwischen Varianten, damit es nicht jeden Tag gleich klingt.
  static CompanionMessage message(
    CompanionContext context, {
    required CompanionSettings companion,
    required CalendarDay day,
  }) {
    final mood = CompanionVoice.mood(context);
    final name = companion.displayName;
    final session = context.plannedToday.isEmpty ? 'Training' : context.plannedToday.first;
    final variants = switch ((companion.voice, mood)) {
      (CompanionKind.dog, CompanionMood.happy) => [
        'Wuff! Du warst heute fleißig – $name wedelt ganz doll mit dem Schwanz.',
        "$name ist stolz auf dich! Jetzt gibt's Kuscheln und was Leckeres.",
      ],
      (CompanionKind.dog, CompanionMood.proud) => [
        'Alles geschafft diese Woche! $name dreht vor Freude Kreise.',
        'Wochenziel erreicht – $name bringt dir zur Feier das Lieblingsspielzeug.',
      ],
      (CompanionKind.dog, CompanionMood.excited) => [
        'Heute steht „$session“ an. $name sitzt schon an der Tür und wartet auf dich!',
        '$name stupst dich an: Heute ist „$session“ dran. Du schaffst das!',
      ],
      (CompanionKind.dog, CompanionMood.resting) => [
        'Ruhetag! $name liegt im Körbchen – mach es genauso und erhol dich.',
        'Heute ist frei. $name findet: Spaziergang und Sofa sind auch Training für die Seele.',
      ],
      (CompanionKind.dog, CompanionMood.cozy) => [
        'Du wirkst heute müde. $name kuschelt sich an dich – Ausruhen ist heute das Beste.',
        '$name meint: Heute lieber langsam. Erholung macht dich stärker.',
      ],
      (CompanionKind.dog, CompanionMood.hopeful) => [
        "Gestern hat's nicht geklappt? Egal! $name freut sich einfach auf heute: „$session“.",
        'Neuer Tag, neues Glück – $name wedelt und wartet auf „$session“.',
      ],
      (CompanionKind.cat, CompanionMood.happy) => ['$name schnurrt zufrieden: gut gemacht heute!'],
      (CompanionKind.cat, CompanionMood.proud) => ['Wochenziel erreicht. $name ist (ausnahmsweise) beeindruckt.'],
      (CompanionKind.cat, CompanionMood.excited) => ['$name streckt sich: Heute ist „$session“ dran. Du auch?'],
      (CompanionKind.cat, CompanionMood.resting) => ['Ruhetag. $name zeigt dir, wie Entspannen geht.'],
      (CompanionKind.cat, CompanionMood.cozy) => ['$name rollt sich neben dir ein: Heute ist Erholung angesagt.'],
      (CompanionKind.cat, CompanionMood.hopeful) => [
        'Gestern verpasst? $name ist nicht nachtragend. Heute: „$session“.',
      ],
      (CompanionKind.coach, CompanionMood.happy) => ['Stark! Einheit erledigt. Jetzt essen, trinken, erholen.'],
      (CompanionKind.coach, CompanionMood.proud) => [
        'Wochenziel erreicht. Genau so geht Fortschritt: Woche für Woche.',
      ],
      (CompanionKind.coach, CompanionMood.excited) => ['Heute: „$session“. Ruhig starten, sauber durchziehen.'],
      (CompanionKind.coach, CompanionMood.resting) => ['Ruhetag. Erholung gehört zum Training.'],
      (CompanionKind.coach, CompanionMood.cozy) => [
        'Deine Erholung ist niedrig. Heute lieber locker oder frei – das zahlt sich aus.',
      ],
      (CompanionKind.coach, CompanionMood.hopeful) => ['Gestern ist vorbei. Heute zählt: „$session“.'],
      // Nicht erreicht: `voice` bildet Daisy auf den Hund ab.
      (CompanionKind.daisy, _) => ['$name ist bei dir.'],
    };
    final index = (day.day + day.month * 31).abs() % variants.length;
    return CompanionMessage(mood: mood, text: variants[index]);
  }

  /// Kurzer Zusatz für die Erinnerung, z. B. „Daisy wartet schon“.
  static String? reminderLead(CompanionSettings companion) {
    if (!companion.isActive) return null;
    return switch (companion.kind) {
      CompanionKind.dog || CompanionKind.daisy => '${companion.displayName} wartet schon an der Tür.',
      CompanionKind.cat => '${companion.displayName} schaut erwartungsvoll.',
      CompanionKind.coach => null,
    };
  }
}
