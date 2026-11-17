import 'dart:async';

import 'package:coach_core/coach_core.dart' hide Badge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/symbols.dart';
import '../gym/gym_library.dart';
import '../gym/gym_providers.dart';
import '../recipes/recipe_views.dart';
import '../settings/ai_settings.dart';
import 'ai_controller.dart';
import 'ai_data.dart';
import 'chat_screen.dart';
import 'coach_exchange.dart';
import 'prompt_library_screen.dart';

IconData _icon(String symbol) => switch (symbol) {
  'dumbbell' => Icons.fitness_center,
  'figure.run' => Icons.directions_run,
  'fork.knife' => Icons.restaurant,
  'bed.double' => Icons.bed_outlined,
  'heart.text.square' => Icons.monitor_heart_outlined,
  'scalemass' => Icons.monitor_weight_outlined,
  'figure.mixed.cardio' => Icons.sports,
  'calendar' => Icons.calendar_month,
  'chart.line.uptrend.xyaxis' => Icons.show_chart,
  'arrow.up.right' => Icons.north_east,
  'pause.circle' => Icons.pause_circle_outline,
  'checklist' => Icons.checklist,
  final other => AppSymbols.of(other),
};

/// Bereich „AI“ (über „Heute“): alle Empfehlungen aus Regeln und KI an einem Ort, nach Themen, mit
/// Bearbeitungsstand; dazu die KI-Analyse auf Anfrage und die übrigen KI-Funktionen. Die Grundlage bleibt intern
/// (lange drücken › „Worauf beruht das?“) (Port von `AIView`).
class AIScreen extends ConsumerStatefulWidget {
  const AIScreen({super.key, this.startAnalysis = false, this.coachNote});

  /// Schnellaktion „KI-Analyse starten“: zur Analyse springen und sie anstoßen, sofern erlaubt.
  final bool startAnalysis;

  /// Coach-Notiz bzw. „Warum?“ von „Heute“, ganz oben (früher eigener Abschnitt auf „Heute“).
  final Widget? coachNote;

  @override
  ConsumerState<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends ConsumerState<AIScreen> {
  late final AIController _controller = AIController(
    store: ref.read(settingsStoreProvider),
    schedule: ref.read(seasonScheduleProvider),
  )..addListener(_changed);
  InsightCategory? _category;
  bool _showsClosed = false;
  AIData? _data;
  final _analysisKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    unawaited(_refresh().then((_) => _startFromShortcut()));
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final data = await loadAIData(ref);
    if (!mounted) return;
    _data = data;
    _controller.refreshRules(
      settings: ref.read(coachSettingsProvider),
      sync: ref.read(garminSyncServiceProvider),
      data: data,
    );
  }

  Future<void> _analyze() async {
    final data = _data;
    if (data == null) return;
    await _controller.analyze(
      topic: _category?.analysisTopic,
      settings: ref.read(coachSettingsProvider),
      sync: ref.read(garminSyncServiceProvider),
      ai: ref.read(aiClientProvider),
      data: data,
    );
  }

