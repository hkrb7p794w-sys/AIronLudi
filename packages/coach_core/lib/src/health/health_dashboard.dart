import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import '../coach/trends.dart';
import '../garmin/daily_metrics.dart';
import '../util/enum_codec.dart';
import 'body_battery.dart';

/// Bereiche, nach denen die Gesundheitswerte gruppiert sind.
enum HealthCategory implements RawEnum {
  health('Gesundheit'),
  sleep('Schlaf'),
  recovery('Erholung'),
  load('Trainingsbelastung'),
  performance('Leistung');

  const HealthCategory(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Ein Widget im Gesundheitsbereich. Jedes zeigt einen gemessenen Wert; ohne Daten wird es nicht angeboten.
enum HealthWidget implements RawEnum {
  bodyBattery('Body Battery', ''),
  hrv('HRV', 'ms'),
  restingHeartRate('Ruhepuls', 'bpm'),
  sleep('Schlaf', 'h'),
  stress('Stress', ''),
  vo2Max('VO2max', ''),
  trainingLoad('Trainingsbelastung', ''),
  recoveryTime('Regenerationszeit', 'h'),
  readiness('Training Readiness', ''),
  steps('Schritte', ''),
  activeCalories('Aktivitätskalorien', 'kcal'),
  restingCalories('Ruhekalorien', 'kcal'),
  weight('Gewicht', 'kg'),
  heartRateRange('Puls tief/hoch', 'bpm'),
  respiration('Atemfrequenz', '/min'),
  spo2('SpO2', '%');

  const HealthWidget(this.title, this.unit);

  final String title;
  final String unit;

  @override
  String get rawValue => name;

  String get id => rawValue;

  int get digits => this == sleep || this == vo2Max || this == weight || this == respiration ? 1 : 0;

  HealthCategory get category => switch (this) {
    restingHeartRate ||
    heartRateRange ||
    weight ||
    spo2 ||
    respiration ||
    steps ||
    activeCalories ||
    restingCalories => HealthCategory.health,
    sleep => HealthCategory.sleep,
    bodyBattery || hrv || stress || recoveryTime || readiness => HealthCategory.recovery,
    trainingLoad => HealthCategory.load,
    vo2Max => HealthCategory.performance,
  };

  /// Höher ist besser (Farbe der Veränderung); `null` = neutral.
  bool? get higherIsBetter => switch (this) {
    bodyBattery || readiness || vo2Max || steps => true,
    restingHeartRate || stress || recoveryTime => false,
    _ => null,
  };

  /// Wert eines Tages. Gewicht kommt aus den Wägungen, die Belastung ersatzweise aus den Aktivitäten (`extra`).
  double? value(DailyMetrics metrics) => switch (this) {
    bodyBattery => BodyBatteryAnalysis.wakeValue(metrics) ?? metrics.bodyBatteryHigh,
    hrv => metrics.hrvLastNightAverage,
    restingHeartRate => metrics.restingHeartRate,
    sleep => metrics.sleepHours,
    stress => metrics.stressAverage,
    vo2Max => metrics.vo2Max,
    trainingLoad => metrics.acuteLoad,
    recoveryTime => metrics.recoveryHours,
    readiness => metrics.trainingReadiness,
    steps => metrics.steps,
    activeCalories => metrics.activeKilocalories,
    restingCalories => metrics.restingKilocalories,
    weight => null,
    heartRateRange => metrics.maxHeartRate,
    respiration => metrics.respirationWaking ?? metrics.respirationSleep,
    spo2 => metrics.spo2Average,
  };

  /// Woher der Wert kommen kann – für den Hinweis bei fehlenden Daten.
  String get sources => switch (this) {
    bodyBattery || stress || readiness || recoveryTime => 'nur Garmin',
    trainingLoad => 'Garmin-Konto oder eigene Aktivitäten',
    weight => 'Garmin, Apple Health oder eigene Wägungen',
    _ => 'Garmin oder Apple Health',
  };

  static HealthWidget? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Darstellung eines Widgets.
enum HealthWidgetStyle implements RawEnum {
  value('Nur Wert'),
  week('Verlauf 7 Tage'),
  month('Verlauf 30 Tage');

  const HealthWidgetStyle(this.label);

  final String label;

  @override
  String get rawValue => name;

  int get days => this == month ? 30 : 7;

  static HealthWidgetStyle? fromRaw(Object? raw) => enumFromRaw(values, raw);
}

/// Ein Widget mit Darstellung und Sichtbarkeit.
final class HealthDashboardEntry {
  HealthDashboardEntry({required this.kind, this.style = HealthWidgetStyle.week, this.hidden = false});

  final HealthWidget kind;
  HealthWidgetStyle style;
  bool hidden;

  String get id => kind.rawValue;

  Map<String, Object?> toJson() => {'kind': kind.rawValue, 'style': style.rawValue, 'hidden': hidden};

  /// Art ist Pflicht; Darstellung und Sichtbarkeit fallen auf den Standard zurück.
  static HealthDashboardEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = HealthWidget.fromRaw(json['kind']);
    if (kind == null) return null;
    final hidden = json['hidden'];
    return HealthDashboardEntry(
      kind: kind,
      style: HealthWidgetStyle.fromRaw(json['style']) ?? HealthWidgetStyle.week,
      hidden: hidden is bool && hidden,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HealthDashboardEntry && other.kind == kind && other.style == style && other.hidden == hidden;

  @override
  int get hashCode => Object.hash(kind, style, hidden);

  @override
  String toString() => 'HealthDashboardEntry($kind, $style, hidden: $hidden)';
}

/// Aufbau des Gesundheitsbereichs: hinzugefügte Widgets in Reihenfolge, je mit Darstellung und Sichtbarkeit.
/// Ausgeblendete bleiben in der Liste (Reihenfolge und Darstellung bleiben erhalten), entfernte nicht.
final class HealthDashboard {
  HealthDashboard({List<HealthDashboardEntry>? entries})
    : entries = _unique(entries ?? [for (final kind in standard) HealthDashboardEntry(kind: kind)]);

  List<HealthDashboardEntry> entries;

  static const standard = [
    HealthWidget.bodyBattery,
    HealthWidget.sleep,
    HealthWidget.hrv,
    HealthWidget.restingHeartRate,
    HealthWidget.stress,
    HealthWidget.trainingLoad,
    HealthWidget.recoveryTime,
    HealthWidget.steps,
  ];

  static List<HealthDashboardEntry> _unique(List<HealthDashboardEntry> entries) {
    final seen = <HealthWidget>{};
    return [
      for (final entry in entries)
        if (seen.add(entry.kind)) entry,
    ];
  }

  Map<String, Object?> toJson() => {
    'entries': [for (final entry in entries) entry.toJson()],
  };

  /// Unbekannte Widgets (aus einer neueren Version) und Doppelte fallen weg statt alles zu verwerfen. Ohne lesbare
  /// Liste `null` (wie der Swift-Decoder, der dann scheitert).
  static HealthDashboard? fromJson(Object? json) {
    if (json is! Map || json['entries'] is! List) return null;
    return HealthDashboard(entries: [for (final item in json['entries'] as List) ?HealthDashboardEntry.fromJson(item)]);
  }

  bool contains(HealthWidget kind) => entries.any((entry) => entry.kind == kind);

  void add(HealthWidget kind, {HealthWidgetStyle style = HealthWidgetStyle.week}) {
    if (contains(kind)) {
      setHidden(kind, false);
      return;
    }
    entries.add(HealthDashboardEntry(kind: kind, style: style));
  }

  void remove(HealthWidget kind) => entries.removeWhere((entry) => entry.kind == kind);

  void setHidden(HealthWidget kind, bool hidden) {
    for (final entry in entries) {
      if (entry.kind == kind) {
        entry.hidden = hidden;
        return;
      }
    }
  }

  void setStyle(HealthWidget kind, HealthWidgetStyle style) {
    for (final entry in entries) {
      if (entry.kind == kind) {
        entry.style = style;
        return;
      }
    }
  }

  /// Wie `move(fromOffsets:toOffset:)` in SwiftUI-Listen: [toOffset] zählt in der Liste vor dem Verschieben.
  void move({required Set<int> fromOffsets, required int toOffset}) {
    final moving = [
      for (final index in fromOffsets.toList()..sort())
        if (index < entries.length) entries[index],
    ];
    final before = fromOffsets.where((index) => index < toOffset).length;
    final rest = [
      for (var index = 0; index < entries.length; index++)
        if (!fromOffsets.contains(index)) entries[index],
    ];
    rest.insertAll(math.min(math.max(toOffset - before, 0), rest.length), moving);
    entries = rest;
  }

  /// Angezeigt: nicht ausgeblendet und mit Daten.
  List<HealthDashboardEntry> visible(Set<HealthWidget> available) =>
      entries.where((entry) => !entry.hidden && available.contains(entry.kind)).toList();

  /// Zum Hinzufügen: noch nicht in der Liste und mit Daten.
  List<HealthWidget> addable(Set<HealthWidget> available) =>
      HealthWidget.values.where((kind) => !contains(kind) && available.contains(kind)).toList();

  /// Widgets, für die in den letzten [window] Tagen mindestens ein Wert vorliegt.
  static Set<HealthWidget> available({
    required List<DailyMetrics> days,
    Map<HealthWidget, List<DayValue>> extra = const {},
    required CalendarDay today,
    int window = 30,
  }) {
    final start = today.adding(-(window - 1));
    final recent = days.where((metrics) => metrics.day >= start && metrics.day <= today).toList();
    return {
      for (final kind in HealthWidget.values)
        if (recent.any((metrics) => kind.value(metrics) != null) ||
            (extra[kind] ?? const []).any((value) => value.day >= start && value.day <= today))
          kind,
    };
  }

  /// Werte eines Widgets für die letzten [window] Tage (Tageswerte vor Ersatzquellen).
  static List<DayValue> series(
    HealthWidget kind, {
    required List<DailyMetrics> days,
    Map<HealthWidget, List<DayValue>> extra = const {},
    required CalendarDay today,
    required int window,
  }) {
    final start = today.adding(-(window - 1));
    final byDay = <CalendarDay, double>{};
    for (final value in extra[kind] ?? const <DayValue>[]) {
      if (value.day >= start && value.day <= today) byDay[value.day] = value.value;
    }
    for (final metrics in days) {
      if (metrics.day < start || metrics.day > today) continue;
      if (kind.value(metrics) case final value?) byDay[metrics.day] = value;
    }
    final keys = byDay.keys.toList()..sort();
    return [for (final day in keys) DayValue(day: day, value: byDay[day] ?? 0)];
  }
}
