// Empfehlungen aus dem Bereich „KI“ mit einer externen KI prüfen lassen: Export mit Prüfauftrag, Import mit Auswahl
// (neu in AIronLudi, keine Swift-Vorlage).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 11, 17, 8);

Insight insight(
  InsightTopic topic,
  String subject, {
  InsightOrigin origin = InsightOrigin.ai,
  InsightDirection direction = InsightDirection.more,
  String title = 'Titel',
  int validDays = 7,
}) => Insight(
  topic: topic,
  subject: subject,
  title: title,
  text: 'Text zu $subject',
  direction: direction,
  origin: origin,
  created: now.subtract(const Duration(days: 1)),
  validUntil: now.add(Duration(days: validDays)),
  basis: const ['Ruhepuls 52 bpm'],
  model: origin == InsightOrigin.ai ? 'llama-3.3-70b' : null,
);

CoachExportInput exportInput(List<Insight> insights, {DateTime? at}) => CoachExportInput(
  profile: UserProfile(mode: ProfileMode.personal, sports: const [TrainingSport.run]),
  schedule: WeekSchedule(),
  routines: [],
  custom: [],
  equipment: Equipment.gym,
  metrics: [],
  activities: [],
  gym: [],
  meals: [],
  weights: [],
  insights: insights,
  now: at ?? now,
);

final existing = [
  insight(InsightTopic.recovery, 'schlaf', title: 'Mehr schlafen'),
  insight(InsightTopic.nutrition, 'protein', origin: InsightOrigin.rules, title: 'Protein erhöhen'),
  insight(InsightTopic.training, 'bankdruecken', title: 'Bankdrücken steigern'),
  insight(InsightTopic.training, 'alt', title: 'Abgelaufen', validDays: -1),
  insight(
    InsightTopic.progress,
    'erledigt',
    title: 'Schon umgesetzt',
  ).copyWith(status: InsightStatus.done, statusChanged: () => now),
];

const answer = '''
Hier meine Analyse …

```ironludi
{
  "modell": "Claude Opus",
  "empfehlungen": [
    {"id": "erholung.schlaf", "titel": "Vor harten Tagen 8 h schlafen", "text": "Genauer: vor Intervallen früher ins Bett.",
     "richtung": "mehr", "prioritaet": 1, "gueltig_tage": 21, "begruendung": "Schlaf unter 6,5 h vor 3 von 4 harten Tagen"},
    {"id": "ernaehrung.protein", "titel": "Protein auf 1,8 g/kg", "text": "Mehr Protein am Abend.", "richtung": "mehr"},
    {"thema": "plan", "betreff": "Deload Woche", "titel": "Entlastungswoche einplanen", "text": "Nach drei Wochen.",
     "richtung": "aendern", "prioritaet": 9},
    {"thema": "unbekannt", "titel": "Kaputt", "text": "x"},
    {"id": "erholung.schlaf", "titel": "Doppelt", "text": "zweimal"}
  ],
  "verwerfen": ["training.bankdruecken", "ernaehrung.protein", "kein-punkt", "training.bankdruecken"]
}
```
''';

ImportPreview preview() =>
    CoachImport.preview(answer, profile: UserProfile(), equipment: Equipment.gym, custom: const [], now: now);

