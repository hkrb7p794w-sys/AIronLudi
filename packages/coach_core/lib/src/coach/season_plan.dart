import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import 'template_item.dart';

/// Renntermine und Testwerte der Saison – in der App änderbar, Standardwerte aus dem Altbestand
/// (`garmin_ai_coach/plan.py`, Stand 21.10.2026). Schlüssel `coach.season`.
final class SeasonConfig {
  SeasonConfig();

  String mainRaceName = 'Challenge Almere';
  String mainRaceDescription = 'Challenge Almere-Amsterdam, Mitteldistanz (1,9 km / 94 km / 21,1 km)';
  CalendarDay mainRaceDate = const CalendarDay(2027, 9, 11);
  String raceGoal = 'Finish in 5:30–6:00 h';
  CalendarDay marathonDate = const CalendarDay(2027, 5, 2);
  CalendarDay baseStart = const CalendarDay(2026, 9, 1);
  CalendarDay marathonBlockStart = const CalendarDay(2027, 1, 4);

  /// Zwift-FTP in Watt (Ramp Test).
  int ftpWatts = 178;

  /// Critical Swim Speed in Sekunden je 100 m.
  int cssSecondsPer100m = 130;

  /// Lauf-Schwellenpace in Sekunden je km.
  int thresholdPaceSecondsPerKm = 295;

  /// Marathon-Zielpace in Sekunden je km.
  int marathonPaceSecondsPerKm = 325;

  /// Renn-Laufpace für den Halbmarathon nach dem Rad (Almere-Benchmark) in Sekunden je km.
  int racePaceSecondsPerKm = 342;

  /// Erwarteter Rad-Schnitt auf den 94 km in km/h (Benchmark für die Zielzeit).
  double raceBikeSpeedKmh = 30.0;

  static SeasonConfig get standard => SeasonConfig();

  SeasonConfig copy() => fromJson(toJson()) ?? SeasonConfig();

  Map<String, Object?> toJson() => {
    'mainRaceName': mainRaceName,
    'mainRaceDescription': mainRaceDescription,
    'mainRaceDate': mainRaceDate.toJson(),
    'raceGoal': raceGoal,
    'marathonDate': marathonDate.toJson(),
    'baseStart': baseStart.toJson(),
    'marathonBlockStart': marathonBlockStart.toJson(),
    'ftpWatts': ftpWatts,
    'cssSecondsPer100m': cssSecondsPer100m,
    'thresholdPaceSecondsPerKm': thresholdPaceSecondsPerKm,
    'marathonPaceSecondsPerKm': marathonPaceSecondsPerKm,
    'racePaceSecondsPerKm': racePaceSecondsPerKm,
    'raceBikeSpeedKmh': raceBikeSpeedKmh,
  };

  /// Tolerant: fehlende Felder (ältere gespeicherte Stände) bekommen den Standardwert. Ein Feld mit falschem Typ
  /// macht wie in Swift das ganze Objekt unlesbar (`null`).
  static SeasonConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final config = SeasonConfig();
    String? text(String key, String fallback) {
      final value = json[key];
      if (value == null) return fallback;
      return value is String ? value : null;
    }

