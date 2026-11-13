import 'package:collection/collection.dart';

import '../calendar/calendar_day.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../garmin/strength_duplicates.dart';
import '../gym/gym_session.dart';
import '../nutrition/meal.dart';
import '../nutrition/nutrient.dart';
import '../nutrition/weight_trend.dart';
import '../profile/plan_adjustments.dart';
import '../profile/user_profile.dart';
import '../util/enum_codec.dart';
import '../util/swift_json.dart';
import 'coach_export.dart';

/// Welche Daten der KI-Export enthält.
enum ExportCategory implements RawEnum {
  gym('gym', 'Gym', 'Einheiten mit allen Sätzen, Trainingspläne, Übungsliste'),
  endurance('ausdauer', 'Ausdauertraining', 'Aktivitäten mit Dauer, Distanz, Herzfrequenz, Belastung'),
  health('gesundheit', 'Gesundheit', 'Schritte, Stress, Kalorien, VO2max, SpO2'),
  sleep('schlaf', 'Schlaf', 'Dauer, Score, Phasen, Einschlafzeit'),
  nutrition('ernaehrung', 'Ernährung', 'Mahlzeiten mit Positionen und Tagessummen'),
  weight('gewicht', 'Gewicht und Körper', 'Gewichtsverlauf'),
  recovery('erholung', 'Erholung', 'Ruhepuls, HRV, Body Battery, Readiness'),
  history('verlauf', 'Trainingsverlauf', 'Wochenübersicht: Einheiten, Minuten, Kilometer');

  const ExportCategory(this.rawValue, this.label, this.detail);

  @override
  final String rawValue;
  final String label;
  final String detail;
}

enum ExportFormat implements RawEnum {
  markdown('Markdown (lesbar)', 'md'),
  json('JSON (strukturiert)', 'json'),
  csv('CSV (Tabellen)', 'csv');

  const ExportFormat(this.label, this.fileExtension);

  final String label;
  final String fileExtension;

  @override
  String get rawValue => name;
}

/// Eine erzeugte Datei.
final class ExportFile {
  const ExportFile({required this.name, required this.content});

  final String name;
  final String content;

  @override
  bool operator ==(Object other) => other is ExportFile && other.name == name && other.content == content;

  @override
  int get hashCode => Object.hash(name, content);
}

/// Die Daten im Zeitraum, sortiert.
final class _Slice {
  _Slice(CoachExportInput input, {required CalendarDay from, required CalendarDay to}) {
    bool inRange(CalendarDay? day) => day != null && from <= day && day <= to;
    List<T> sorted<T>(Iterable<T> items, int Function(T, T) compare) {
      final list = items.toList();
      mergeSort(list, compare: compare);
      return list;
    }

    metrics = sorted(input.metrics.where((m) => inRange(m.day)), (a, b) => a.day.compareTo(b.day));
    // Krafttraining der Uhr steht schon unter Gym (mit Sätzen); doppelte Uploads fallen weg.
    final redundant = StrengthDuplicates.redundant(input.activities);
    endurance = sorted(
      input.activities.where((a) => inRange(a.day) && a.typeKey != 'strength_training' && !redundant.contains(a.id)),
      (a, b) => (a.startLocal ?? '').compareTo(b.startLocal ?? ''),
    );
    gym = sorted(input.gym.where((s) => inRange(s.day)), (a, b) => a.start.compareTo(b.start));
    meals = input.meals.where((meal) => inRange(meal.day)).toList();
    weights = sorted(input.weights.where((w) => inRange(w.day)), (a, b) => a.day.compareTo(b.day));
  }

  late final List<DailyMetrics> metrics;
  late final List<GarminActivity> endurance;
  late final List<GymSession> gym;
  late final List<ExportMeal> meals;
  late final List<WeightEntry> weights;
}

final class _Week {
  _Week(this.monday);

  final CalendarDay monday;
  int endurance = 0;
  int minutes = 0;
  double kilometers = 0;
  int gym = 0;
  int sets = 0;
}

/// KI-Export mit Auswahl der Daten. Fehlende Werte stehen als „–“ bzw. `null` da – nie als 0, damit eine externe KI
/// nichts hineinliest, was nicht gemessen wurde.
abstract final class DataExport {
  static List<ExportCategory> _ordered(Set<ExportCategory> categories) =>
      ExportCategory.values.where(categories.contains).toList();

  // Markdown

