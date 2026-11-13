import '../calendar/calendar_day.dart';
import '../nutrition/meal.dart';
import '../profile/user_profile.dart';
import '../util/enum_codec.dart';
import '../util/german_format.dart';
import 'coach_export.dart';
import 'data_export.dart';

/// Ein Prompt für eine externe KI. Platzhalter: `{zeitraum}`, `{tage}`, `{ziel}`, `{sportarten}`.
final class PromptTemplate {
  PromptTemplate({
    String? id,
    required this.title,
    required this.text,
    required this.categories,
    required int days,
    this.isCustom = true,
  }) : id = id ?? newUuid(),
       days = days.clamp(1, 365);

  const PromptTemplate._builtIn({
    required this.id,
    required this.title,
    required this.text,
    required this.categories,
    required this.days,
  }) : isCustom = false;

  final String id;
  final String title;
  final String text;

  /// Daten, die automatisch angehängt werden.
  final List<ExportCategory> categories;

  /// Standardzeitraum in Tagen.
  final int days;
  final bool isCustom;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'categories': [for (final category in categories) category.rawValue],
    'days': days,
    'isCustom': isCustom,
  };

  /// Wie das synthetisierte `Decodable` (ohne Begrenzen der Tage, das gilt nur beim Anlegen).
  static PromptTemplate? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, title, text, days, isCustom) = (json['id'], json['title'], json['text'], json['days'], json['isCustom']);
    final categories = enumListStrict(ExportCategory.values, json['categories']);
    if (id is! String ||
        title is! String ||
        text is! String ||
        days is! int ||
        isCustom is! bool ||
        categories == null) {
      return null;
    }
    return PromptTemplate._raw(id, title, text, categories, days, isCustom);
  }

  const PromptTemplate._raw(this.id, this.title, this.text, this.categories, this.days, this.isCustom);

  @override
  bool operator ==(Object other) =>
      other is PromptTemplate &&
      other.id == id &&
      other.title == title &&
      other.text == text &&
      other.days == days &&
      other.isCustom == isCustom &&
      other.categories.length == categories.length &&
      Iterable<int>.generate(categories.length).every((index) => other.categories[index] == categories[index]);

  @override
  int get hashCode => Object.hash(id, title, text, days, isCustom);
}