    CalendarDay? day(String key, CalendarDay fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! Map) return null;
      final year = jsonInt(value['year']);
      final month = jsonInt(value['month']);
      final dayOfMonth = jsonInt(value['day']);
      return year == null || month == null || dayOfMonth == null ? null : CalendarDay(year, month, dayOfMonth);
    }

    int? integer(String key, int fallback) {
      final value = json[key];
      if (value == null) return fallback;
      return value is num && value == value.roundToDouble() ? value.toInt() : null;
    }

    final values = (
      text('mainRaceName', config.mainRaceName),
      text('mainRaceDescription', config.mainRaceDescription),
      day('mainRaceDate', config.mainRaceDate),
      text('raceGoal', config.raceGoal),
      day('marathonDate', config.marathonDate),
      day('baseStart', config.baseStart),
      day('marathonBlockStart', config.marathonBlockStart),
      integer('ftpWatts', config.ftpWatts),
      integer('cssSecondsPer100m', config.cssSecondsPer100m),
      integer('thresholdPaceSecondsPerKm', config.thresholdPaceSecondsPerKm),
      integer('marathonPaceSecondsPerKm', config.marathonPaceSecondsPerKm),
      integer('racePaceSecondsPerKm', config.racePaceSecondsPerKm),
      json['raceBikeSpeedKmh'] == null ? config.raceBikeSpeedKmh : jsonDouble(json['raceBikeSpeedKmh']),
    );
    if (values case (
      final String mainRaceName,
      final String mainRaceDescription,
      final CalendarDay mainRaceDate,
      final String raceGoal,
      final CalendarDay marathonDate,
      final CalendarDay baseStart,
      final CalendarDay marathonBlockStart,
      final int ftpWatts,
      final int cssSecondsPer100m,
      final int thresholdPaceSecondsPerKm,
      final int marathonPaceSecondsPerKm,
      final int racePaceSecondsPerKm,
      final double raceBikeSpeedKmh,
    )) {
      return config
        ..mainRaceName = mainRaceName
        ..mainRaceDescription = mainRaceDescription
        ..mainRaceDate = mainRaceDate
        ..raceGoal = raceGoal
        ..marathonDate = marathonDate
        ..baseStart = baseStart
        ..marathonBlockStart = marathonBlockStart
        ..ftpWatts = ftpWatts
        ..cssSecondsPer100m = cssSecondsPer100m
        ..thresholdPaceSecondsPerKm = thresholdPaceSecondsPerKm
        ..marathonPaceSecondsPerKm = marathonPaceSecondsPerKm
        ..racePaceSecondsPerKm = racePaceSecondsPerKm
        ..raceBikeSpeedKmh = raceBikeSpeedKmh;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SeasonConfig && const DeepCollectionEquality().equals(other.toJson(), toJson());

  @override
  int get hashCode => const DeepCollectionEquality().hash(toJson());
}

enum TrainingPhase implements RawEnum {
  grundlage(
    'Grundlage',
    'aerobe Basis, Sweet-Spot-Progression auf Zwift, CSS-Schwimmen, Z2-Lauf bis 90 min verlängern',
  ),
  marathonAufbau(
    'Marathon-Aufbau',
    'Longrun von 16 auf 32 km, Schwelle und Marathontempo im Wechsel, Rad und Schwimmen halten',
  ),
  marathonTaper('Marathon-Taper', 'Umfang -25/-40/-60 %, Tempo halten, Rennverpflegung festlegen'),
  regeneration('Regeneration', '2 Wochen ohne Lauftempo, lockere Bewegung, Erholung vom Marathon'),
  almereAufbau(
    'Almere-Aufbau',
    'Rad wird Priorität (Almere: flach und windig – Aeroposition, gleichmäßige Watt): lange Ausfahrten mit '
        'Renntempo und Koppellauf, Freiwasser',
  ),
  almerePeak('Almere-Peak', 'Rennsimulation 94 km, Formtest, höchste spezifische Belastung'),
  almereTaper('Almere-Taper', 'Volumen -40 bis -60 %, Intensität und Häufigkeit halten, Rennwoche');

  const TrainingPhase(this.rawValue, this.focus);

  @override
  final String rawValue;
  final String focus;

  TrainingPhase? get next => index + 1 < values.length ? values[index + 1] : null;
}

final class PhaseSpan {
  const PhaseSpan({required this.phase, required this.start, required this.end});

  final TrainingPhase phase;
  final CalendarDay start;
  final CalendarDay end;

  @override
  bool operator ==(Object other) =>
      other is PhaseSpan && other.phase == phase && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(phase, start, end);

  @override
  String toString() => 'PhaseSpan(${phase.rawValue}, $start, $end)';
}

final class SportTarget {
  const SportTarget({
    required this.sport,
    required this.label,
    required this.minimum,
    required this.maximum,
    required this.detail,
  });

  final ActivitySport sport;
  final String label;
  final int minimum;
  final int maximum;
  final String detail;
}

final class TargetProgress {
  const TargetProgress({required this.target, required this.done});

  final SportTarget target;
  final int done;

  int get percent => target.minimum == 0 ? 100 : math.min(100, (done / target.minimum * 100).round());
}

