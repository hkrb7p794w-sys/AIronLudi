import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../coach/template_item.dart';
import '../nutrition/nutrition_settings.dart';
import '../util/enum_codec.dart';
import 'session_match.dart';
import 'user_profile.dart';

/// Wochentag; der Rohwert ist die Zahl ab Montag = 0 (so steht er in Swift-Daten).
enum Weekday {
  monday('Mo', 'Montag'),
  tuesday('Di', 'Dienstag'),
  wednesday('Mi', 'Mittwoch'),
  thursday('Do', 'Donnerstag'),
  friday('Fr', 'Freitag'),
  saturday('Sa', 'Samstag'),
  sunday('So', 'Sonntag');

  const Weekday(this.short, this.long);

  final String short;
  final String long;

  factory Weekday.of(CalendarDay day) => values[day.weekdayIndex];

  int get rawValue => index;

  /// Der folgende Tag; auf den Sonntag folgt der Montag.
  Weekday get next => values[(index + 1) % 7];

  Weekday get previous => values[(index + 6) % 7];

  Weekday adding(int days) => values[((index + days) % 7 + 7) % 7];
}

/// Wie fordernd eine Einheit ist. Die meisten Einheiten sollen locker sein (Seiler 2006).
enum SessionIntensity implements RawEnum {
  easy('Locker'),
  hard('Intensiv'),
  long('Lang');

  const SessionIntensity(this.label);

  final String label;

  @override
  String get rawValue => name;

  /// Fordernd für die Erholung: intensive und lange Einheiten.
  bool get isDemanding => this != easy;
}

/// Eine Einheit an einem Tag: Sportart plus Intensität.
final class SessionSlot {
  const SessionSlot(this.sport, [this.intensity = SessionIntensity.easy]);

  final TrainingSport sport;
  final SessionIntensity intensity;

  String get id => '${sport.rawValue}-${intensity.rawValue}';

  /// Kurzer Name der Einheit.
  String get title => switch ((sport, intensity)) {
    (TrainingSport.run, SessionIntensity.easy) => 'Lockerer Lauf',
    (TrainingSport.run, SessionIntensity.hard) => 'Qualitätslauf (Tempo oder Intervalle)',
    (TrainingSport.run, SessionIntensity.long) => 'Langer Lauf',
    (TrainingSport.bike, SessionIntensity.easy) => 'Lockere Radfahrt',
    (TrainingSport.bike, SessionIntensity.hard) => 'Intensive Radeinheit',
    (TrainingSport.bike, SessionIntensity.long) => 'Lange Radfahrt',
    (TrainingSport.swim, SessionIntensity.easy) => 'Lockeres Schwimmen',
    (TrainingSport.swim, SessionIntensity.hard) => 'Intensives Schwimmen',
    (TrainingSport.swim, SessionIntensity.long) => 'Langes Schwimmen',
    (TrainingSport.strength, SessionIntensity.easy) => 'Kraft leicht (Technik, Mobilität)',
    (TrainingSport.strength, _) => 'Krafttraining',
    (TrainingSport.other, _) => 'Yoga / Beweglichkeit / Wandern',
  };

  /// Kurze Anleitung, wie die Einheit gemeint ist (allgemein, ohne Zahlen aus einem Trainingsplan).
  String get guide => switch ((sport, intensity)) {
    (TrainingSport.run || TrainingSport.bike || TrainingSport.swim, SessionIntensity.easy) =>
      'So locker, dass du dich dabei noch unterhalten kannst. Lieber etwas kürzer als zu hart.',
    (TrainingSport.run, SessionIntensity.hard) =>
      'Nach etwa 10 Minuten Einlaufen zügig laufen (Tempo oder Intervalle), danach locker auslaufen. '
          'Nur wenn du dich erholt fühlst.',
    (TrainingSport.bike || TrainingSport.swim, SessionIntensity.hard) =>
      'Nach dem Einrollen bzw. Einschwimmen zügige Intervalle, danach locker ausklingen lassen.',
    (TrainingSport.run || TrainingSport.bike || TrainingSport.swim, SessionIntensity.long) =>
      'Die längste Einheit der Woche, ruhig und gleichmäßig.',
    (TrainingSport.strength, SessionIntensity.easy) => 'Leichte Gewichte, saubere Technik und Beweglichkeit.',
    (TrainingSport.strength, _) => 'Ganzkörper oder Ober-/Unterkörper, mehrere Sätze je Übung mit sauberer Technik.',
    (TrainingSport.other, _) => 'Locker, beweglich bleiben und erholen.',
  };

  /// Ausdauereinheit mit hoher Belastung. Krafttraining zählt hier nicht: Es belastet andere Strukturen.
  bool get isDemandingEndurance => sport.isEndurance && intensity.isDemanding;

  /// Tagestyp der Ernährung: Nur lange Einheiten sind harte Tage, ein Intervalltraining dauert 30 bis 50 Minuten.
  DayType? get plannedDayType => switch (sport) {
    TrainingSport.other => null,
    TrainingSport.strength => DayType.light,
    _ => switch (intensity) {
      SessionIntensity.long => DayType.hard,
      SessionIntensity.hard => DayType.moderate,
      SessionIntensity.easy => DayType.light,
    },
  };

