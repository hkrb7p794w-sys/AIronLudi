import 'dart:convert';

import '../calendar/calendar_day.dart';
import '../coach/season_plan.dart';
import '../garmin/garmin_activity.dart';
import '../gym/gym_plan.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';

String? _optionalString(Object? value) => value is String ? value : null;

int? _optionalInt(Object? value) => value is int ? value : null;

/// Ein Schritt einer Schwimmeinheit (`swim_plan.json` im Altbestand), auch verschachtelt (Wiederholungen).
final class SwimStep {
  const SwimStep({required this.t, this.m, this.s, this.n, this.note, this.lo, this.hi, this.eq, this.steps});

  /// `warmup`, `int`, `rest`, `rec`, `rep`, `cool`
  final String t;

  /// Meter
  final int? m;

  /// Sekunden (Pause)
  final int? s;

  /// Wiederholungen bei `rep`
  final int? n;
  final String? note;

  /// Tempo relativ zur CSS in Sekunden je 100 m (untere/obere Grenze).
  final int? lo;
  final int? hi;

  /// Ausrüstung, z. B. `pull_buoy`
  final String? eq;
  final List<SwimStep>? steps;

  static SwimStep? fromJson(Object? json) {
    if (json is! Map || json['t'] is! String) return null;
    final rawSteps = json['steps'];
    final steps = rawSteps == null ? null : listStrict(rawSteps, fromJson);
    if (rawSteps != null && steps == null) return null;
    return SwimStep(
      t: json['t'] as String,
      m: _optionalInt(json['m']),
      s: _optionalInt(json['s']),
      n: _optionalInt(json['n']),
      note: _optionalString(json['note']),
      lo: _optionalInt(json['lo']),
      hi: _optionalInt(json['hi']),
      eq: _optionalString(json['eq']),
      steps: steps,
    );
  }

  Map<String, Object?> toJson() => {
    't': t,
    'm': ?m,
    's': ?s,
    'n': ?n,
    'note': ?note,
    'lo': ?lo,
    'hi': ?hi,
    'eq': ?eq,
    if (steps case final steps?) 'steps': [for (final step in steps) step.toJson()],
  };

  @override
  bool operator ==(Object other) => other is SwimStep && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Eine Woche des Saisonplans (Felder wie in `coach_plan.jinja`).
final class PlanWeek {
  const PlanWeek({
    required this.w,
    required this.ph,
    required this.f,
    required this.z,
    required this.zc,
    required this.z2,
    required this.s,
    required this.sc,
    required this.q,
    required this.qc,
    required this.e,
    required this.l,
    required this.lr,
    this.key,
    this.qw,
    this.qa,
    this.qca,
    this.lw,
    this.la,
    this.ss,
    this.sm,
  });

  final String w;
  final String ph;

  /// Hinweis zur Woche (z. B. „Entlastungswoche“)
  final String f;

  /// Zwift-Einheit (Text mit Platzhaltern) und Kürzel
  final String z;
  final String zc;

  /// Optionale zweite Zwift-Einheit
  final String z2;

  /// Schwimmeinheit und Name
  final String s;
  final String sc;

  /// Qualitätslauf und Name
  final String q;
  final String qc;

  /// Z2-Lauf
  final String e;

  /// Longrun und Länge in km (0 = keiner)
  final String l;
  final double lr;

  /// Besondere Woche, z. B. `marathon`
  final String? key;

  /// Wettkampfspezifischer Qualitätslauf/Longrun (zum Annehmen/Ablehnen) mit Alternative
  final int? qw;
  final String? qa;
  final String? qca;
  final int? lw;
  final String? la;

  /// Schwimmschritte und Gesamtmeter (`swim_plan.json`)
  final List<SwimStep>? ss;
  final int? sm;

  String get id => w;
  CalendarDay? get monday => CalendarDay.tryParse(w);