/// Kurzplan einer Phase je Disziplin.
final class PhasePlanText {
  const PhasePlanText({required this.run, required this.swim, required this.bike, required this.strength});

  final String run;
  final String swim;
  final String bike;
  final String strength;

  /// Kompakter Plantext für KI-Prompts (wie `phase_detail_text` im Altbestand).
  String get promptText => 'Lauf: $run. Schwimmen: $swim. Rad (Zwift): $bike. Kraft: $strength.';
}

/// Planzustand für einen Tag: Phase, heutige Fixpunkte, was diese Woche noch offen ist, Soll/Ist.
final class PlanState {
  const PlanState({
    required this.today,
    required this.weekday,
    required this.phase,
    required this.phaseEnd,
    required this.nextPhase,
    required this.daysToRace,
    required this.daysToMarathon,
    required this.todayFixed,
    required this.weekOpen,
    required this.daysLeftInWeek,
    required this.targets,
    required this.plan,
    required this.phases,
  });

  final CalendarDay today;
  final String weekday;
  final TrainingPhase phase;
  final CalendarDay phaseEnd;
  final TrainingPhase? nextPhase;
  final int daysToRace;
  final int daysToMarathon;
  final List<TemplateItem> todayFixed;
  final List<String> weekOpen;
  final int daysLeftInWeek;
  final List<TargetProgress> targets;
  final PhasePlanText plan;
  final List<PhaseSpan> phases;
}

/// Portierung von `garmin_ai_coach/plan.py`: einzige Quelle für Phasen, Wochen-Soll und Musterwoche.
abstract final class SeasonPlan {
  static const weekdayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

  /// Taper Almere 14 Tage: Volumenreduktion um 41–60 % bei gleicher Intensität über 8–14 Tage (Bosquet et al. 2007;
  /// Wang et al. 2023, PLOS One, doi:10.1371/journal.pone.0282838).
  static const taperDays = 14;
  static const marathonTaperDays = 21;
  static const regenerationDays = 14;
  static const peakDays = 21;

  static List<PhaseSpan> phaseBounds(SeasonConfig config) {
    final marathonTaperStart = config.marathonDate.adding(-(marathonTaperDays - 1));
    final regenerationEnd = config.marathonDate.adding(regenerationDays);
    // Taper beginnt am Montag der vorletzten Rennwoche (Rennen Sa 11.09. → Taper ab Mo 30.08.).
    final raceMonday = config.mainRaceDate.adding(-config.mainRaceDate.weekdayIndex);
    final taperStart = raceMonday.adding(-(taperDays - 7));
    final peakStart = taperStart.adding(-peakDays);
    return [
      PhaseSpan(phase: TrainingPhase.grundlage, start: config.baseStart, end: config.marathonBlockStart.adding(-1)),
      PhaseSpan(
        phase: TrainingPhase.marathonAufbau,
        start: config.marathonBlockStart,
        end: marathonTaperStart.adding(-1),
      ),
      PhaseSpan(phase: TrainingPhase.marathonTaper, start: marathonTaperStart, end: config.marathonDate),
      PhaseSpan(phase: TrainingPhase.regeneration, start: config.marathonDate.adding(1), end: regenerationEnd),
      PhaseSpan(phase: TrainingPhase.almereAufbau, start: regenerationEnd.adding(1), end: peakStart.adding(-1)),
      PhaseSpan(phase: TrainingPhase.almerePeak, start: peakStart, end: taperStart.adding(-1)),
      PhaseSpan(phase: TrainingPhase.almereTaper, start: taperStart, end: config.mainRaceDate),
    ];
  }

  static TrainingPhase phase(CalendarDay day, SeasonConfig config) {
    final span = phaseBounds(config).firstWhereOrNull((span) => span.start <= day && day <= span.end);
    if (span != null) return span.phase;
    return day > config.mainRaceDate ? TrainingPhase.almereTaper : TrainingPhase.grundlage;
  }