  /// [withImportFormat]: Anleitung samt Antwortformat (`CoachImport`) für den manuellen KI-Coach voranstellen.
  static String markdown(
    CoachExportInput input, {
    required CalendarDay from,
    required CalendarDay to,
    required Set<ExportCategory> categories,
    bool withImportFormat = false,
  }) {
    final data = _Slice(input, from: from, to: to);
    final lines = [
      '# AIronLudi – Daten ${from.iso} bis ${to.iso}',
      '',
      'Enthalten: ${_ordered(categories).map((category) => category.label).join(', ')}',
      'Fehlende Werte stehen als „–“ da und bedeuten: nicht gemessen.',
      '',
      if (withImportFormat) ...CoachExport.instructions(input),
      ...CoachExport.profile(input),
    ];
    if (categories.contains(ExportCategory.recovery)) {
      lines.addAll(
        table(
          'Erholung',
          ['Datum', 'Ruhepuls', 'HRV (ms)', 'HRV-Status', 'Body Battery max', 'Readiness'],
          data.metrics,
          (day) {
            return [
              day.day.iso,
              num(day.restingHeartRate),
              num(day.hrvLastNightAverage),
              day.hrvStatus ?? '–',
              num(day.bodyBatteryHigh),
              num(day.trainingReadiness),
            ];
          },
        ),
      );
    }
    if (categories.contains(ExportCategory.sleep)) {
      lines.addAll(
        table(
          'Schlaf',
          ['Datum', 'Schlaf (h)', 'Score', 'Tief (h)', 'REM (h)', 'Wach (min)'],
          data.metrics.where((day) => day.sleepSeconds != null).toList(),
          (day) => [
            day.day.iso,
            num(day.sleepHours),
            num(day.sleepScore),
            hours(day.deepSleepSeconds),
            hours(day.remSleepSeconds),
            num(day.awakeSleepSeconds == null ? null : day.awakeSleepSeconds! / 60),
          ],
        ),
      );
    }
    if (categories.contains(ExportCategory.health)) {
      lines.addAll(
        table(
          'Gesundheit',
          ['Datum', 'Schritte', 'Stress', 'aktive kcal', 'VO2max', 'SpO2'],
          data.metrics,
          (day) => [
            day.day.iso,
            num(day.steps),
            num(day.stressAverage),
            num(day.activeKilocalories),
            num(day.vo2Max),
            num(day.spo2Average),
          ],
        ),
      );
    }
    if (categories.contains(ExportCategory.endurance)) lines.addAll(CoachExport.activities(data.endurance));
    if (categories.contains(ExportCategory.gym)) lines.addAll(CoachExport.gym(data.gym));
    if (categories.contains(ExportCategory.nutrition)) lines.addAll(CoachExport.meals(data.meals));
    if (categories.contains(ExportCategory.weight)) lines.addAll(CoachExport.weights(data.weights));
    if (categories.contains(ExportCategory.history)) {
      lines.addAll(
        table(
          'Trainingsverlauf je Woche',
          ['Woche ab', 'Ausdauer-Einheiten', 'Ausdauer (min)', 'Kilometer', 'Krafteinheiten', 'Sätze'],
          _weeks(data, from: from, to: to),
          (week) => [
            week.monday.iso,
            '${week.endurance}',
            '${week.minutes}',
            num(week.kilometers),
            '${week.gym}',
            '${week.sets}',
          ],
        ),
      );
    }
    lines.addAll(CoachExport.sources(input.userSources));
    if (categories.contains(ExportCategory.gym) || withImportFormat) lines.addAll(CoachExport.exerciseList(input));
    return lines.join('\n');
  }

  // JSON

  static double? _div(double? value, double divisor) => value == null ? null : value / divisor;