  Map<String, Object?> toJson() => {'sport': sport.rawValue, 'intensity': intensity.rawValue};

  static SessionSlot? fromJson(Object? json) {
    if (json is! Map) return null;
    final sport = enumFromRaw(TrainingSport.values, json['sport']);
    final intensity = enumFromRaw(SessionIntensity.values, json['intensity']);
    if (sport == null || intensity == null) return null;
    return SessionSlot(sport, intensity);
  }

  @override
  bool operator ==(Object other) => other is SessionSlot && other.sport == sport && other.intensity == intensity;

  @override
  int get hashCode => Object.hash(sport, intensity);

  @override
  String toString() => id;
}

/// Der Wochenplan: sieben Tage, an jedem keine, eine oder mehrere Einheiten. Unveränderlich; [withSlots] liefert eine
/// geänderte Kopie.
final class WeekSchedule {
  WeekSchedule([List<List<SessionSlot>> days = const []]) : days = _normalized(days);

  final List<List<SessionSlot>> days;

  static List<List<SessionSlot>> _normalized(List<List<SessionSlot>> days) {
    final result = [for (final day in days.take(7)) List<SessionSlot>.unmodifiable(day)];
    while (result.length < 7) {
      result.add(const []);
    }
    return List.unmodifiable(result);
  }

  List<SessionSlot> slots(Weekday weekday) => days[weekday.index];

  WeekSchedule withSlots(List<SessionSlot> slots, Weekday weekday) =>
      WeekSchedule([for (final day in Weekday.values) day == weekday ? slots : this.slots(day)]);

  List<Weekday> get trainingDays => Weekday.values.where((day) => slots(day).isNotEmpty).toList();

  List<Weekday> get restDays => Weekday.values.where((day) => slots(day).isEmpty).toList();

  int get sessionCount => days.fold(0, (sum, day) => sum + day.length);

  bool get isEmpty => sessionCount == 0;

  int count(TrainingSport sport) => days.fold(0, (sum, day) => sum + day.where((slot) => slot.sport == sport).length);

  /// Tage mit mindestens einer intensiven oder langen Ausdauereinheit.
  List<Weekday> get demandingEnduranceDays =>
      Weekday.values.where((day) => slots(day).any((slot) => slot.isDemandingEndurance)).toList();

  /// Nächster freier Tag innerhalb von [within] Tagen nach [weekday] (der Plan ist zyklisch).
  Weekday? nextRestDay(Weekday weekday, {required int within}) {
    for (var offset = 1; offset <= within; offset++) {
      final candidate = weekday.adding(offset);
      if (slots(candidate).isEmpty) return candidate;
    }
    return null;
  }

  /// Längste Folge aufeinanderfolgender Trainingstage (zyklisch: Sonntag und Montag hängen zusammen).
  int get longestStreak {
    final training = [for (final day in Weekday.values) slots(day).isNotEmpty];
    if (!training.contains(false)) return 7;
    var longest = 0;
    var current = 0;
    // Zweimal durchlaufen, damit Folgen über die Wochengrenze mitzählen.
    for (var index = 0; index < 14; index++) {
      if (training[index % 7]) {
        current += 1;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return longest > 7 ? 7 : longest;
  }

  /// Einträge für die Tagestyp-Erkennung der Ernährung (`NutritionPlanner.plannedDayType`).
  List<TemplateItem> templateItems(Weekday weekday, {List<int> runMinutes = const []}) {
    var runIndex = 0;
    return [
      for (final slot in slots(weekday))
        () {
          final kind = switch (slot.sport) {
            TrainingSport.run => TemplateItemKind.run,
            TrainingSport.bike => TemplateItemKind.bike,
            TrainingSport.swim => TemplateItemKind.swimOrLegs,
            TrainingSport.strength => TemplateItemKind.strength,
            TrainingSport.other => TemplateItemKind.optional,
          };
          var minutes = slot.sport == TrainingSport.other ? null : SessionMatcher.defaultMinutes(slot);
          if (slot.sport == TrainingSport.run && runIndex < runMinutes.length) {
            minutes = runMinutes[runIndex];
            runIndex += 1;
          }
          return TemplateItem(kind: kind, text: slot.title, minutes: minutes, plannedType: slot.plannedDayType);
        }(),
    ];
  }

  /// JSON wie in Swift: Liste von sieben Listen.
  List<Object?> toJson() => [
    for (final day in days) [for (final slot in day) slot.toJson()],
  ];

  /// Wie Swift: ist ein Tag oder eine Einheit nicht lesbar, gilt der leere Plan.
  static WeekSchedule fromJson(Object? json) {
    final days = listStrict(json, (day) => listStrict(day, SessionSlot.fromJson));
    return WeekSchedule(days ?? const []);
  }

  @override
  bool operator ==(Object other) => other is WeekSchedule && const DeepCollectionEquality().equals(days, other.days);

  @override
  int get hashCode => const DeepCollectionEquality().hash(days);

  @override
  String toString() => 'WeekSchedule($days)';
}
