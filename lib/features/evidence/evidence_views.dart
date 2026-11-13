import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';

/// Aufklappbare Quellen zu einer Empfehlung; nur sichtbar, wenn „Quellen einblenden“ an ist.
class EvidenceDisclosure extends ConsumerWidget {
  const EvidenceDisclosure({super.key, required this.ruleIDs, this.title = 'Quellen'});

  final List<String> ruleIDs;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final unique = ruleIDs.toSet().toList();
    final rules = Evidence.rulesFor(unique);
    final own = settings.userSources.where((source) => unique.contains(source.evidenceID)).toList();
    if (!settings.showsEvidence || (rules.isEmpty && own.isEmpty)) return const SizedBox.shrink();
    return ExpansionTile(
      leading: const Icon(Icons.menu_book, size: 20),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final rule in rules) EvidenceRuleRow(rule: rule),
        for (final source in own) UserSourceRow(source: source),
      ],
    );
  }
}

class EvidenceRuleRow extends StatelessWidget {
  const EvidenceRuleRow({super.key, required this.rule});

  final EvidenceRule rule;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(rule.title, style: text.titleSmall)),
              StrengthBadge(strength: rule.strength),
            ],
          ),
          const SizedBox(height: 4),
          Text(rule.statement, style: text.bodySmall),
          for (final study in rule.studies)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () => launchUrl(study.url),
              child: Text('${study.citation} · ${study.kind.rawValue}', style: text.labelSmall),
            ),
        ],
      ),
    );
  }
}

class StrengthBadge extends StatelessWidget {
  const StrengthBadge({super.key, required this.strength});

  final EvidenceStrength strength;

  @override
  Widget build(BuildContext context) => AppChip(
    text: strength.rawValue,
    color: switch (strength) {
      EvidenceStrength.strong => Colors.green,
      EvidenceStrength.moderate => Colors.blue,
      EvidenceStrength.practice => Colors.orange,
    },
  );
}

class UserSourceRow extends StatelessWidget {
  const UserSourceRow({super.key, required this.source});

  final UserSource source;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final topics = source.topics.toList()..sort((a, b) => a.rawValue.compareTo(b.rawValue));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(source.citation, style: text.titleSmall)),
              Text(
                'Eigene Quelle',
                style: text.labelSmall?.copyWith(color: Colors.purple, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Text(source.statement, style: text.bodySmall),
          Text(
            topics.map((topic) => topic.label).join(' · '),
            style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (source.url case final url?)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              onPressed: () => launchUrl(url),
              child: Text(source.reference, style: text.labelSmall),
            ),
        ],
      ),
    );
  }
}

