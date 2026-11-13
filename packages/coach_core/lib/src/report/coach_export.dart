import 'package:collection/collection.dart';

import '../analysis/activity_details.dart';
import '../analysis/activity_report.dart';
import '../calendar/calendar_day.dart';
import '../evidence/user_sources.dart';
import '../fit/fit_decoder.dart';
import '../garmin/daily_metrics.dart';
import '../garmin/garmin_activity.dart';
import '../gym/exercise_library.dart';
import '../gym/gym_session.dart';
import '../gym/routine.dart';
import '../nutrition/meal.dart';
import '../nutrition/nutrient.dart';
import '../nutrition/weight_trend.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';

/// Eine Mahlzeit, wie sie exportiert wird (die App liest sie aus der Datenbank).
final class ExportMeal {
  const ExportMeal({required this.day, required this.category, required this.title, required this.items});

  final CalendarDay day;
  final String category;
  final String title;
  final List<MealItem> items;
}

/// Alles, was ein Export braucht.
final class CoachExportInput {
  CoachExportInput({
    required this.profile,
    required this.schedule,
    required this.routines,
    required this.custom,
    required this.equipment,
    required this.metrics,
    required this.activities,
    required this.gym,
    required this.meals,
    required this.weights,
    this.userSources = const [],
    this.reports = const [],
  });

  final UserProfile profile;
  final WeekSchedule schedule;
  final List<Routine> routines;
  final List<ExerciseInfo> custom;
  final Set<Equipment> equipment;
  final List<DailyMetrics> metrics;
  final List<GarminActivity> activities;
  final List<GymSession> gym;
  final List<ExportMeal> meals;
  final List<WeightEntry> weights;
  final List<UserSource> userSources;

  /// Vollständige Berichte aus den Aufzeichnungen der Uhr (Runden, Auswertung), soweit übertragen.
  List<ActivityReport> reports;
}

final class ExportPreset {
  const ExportPreset(this.label, this.days);

  final String label;
  final int days;

  int get id => days;
}

/// Export für den „manuellen KI-Coach“: alle Daten eines Zeitraums als eine Markdown-Datei, die sich in ChatGPT,
/// Gemini oder Claude hochladen lässt. Oben steht die Anleitung für die KI samt Antwortformat (`CoachImport`),
/// damit ihre Vorschläge wieder in die App übernommen werden können.
abstract final class CoachExport {
  static const presets = [
    ExportPreset('7 Tage', 7),
    ExportPreset('30 Tage', 30),
    ExportPreset('90 Tage', 90),
    ExportPreset('1 Jahr', 365),
  ];

  static String markdown(CoachExportInput input, {required CalendarDay from, required CalendarDay to}) {
    bool inRange(CalendarDay? day) => day != null && from <= day && day <= to;
    List<T> sorted<T>(Iterable<T> items, int Function(T, T) compare) {
      final list = items.toList();
      mergeSort(list, compare: compare);
      return list;
    }

    return [
      '# AIronLudi – Trainingsdaten ${from.iso} bis ${to.iso}',
      '',
      ...instructions(input),
      ...profile(input),
      ...metrics(sorted(input.metrics.where((m) => inRange(m.day)), (a, b) => a.day.compareTo(b.day))),
      ...activities(
        sorted(
          input.activities.where((a) => inRange(a.day)),
          (a, b) => (a.startLocal ?? '').compareTo(b.startLocal ?? ''),
        ),
      ),
      ...reports(
        sorted(input.reports.where((r) => inRange(r.day)), (a, b) {
          final byDay = a.day.compareTo(b.day);
          return byDay != 0 ? byDay : a.id.compareTo(b.id);
        }),
      ),
      ...gym(sorted(input.gym.where((s) => inRange(s.day)), (a, b) => a.start.compareTo(b.start))),
      ...meals(input.meals.where((meal) => inRange(meal.day)).toList()),
      ...weights(sorted(input.weights.where((w) => inRange(w.day)), (a, b) => a.day.compareTo(b.day))),
      ...sources(input.userSources),
      ...exerciseList(input),
    ].join('\n');
  }