void main() {
  group('Export mit Prüfauftrag', () {
    test('offene Empfehlungen mit ID, Herkunft und Belegen; Abgelaufenes und Erledigtes nicht', () {
      final text = CoachExport.markdown(
        exportInput(existing),
        from: CalendarDay(2026, 11, 1),
        to: CalendarDay(2026, 11, 17),
      );
      expect(text, contains('## Empfehlungen der App (bitte prüfen)'));
      expect(text, contains('`erholung.schlaf` (KI, llama-3.3-70b, Priorität 2, Richtung mehr): **Mehr schlafen**'));
      expect(text, contains('`ernaehrung.protein` (Regeln,'));
      expect(text, contains('  - Belege: Ruhepuls 52 bpm'));
      expect(text, isNot(contains('Abgelaufen')));
      expect(text, isNot(contains('Schon umgesetzt')));
      expect(text, contains('"verwerfen": ["training.bankdruecken"]'));
      expect(text, contains('`verwerfen`: IDs von Empfehlungen der App'));
      // Abschnitt steht nach der Anleitung und vor dem Profil.
      expect(text.indexOf('## Empfehlungen der App'), greaterThan(text.indexOf('## Anleitung für die KI')));
      expect(text.indexOf('## Empfehlungen der App'), lessThan(text.indexOf('## Profil')));
    });

    test('ohne offene Empfehlungen bzw. ohne Zeitpunkt kein Abschnitt; Datenexport nur mit Antwortformat', () {
      final none = CoachExport.markdown(
        exportInput(const []),
        from: CalendarDay(2026, 11, 1),
        to: CalendarDay(2026, 11, 17),
      );
      expect(none, isNot(contains('## Empfehlungen der App')));
      expect(exportInput(existing, at: null).openInsights, hasLength(3));
      final withFormat = DataExport.markdown(
        exportInput(existing),
        from: CalendarDay(2026, 11, 1),
        to: CalendarDay(2026, 11, 17),
        categories: {ExportCategory.recovery},
        withImportFormat: true,
      );
      expect(withFormat, contains('## Empfehlungen der App (bitte prüfen)'));
      final plain = DataExport.markdown(
        exportInput(existing),
        from: CalendarDay(2026, 11, 1),
        to: CalendarDay(2026, 11, 17),
        categories: {ExportCategory.recovery},
      );
      expect(plain, isNot(contains('## Empfehlungen der App')));
    });
  });

  group('Import', () {
    test('Empfehlungen lesen: ID ersetzt, Grenzen, Doppeltes und Unvollständiges', () {
      final checked = preview();
      expect(checked.model, 'Claude Opus');
      expect(checked.isEmpty, isFalse);
      expect(checked.insights.map((insight) => insight.id), [
        'erholung.schlaf',
        'ernaehrung.protein',
        'plan.deload-woche',
      ]);
      final sleep = checked.insights.first;
      expect(sleep.topic, InsightTopic.recovery);
      expect(sleep.origin, InsightOrigin.ai);
      expect(sleep.model, 'Claude Opus');
      expect(sleep.priority, 1);
      expect(sleep.validUntil, now.add(const Duration(days: 21)));
      expect(sleep.basis, ['Schlaf unter 6,5 h vor 3 von 4 harten Tagen']);
      expect(checked.insights[1].basis, ['Import aus Claude Opus']);
      expect(checked.insights[2].priority, 3);
      expect(checked.insights[2].validUntil, now.add(const Duration(days: 14)));
      expect(checked.corrections, contains('Empfehlung „Kaputt“ ignoriert: Thema, Titel oder Text fehlt.'));
      expect(checked.dismiss, ['training.bankdruecken', 'ernaehrung.protein']);
    });

    test('Vorauswahl: Regeln werden nur ausdrücklich überschrieben bzw. verworfen', () {
      final checked = preview();
      final selection = ImportSelection.defaults(checked, existing: const [], existingInsights: existing);
      expect(selection.insights, {'erholung.schlaf', 'plan.deload-woche'});
      expect(selection.dismiss, {'training.bankdruecken'});
      expect(CoachImport.hasChanges(checked, selection: selection), isTrue);
      final nothing = ImportSelection.defaults(checked, existing: const [], existingInsights: existing)
        ..insights.clear()
        ..dismiss.clear()
        ..notes.clear();
      expect(CoachImport.hasChanges(checked, selection: nothing), isFalse);
    });

    test('Übernehmen: ersetzt, ergänzt, verwirft – nur was ausgewählt ist', () {
      final checked = preview();
      final selection = ImportSelection.defaults(checked, existing: const [], existingInsights: existing);
      final result = CoachImport.applyInsights(checked, selection: selection, existing: existing, now: now);
      Insight byID(String id) => result.singleWhere((insight) => insight.id == id);
      expect(byID('erholung.schlaf').title, 'Vor harten Tagen 8 h schlafen');
      expect(byID('erholung.schlaf').status, InsightStatus.newInsight);
      expect(byID('ernaehrung.protein').title, 'Protein erhöhen'); // Regel bleibt
      expect(byID('ernaehrung.protein').status, InsightStatus.newInsight);
      expect(byID('training.bankdruecken').status, InsightStatus.dismissed);
      expect(byID('plan.deload-woche').model, 'Claude Opus');

      // Ausdrücklich: auch die Regel überschreiben und verwerfen.
      selection
        ..insights.add('ernaehrung.protein')
        ..dismiss.add('ernaehrung.protein');
      final forced = CoachImport.applyInsights(checked, selection: selection, existing: existing, now: now);
      final protein = forced.singleWhere((insight) => insight.id == 'ernaehrung.protein');
      expect(protein.title, 'Protein auf 1,8 g/kg');
      expect(protein.origin, InsightOrigin.ai);
      expect(protein.status, InsightStatus.newInsight);

      // Nichts ausgewählt: unverändert (bis auf Aufräumen wie in der App).
      final unchanged = CoachImport.applyInsights(checked, selection: ImportSelection(), existing: existing, now: now);
      expect(unchanged, InsightInbox.prune(existing, now: now));
    });

    test('Widersprechende KI-Empfehlung wird ersetzt, Block nur mit Empfehlungen wird gefunden', () {
      final less = insight(InsightTopic.recovery, 'schlaf-dauer', direction: InsightDirection.less, title: 'Weniger');
      final checked = CoachImport.preview(
        '```json\n{"empfehlungen": [{"thema": "erholung", "betreff": "schlaf dauer", "titel": "Mehr", "text": "t", '
        '"richtung": "mehr"}]}\n```',
        profile: UserProfile(),
        equipment: Equipment.gym,
        custom: const [],
        now: now,
      );
      expect(checked.model, CoachImport.externalModel);
      final selection = ImportSelection.defaults(checked, existing: const [], existingInsights: [less]);
      final result = CoachImport.applyInsights(checked, selection: selection, existing: [less], now: now);
      expect(result.single.title, 'Mehr');
    });
  });
}