  static String json(
    CoachExportInput input, {
    required CalendarDay from,
    required CalendarDay to,
    required Set<ExportCategory> categories,
  }) {
    final data = _Slice(input, from: from, to: to);
    final root = <String, Object?>{
      'export': {
        'app': 'AIronLudi',
        'von': from.iso,
        'bis': to.iso,
        'kategorien': [for (final category in _ordered(categories)) category.rawValue],
        'hinweis': 'null = nicht gemessen. Gewicht in kg, Zeiten in Minuten, Distanz in km.',
      },
      'profil': {
        'ziel': input.profile.goal.label,
        'planart': input.profile.mode == ProfileMode.season ? 'saisonplan' : 'eigener_wochenplan',
        'sportarten': [for (final sport in input.profile.sports) sport.label],
      },
    };
    if (categories.contains(ExportCategory.recovery)) {
      root['erholung'] = [
        for (final day in data.metrics)
          {
            'datum': day.day.iso,
            'ruhepuls': value(day.restingHeartRate),
            'hrv_ms': value(day.hrvLastNightAverage),
            'hrv_status': day.hrvStatus,
            'body_battery_max': value(day.bodyBatteryHigh),
            'readiness': value(day.trainingReadiness),
          },
      ];
    }
    if (categories.contains(ExportCategory.sleep)) {
      root['schlaf'] = [
        for (final day in data.metrics)
          if (day.sleepSeconds != null)
            {
              'datum': day.day.iso,
              'stunden': value(day.sleepHours),
              'score': value(day.sleepScore),
              'tief_min': value(_div(day.deepSleepSeconds, 60)),
              'rem_min': value(_div(day.remSleepSeconds, 60)),
              'wach_min': value(_div(day.awakeSleepSeconds, 60)),
            },
      ];
    }
    if (categories.contains(ExportCategory.health)) {
      root['gesundheit'] = [
        for (final day in data.metrics)
          {
            'datum': day.day.iso,
            'schritte': value(day.steps),
            'stress': value(day.stressAverage),
            'aktive_kcal': value(day.activeKilocalories),
            'vo2max': value(day.vo2Max),
            'spo2': value(day.spo2Average),
          },
      ];
    }
    if (categories.contains(ExportCategory.endurance)) {
      root['ausdauer'] = [
        for (final activity in data.endurance)
          {
            'start': activity.startLocal,
            'sport': activity.typeKey,
            'name': activity.name,
            'dauer_min': value(_div(activity.durationSeconds, 60)),
            'distanz_km': value(_div(activity.distanceMeters, 1000)),
            'hf_schnitt': value(activity.averageHeartRate),
            'hf_max': value(activity.maxHeartRate),
            'belastung': value(activity.trainingLoad),
            'aerober_te': value(activity.aerobicTrainingEffect),
          },
      ];
    }
    if (categories.contains(ExportCategory.gym)) {
      root['gym'] = [
        for (final session in data.gym)
          {
            'datum': session.day.iso,
            'titel': session.title,
            'dauer_min': value(switch (session.end) {
              final end? => end.difference(session.start).inMicroseconds / 1e6 / 60,
              null => null,
            }),
            'uebungen': [
              for (final exercise in session.exercises)
                if (exercise.loggedSets.isNotEmpty)
                  {
                    'id': exercise.exerciseID,
                    'name': exercise.name,
                    'saetze': [
                      for (final set in exercise.loggedSets)
                        {
                          'kg': set.weightKg,
                          'wdh': set.reps.toDouble(),
                          'rir': set.rir?.toDouble(),
                          'art': set.kind.rawValue,
                        },
                    ],
                  },
            ],
          },
      ];
      root['trainingsplaene'] = [
        for (final routine in input.routines)
          {
            'name': routine.name,
            'uebungen': [
              for (final item in routine.items)
                {
                  'id': item.exerciseID,
                  'name': item.name,
                  'saetze': item.sets.toDouble(),
                  'wdh_min': item.lowerReps.toDouble(),
                  'wdh_max': item.upperReps.toDouble(),
                  'kg': value(item.weightKg),
                },
            ],
          },
      ];
    }
    if (categories.contains(ExportCategory.nutrition)) {
      final byDay = groupBy(data.meals, (ExportMeal meal) => meal.day);
      root['ernaehrung'] = [
        for (final day in byDay.keys.toList()..sort())
          () {
            final meals = byDay[day]!;
            final totals = NutritionSummary.totals(meals.expand((meal) => meal.items));
            return {
              'datum': day.iso,
              'kcal': value(totals[Nutrient.kcal]),
              'protein_g': value(totals[Nutrient.protein]),
              'kohlenhydrate_g': value(totals[Nutrient.carbs]),
              'fett_g': value(totals[Nutrient.fat]),
              'ballaststoffe_g': value(totals[Nutrient.fiber]),
              'mahlzeiten': [
                for (final meal in meals)
                  {
                    'kategorie': meal.category,
                    'titel': meal.title,
                    'positionen': [
                      for (final item in meal.items) {'name': item.name, 'g': item.grams.roundToDouble()},
                    ],
                  },
              ],
            };
          }(),
      ];
    }
    if (categories.contains(ExportCategory.weight)) {
      root['gewicht'] = [
        for (final entry in WeightTrend.merged(data.weights)) {'datum': entry.day.iso, 'kg': entry.kilograms},
      ];
    }
    if (categories.contains(ExportCategory.history)) {
      root['verlauf_wochen'] = [
        for (final week in _weeks(data, from: from, to: to))
          {
            'woche_ab': week.monday.iso,
            'ausdauer_einheiten': week.endurance.toDouble(),
            'ausdauer_min': week.minutes.toDouble(),
            'kilometer': week.kilometers,
            'krafteinheiten': week.gym.toDouble(),
            'saetze': week.sets.toDouble(),
          },
      ];
    }
    return swiftPrettyJson(root);
  }