  static List<SportTarget> targets(TrainingPhase phase) {
    const swim = SportTarget(sport: ActivitySport.swim, label: 'Schwimmen', minimum: 1, maximum: 1, detail: '');
    const strength = SportTarget(
      sport: ActivitySport.strength,
      label: 'Kraft',
      minimum: 4,
      maximum: 4,
      detail: '1x Beine + 3x Home-Gym (Push, Pull, Push+Pull)',
    );
    SportTarget run(int minimum, int maximum, String detail) =>
        SportTarget(sport: ActivitySport.run, label: 'Laufen', minimum: minimum, maximum: maximum, detail: detail);
    SportTarget bike(int minimum, int maximum, String detail) =>
        SportTarget(sport: ActivitySport.bike, label: 'Rad', minimum: minimum, maximum: maximum, detail: detail);
    SportTarget strengthTarget(int minimum, int maximum, String detail) =>
        SportTarget(sport: ActivitySport.strength, label: 'Kraft', minimum: minimum, maximum: maximum, detail: detail);
    return switch (phase) {
      TrainingPhase.grundlage => [
        swim,
        run(2, 2, '1x Zone 2, 1x Schwelle/Intervall im Wechsel'),
        strength,
        bike(1, 2, '1x Zwift-Intervall, optional 1x locker'),
      ],
      TrainingPhase.marathonAufbau => [swim, run(3, 3, 'Qualität, locker, Longrun'), strength, bike(1, 1, '1x Zwift')],
      TrainingPhase.marathonTaper => [
        swim,
        run(3, 3, 'kürzer, Tempo halten'),
        strengthTarget(2, 4, 'Beine nur bis 10 Tage vor dem Rennen'),
        bike(0, 1, 'kurz und locker'),
      ],
      TrainingPhase.regeneration => [
        const SportTarget(sport: ActivitySport.swim, label: 'Schwimmen', minimum: 0, maximum: 1, detail: ''),
        run(0, 2, 'nur sehr locker'),
        strengthTarget(0, 3, 'leicht'),
        bike(0, 2, 'locker'),
      ],
      TrainingPhase.almereAufbau => [
        swim,
        run(2, 2, '1x Qualität, 1x Zone 2 (+ Koppellauf)'),
        strength,
        bike(2, 2, 'Zwift-Intervall + lange Ausfahrt'),
      ],
      TrainingPhase.almerePeak => [
        swim,
        run(2, 2, '1x Qualität, 1x Zone 2 (+ Koppellauf)'),
        strengthTarget(2, 4, 'Erhalt, 1-2 Sätze pro Übung'),
        bike(2, 2, 'Renntempo + Rennsimulation'),
      ],
      TrainingPhase.almereTaper => [
        swim,
        run(2, 2, 'kurz mit Renntempo'),
        strengthTarget(0, 2, 'letzte Einheit ca. 5 Tage vor dem Rennen'),
        bike(1, 2, 'kurz mit Renntempo'),
      ],
    };
  }

  /// Musterwoche (Stand 14.10.2026): Mo Push · Di/Do Schwimmen und Beine · Mi Pull · Fr Push+Pull · Wochenende Zwift
  /// bzw. lange Einheiten. Läufe ohne festen Tag erscheinen über „offen“.
  static List<TemplateItem> template(TrainingPhase phase, int weekday) {
    if (phase == TrainingPhase.regeneration) {
      return [TemplateItem(kind: TemplateItemKind.optional, text: 'Regeneration: nur locker, nach Gefühl')];
    }
    switch (weekday) {
      case 0:
        return [TemplateItem(kind: TemplateItemKind.strength, text: 'Push (Home-Gym)')];
      case 1:
        return [
          TemplateItem(
            kind: TemplateItemKind.swimOrLegs,
            text: 'Schwimmen oder Beine vor der Arbeit (das andere am Donnerstag)',
          ),
        ];
      case 2:
        return [TemplateItem(kind: TemplateItemKind.strength, text: 'Pull (Home-Gym)')];
      case 3:
        return [
          TemplateItem(
            kind: TemplateItemKind.swimOrLegs,
            text: 'Schwimmen oder Beine vor der Arbeit (was am Dienstag nicht dran war)',
          ),
        ];
      case 4:
        return [TemplateItem(kind: TemplateItemKind.strength, text: 'Push + Pull kombiniert (Home-Gym)')];
    }
    final saturday = weekday == 5;
    return switch (phase) {
      TrainingPhase.marathonAufbau || TrainingPhase.marathonTaper =>
        saturday
            ? [TemplateItem(kind: TemplateItemKind.bike, text: 'Zwift oder Longrun (auf Sa/So verteilen)')]
            : [TemplateItem(kind: TemplateItemKind.run, text: 'Longrun oder Zwift (was Samstag nicht dran war)')],
      TrainingPhase.almereAufbau || TrainingPhase.almerePeak || TrainingPhase.almereTaper =>
        saturday
            ? [TemplateItem(kind: TemplateItemKind.bike, text: 'Lange Radeinheit + Koppellauf (Sa oder So)')]
            : [TemplateItem(kind: TemplateItemKind.bike, text: 'Lange Radeinheit, falls Samstag nicht geklappt hat')],
      TrainingPhase.grundlage || TrainingPhase.regeneration =>
        saturday
            ? [TemplateItem(kind: TemplateItemKind.bike, text: 'Zwift-Einheit (Sa oder So)')]
            : [TemplateItem(kind: TemplateItemKind.bike, text: 'Zwift-Einheit, falls Samstag nicht geklappt hat')],
    };
  }