/// Alle Regeln der App mit ihren Quellen (Einstellungen › Wissenschaftliche Grundlagen).
class EvidenceLibraryScreen extends ConsumerWidget {
  const EvidenceLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Quellen und Regeln')),
      body: ListView(
        children: [
          const FormSection(
            footer:
                'Die App entscheidet nach festen Regeln; die KI formuliert nur. Jede Regel nennt ihre Quellen. '
                '„Praxisregel“ heißt: vorsichtig gewählt, aber ohne direkte Studie für genau diesen Wert.',
            children: [],
          ),
          FormSection(
            footer: 'Eigene Studien ergänzen, die die KI zusätzlich berücksichtigt.',
            children: [
              ListTile(
                title: Text('Eigene Quellen (${settings.userSources.length})'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UserSourcesScreen())),
              ),
            ],
          ),
          for (final rule in Evidence.rules)
            FormSection(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: EvidenceRuleRow(rule: rule),
                ),
              ],
            ),
          const FormSection(
            header: 'Kontrolle der KI',
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Die KI bekommt nur die Fakten der App und diese Regeln. Der Worker prüft jede Antwort: Zahlen, die '
                  'nicht in den Fakten stehen, und unbekannte Quellen werden verworfen. Ist nichts belegt, zeigt die '
                  'App die regelbasierte Notiz.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Eigene wissenschaftliche Quellen: Kurzbeleg, DOI/PMID/Link, Kernaussage und Themen. Die KI bekommt sie bei passenden
/// Aufgaben als zusätzliche belegte Regeln; die Entscheidungen der App ändern sie nicht.
class UserSourcesScreen extends ConsumerWidget {
  const UserSourcesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, UserSource source) async {
    final saved = await Navigator.of(context)
        .push<UserSource>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => UserSourceEditor(source: source)));
    if (saved == null) return;
    final settings = ref.read(coachSettingsProvider);
    final list = [...settings.userSources];
    final index = list.indexWhere((item) => item.id == saved.id);
    if (index >= 0) {
      list[index] = saved;
    } else {
      list.add(saved);
    }
    settings.userSources = list;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final sources = settings.userSources;
    return Scaffold(
      appBar: AppBar(title: const Text('Eigene Quellen')),
      body: ListView(
        children: [
          FormSection(
            footer:
                'Gemini Flash bekommt passende Quellen bei Coach-Notiz, Gym-Tipps, KI-Trainingsplan, '
                'Ernährungsauswertung, Rezeptideen und im Chat zusätzlich zu den Regeln der App (höchstens '
                '${UserSources.maxPerRequest} je Anfrage) und darf sie zitieren. Tagesampel, Ziele, Gewichtssteigerung '
                'und Schutzgrenzen bleiben bei den geprüften Regeln der App. Am besten Übersichtsarbeiten oder '
                'Meta-Analysen eintragen.',
            children: [
              if (sources.isEmpty) const ListTile(title: Text('Noch keine eigenen Quellen.')),
              for (final source in sources)
                Dismissible(
                  key: ValueKey(source.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => settings.userSources = sources.where((item) => item.id != source.id).toList(),
                  child: InkWell(
                    onTap: () => _edit(context, ref, source),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: UserSourceRow(source: source),
                    ),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Quelle hinzufügen'),
                onTap: () => _edit(context, ref, UserSource(citation: '', statement: '')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class UserSourceEditor extends StatefulWidget {
  const UserSourceEditor({super.key, required this.source});

  final UserSource source;

  @override
  State<UserSourceEditor> createState() => _UserSourceEditorState();
}

class _UserSourceEditorState extends State<UserSourceEditor> {
  late final _citation = TextEditingController(text: widget.source.citation);
  late final _reference = TextEditingController(text: widget.source.reference);
  late final _statement = TextEditingController(text: widget.source.statement);
  late final Set<UserSourceTopic> _topics = {...widget.source.topics};

  UserSource get _draft => UserSource(
    id: widget.source.id,
    citation: _citation.text,
    reference: _reference.text,
    statement: _statement.text,
    topics: _topics,
  );

  @override
  void initState() {
    super.initState();
    for (final controller in [_citation, _reference, _statement]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _citation.dispose();
    _reference.dispose();
    _statement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eigene Quelle'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
        actions: [
          TextButton(
            onPressed: !draft.isValid || _topics.isEmpty
                ? null
                : () {
                    final statement = draft.statement;
                    draft.statement = statement.runes.length > UserSources.maxStatementLength
                        ? String.fromCharCodes(statement.runes.take(UserSources.maxStatementLength))
                        : statement;
                    Navigator.of(context).pop(draft);
                  },
            child: const Text('Sichern'),
          ),
        ],
      ),
      body: ListView(
        children: [
          FormSection(
            header: 'Quelle',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _citation,
                  decoration: const InputDecoration(hintText: 'Kurzbeleg, z. B. Schoenfeld et al. 2017'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _reference,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(hintText: 'DOI, PMID oder Link'),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Kernaussage',
            footer:
                'In eigenen Worten und so konkret wie möglich, höchstens ${UserSources.maxStatementLength} Zeichen. '
                'Diese Aussage bekommt die KI.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _statement,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(hintText: 'Was sagt die Studie?'),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Themen',
            children: [
              for (final topic in UserSourceTopic.values)
                SwitchListTile(
                  title: Text(topic.label),
                  value: _topics.contains(topic),
                  onChanged: (on) => setState(() => on ? _topics.add(topic) : _topics.remove(topic)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
