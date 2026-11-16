import '../calendar/calendar_day.dart';
import '../garmin/garmin_activity.dart';
import '../garmin/garmin_workout.dart';
import '../profile/week_schedule.dart';
import '../util/enum_codec.dart';

// Datenmodell des adaptiven Ausdauerplans (Laufen, Rad inkl. Zwift, Schwimmen). Alles ist JSON-fähig und gehört
// genau einem Benutzer (`username`); gespeichert wird es im Speicher dieses Benutzers (`coach.endurancePlan`).

/// Disziplin eines Ausdauerplans.
enum EnduranceSport implements RawEnum {
  run('Laufen', 'figure.run'),
  bike('Rad', 'figure.outdoor.cycle'),
  swim('Schwimmen', 'figure.pool.swim');

  const EnduranceSport(this.label, this.symbol);

  final String label;
  final String symbol;

  @override
  String get rawValue => name;

  ActivitySport get activitySport => switch (this) {
    run => ActivitySport.run,
    bike => ActivitySport.bike,
    swim => ActivitySport.swim,
  };

  WorkoutSport get workoutSport => switch (this) {
    run => WorkoutSport.run,
    bike => WorkoutSport.bike,
    swim => WorkoutSport.swim,
  };

  static EnduranceSport? of(ActivitySport sport) => switch (sport) {
    ActivitySport.run => run,
    ActivitySport.bike => bike,
    ActivitySport.swim => swim,
    ActivitySport.strength || ActivitySport.other => null,
  };
}

/// Planungsart: auf ein Ziel hin oder für einen frei gewählten Zeitraum.
enum PlanningMode implements RawEnum {
  goal('Auf ein Ziel'),
  period('Für einen Zeitraum');