  static String testValuesText(SeasonConfig config) {
    final pace = TestPaces(config);
    return 'Testwerte: FTP ${config.ftpWatts} W (Zwift), CSS ${pace.swim()} /100 m, Lauf-Schwellenpace '
        '${pace.run()} /km, lockere Läufe ${pace.run(65)}–${pace.run(100)} /km bzw. HF Zone 2, Marathon-Zielpace '
        '${GermanFormat.minutesSeconds(config.marathonPaceSecondsPerKm)} /km, Renn-Zielwatt Almere '
        '${pace.watts(75)}–${pace.watts(78)} W';
  }

  static PhasePlanText planText(TrainingPhase phase, SeasonConfig config) =>
      PhasePlanTexts.text(phase, TestPaces(config));

  static PlanState state({required CalendarDay today, required SeasonConfig config, required WeeklyVolume week}) {
    final phase = SeasonPlan.phase(today, config);
    final bounds = phaseBounds(config);
    final targets = SeasonPlan.targets(phase);
    final progress = [
      for (final target in targets) TargetProgress(target: target, done: week.sessions[target.sport] ?? 0),
    ];
    final open = <String>[];
    for (final item in progress.where((item) => item.done < item.target.minimum)) {
      final missing = item.target.minimum - item.done;
      final detail = item.target.sport == ActivitySport.run && item.target.detail.isNotEmpty
          ? ' (${item.target.detail})'
          : '';
      open.add('$missing× ${item.target.label}$detail');
    }
    final weekday = today.weekdayIndex;
    final bikeMinimum = math.max(
      targets.firstWhereOrNull((target) => target.sport == ActivitySport.bike)?.minimum ?? 1,
      1,
    );
    // Wochenende: Ist das Rad-Soll schon erreicht, ist die Ersatzeinheit hinfällig (sonst verordnete die KI-Notiz sie
    // sonntags erneut, Befund 18.10.2026).
    final fixed = [
      for (final item in template(phase, weekday))
        if (item.kind == TemplateItemKind.bike &&
            weekday >= 5 &&
            (week.sessions[ActivitySport.bike] ?? 0) >= bikeMinimum)
          (item
            ..done = true
            ..text = '${item.text} – diese Woche schon erledigt')
        else
          item,
    ];
    return PlanState(
      today: today,
      weekday: weekdayNames[weekday],
      phase: phase,
      phaseEnd: bounds.firstWhereOrNull((span) => span.phase == phase)?.end ?? config.mainRaceDate,
      nextPhase: phase.next,
      daysToRace: today.daysUntil(config.mainRaceDate),
      daysToMarathon: today.daysUntil(config.marathonDate),
      todayFixed: fixed,
      weekOpen: open,
      daysLeftInWeek: 6 - weekday,
      targets: progress,
      plan: planText(phase, config),
      phases: bounds,
    );
  }
}

/// Wochenvolumen je Disziplin (Kalenderwoche Mo–So).
final class WeeklyVolume {
  WeeklyVolume();