  // CSV

  /// Eine Tabelle je Kategorie (Komma als Trenner, Punkt als Dezimalzeichen, leere Zelle = nicht gemessen).
  static List<ExportFile> csv(
    CoachExportInput input, {
    required CalendarDay from,
    required CalendarDay to,
    required Set<ExportCategory> categories,
  }) {
    final data = _Slice(input, from: from, to: to);
    final files = <ExportFile>[];
    void add(ExportCategory category, List<String> header, List<List<String>> rows) {
      if (!categories.contains(category)) return;
      files.add(
        ExportFile(
          name: 'IronLudi-${category.rawValue}-${from.iso}-bis-${to.iso}.csv',
          content: '${[header, ...rows].map((row) => row.map(csvCell).join(',')).join('\n')}\n',
        ),
      );
    }

    add(
      ExportCategory.recovery,
      ['datum', 'ruhepuls', 'hrv_ms', 'hrv_status', 'body_battery_max', 'readiness'],
      [
        for (final day in data.metrics)
          [
            day.day.iso,
            raw(day.restingHeartRate),
            raw(day.hrvLastNightAverage),
            day.hrvStatus ?? '',
            raw(day.bodyBatteryHigh),
            raw(day.trainingReadiness),
          ],
      ],
    );
    add(
      ExportCategory.sleep,
      ['datum', 'stunden', 'score', 'tief_min', 'rem_min', 'wach_min'],
      [
        for (final day in data.metrics)
          if (day.sleepSeconds != null)
            [
              day.day.iso,
              raw(day.sleepHours),
              raw(day.sleepScore),
              raw(_div(day.deepSleepSeconds, 60)),
              raw(_div(day.remSleepSeconds, 60)),
              raw(_div(day.awakeSleepSeconds, 60)),
            ],
      ],
    );
    add(
      ExportCategory.health,
      ['datum', 'schritte', 'stress', 'aktive_kcal', 'vo2max', 'spo2'],
      [
        for (final day in data.metrics)
          [
            day.day.iso,
            raw(day.steps),
            raw(day.stressAverage),
            raw(day.activeKilocalories),
            raw(day.vo2Max),
            raw(day.spo2Average),
          ],
      ],
    );
    add(
      ExportCategory.endurance,
      ['start', 'sport', 'name', 'dauer_min', 'distanz_km', 'hf_schnitt', 'hf_max', 'belastung', 'aerober_te'],
      [
        for (final activity in data.endurance)
          [
            activity.startLocal ?? '',
            activity.typeKey ?? '',
            activity.name ?? '',
            raw(_div(activity.durationSeconds, 60)),
            raw(_div(activity.distanceMeters, 1000)),
            raw(activity.averageHeartRate),
            raw(activity.maxHeartRate),
            raw(activity.trainingLoad),
            raw(activity.aerobicTrainingEffect),
          ],
      ],
    );
    add(
      ExportCategory.gym,
      ['datum', 'einheit', 'uebung_id', 'uebung', 'satz', 'kg', 'wdh', 'rir', 'art'],
      [
        for (final session in data.gym)
          for (final exercise in session.exercises)
            for (final (index, set) in exercise.loggedSets.indexed)
              [
                session.day.iso,
                session.title,
                exercise.exerciseID,
                exercise.name,
                '${index + 1}',
                raw(set.weightKg),
                '${set.reps}',
                set.rir?.toString() ?? '',
                set.kind.rawValue,
              ],
      ],
    );
    final meals = [...data.meals];
    mergeSort(meals, compare: (a, b) => a.day.compareTo(b.day));
    add(
      ExportCategory.nutrition,
      ['datum', 'kategorie', 'mahlzeit', 'position', 'g', 'kcal', 'protein_g', 'kohlenhydrate_g', 'fett_g'],
      [
        for (final meal in meals)
          for (final item in meal.items)
            [
              meal.day.iso,
              meal.category,
              meal.title,
              item.name,
              raw(item.grams.roundToDouble()),
              raw(item.amounts[Nutrient.kcal]),
              raw(item.amounts[Nutrient.protein]),
              raw(item.amounts[Nutrient.carbs]),
              raw(item.amounts[Nutrient.fat]),
            ],
      ],
    );
    add(
      ExportCategory.weight,
      ['datum', 'kg'],
      [
        for (final entry in WeightTrend.merged(data.weights)) [entry.day.iso, raw(entry.kilograms)],
      ],
    );
    add(
      ExportCategory.history,
      ['woche_ab', 'ausdauer_einheiten', 'ausdauer_min', 'kilometer', 'krafteinheiten', 'saetze'],
      [
        for (final week in _weeks(data, from: from, to: to))
          [
            week.monday.iso,
            '${week.endurance}',
            '${week.minutes}',
            raw(week.kilometers),
            '${week.gym}',
            '${week.sets}',
          ],
      ],
    );
    return files;
  }