  const PlanningMode(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Schwerpunkt eines Zeitraum-Plans.
enum PeriodFocus implements RawEnum {
  base('Grundlagenausdauer'),
  fitness('Formsteigerung');

  const PeriodFocus(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Wettkampf bzw. Leistungsziel eines Ziel-Plans.
enum EnduranceEvent implements RawEnum {
  run5k('5 km', [EnduranceSport.run], 1, 25),
  run10k('10 km', [EnduranceSport.run], 1, 50),
  halfMarathon('Halbmarathon', [EnduranceSport.run], 2, 110),
  marathon('Marathon', [EnduranceSport.run], 2, 240),
  triSprint('Triathlon Sprint', [EnduranceSport.swim, EnduranceSport.bike, EnduranceSport.run], 1, 80),
  triOlympic('Triathlon olympisch', [EnduranceSport.swim, EnduranceSport.bike, EnduranceSport.run], 2, 160),
  triMiddle('Triathlon Mitteldistanz', [EnduranceSport.swim, EnduranceSport.bike, EnduranceSport.run], 2, 330),
  triFull('Triathlon Langdistanz', [EnduranceSport.swim, EnduranceSport.bike, EnduranceSport.run], 3, 720),
  bikeEvent('Radrennen / Radmarathon', [EnduranceSport.bike], 2, 240),
  swimEvent('Schwimmwettkampf / Freiwasser', [EnduranceSport.swim], 1, 60);

  const EnduranceEvent(this.label, this.sports, this.taperWeeks, this.defaultMinutes);

  final String label;
  final List<EnduranceSport> sports;

  /// Wochen mit reduziertem Umfang einschließlich der Wettkampfwoche.
  final int taperWeeks;

  /// Übliche Dauer, falls keine Zielzeit angegeben ist.
  final int defaultMinutes;

  bool get isTriathlon => sports.length == 3;

  /// Hauptdisziplin (lange Einheit).
  EnduranceSport get primary => isTriathlon ? EnduranceSport.bike : sports.first;

  @override
  String get rawValue => name;
}

/// Phase der Periodisierung.
enum EndurancePhase implements RawEnum {
  base('Grundlage'),
  build('Aufbau'),
  peak('Spitze'),
  taper('Tapering'),
  recovery('Entlastung'),
  race('Wettkampfwoche');

  const EndurancePhase(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Art einer Einheit.
enum EnduranceWorkoutType implements RawEnum {
  rest('Ruhetag'),
  recovery('Regeneration'),
  endurance('Grundlage'),
  long('Lange Einheit'),
  tempo('Tempo'),
  threshold('Schwelle'),
  vo2max('VO2max-Intervalle'),
  race('Wettkampf');

  const EnduranceWorkoutType(this.label);

  final String label;

  /// Hart im Sinne der Belastungssteuerung (Intensität über Zone 2).
  bool get isHard => this == tempo || this == threshold || this == vo2max || this == race;

  /// Schlüsseleinheit, die bei Ausfall nachgeholt werden darf.
  bool get isKey => this == long || this == tempo || this == threshold || this == vo2max;

  @override
  String get rawValue => name;
}

/// Intensitätszone (1 bis 5), aus der sich die konkreten Ziele je Disziplin ergeben.
enum IntensityZone implements RawEnum {
  recovery('Zone 1 · sehr locker'),
  endurance('Zone 2 · Grundlage'),
  tempo('Zone 3 · Tempo'),
  threshold('Zone 4 · Schwelle'),
  vo2max('Zone 5 · VO2max');

  const IntensityZone(this.label);

  final String label;

  int get number => index + 1;

  @override
  String get rawValue => name;
}

/// Art des Ziels eines Schritts.
enum TargetKind implements RawEnum {
  /// Pace in Sekunden je km (Laufen) bzw. je 100 m (Schwimmen).
  pace,

  /// Leistung in Watt.
  power,

  /// Herzfrequenz in Schlägen je Minute.
  heartRate,

  /// Ohne Zahl (nur Zone als Notiz).
  open;

  @override
  String get rawValue => name;
}

/// Ziel eines Schritts. Bei der Pace ist [low] die schnellere (kleinere) Zahl.
final class StepTarget {
  const StepTarget(this.kind, {this.low = 0, this.high = 0});

  const StepTarget.open() : kind = TargetKind.open, low = 0, high = 0;

  final TargetKind kind;
  final int low;
  final int high;

  Map<String, Object?> toJson() => {'kind': kind.rawValue, 'low': low, 'high': high};

  static StepTarget? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = enumFromRaw(TargetKind.values, json['kind']);
    final low = json['low'];
    final high = json['high'];
    if (kind == null || low is! num || high is! num) return null;
    return StepTarget(kind, low: low.toInt(), high: high.toInt());
  }

  @override
  bool operator ==(Object other) => other is StepTarget && other.kind == kind && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(kind, low, high);
}

/// Baustein einer Einheit: Schritt oder Wiederholung.
sealed class EnduranceBlock {
  const EnduranceBlock();

  Map<String, Object?> toJson();

  static EnduranceBlock? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['repeat'] case final num count) {
      final steps = <EnduranceStep>[];
      final raw = json['steps'];
      if (raw is! List) return null;
      for (final item in raw) {
        final step = EnduranceStep.fromJson(item);
        if (step == null) return null;
        steps.add(step);
      }
      return EnduranceRepeat(count.toInt(), steps);
    }
    return EnduranceStep.fromJson(json);
  }
}

/// Ausführbarer Schritt mit Dauer ([seconds]) oder Strecke ([meters]).
final class EnduranceStep extends EnduranceBlock {
  const EnduranceStep({
    required this.kind,
    required this.zone,
    this.seconds,
    this.meters,
    this.target = const StepTarget.open(),
    this.note = '',
  });

  /// Notiz der Pausen am Beckenrand (auf der Uhr als Pause, nicht als Erholungsschritt).
  static const pauseNote = 'Pause am Rand';

  final WorkoutStepKind kind;
  final IntensityZone zone;
  final int? seconds;
  final int? meters;
  final StepTarget target;
  final String note;

  bool get isPause => kind == WorkoutStepKind.recovery && note == pauseNote;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'zone': zone.rawValue,
    'seconds': ?seconds,
    'meters': ?meters,
    'target': target.toJson(),
    if (note.isNotEmpty) 'note': note,
  };

  static EnduranceStep? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = WorkoutStepKind.values.where((value) => value.name == json['kind']).firstOrNull;
    final zone = enumFromRaw(IntensityZone.values, json['zone']);
    final target = StepTarget.fromJson(json['target']) ?? const StepTarget.open();
    if (kind == null || zone == null) return null;
    return EnduranceStep(
      kind: kind,
      zone: zone,
      seconds: (json['seconds'] as num?)?.toInt(),
      meters: (json['meters'] as num?)?.toInt(),
      target: target,
      note: json['note'] is String ? json['note'] as String : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EnduranceStep &&
      other.kind == kind &&
      other.zone == zone &&
      other.seconds == seconds &&
      other.meters == meters &&
      other.target == target &&
      other.note == note;

  @override
  int get hashCode => Object.hash(kind, zone, seconds, meters, target, note);
}

/// Wiederholung von Schritten (z. B. 5 × [8 min Schwelle, 2 min locker]).
final class EnduranceRepeat extends EnduranceBlock {
  const EnduranceRepeat(this.count, this.steps);

  final int count;
  final List<EnduranceStep> steps;

  @override
  Map<String, Object?> toJson() => {
    'repeat': count,
    'steps': [for (final step in steps) step.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is EnduranceRepeat &&
      other.count == count &&
      other.steps.length == steps.length &&
      Iterable<int>.generate(steps.length).every((index) => other.steps[index] == steps[index]);

  @override
  int get hashCode => Object.hash(count, Object.hashAll(steps));
}

/// Eine strukturierte Einheit (geplant oder angepasst).
final class EnduranceWorkout {
  const EnduranceWorkout({
    required this.sport,
    required this.type,
    required this.title,
    required this.minutes,
    required this.steps,
    required this.load,
    this.meters,
    this.note = '',
  });

  final EnduranceSport sport;
  final EnduranceWorkoutType type;
  final String title;

  /// Geschätzte Dauer in Minuten.
  final int minutes;

  /// Gesamtstrecke bei Schwimmeinheiten.
  final int? meters;
  final List<EnduranceBlock> steps;

  /// Geplante Belastung (Training-Stress-Punkte, 100 = eine Stunde an der Schwelle).
  final double load;
  final String note;

  bool get isRest => type == EnduranceWorkoutType.rest;

  Map<String, Object?> toJson() => {
    'sport': sport.rawValue,
    'type': type.rawValue,
    'title': title,
    'minutes': minutes,
    'meters': ?meters,
    'steps': [for (final step in steps) step.toJson()],
    'load': load,
    if (note.isNotEmpty) 'note': note,
  };

  static EnduranceWorkout? fromJson(Object? json) {
    if (json is! Map) return null;
    final sport = enumFromRaw(EnduranceSport.values, json['sport']);
    final type = enumFromRaw(EnduranceWorkoutType.values, json['type']);
    final title = json['title'];
    final minutes = json['minutes'];
    final load = json['load'];
    final rawSteps = json['steps'];
    if (sport == null || type == null || title is! String || minutes is! num || load is! num || rawSteps is! List) {
      return null;
    }
    final steps = <EnduranceBlock>[];
    for (final item in rawSteps) {
      final block = EnduranceBlock.fromJson(item);
      if (block == null) return null;
      steps.add(block);
    }
    return EnduranceWorkout(
      sport: sport,
      type: type,
      title: title,
      minutes: minutes.toInt(),
      meters: (json['meters'] as num?)?.toInt(),
      steps: steps,
      load: load.toDouble(),
      note: json['note'] is String ? json['note'] as String : '',
    );
  }

  /// Gleicher Inhalt (für die Erkennung von Änderungen und den Kalender-Abgleich).
  bool sameContent(EnduranceWorkout other) =>
      other.sport == sport &&
      other.type == type &&
      other.title == title &&
      other.minutes == minutes &&
      other.meters == meters &&
      other.note == note &&
      other.steps.length == steps.length &&
      Iterable<int>.generate(steps.length).every((index) => other.steps[index] == steps[index]);

  /// Kurzbeschreibung für Verlauf und Liste („Rad · Schwelle · 70 min“).
  String get summary =>
      isRest ? 'Ruhetag' : '${sport.label} · ${type.label} · ${meters != null ? '$meters m' : '$minutes min'}';
}

/// Stand einer geplanten Einheit.
enum SlotStatus implements RawEnum {
  planned('geplant'),
  completed('erledigt'),
  missed('ausgefallen');

  const SlotStatus(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Eine Einheit im Plan: ursprünglich geplant ([baseline]) und aktuell gültig ([current], nach Anpassungen).
final class PlanSlot {
  PlanSlot({
    required this.id,
    required this.day,
    required this.week,
    required this.phase,
    required this.baseline,
    EnduranceWorkout? current,
    this.status = SlotStatus.planned,
    this.actualLoad,
    this.activityKey,
  }) : current = current ?? baseline;

  final String id;
  final CalendarDay day;

  /// Index der Woche im Plan (ab 0).
  final int week;
  final EndurancePhase phase;
  final EnduranceWorkout baseline;
  EnduranceWorkout current;
  SlotStatus status;

  /// Tatsächliche Belastung der zugeordneten Aktivität.
  double? actualLoad;

  /// Kennung der zugeordneten Aktivität.
  String? activityKey;

  bool get isAdapted => !current.sameContent(baseline);

  PlanSlot copy() => PlanSlot(
    id: id,
    day: day,
    week: week,
    phase: phase,
    baseline: baseline,
    current: current,
    status: status,
    actualLoad: actualLoad,
    activityKey: activityKey,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'day': day.iso,
    'week': week,
    'phase': phase.rawValue,
    'baseline': baseline.toJson(),
    if (isAdapted) 'current': current.toJson(),
    'status': status.rawValue,
    'actualLoad': ?actualLoad,
    'activityKey': ?activityKey,
  };

  static PlanSlot? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final day = json['day'] is String ? CalendarDay.tryParse(json['day'] as String) : null;
    final week = json['week'];
    final phase = enumFromRaw(EndurancePhase.values, json['phase']);
    final baseline = EnduranceWorkout.fromJson(json['baseline']);
    if (id is! String || day == null || week is! num || phase == null || baseline == null) return null;
    return PlanSlot(
      id: id,
      day: day,
      week: week.toInt(),
      phase: phase,
      baseline: baseline,
      current: json.containsKey('current') ? EnduranceWorkout.fromJson(json['current']) : null,
      status: enumFromRaw(SlotStatus.values, json['status']) ?? SlotStatus.planned,
      actualLoad: (json['actualLoad'] as num?)?.toDouble(),
      activityKey: json['activityKey'] as String?,
    );
  }
}

/// Woche im Makrozyklus.
final class PlanWeekInfo {
  const PlanWeekInfo({required this.index, required this.monday, required this.phase, required this.minutes});

  final int index;
  final CalendarDay monday;
  final EndurancePhase phase;

  /// Geplanter Umfang der Woche in Minuten.
  final int minutes;

  Map<String, Object?> toJson() => {'index': index, 'monday': monday.iso, 'phase': phase.rawValue, 'minutes': minutes};

  static PlanWeekInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final index = json['index'];
    final monday = json['monday'] is String ? CalendarDay.tryParse(json['monday'] as String) : null;
    final phase = enumFromRaw(EndurancePhase.values, json['phase']);
    final minutes = json['minutes'];
    if (index is! num || monday == null || phase == null || minutes is! num) return null;
    return PlanWeekInfo(index: index.toInt(), monday: monday, phase: phase, minutes: minutes.toInt());
  }
}

/// Leistungsschwellen des Benutzers. Fehlt eine, plant der Plan mit Puls oder ohne Zahl (nur Zone).
final class AthleteThresholds {
  const AthleteThresholds({
    this.runThresholdPace,
    this.ftpWatts,
    this.swimCss,
    this.runThresholdHeartRate,
    this.bikeThresholdHeartRate,
  });

  /// Schwellen-Pace Laufen in Sekunden je km.
  final int? runThresholdPace;
  final int? ftpWatts;

  /// Critical Swim Speed in Sekunden je 100 m.
  final int? swimCss;
  final int? runThresholdHeartRate;
  final int? bikeThresholdHeartRate;

  int? thresholdHeartRate(EnduranceSport sport) => switch (sport) {
    EnduranceSport.run => runThresholdHeartRate,
    EnduranceSport.bike => bikeThresholdHeartRate ?? runThresholdHeartRate.let((value) => value - 5),
    EnduranceSport.swim => null,
  };

  Map<String, Object?> toJson() => {
    'runThresholdPace': ?runThresholdPace,
    'ftpWatts': ?ftpWatts,
    'swimCss': ?swimCss,
    'runThresholdHeartRate': ?runThresholdHeartRate,
    'bikeThresholdHeartRate': ?bikeThresholdHeartRate,
  };

  static AthleteThresholds fromJson(Object? json) {
    if (json is! Map) return const AthleteThresholds();
    int? read(String key) => (json[key] as num?)?.toInt();
    return AthleteThresholds(
      runThresholdPace: read('runThresholdPace'),
      ftpWatts: read('ftpWatts'),
      swimCss: read('swimCss'),
      runThresholdHeartRate: read('runThresholdHeartRate'),
      bikeThresholdHeartRate: read('bikeThresholdHeartRate'),
    );
  }
}

extension on int? {
  int? let(int Function(int value) transform) => this == null ? null : transform(this!);
}

/// Wünsche bei der Erstellung.
final class TrainingPlanRequest {
  const TrainingPlanRequest({
    required this.username,
    required this.mode,
    required this.sports,
    required this.start,
    required this.weeklyMinutes,
    required this.days,
    required this.longDay,
    this.weeks = 8,
    this.focus = PeriodFocus.fitness,
    this.event,
    this.eventDay,
    this.targetMinutes,
    this.thresholds = const AthleteThresholds(),
  });

  final String username;
  final PlanningMode mode;
  final List<EnduranceSport> sports;
  final CalendarDay start;

  /// Verfügbare Zeit je Woche in Minuten (Höchstwert in Aufbauwochen).
  final int weeklyMinutes;

  /// Trainingstage.
  final List<Weekday> days;

  /// Tag der langen Einheit.
  final Weekday longDay;

  /// Länge des Zeitraum-Plans.
  final int weeks;
  final PeriodFocus focus;
  final EnduranceEvent? event;
  final CalendarDay? eventDay;

  /// Zielzeit des Wettkampfs in Minuten.
  final int? targetMinutes;
  final AthleteThresholds thresholds;

  /// Disziplinen des Plans: beim Ziel die des Wettkampfs plus gewählte Ergänzungen.
  List<EnduranceSport> get planSports {
    final result = <EnduranceSport>{if (mode == PlanningMode.goal && event != null) ...event!.sports, ...sports};
    return [
      for (final sport in EnduranceSport.values)
        if (result.contains(sport)) sport,
    ];
  }

  TrainingPlanRequest copyWith({AthleteThresholds? thresholds, String? username}) => TrainingPlanRequest(
    username: username ?? this.username,
    mode: mode,
    sports: sports,
    start: start,
    weeklyMinutes: weeklyMinutes,
    days: days,
    longDay: longDay,
    weeks: weeks,
    focus: focus,
    event: event,
    eventDay: eventDay,
    targetMinutes: targetMinutes,
    thresholds: thresholds ?? this.thresholds,
  );

  Map<String, Object?> toJson() => {
    'username': username,
    'mode': mode.rawValue,
    'sports': [for (final sport in sports) sport.rawValue],
    'start': start.iso,
    'weeklyMinutes': weeklyMinutes,
    'days': [for (final day in days) day.name],
    'longDay': longDay.name,
    'weeks': weeks,
    'focus': focus.rawValue,
    'event': ?event?.rawValue,
    'eventDay': ?eventDay?.iso,
    'targetMinutes': ?targetMinutes,
    'thresholds': thresholds.toJson(),
  };

  static TrainingPlanRequest? fromJson(Object? json) {
    if (json is! Map) return null;
    Weekday? weekday(Object? raw) => Weekday.values.where((value) => value.name == raw).firstOrNull;
    final username = json['username'];
    final mode = enumFromRaw(PlanningMode.values, json['mode']);
    final start = json['start'] is String ? CalendarDay.tryParse(json['start'] as String) : null;
    final weeklyMinutes = json['weeklyMinutes'];
    final longDay = weekday(json['longDay']);
    final rawDays = json['days'];
    if (username is! String || mode == null || start == null || weeklyMinutes is! num || longDay == null) return null;
    return TrainingPlanRequest(
      username: username,
      mode: mode,
      sports: enumListFromRaw(EnduranceSport.values, json['sports']),
      start: start,
      weeklyMinutes: weeklyMinutes.toInt(),
      days: rawDays is List ? rawDays.map(weekday).nonNulls.toList() : const [],
      longDay: longDay,
      weeks: (json['weeks'] as num?)?.toInt() ?? 8,
      focus: enumFromRaw(PeriodFocus.values, json['focus']) ?? PeriodFocus.fitness,
      event: enumFromRaw(EnduranceEvent.values, json['event']),
      eventDay: json['eventDay'] is String ? CalendarDay.tryParse(json['eventDay'] as String) : null,
      targetMinutes: (json['targetMinutes'] as num?)?.toInt(),
      thresholds: AthleteThresholds.fromJson(json['thresholds']),
    );
  }
}

/// Grund einer Anpassung.
enum AdjustmentCause implements RawEnum {
  /// Vorherige Einheit (auch andere Disziplin) war deutlich härter als geplant.
  load('Belastung'),

  /// Ausgefallene Schlüsseleinheit wird nachgeholt.
  missed('Ausfall'),

  /// Erholungswerte (HRV, Ruhepuls, Schlaf, Body Battery, Readiness).
  recovery('Erholung'),

  /// Ermüdung aus den letzten Wochen (Form deutlich negativ).
  fatigue('Ermüdung'),

  /// Der Grund ist entfallen, die Einheit gilt wieder wie ursprünglich geplant.
  restored('Wieder wie geplant');

  const AdjustmentCause(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Eintrag im Anpassungsverlauf.
final class PlanAdjustmentEntry {
  const PlanAdjustmentEntry({
    required this.at,
    required this.slotID,
    required this.day,
    required this.cause,
    required this.reason,
    required this.before,
    required this.after,
  });

  final DateTime at;
  final String slotID;
  final CalendarDay day;
  final AdjustmentCause cause;
  final String reason;
  final String before;
  final String after;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'slotID': slotID,
    'day': day.iso,
    'cause': cause.rawValue,
    'reason': reason,
    'before': before,
    'after': after,
  };

  static PlanAdjustmentEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'] is String ? DateTime.tryParse(json['at'] as String) : null;
    final day = json['day'] is String ? CalendarDay.tryParse(json['day'] as String) : null;
    final cause = enumFromRaw(AdjustmentCause.values, json['cause']);
    final slotID = json['slotID'];
    final reason = json['reason'];
    if (at == null || day == null || cause == null || slotID is! String || reason is! String) return null;
    return PlanAdjustmentEntry(
      at: at,
      slotID: slotID,
      day: day,
      cause: cause,
      reason: reason,
      before: json['before'] is String ? json['before'] as String : '',
      after: json['after'] is String ? json['after'] as String : '',
    );
  }
}

/// Ein in den Garmin-Kalender übertragenes Workout (Kennung bei Garmin und Fingerabdruck des Inhalts).
final class SyncedWorkout {
  const SyncedWorkout({required this.workoutID, required this.fingerprint, required this.day});

  final int workoutID;
  final String fingerprint;
  final CalendarDay day;

  Map<String, Object?> toJson() => {'workoutID': workoutID, 'fingerprint': fingerprint, 'day': day.iso};

  static SyncedWorkout? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['workoutID'];
    final fingerprint = json['fingerprint'];
    final day = json['day'] is String ? CalendarDay.tryParse(json['day'] as String) : null;
    if (id is! num || fingerprint is! String || day == null) return null;
    return SyncedWorkout(workoutID: id.toInt(), fingerprint: fingerprint, day: day);
  }
}

/// Der vollständige Plan eines Benutzers.
final class EndurancePlan {
  EndurancePlan({
    required this.id,
    required this.username,
    required this.request,
    required this.createdAt,
    required this.weeks,
    required this.slots,
    List<PlanAdjustmentEntry>? adjustments,
    this.revision = 1,
    this.autoSyncGarmin = false,
    this.lastAdapted,
    Map<String, SyncedWorkout>? synced,
  }) : adjustments = adjustments ?? [],
       synced = synced ?? {};

  final String id;

  /// Besitzer. Ein Plan wird nur für genau diesen Benutzer geladen, angepasst und übertragen.
  final String username;
  final TrainingPlanRequest request;
  final DateTime createdAt;
  final List<PlanWeekInfo> weeks;
  final List<PlanSlot> slots;
  final List<PlanAdjustmentEntry> adjustments;

  /// Steigt mit jeder Änderung an kommenden Einheiten (Auslöser für den Kalender-Abgleich).
  int revision;

  /// Kommende Einheiten automatisch in den Garmin-Kalender übertragen.
  bool autoSyncGarmin;
  CalendarDay? lastAdapted;

  /// Übertragene Workouts je Einheit ([PlanSlot.id]).
  final Map<String, SyncedWorkout> synced;

  /// Höchstens so viele Einträge im Anpassungsverlauf.
  static const maxAdjustments = 300;

  CalendarDay get firstDay => weeks.first.monday;
  CalendarDay get lastDay => weeks.last.monday.adding(6);

  PlanWeekInfo? weekOf(CalendarDay day) {
    for (final week in weeks) {
      if (day >= week.monday && day <= week.monday.adding(6)) return week;
    }
    return null;
  }

  List<PlanSlot> slotsOn(CalendarDay day) => [
    for (final slot in slots)
      if (slot.day == day) slot,
  ];

  List<PlanSlot> slotsInWeek(int week) => [
    for (final slot in slots)
      if (slot.week == week) slot,
  ];

  PlanSlot? slot(String id) => slots.where((slot) => slot.id == id).firstOrNull;

  EndurancePlan copy() => EndurancePlan(
    id: id,
    username: username,
    request: request,
    createdAt: createdAt,
    weeks: weeks,
    slots: [for (final slot in slots) slot.copy()],
    adjustments: [...adjustments],
    revision: revision,
    autoSyncGarmin: autoSyncGarmin,
    lastAdapted: lastAdapted,
    synced: {...synced},
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'username': username,
    'request': request.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'weeks': [for (final week in weeks) week.toJson()],
    'slots': [for (final slot in slots) slot.toJson()],
    'adjustments': [for (final entry in adjustments) entry.toJson()],
    'revision': revision,
    'autoSyncGarmin': autoSyncGarmin,
    'lastAdapted': ?lastAdapted?.iso,
    'synced': {for (final entry in synced.entries) entry.key: entry.value.toJson()},
  };

  /// Liest einen Plan. Gehört er einem anderen Benutzer als [username], ist das Ergebnis `null` – ein fremder Plan
  /// wird nie angezeigt, angepasst oder übertragen.
  static EndurancePlan? fromJson(Object? json, {required String username}) {
    if (json is! Map) return null;
    final id = json['id'];
    final owner = json['username'];
    final request = TrainingPlanRequest.fromJson(json['request']);
    final createdAt = json['createdAt'] is String ? DateTime.tryParse(json['createdAt'] as String) : null;
    final rawWeeks = json['weeks'];
    final rawSlots = json['slots'];
    if (id is! String || owner is! String || request == null || createdAt == null) return null;
    if (owner != username || request.username != username) return null;
    if (rawWeeks is! List || rawSlots is! List) return null;
    final weeks = rawWeeks.map(PlanWeekInfo.fromJson).nonNulls.toList();
    final slots = rawSlots.map(PlanSlot.fromJson).nonNulls.toList();
    if (weeks.isEmpty) return null;
    final rawAdjustments = json['adjustments'];
    final rawSynced = json['synced'];
    return EndurancePlan(
      id: id,
      username: owner,
      request: request,
      createdAt: createdAt,
      weeks: weeks,
      slots: slots,
      adjustments: rawAdjustments is List ? rawAdjustments.map(PlanAdjustmentEntry.fromJson).nonNulls.toList() : [],
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      autoSyncGarmin: json['autoSyncGarmin'] == true,
      lastAdapted: json['lastAdapted'] is String ? CalendarDay.tryParse(json['lastAdapted'] as String) : null,
      synced: {
        if (rawSynced is Map)
          for (final entry in rawSynced.entries)
            if (entry.key is String) entry.key as String: ?SyncedWorkout.fromJson(entry.value),
      },
    );
  }
}