  Future<void> _startFromShortcut() async {
    if (!widget.startAnalysis || !mounted) return;
    setState(() => _category = null);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_analysisKey.currentContext case final context? when context.mounted) {
      await Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 300));
    }
    if (ref.read(aiClientProvider).allows('ai_insights') && !_controller.isAnalyzing) await _analyze();
  }

  void _mark(InsightStatus status, Insight insight, {bool onlyIfNew = false}) =>
      AIController.mark(status, insight, ref.read(coachSettingsProvider), onlyIfNew: onlyIfNew);

  Future<void> _actions(Insight insight) async {
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (insight.status == InsightStatus.newInsight)
              ListTile(
                leading: const Icon(Icons.drafts_outlined),
                title: const Text('Als gelesen markieren'),
                onTap: () => Navigator.of(context).pop(() => _mark(InsightStatus.read, insight)),
              ),
            if (insight.status != InsightStatus.done)
              ListTile(
                leading: const Icon(Icons.check),
                title: const Text('Umgesetzt'),
                onTap: () => Navigator.of(context).pop(() => _mark(InsightStatus.done, insight)),
              ),
            if (insight.status != InsightStatus.dismissed)
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Verwerfen'),
                onTap: () => Navigator.of(context).pop(() => _mark(InsightStatus.dismissed, insight)),
              ),
            if (insight.status == InsightStatus.done || insight.status == InsightStatus.dismissed)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Wieder öffnen'),
                onTap: () => Navigator.of(context).pop(() => _mark(InsightStatus.read, insight)),
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Worauf beruht das?'),
              onTap: () => Navigator.of(context).pop(
                () => showModalBottomSheet<void>(
                  context: this.context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => InsightBasisSheet(insight: insight),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    action?.call();
  }

  List<Widget> _rows(List<Insight> insights) => [
    for (final insight in insights)
      Dismissible(
        key: ValueKey('${insight.id}-${insight.status.rawValue}'),
        // Nach rechts: umgesetzt; nach links: verwerfen (wie die Wischaktionen in Swift).
        direction: switch (insight.status) {
          InsightStatus.done => DismissDirection.endToStart,
          InsightStatus.dismissed => DismissDirection.startToEnd,
          _ => DismissDirection.horizontal,
        },
        background: Container(
          color: Colors.green,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Text('Umgesetzt', style: TextStyle(color: Colors.white)),
        ),
        secondaryBackground: Container(
          color: Colors.grey,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Text('Verwerfen', style: TextStyle(color: Colors.white)),
        ),
        confirmDismiss: (direction) async {
          _mark(direction == DismissDirection.startToEnd ? InsightStatus.done : InsightStatus.dismissed, insight);
          return false;
        },
        child: InsightRow(
          insight: insight,
          onTap: () => _mark(InsightStatus.read, insight, onlyIfNew: true),
          onLongPress: () => _actions(insight),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final ai = ref.watch(aiClientProvider);
    final now = DateTime.now();
    final goals = settings.profile.effectiveGoals(CalendarDay.fromDate(now));
    final groups = InsightInbox.groups(
      settings.insights,
      category: _category,
      focus: Personalization.insightTopics(goals),
      now: now,
    );
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('AI')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ?widget.coachNote,
            _CategoryChips(
              selection: _category,
              insights: settings.insights,
              now: now,
              onSelect: (category) => setState(() => _category = category),
            ),
            if (groups.newItems.isEmpty && groups.open.isEmpty)
              FormSection(
                children: [
                  ListTile(
                    title: Text(
                      _category == null
                          ? 'Gerade keine offenen Empfehlungen. Die Regeln der App melden sich, sobald es etwas gibt.'
                          : 'Zu „${_category!.label}“ gibt es gerade nichts Offenes.',
                      style: TextStyle(color: secondary),
                    ),
                  ),
                ],
              ),
            if (groups.newItems.isNotEmpty) FormSection(header: 'Neu', children: _rows(groups.newItems)),
            if (groups.open.isNotEmpty) FormSection(header: 'Aktuell', children: _rows(groups.open)),
            FormSection(
              key: _analysisKey,
              header: 'KI-Analyse',
              footer:
                  'Die KI wertet nur deine Daten aus, die die App selbst berechnet hat, und widerspricht den Regeln '
                  'nicht. Unsichere Aussagen sind gekennzeichnet.',
              children: [
                if (ai.allows('ai_insights'))
                  ListTile(
                    enabled: !controller.isAnalyzing,
                    leading: Icon(controller.isAnalyzing ? Icons.hourglass_top : Icons.auto_awesome),
                    title: Text(switch (_category?.analysisTopic) {
                      final topic? => '„${topic.label}“ analysieren',
                      null => 'Alles analysieren',
                    }),
                    textColor: Theme.of(context).colorScheme.primary,
                    onTap: _analyze,
                  )
                else
                  ListTile(
                    title: Text(
                      ai.isConfigured
                          ? AIPolicy.blockedMessage(settings.ai.mode)
                          : 'Für die KI-Analyse den KI-Worker in den Einstellungen einrichten.',
                      style: TextStyle(color: secondary),
                    ),
                  ),
                if (controller.error case final error?)
                  ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.orange)),
                  ),
                if (controller.note case final note?)
                  ListTile(
                    title: Text(note, style: TextStyle(fontSize: 13, color: secondary)),
                  ),
                if ([...groups.newItems, ...groups.open].any((insight) => insight.origin == InsightOrigin.ai))
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('Von Claude oder ChatGPT prüfen lassen'),
                    subtitle: const Text(
                      'Export mit allen offenen Empfehlungen und Prüfauftrag; die Antwort danach übernehmen – du '
                      'wählst, was überschrieben wird.',
                    ),
                    trailing: const DisclosureChevron(),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CoachExportScreen())),
                  ),
                if (controller.missing.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          'Es fehlen Daten – dazu gibt es keine Aussage:',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: secondary),
                        ),
                        for (final line in controller.missing)
                          Text('· $line', style: TextStyle(fontSize: 13, color: secondary)),
                      ],
                    ),
                  ),
              ],
            ),
            if (groups.expired.isNotEmpty)
              FormSection(
                header: 'Nicht mehr aktuell',
                footer: 'Gilt nicht mehr, weil sich deine Daten geändert haben oder die Zeit abgelaufen ist.',
                children: _rows(groups.expired),
              ),
            if (groups.closed.isNotEmpty)
              FormSection(
                children: [
                  ExpansionTile(
                    title: Text('Umgesetzt und verworfen (${groups.closed.length})'),
                    initiallyExpanded: _showsClosed,
                    onExpansionChanged: (open) => _showsClosed = open,
                    children: _rows(groups.closed),
                  ),
                ],
              ),
            FormSection(
              header: 'Weitere KI-Funktionen',
              footer:
                  'Mahlzeiten per Foto oder Text erfasst du im Reiter Ernährung, die Tagesnotiz steht unter „Heute“.',
              children: [
                if (ai.allows('coach_chat'))
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('Coach fragen'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => ChatScreen(snapshot: controller.snapshot),
                      ),
                    ),
                  ),
                if (settings.profile.trains(TrainingSport.strength))
                  ListTile(
                    leading: const Icon(Icons.fitness_center),
                    title: const Text('Trainingsplan von der KI'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => GymPlanScreen(gym: ref.read(gymControllerProvider)),
                      ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.soup_kitchen_outlined),
                  title: const Text('Rezeptideen für die Woche'),
                  trailing: const DisclosureChevron(),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RecipesScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Prompt-Bibliothek für externe KI'),
                  trailing: const DisclosureChevron(),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PromptLibraryScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Daten für eine externe KI exportieren'),
                  trailing: const DisclosureChevron(),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CoachExportScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Antwort einer externen KI übernehmen'),
                  trailing: const DisclosureChevron(),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CoachImportScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('KI-Einstellungen'),
                  trailing: const DisclosureChevron(),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('KI-Einstellungen')),
                        body: ListView(children: const [AISettingsSection()]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bereiche als Filter; die Zahl zeigt neue Empfehlungen.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selection, required this.insights, required this.now, required this.onSelect});

  final InsightCategory? selection;
  final List<Insight> insights;
  final DateTime now;
  final ValueChanged<InsightCategory?> onSelect;

  Widget _chip(BuildContext context, InsightCategory? category, String label, int count) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      selected: selection == category,
      avatar: category == null ? null : Icon(_icon(category.symbol), size: 16),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(label),
          if (count > 0) Badge(label: Text('$count'), backgroundColor: Colors.red),
        ],
      ),
      onSelected: (_) => onSelect(category),
    ),
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        _chip(context, null, 'Alle', InsightInbox.unreadCount(insights, now: now)),
        for (final category in InsightCategory.values)
          if (insights.where((insight) => insight.category == category).toList() case final matching
              when matching.isNotEmpty)
            _chip(context, category, category.label, InsightInbox.unreadCount(matching, now: now)),
      ],
    ),
  );
}