  static PlanWeek? fromJson(Object? json) {
    if (json is! Map) return null;
    String? text(String key) => _optionalString(json[key]);
    final lr = jsonDouble(json['lr']);
    final (w, ph, f, z, zc, z2) = (text('w'), text('ph'), text('f'), text('z'), text('zc'), text('z2'));
    final (s, sc, q, qc, e, l) = (text('s'), text('sc'), text('q'), text('qc'), text('e'), text('l'));
    if (w == null ||
        ph == null ||
        f == null ||
        z == null ||
        zc == null ||
        z2 == null ||
        s == null ||
        sc == null ||
        q == null ||
        qc == null ||
        e == null ||
        l == null ||
        lr == null) {
      return null;
    }
    final rawSteps = json['ss'];
    final steps = rawSteps == null ? null : listStrict(rawSteps, SwimStep.fromJson);
    if (rawSteps != null && steps == null) return null;
    return PlanWeek(
      w: w,
      ph: ph,
      f: f,
      z: z,
      zc: zc,
      z2: z2,
      s: s,
      sc: sc,
      q: q,
      qc: qc,
      e: e,
      l: l,
      lr: lr,
      key: text('key'),
      qw: _optionalInt(json['qw']),
      qa: text('qa'),
      qca: text('qca'),
      lw: _optionalInt(json['lw']),
      la: text('la'),
      ss: steps,
      sm: _optionalInt(json['sm']),
    );
  }
}

final class PlanPhaseInfo {
  const PlanPhaseInfo({required this.mw, required this.prio});

  /// Musterwoche
  final String mw;

  /// Priorität, wenn die Zeit knapp ist
  final String prio;

  static PlanPhaseInfo? fromJson(Object? json) {
    if (json is! Map || json['mw'] is! String || json['prio'] is! String) return null;
    return PlanPhaseInfo(mw: json['mw'] as String, prio: json['prio'] as String);
  }
}

final class ZwiftWorkout {
  const ZwiftWorkout({required this.c, required this.n, required this.t});

  final String c;
  final String n;
  final String t;

  String get id => c;

  static ZwiftWorkout? fromJson(Object? json) {
    if (json is! Map || json['c'] is! String || json['n'] is! String || json['t'] is! String) return null;
    return ZwiftWorkout(c: json['c'] as String, n: json['n'] as String, t: json['t'] as String);
  }
}

/// Der komplette Saisonplan aus dem Altbestand (48 Wochen, 12.10.2026–11.09.2027). Die Daten liegen in
/// `assets/season-plan.json` und werden von der App über das Asset-Bundle geladen.
final class SeasonSchedule {
  const SeasonSchedule({required this.weeks, required this.zw, required this.phases});

  final List<PlanWeek> weeks;
  final List<ZwiftWorkout> zw;
  final Map<String, PlanPhaseInfo> phases;

  static const assetPath = 'packages/coach_core/assets/season-plan.json';