  /// Wie `_window_totals` im Altbestand. Rad ohne Distanz zählt nicht: Neben der Zwift-Fahrt läuft oft eine zweite
  /// Aufzeichnung auf der Uhr („Indoor Radfahren“ ohne km), die sonst doppelt zählen würde. [gymDays]: Krafteinheiten
  /// aus der App. Sie zählen als Kraft, außer an Tagen mit eigener Kraft-Aufzeichnung der Uhr (dieselbe Einheit,
  /// sonst doppelt).
  factory WeeklyVolume.from(
    List<GarminActivity> activities, {
    required CalendarDay weekContaining,
    Iterable<CalendarDay> gymDays = const [],
  }) {
    final volume = WeeklyVolume();
    final monday = weekContaining.adding(-weekContaining.weekdayIndex);
    final sunday = monday.adding(6);
    bool inWeek(CalendarDay day) => monday <= day && day <= sunday;
    final watchStrengthDays = activities
        .where((activity) => activity.sport == ActivitySport.strength)
        .map((activity) => activity.day)
        .nonNulls
        .where(inWeek)
        .toSet();
    final appOnly = gymDays.toSet().where((day) => inWeek(day) && !watchStrengthDays.contains(day));
    if (appOnly.isNotEmpty) {
      volume.sessions[ActivitySport.strength] = (volume.sessions[ActivitySport.strength] ?? 0) + appOnly.length;
    }
    for (final activity in activities) {
      final day = activity.day;
      if (day == null || !inWeek(day)) continue;
      final sport = activity.sport;
      if (sport == ActivitySport.other) continue;
      final kilometers = (activity.distanceMeters ?? 0) / 1000;
      if (sport == ActivitySport.bike && kilometers <= 0) continue;
      volume.sessions[sport] = (volume.sessions[sport] ?? 0) + 1;
      volume.kilometers[sport] = (volume.kilometers[sport] ?? 0) + kilometers;
      volume.minutes[sport] = (volume.minutes[sport] ?? 0) + (activity.durationSeconds ?? 0) / 60;
    }
    return volume;
  }

  Map<ActivitySport, int> sessions = {};
  Map<ActivitySport, double> kilometers = {};
  Map<ActivitySport, double> minutes = {};
}

/// Watt- und Pace-Angaben aus den Testwerten.
final class TestPaces {
  const TestPaces(this.config);

  final SeasonConfig config;

  /// Watt bei [percent] % der FTP.
  int watts(double percent) => (config.ftpWatts * percent / 100).round();

  String swim([int offset = 0]) => GermanFormat.minutesSeconds(config.cssSecondsPer100m + offset);

  String run([int offset = 0]) => GermanFormat.minutesSeconds(config.thresholdPaceSecondsPerKm + offset);

  String get marathon => GermanFormat.minutesSeconds(config.marathonPaceSecondsPerKm);
}