  // Abschnitte

  static List<String> instructions(CoachExportInput input) {
    final personal = input.profile.mode == ProfileMode.personal;
    return [
      '## Anleitung für die KI',
      '',
      'Du bist mein Trainings- und Ernährungscoach. Analysiere die Daten unten: Erholung (Ruhepuls, HRV, Schlaf), '
          'Trainingsumfang und -verteilung, Fortschritt im Krafttraining, Ernährung und Gewicht. Nenne die '
          'wichtigsten Erkenntnisse und konkrete Verbesserungen. Stütze dich auf anerkannte sportwissenschaftliche '
          'Empfehlungen und nenne Zahlen nur, wenn sie aus den Daten folgen.',
      '',
      'Wenn du Änderungen an meinen Trainingsplänen vorschlägst, gib sie zusätzlich am Ende in genau einem '
          'Codeblock mit der Sprache `ironludi` aus (JSON, nur die Teile, die du ändern willst). Die App prüft den '
          'Block mit ihren Regeln, bevor sie ihn übernimmt:',
      '',
      '```ironludi',
      '{',
      '  "routinen": {',
      '    "modus": "ergaenzen",',
      '    "liste": [',
      '      {"name": "Push A", "uebungen": [',
      '        {"id": "bankdruecken", "saetze": 3, "wdh_min": 6, "wdh_max": 10, "pause": 120, "gewicht": 55}',
      '      ]}',
      '    ]',
      '  },',
      if (personal) ...[
        '  "wochenplan": {',
        '    "gilt_fuer": "dauerhaft",',
        '    "tage": {"mo": [{"sport": "strength", "intensitaet": "hard"}], "di": [], "mi": '
            '[{"sport": "run", "intensitaet": "easy"}]}',
        '  },',
      ],
      '  "hinweise": ["Kurzer Hinweis, der in der App angezeigt wird"]',
      '}',
      '```',
      '',
      '- `routinen.modus`: `ergaenzen` (zu meinen Routinen hinzufügen bzw. gleichnamige ersetzen) oder `ersetzen` '
          '(alle Routinen ersetzen). Übungen nur mit einer `id` aus der Liste „Erlaubte Übungen“ am Ende. '
          '`saetze` 1–5, `pause` in Sekunden, `gewicht` in kg (optional), bei Übungen mit Sekunden sind '
          '`wdh_min`/`wdh_max` Sekunden.',
      if (personal)
        '- `wochenplan.gilt_fuer`: `dauerhaft` oder `naechste_woche`. Tage `mo`–`so`; `sport`: run, bike, swim, '
            'strength, other; `intensitaet`: easy, hard, long. Nicht genannte Tage bleiben unverändert, `[]` = frei.'
      else
        '- Mein Ausdauerplan ist ein fester Saisonplan; schlage dafür keine Wochenplan-Änderungen vor.',
      '- Ernährungsziele berechnet die App selbst (mit Schutzgrenzen); Vorschläge dazu bitte nur als Text.',
      '',
    ];
  }