  /// Wie viele Einträge je Kategorie im Zeitraum vorhanden sind (für die Auswahl in der App).
  static Map<ExportCategory, int> counts(CoachExportInput input, {required CalendarDay from, required CalendarDay to}) {
    final data = _Slice(input, from: from, to: to);
    return {
      ExportCategory.gym: data.gym.length,
      ExportCategory.endurance: data.endurance.length,
      ExportCategory.health: data.metrics.where((d) => d.steps != null || d.stressAverage != null).length,
      ExportCategory.sleep: data.metrics.where((d) => d.sleepSeconds != null).length,
      ExportCategory.nutrition: {for (final meal in data.meals) meal.day}.length,
      ExportCategory.weight: WeightTrend.merged(data.weights).length,
      ExportCategory.recovery: data.metrics
          .where((d) => d.restingHeartRate != null || d.hrvLastNightAverage != null)
          .length,
      ExportCategory.history: data.gym.length + data.endurance.length,
    };
  }

  // Bausteine

  static List<_Week> _weeks(_Slice data, {required CalendarDay from, required CalendarDay to}) {
    final weeks = <CalendarDay, _Week>{};
    for (var monday = PlanAdjustments.monday(from); monday <= to; monday = monday.adding(7)) {
      weeks[monday] = _Week(monday);
    }
    for (final activity in data.endurance) {
      final day = activity.day;
      if (day == null) continue;
      final key = PlanAdjustments.monday(day);
      weeks.putIfAbsent(key, () => _Week(key))
        ..endurance += 1
        ..minutes += ((activity.durationSeconds ?? 0) / 60).round()
        ..kilometers += ((activity.distanceMeters ?? 0) / 100).roundToDouble() / 10;
    }
    for (final session in data.gym) {
      final key = PlanAdjustments.monday(session.day);
      weeks.putIfAbsent(key, () => _Week(key))
        ..gym += 1
        ..sets += session.exercises.fold(0, (sum, exercise) => sum + exercise.doneSets.length);
    }
    return weeks.values.toList()..sort((a, b) => a.monday.compareTo(b.monday));
  }

  static List<String> table<T>(String title, List<String> header, List<T> rows, List<String> Function(T) cells) {
    if (rows.isEmpty) return [];
    return [
      '## $title',
      '',
      '| ${header.join(' | ')} |',
      '|${'---|' * header.length}',
      for (final row in rows) '| ${cells(row).map((cell) => cell.replaceAll('|', '/')).join(' | ')} |',
      '',
    ];
  }

  static String num(double? value) => value == null ? '–' : CoachExport.number(value);

  static String hours(double? seconds) => num(seconds == null ? null : (seconds / 360).roundToDouble() / 10);

  /// Auf zwei Stellen gerundet; ganzzahlig ohne Nachkommastelle (wie `String(Double)` in Swift für kurze Werte).
  static String raw(double? value) {
    if (value == null || !value.isFinite) return '';
    final rounded = (value * 100).roundToDouble() / 100;
    return rounded == rounded.roundToDouble() ? rounded.truncate().toString() : rounded.toString();
  }

  static double? value(double? number) {
    if (number == null || !number.isFinite) return null;
    return (number * 100).roundToDouble() / 100;
  }

  static String csvCell(String text) {
    if (!text.contains(',') && !text.contains('"') && !text.contains('\n')) return text;
    return '"${text.replaceAll('"', '""')}"';
  }
}