/// Kurzpläne je Phase und Disziplin (`PHASE_PLAN` im Altbestand). Watt und Pace rechnen sich aus den Testwerten,
/// damit ein neuer Test nur an einer Stelle eingetragen werden muss.
abstract final class PhasePlanTexts {
  static PhasePlanText text(TrainingPhase phase, TestPaces p) => switch (phase) {
    TrainingPhase.grundlage => PhasePlanText(
      run:
          'Z2-Lauf mit Partnerin 50 → 90 min (HF Zone 2) · Qualitätslauf im Wechsel: Schwelle (z. B. 3×2 km @ '
          '${p.run()} /km) und 4×4-min-Intervall (90–95 % HFmax, Richtwert ${p.run(-23)}–${p.run(-18)} /km, '
          '3 min Trab) · 30-min-Lauftest Mitte Dezember',
      swim:
          'CSS-Serien im 4-Wochen-Wechsel: 100er @ ${p.swim()}, 200er–400er @ ${p.swim(1)}–${p.swim(4)}, '
          'Technik + Ausdauer, Tempo-50er @ ${p.swim(-4)}–${p.swim(-2)} /100 m · CSS-Test 30.11.',
      bike:
          '1x Zwift: Sweet Spot 3×10 → 2×20 min @ ${p.watts(88)}–${p.watts(94)} W, dann Schwelle '
          '${p.watts(98)} W und Over-Under · FTP-Test 07.12. · optional 1x Z2 ${p.watts(65)}–${p.watts(70)} W',
      strength: 'Mo Push · Mi Pull · Fr Push+Pull · Beine Di oder Do',
    ),
    TrainingPhase.marathonAufbau => PhasePlanText(
      run:
          'So Longrun 16 → 32 km (${p.run(65)}–${p.run(100)} /km, Spitze 11.04.) · unter der Woche Schwelle @ '
          '${p.run()} oder Marathontempo @ ${p.marathon} /km im Wechsel + locker mit Partnerin · '
          'Halbmarathon-Test 14.03.',
      swim: '1x CSS-Serie wie bisher (@ ${p.swim()} /100 m), Wiederholungen steigern, Pausen kürzen',
      bike:
          '1x Zwift am Wochenende zum Erhalt: Sweet Spot @ ${p.watts(90)}–${p.watts(94)} W, in '
          'Entlastungswochen Z2 · FTP-Tests 01.02. und 29.03.',
      strength:
          'Home-Gym wie gewohnt · Beine schwer und kurz (2-3 Sätze à 4-6 Wdh.), 48 h Abstand zu '
          'Longrun/Qualität',
    ),
    TrainingPhase.marathonTaper => PhasePlanText(
      run: 'Longrun 24 → 16 km, Marathontempo kurz @ ${p.marathon} /km · Rennen So 02.05., 60-90 g KH/h',
      swim: 'kurz und locker, ein paar zügige 50er',
      bike: 'Zwift kurz mit Aktivierung (3×3 min @ ${p.watts(80)} W)',
      strength: 'Volumen reduzieren, letzte schwere Beine-Einheit ca. 10 Tage vor dem Rennen',
    ),
    TrainingPhase.regeneration => PhasePlanText(
      run: 'ab Tag 5 sehr locker 20-30 min, Woche 2: 2× 30-40 min locker',
      swim: 'locker, Technik',
      bike: 'Zwift locker Z2 (${p.watts(65)}–${p.watts(70)} W)',
      strength: 'Oberkörper leicht, Beine erst in Woche 2 leicht',
    ),
    TrainingPhase.almereAufbau => PhasePlanText(
      run:
          'Qualitätslauf im Wechsel Schwelle @ ${p.run()} /km und Renn-Laufpace · So Z2 mit Partnerin · '
          'Koppellauf nach jeder langen Radeinheit',
      swim:
          'CSS-Serien und Renn-Simulation 1200 → 1900 m @ ${p.swim(1)}–${p.swim(3)} /100 m (1,9 km ≈ CSS bis '
          '+3 s), Sighting, ab Juni Freiwasser mit Neo',
      bike:
          'Zwift-Intervall unter der Woche (Sweet Spot, Renntempo 2×30 / 3×20 min @ ${p.watts(77)}–'
          '${p.watts(78)} W) · Wochenende lange Ausfahrt 2:00 → 3:00 h mit Renntempo-Blöcken + Koppellauf',
      strength: 'Home-Gym wie gewohnt, Beine 1x',
    ),
    TrainingPhase.almerePeak => PhasePlanText(
      run: 'Renn-Laufpace 2×5 km / 3×3 km, Koppelläufe 20-30 min',
      swim: 'Freiwasser 1500-2000 m am Stück mit Neo',
      bike:
          'Rennsimulation 94 km @ ${p.watts(75)}–${p.watts(78)} W + 30 min Koppellauf · Formtest (z. B. '
          'Olympische Distanz)',
      strength: 'Erhalt: 1-2 Sätze pro Übung, keine neuen Reize',
    ),
    TrainingPhase.almereTaper => PhasePlanText(
      run: 'kürzer (30-40 min) mit kurzen Renntempo-Abschnitten, kein Longrun',
      swim: '8×50 m zügig, viel Pause',
      bike: 'Aktivierung 35 min (3×3 min @ ${p.watts(80)} W) · Rennen: ${p.watts(75)}–${p.watts(78)} W',
      strength: 'Volumen -40 bis -60 %, letzte Einheit ca. 5 Tage vor dem Rennen',
    ),
  };
}