  static List<String> profile(CoachExportInput input) {
    final profile = input.profile;
    final event = profile.event;
    return [
      '## Profil',
      '',
      '- Planart: ${profile.mode == ProfileMode.season ? 'fester Saisonplan (Triathlon, Krafttraining nach Routinen)' : 'eigener Wochenplan'}',
      '- Ziel: ${profile.goal.label}',
      '- Sportarten: ${profile.sports.map((sport) => '${sport.label} (${profile.level(sport).label})').join(', ')}',
      if (event != null) '- Wettkampf: ${event.name} am ${event.date.iso}',
      if (profile.health.isNotEmpty) '- Gesundheit: ${profile.health.map((flag) => flag.label).join('; ')}',
      '- Ausstattung: ${Equipment.values.where(input.equipment.contains).map((item) => item.label).join(', ')}',
      if (profile.mode == ProfileMode.personal) ...[
        '',
        '### Wochenplan',
        for (final weekday in Weekday.values)
          '- ${weekday.long}: ${input.schedule.slots(weekday).isEmpty ? 'frei' : input.schedule.slots(weekday).map((slot) => slot.title).join(', ')}',
      ],
      if (input.routines.isNotEmpty) ...[
        '',
        '### Krafttraining-Routinen',
        for (final routine in input.routines)
          '- ${routine.name}: ${routine.items.map((item) {
            var text = '${item.name} [${item.exerciseID}] ${item.sets}×${item.lowerReps}–${item.upperReps}';
            if (item.weightKg case final weight?) text += ' @ ${number(weight)} kg';
            return text;
          }).join('; ')}',
      ],
      '',
    ];
  }

  static String _cell(double? value) => value == null ? '–' : number(value);

  static List<String> metrics(List<DailyMetrics> days) {
    if (days.isEmpty) return [];
    return [
      '## Tageswerte',
      '',
      '| Datum | Ruhepuls | HRV (ms) | Schlaf (h) | Schlaf-Score | Body Battery max | Stress | Schritte | '
          'aktive kcal | VO2max |',
      '|---|---|---|---|---|---|---|---|---|---|',
      for (final day in days)
        '| ${day.day.iso} | ${[day.restingHeartRate, day.hrvLastNightAverage, day.sleepHours, day.sleepScore, day.bodyBatteryHigh, day.stressAverage, day.steps, day.activeKilocalories, day.vo2Max].map(_cell).join(' | ')} |',
      '',
    ];
  }

  static List<String> activities(List<GarminActivity> activities) {
    if (activities.isEmpty) return [];
    return [
      '## Ausdauer und andere Aktivitäten',
      '',
      '| Start | Sport | Name | Dauer (min) | Distanz (km) | Ø HF | Max HF | Belastung | Aerober TE |',
      '|---|---|---|---|---|---|---|---|---|',
      for (final activity in activities)
        '| ${[
          activity.startLocal ?? '–',
          activity.typeKey ?? '–',
          activity.name ?? '–',
          ...[activity.durationSeconds == null ? null : (activity.durationSeconds! / 60).roundToDouble(), activity.distanceMeters == null ? null : (activity.distanceMeters! / 10).roundToDouble() / 100, activity.averageHeartRate, activity.maxHeartRate, activity.trainingLoad, activity.aerobicTrainingEffect].map(_cell),
        ].map((cell) => cell.replaceAll('|', '/')).join(' | ')} |',
      '',
    ];
  }

  /// Je Aktivität die Aussagen der Regeln und die Runden der Uhr (höchstens 30 je Einheit).
  static List<String> reports(List<ActivityReport> reports) {
    if (reports.isEmpty) return [];
    final lines = ['## Auswertung und Runden der Aufzeichnungen', ''];
    for (final report in reports) {
      lines
        ..add('### ${report.name ?? 'Aktivität'} (${report.day.iso})')
        ..addAll([for (final finding in ActivityFindings.findings(report)) '- ${finding.text}']);
      final laps = report.laps.take(30).toList();
      if (laps.length > 1) {
        lines
          ..addAll(['', '| Runde | Art | Zeit (s) | Distanz (m) | Ø Tempo | Ø HF | Max HF |'])
          ..add('|---|---|---|---|---|---|---|');
        for (var index = 0; index < laps.length; index++) {
          final lap = laps[index];
          var speed = lap.averageSpeed;
          final (seconds, meters) = (lap.timerSeconds, lap.distanceMeters);
          if (speed == null && seconds != null && meters != null && seconds > 0 && meters > 0) speed = meters / seconds;
          var kind = '–';
          if (lap.intensity case final intensity?) {
            kind = lap.isWork
                ? 'Belastung'
                : intensity == FitLapIntensity.warmup
                ? 'Einlaufen'
                : 'Pause';
          }
          final cells = [
            '${index + 1}',
            kind,
            _cell(lap.timerSeconds),
            _cell(lap.distanceMeters),
            speed == null ? '–' : ActivityDetails.speed(speed, report.sport),
            _cell(lap.averageHeartRate),
            _cell(lap.maxHeartRate),
          ];
          lines.add('| ${cells.join(' | ')} |');
        }
      }
      lines.add('');
    }
    return lines;
  }

  static List<String> gym(List<GymSession> sessions) {
    if (sessions.isEmpty) return [];
    final lines = ['## Krafttraining (Gewicht × Wiederholungen je Satz)', ''];
    for (final session in sessions) {
      final minutes = switch (session.end) {
        final end? => (end.difference(session.start).inMicroseconds / 1e6 / 60).round(),
        null => null,
      };
      lines.add('### ${session.day.iso} – ${session.title}${minutes == null ? '' : ' ($minutes min)'}');
      for (final exercise in session.exercises) {
        final sets = [
          for (final set in exercise.doneSets)
            '${set.weightKg > 0 ? '${number(set.weightKg)}×${set.reps}' : '${set.reps}'}'
                '${set.rir == null ? '' : ' (RIR ${set.rir})'}',
        ];
        if (sets.isEmpty) continue;
        lines.add('- ${exercise.name} [${exercise.exerciseID}]: ${sets.join(', ')}');
      }
      lines.add('');
    }
    return lines;
  }

  static List<String> meals(List<ExportMeal> meals) {
    if (meals.isEmpty) return [];
    final lines = ['## Ernährung', ''];
    final byDay = groupBy(meals, (ExportMeal meal) => meal.day);
    for (final day in byDay.keys.toList()..sort()) {
      final entries = byDay[day]!;
      final total = <Nutrient, double>{};
      for (final item in entries.expand((meal) => meal.items)) {
        for (final nutrient in const [Nutrient.kcal, Nutrient.protein, Nutrient.carbs, Nutrient.fat]) {
          total[nutrient] = (total[nutrient] ?? 0) + (item.amounts[nutrient] ?? 0);
        }
      }
      String rounded(Nutrient nutrient) => number((total[nutrient] ?? 0).roundToDouble());
      lines.add(
        '### ${day.iso}: ${rounded(Nutrient.kcal)} kcal, Protein ${rounded(Nutrient.protein)} g, Kohlenhydrate '
        '${rounded(Nutrient.carbs)} g, Fett ${rounded(Nutrient.fat)} g',
      );
      for (final meal in entries) {
        final items = meal.items.map((item) => '${item.name} ${number(item.grams.roundToDouble())} g').join(', ');
        lines.add('- ${meal.category}: ${meal.title}${items.isEmpty ? '' : ' – $items'}');
      }
      lines.add('');
    }
    return lines;
  }

  static List<String> weights(List<WeightEntry> entries) {
    final merged = WeightTrend.merged(entries);
    if (merged.isEmpty) return [];
    return ['## Gewicht', '', for (final entry in merged) '- ${entry.day.iso}: ${number(entry.kilograms)} kg', ''];
  }

  /// Eigene Quellen, damit die externe KI sie ebenfalls berücksichtigt.
  static List<String> sources(List<UserSource> sources) {
    final valid = sources.where((source) => source.isValid).toList();
    if (valid.isEmpty) return [];
    return [
      '## Eigene wissenschaftliche Quellen (bitte berücksichtigen)',
      '',
      for (final source in valid)
        '- ${source.citation}${source.reference.isEmpty ? '' : ' (${source.reference})'}: ${source.statement}',
      '',
    ];
  }

  static List<String> exerciseList(CoachExportInput input) => [
    '## Erlaubte Übungen (id – Name – Muskel)',
    '',
    for (final exercise in [...ExerciseLibrary.all, ...input.custom])
      if (exercise.isAvailable(input.equipment))
        '- ${exercise.id} – ${exercise.name} – ${exercise.group.rawValue}'
            '${exercise.tracking == ExerciseTracking.time ? ' (Sekunden)' : ''}',
    '',
  ];

  /// Ganze Zahl ohne Nachkommastelle, sonst eine Stelle (wie `String(format: "%.1f")`).
  static String number(double value) =>
      value == value.roundToDouble() ? value.truncate().toString() : value.toStringAsFixed(1);
}