  /// Wie `SeasonSchedule.load()`: `null`, wenn die Daten fehlen oder nicht lesbar sind.
  static SeasonSchedule? load(String text) {
    try {
      return fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  static SeasonSchedule? fromJson(Object? json) {
    if (json is! Map) return null;
    final weeks = listStrict(json['weeks'], PlanWeek.fromJson);
    final zw = listStrict(json['zw'], ZwiftWorkout.fromJson);
    final rawPhases = json['phases'];
    if (weeks == null || zw == null || rawPhases is! Map) return null;
    final phases = <String, PlanPhaseInfo>{};
    for (final entry in rawPhases.entries) {
      final info = PlanPhaseInfo.fromJson(entry.value);
      if (entry.key is! String || info == null) return null;
      phases[entry.key as String] = info;
    }
    return SeasonSchedule(weeks: weeks, zw: zw, phases: phases);
  }

  /// Woche, die [day] enthält (Plan-Wochen beginnen montags).
  PlanWeek? week(CalendarDay day) {
    final monday = day.adding(-day.weekdayIndex);
    for (final week in weeks) {
      if (week.monday == monday) return week;
    }
    return null;
  }

  int? index(CalendarDay day) {
    final monday = day.adding(-day.weekdayIndex);
    final index = weeks.indexWhere((week) => week.monday == monday);
    return index < 0 ? null : index;
  }

  static String decisionKey(PlanWeek week, PlannedUnitKind kind) =>
      'wk-lauf-${week.w}-${kind == PlannedUnitKind.longRun ? 'l' : 'q'}';

  /// Einheiten einer Woche in fester Reihenfolge, mit eingesetzten Testwerten.
  List<PlannedUnit> units(
    PlanWeek week, {
    required SeasonConfig config,
    GymPlan? gym,
    CompetitionDecisions decisions = const {},
  }) {
    final plan = gym ?? GymPlan.standard;
    final tokens = PlanTokens(config);
    final units = <PlannedUnit>[];

    if (week.z.isNotEmpty) {
      final (title, detail) = split(tokens.fill(week.z), fallbackTitle: week.zc);
      units.add(PlannedUnit(kind: PlannedUnitKind.bike, title: title, detail: detail)..zwiftCode = week.zc);
    }
    if (week.z2.isNotEmpty) {
      units.add(PlannedUnit(kind: PlannedUnitKind.bikeOptional, title: 'Zweite Zwift-Einheit', detail: week.z2));
    }
    if (week.s.isNotEmpty) {
      final (title, detail) = split(tokens.fill(week.s), fallbackTitle: week.sc);
      units.add(
        PlannedUnit(kind: PlannedUnitKind.swim, title: title, detail: detail)
          ..swimSteps = week.ss ?? const []
          ..swimMeters = week.sm,
      );
    }
    if (week.q.isNotEmpty) {
      units.add(
        _competitionAware(
          PlannedUnitKind.quality,
          text: week.q,
          isCompetition: week.qw != null,
          alternative: week.qa,
          week: week,
          tokens: tokens,
          decisions: decisions,
        ),
      );
    }
    if (week.e.isNotEmpty) {
      units.add(PlannedUnit(kind: PlannedUnitKind.easyRun, title: 'Lauf Zone 2', detail: tokens.fill(week.e)));
    }
    if (week.l.isNotEmpty) {
      units.add(
        _competitionAware(
          PlannedUnitKind.longRun,
          text: week.l,
          isCompetition: week.lw != null,
          alternative: week.la,
          week: week,
          tokens: tokens,
          decisions: decisions,
        ),
      );
    }
    for (final key in const ['push', 'legs', 'pull', 'pp']) {
      final workout = plan.workout(key);
      if (workout == null) continue;
      units.add(
        PlannedUnit(
          kind: PlannedUnitKind.gym,
          title: workout.name,
          detail: workout.exercises.map((exercise) => exercise.name).join(' · '),
        )..gymWorkout = workout,
      );
    }
    return units;
  }

  /// „Name: Beschreibung“ → Titel und Detail.
  static (String, String) split(String text, {required String fallbackTitle}) {
    final colon = text.indexOf(':');
    if (colon < 0) return (fallbackTitle, text);
    final title = text.substring(0, colon).trim();
    final detail = text.substring(colon + 1).trim();
    return (title.isEmpty ? fallbackTitle : title, detail);
  }

  PlannedUnit _competitionAware(
    PlannedUnitKind kind, {
    required String text,
    required bool isCompetition,
    required String? alternative,
    required PlanWeek week,
    required PlanTokens tokens,
    required CompetitionDecisions decisions,
  }) {
    final decision = isCompetition ? decisions[decisionKey(week, kind)] ?? PlannedUnitDecision.open : null;
    final chosen = tokens.fill(decision == PlannedUnitDecision.rejected ? (alternative ?? text) : text);
    String title;
    String detail;
    if (kind == PlannedUnitKind.longRun) {
      title = 'Longrun${week.lr > 0 ? ' ${GermanFormat.decimal(week.lr)} km' : ''}';
      detail = chosen;
    } else {
      (title, detail) = split(chosen, fallbackTitle: 'Qualitätslauf');
    }
    if (isCompetition && decision != PlannedUnitDecision.rejected) title = '🏁 $title';
    return PlannedUnit(kind: kind, title: title, detail: detail)
      ..isCompetition = isCompetition
      ..decision = decision
      ..alternative = alternative == null ? null : tokens.fill(alternative);
  }
}

/// Setzt die Testwerte in die Platzhalter ein, wie `coach_plan()` im Altbestand:
/// `§S±n§` CSS + n s/100 m, `§Wnn§` nn % FTP in Watt, `§T§` Schwelle, `§I§` Intervallband (Schwelle −23 bis
/// −18 s/km), `§E§` locker (Schwelle +65 bis +100 s/km), `§MP§` Marathonpace, `§R§` Renn-Laufpace.
final class PlanTokens {
  const PlanTokens(this.config);

  final SeasonConfig config;

  static String mmss(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String get easyRange =>
      '${mmss(config.thresholdPaceSecondsPerKm + 65)}–${mmss(config.thresholdPaceSecondsPerKm + 100)}';

  String get intervalRange =>
      '${mmss(config.thresholdPaceSecondsPerKm - 23)}–${mmss(config.thresholdPaceSecondsPerKm - 18)}';

  int watts(int percent) => (config.ftpWatts * percent / 100).round();

  String swimPace(int offset) => mmss(config.cssSecondsPer100m + offset);

  String fill(String text) {
    final result = StringBuffer();
    var rest = text;
    while (true) {
      final start = rest.indexOf('§');
      if (start < 0) break;
      result.write(rest.substring(0, start));
      final end = rest.indexOf('§', start + 1);
      if (end < 0) {
        rest = rest.substring(start);
        break;
      }
      final token = rest.substring(start + 1, end);
      result.write(replacement(token) ?? '§$token§');
      rest = rest.substring(end + 1);
    }
    result.write(rest);
    return result.toString();
  }

  /// Wie `Int(_:)` in Swift: optionales Vorzeichen, nur Ziffern.
  static int? _swiftInt(String text) => RegExp(r'^[+-]?\d+$').hasMatch(text) ? int.tryParse(text) : null;

  String? replacement(String token) {
    switch (token) {
      case 'T':
        return mmss(config.thresholdPaceSecondsPerKm);
      case 'I':
        return intervalRange;
      case 'E':
        return easyRange;
      case 'MP':
        return mmss(config.marathonPaceSecondsPerKm);
      case 'R':
        return mmss(config.racePaceSecondsPerKm);
    }
    if (token.startsWith('S')) {
      if (_swiftInt(token.substring(1)) case final offset?) return swimPace(offset);
    }
    if (token.startsWith('W')) {
      if (_swiftInt(token.substring(1)) case final percent?) return '${watts(percent)}';
    }
    return null;
  }
}

/// Art einer Einheit der Woche.
enum PlannedUnitKind implements RawEnum {
  bike,
  bikeOptional,
  swim,
  quality,
  easyRun,
  longRun,
  gym;

  @override
  String get rawValue => name;

  ActivitySport get sport => switch (this) {
    bike || bikeOptional => ActivitySport.bike,
    swim => ActivitySport.swim,
    quality || easyRun || longRun => ActivitySport.run,
    gym => ActivitySport.strength,
  };

  String get label => switch (this) {
    bike => 'Rad (Zwift)',
    bikeOptional => 'Rad optional',
    swim => 'Schwimmen',
    quality => 'Qualitätslauf',
    easyRun => 'Lauf locker',
    longRun => 'Longrun',
    gym => 'Kraft',
  };
}

/// Entscheidung zu einer Wettkampf-Einheit 🏁 (Marathon-/Renntempo).
enum PlannedUnitDecision implements RawEnum {
  open('offen'),
  accepted('angenommen'),
  rejected('abgelehnt');

  const PlannedUnitDecision(this.rawValue);

  @override
  final String rawValue;

  static PlannedUnitDecision? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Entscheidungen zu Wettkampf-Einheiten, Schlüssel `wk-lauf-<Montag>-q` bzw. `-l` (wie im Altbestand).
typedef CompetitionDecisions = Map<String, PlannedUnitDecision>;

/// Eine Einheit der Woche, fertig zum Anzeigen.
final class PlannedUnit {
  PlannedUnit({required this.kind, required this.title, required this.detail});

  final PlannedUnitKind kind;
  String title;
  String detail;

  /// Wettkampf-Einheit: lässt sich ablehnen (dann gilt die Alternative).
  bool isCompetition = false;
  PlannedUnitDecision? decision;
  String? alternative;
  List<SwimStep> swimSteps = const [];
  int? swimMeters;

  /// Kürzel des Zwift-Workouts (`Z01` … `Z15`, `RAMP`)
  String? zwiftCode;
  Workout? gymWorkout;
  bool done = false;

  String get id => '${kind.rawValue}-$title';

  /// Regeln aus `Evidence`, die diese Einheit begründen.
  List<String> get evidenceIDs => switch (kind) {
    PlannedUnitKind.quality when title.contains('4×4') => ['run.4x4', 'intensity.distribution'],
    PlannedUnitKind.gym => ['strength.economy', 'strength.interference', 'gym.progression'],
    _ => ['intensity.distribution'],
  };

  PlannedUnit copy() => PlannedUnit(kind: kind, title: title, detail: detail)
    ..isCompetition = isCompetition
    ..decision = decision
    ..alternative = alternative
    ..swimSteps = swimSteps
    ..swimMeters = swimMeters
    ..zwiftCode = zwiftCode
    ..gymWorkout = gymWorkout
    ..done = done;

  @override
  String toString() => 'PlannedUnit($kind, $title, done: $done)';
}

/// Erledigt-Status einer Woche: Garmin-Aktivitäten und eigene Krafteinheiten werden den Einheiten zugeordnet.
abstract final class PlanProgress {
  /// Longrun zählt ab 80 % der geplanten Länge; übrige Läufe füllen erst den Qualitätslauf, dann den lockeren Lauf.
  static List<PlannedUnit> mark(
    List<PlannedUnit> units, {
    required PlanWeek week,
    required List<GarminActivity> activities,
    required List<CalendarDay> gymDays,
  }) {
    final monday = week.monday;
    if (monday == null) return units;
    final sunday = monday.adding(6);
    final inWeek = activities.where((activity) {
      final day = activity.day;
      return day != null && monday <= day && day <= sunday;
    }).toList();
    final runs = inWeek.where((activity) => activity.sport == ActivitySport.run).toList()
      ..sort((a, b) => (b.distanceMeters ?? 0).compareTo(a.distanceMeters ?? 0));
    // Rad nur mit Distanz: Neben Zwift läuft oft eine zweite Aufzeichnung ohne km (Altbestand, 0.11.x).
    var bikes = inWeek
        .where((activity) => activity.sport == ActivitySport.bike && (activity.distanceMeters ?? 0) > 0)
        .length;
    var swims = inWeek.where((activity) => activity.sport == ActivitySport.swim).length;
    final strengthDays = {
      ...inWeek.where((activity) => activity.sport == ActivitySport.strength).map((activity) => activity.day).nonNulls,
      ...gymDays.where((day) => monday <= day && day <= sunday),
    };
    var gyms = strengthDays.length;

    final result = [for (final unit in units) unit.copy()];
    final longIndex = result.indexWhere((unit) => unit.kind == PlannedUnitKind.longRun);
    if (longIndex >= 0 && runs.isNotEmpty && (runs.first.distanceMeters ?? 0) / 1000 >= week.lr * 0.8) {
      result[longIndex].done = true;
      runs.removeAt(0);
    }
    for (final unit in result) {
      if (unit.done) continue;
      switch (unit.kind) {
        case PlannedUnitKind.quality || PlannedUnitKind.easyRun:
          if (runs.isNotEmpty) {
            unit.done = true;
            runs.removeAt(0);
          }
        case PlannedUnitKind.bike || PlannedUnitKind.bikeOptional:
          if (bikes > 0) {
            unit.done = true;
            bikes -= 1;
          }
        case PlannedUnitKind.swim:
          if (swims > 0) {
            unit.done = true;
            swims -= 1;
          }
        case PlannedUnitKind.gym:
          if (gyms > 0) {
            unit.done = true;
            gyms -= 1;
          }
        case PlannedUnitKind.longRun:
          break;
      }
    }
    return result;
  }
}

/// Lesbare Schwimmschritte mit Tempo aus der CSS.
abstract final class SwimStepText {
  static const equipmentNames = {
    'pull_buoy': 'Pull-Buoy',
    'paddles': 'Paddles',
    'fins': 'Flossen',
    'snorkel': 'Schnorchel',
  };

  static List<String> lines(List<SwimStep> steps, {required PlanTokens tokens, int indent = 0}) => [
    for (final step in steps) ..._lines(step, tokens, indent),
  ];

  static List<String> _lines(SwimStep step, PlanTokens tokens, int indent) {
    final prefix = '  ' * indent;
    switch (step.t) {
      case 'rep':
        return ['$prefix${step.n ?? 1}×', ...lines(step.steps ?? const [], tokens: tokens, indent: indent + 1)];
      case 'rest' || 'rec':
        return ['$prefix${step.s == null ? 'Pause' : '${step.s} s Pause'}'];
      default:
        final parts = <String>[];
        final label = const {'warmup': 'Ein', 'cool': 'Aus'}[step.t];
        if (step.m case final meters?) parts.add([?label, '$meters m'].join(' '));
        if ((step.lo, step.hi) case (final low?, final high?)) {
          parts.add(
            low == high
                ? '@ ${tokens.swimPace(low)} /100 m'
                : '@ ${tokens.swimPace(low)}–${tokens.swimPace(high)} /100 m',
          );
        }
        if (step.note case final note? when note.isNotEmpty) parts.add(note);
        if (step.eq case final equipment?) parts.add('(${equipmentNames[equipment] ?? equipment})');
        return ['$prefix${parts.join(' · ')}'];
    }
  }

  static List<String> equipment(List<SwimStep> steps) {
    final result = <String>[];
    void walk(List<SwimStep> steps) {
      for (final step in steps) {
        if (step.eq case final eq?) {
          final item = equipmentNames[eq] ?? eq;
          if (!result.contains(item)) result.add(item);
        }
        walk(step.steps ?? const []);
      }
    }

    walk(steps);
    return result;
  }
}