/// Erkenntnis und Empfehlung – ohne Datenquellen.
class InsightRow extends StatelessWidget {
  const InsightRow({super.key, required this.insight, this.onTap, this.onLongPress});

  final Insight insight;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final isNew = insight.status == InsightStatus.newInsight;
    final meta = [
      insight.topic.label,
      if (insight.uncertain) 'unsicher, wenige Daten',
      if (insight.status == InsightStatus.done) 'umgesetzt',
      if (insight.status == InsightStatus.dismissed) 'verworfen',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Icon(_icon(insight.topic.symbol), color: isNew ? theme.colorScheme.primary : secondary),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Row(
                    spacing: 6,
                    children: [
                      Flexible(
                        child: Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      ),
                      if (isNew)
                        Semantics(
                          label: 'neu',
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                  Text(insight.text),
                  Text(meta, style: TextStyle(fontSize: 12, color: secondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interne Nachvollziehbarkeit: worauf eine Empfehlung beruht, woher sie kommt und wie lange sie gilt.
class InsightBasisSheet extends StatelessWidget {
  const InsightBasisSheet({super.key, required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('d. MMM y, HH:mm', 'de_DE');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text('Worauf beruht das?', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig')),
              ],
            ),
          ),
          FormSection(
            header: 'Grundlage',
            children: [for (final line in insight.basis) ListTile(dense: true, title: Text(line))],
          ),
          FormSection(
            header: 'Herkunft',
            children: [
              LabeledRow(label: 'Erstellt von', value: insight.origin == InsightOrigin.rules ? 'Regeln der App' : 'KI'),
              if (insight.model case final model?) LabeledRow(label: 'Modell', value: model),
              LabeledRow(label: 'Erstellt', value: format.format(insight.created.toLocal())),
              LabeledRow(label: 'Gilt bis', value: format.format(insight.validUntil.toLocal())),
              LabeledRow(label: 'Betreff', value: insight.subject),
            ],
          ),
          if (insight.origin == InsightOrigin.ai && insight.model != CoachImport.externalModel)
            const FormSection(
              children: [
                ListTile(
                  dense: true,
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text(
                    'Tipp: Ein stärkeres Modell (Claude, ChatGPT) kann diese Empfehlung prüfen. „AI“ › „Daten für '
                    'eine externe KI exportieren“ legt sie mit Prüfauftrag bei; die Antwort übernimmst du über '
                    '„Antwort einer externen KI übernehmen“.',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