/// Bibliothek der Prompts für externe KI-Analysen. Die App setzt Zeitraum, Ziel und Daten ein und hängt
/// Arbeitsregeln an (nur aus den Daten, Lücken benennen, Unsicherheit kennzeichnen).
abstract final class PromptLibrary {
  static const builtIn = [
    PromptTemplate._builtIn(
      id: 'training',
      title: 'Trainingsanalyse',
      text:
          'Analysiere meine Trainingsdaten der letzten {tage} Tage ({zeitraum}). Bewerte Trainingsvolumen, '
          'Intensität, Verteilung über die Woche, Progression und mögliche Stagnationen. Mein Ziel: {ziel}. '
          'Sportarten: {sportarten}.',
      categories: [ExportCategory.gym, ExportCategory.endurance, ExportCategory.history, ExportCategory.recovery],
      days: 30,
    ),
    PromptTemplate._builtIn(
      id: 'recovery',
      title: 'Erholung',
      text:
          'Bewerte meine Regeneration im Zeitraum {zeitraum} anhand von Schlafdaten, HRV, Ruheherzfrequenz und '
          'der bisherigen Trainingsbelastung. Zeige, an welchen Tagen Belastung und Erholung nicht zusammenpassten, '
          'und was ich in der nächsten Woche anders machen sollte.',
      categories: [ExportCategory.recovery, ExportCategory.sleep, ExportCategory.endurance, ExportCategory.gym],
      days: 14,
    ),
    PromptTemplate._builtIn(
      id: 'nutrition',
      title: 'Ernährung',
      text:
          'Analysiere meine Ernährung im Zeitraum {zeitraum} hinsichtlich meines aktuellen Trainingsziels ({ziel}) '
          'und identifiziere Verbesserungspotenziale bei Kalorien, Protein und Nährstoffverteilung – auch im Bezug '
          'auf Trainings- und Ruhetage.',
      categories: [ExportCategory.nutrition, ExportCategory.weight, ExportCategory.endurance, ExportCategory.gym],
      days: 14,
    ),
    PromptTemplate._builtIn(
      id: 'planning',
      title: 'Trainingsplanung',
      text:
          'Optimiere meinen Trainingsplan unter Berücksichtigung meiner bisherigen Leistungen ({zeitraum}), meiner '
          'Regeneration und der Zeit, die ich laut Wochenplan tatsächlich trainiere. Ziel: {ziel}. Schlage konkrete '
          'Änderungen vor (Übungen, Sätze, Wiederholungen, Tage) und begründe jede kurz.',
      categories: [ExportCategory.gym, ExportCategory.endurance, ExportCategory.recovery, ExportCategory.history],
      days: 28,
    ),
    PromptTemplate._builtIn(
      id: 'stagnation',
      title: 'Stagnation im Krafttraining',
      text:
          'Prüfe meine Krafteinheiten der letzten {tage} Tage auf Stagnation: Bei welchen Übungen steigen Gewicht '
          'oder Wiederholungen nicht mehr? Nenne mögliche Ursachen aus den Daten (Volumen, Häufigkeit, Erholung) und '
          'konkrete Gegenmaßnahmen.',
      categories: [ExportCategory.gym, ExportCategory.history, ExportCategory.recovery],
      days: 90,
    ),
    PromptTemplate._builtIn(
      id: 'progress',
      title: 'Langfristiger Fortschritt',
      text:
          'Fasse meinen Fortschritt im Zeitraum {zeitraum} zusammen: Trainingsumfang, Kraftwerte, Ausdauer und '
          'Gewicht. Was hat sich verbessert, was stagniert, und welche zwei Dinge bringen mich meinem Ziel ({ziel}) '
          'am meisten näher?',
      categories: [ExportCategory.history, ExportCategory.gym, ExportCategory.endurance, ExportCategory.weight],
      days: 365,
    ),
    PromptTemplate._builtIn(
      id: 'sleep',
      title: 'Schlaf',
      text:
          'Analysiere meinen Schlaf im Zeitraum {zeitraum}: Dauer, Regelmäßigkeit, Schlafphasen und den Bezug zu '
          'Trainingstagen und Stress. Gib mir drei konkrete, umsetzbare Empfehlungen.',
      categories: [ExportCategory.sleep, ExportCategory.recovery, ExportCategory.health],
      days: 30,
    ),
    PromptTemplate._builtIn(
      id: 'body',
      title: 'Gewicht und Körper',
      text:
          'Bewerte meinen Gewichtsverlauf im Zeitraum {zeitraum} im Verhältnis zu Ernährung und Training. Passt '
          'das Tempo zu meinem Ziel ({ziel})? Trenne dabei echte Trends von normalen Schwankungen.',
      categories: [ExportCategory.weight, ExportCategory.nutrition, ExportCategory.history],
      days: 90,
    ),
  ];

  /// Arbeitsregeln, die jedem Prompt angehängt werden.
  static const rules =
      'Arbeitsweise:\n'
      '- Stütze dich nur auf die Daten unten. Erfinde keine Werte; „–“ bzw. null heißt nicht gemessen.\n'
      '- Fehlen Daten für eine Aussage, sag das ausdrücklich, statt zu schätzen.\n'
      '- Kennzeichne unsichere Schlüsse als solche.\n'
      '- Keine Diagnosen; bei auffälligen Gesundheitswerten Rücksprache mit Ärztin oder Arzt empfehlen.\n'
      '- Antworte auf Deutsch in dieser Gliederung: 1. Kernaussagen (höchstens 5), 2. Details, '
      '3. Empfehlungen nach Wichtigkeit, 4. Fehlende Daten und offene Fragen.';

  /// Setzt die Platzhalter ein.
  static String filled(
    PromptTemplate template, {
    required UserProfile profile,
    required CalendarDay from,
    required CalendarDay to,
  }) => template.text
      .replaceAll('{zeitraum}', '${GermanFormat.date(from)} bis ${GermanFormat.date(to)}')
      .replaceAll('{tage}', '${from.daysUntil(to) + 1}')
      .replaceAll('{ziel}', profile.goal.label)
      .replaceAll('{sportarten}', profile.sports.map((sport) => sport.label).join(', '));

  /// Prompt, Arbeitsregeln und Daten in einem Text – zum Einfügen in ChatGPT, Gemini, Claude oder ein lokales Modell.
  static String compose(
    PromptTemplate template, {
    required CoachExportInput input,
    required CalendarDay from,
    required CalendarDay to,
    ExportFormat format = ExportFormat.markdown,
  }) {
    final categories = template.categories.toSet();
    final data = switch (format) {
      ExportFormat.json => '```json\n${DataExport.json(input, from: from, to: to, categories: categories)}\n```',
      ExportFormat.markdown ||
      ExportFormat.csv => DataExport.markdown(input, from: from, to: to, categories: categories),
    };
    return [filled(template, profile: input.profile, from: from, to: to), '', rules, '', '---', '', data].join('\n');
  }
}
