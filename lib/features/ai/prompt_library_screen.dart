import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import 'coach_exchange.dart';

/// Prompt-Bibliothek für externe KI: fertige Vorlagen und eigene Prompts. Jeder Prompt wird mit Zeitraum, Ziel und den
/// passenden Daten ergänzt und lässt sich kopieren oder als Datei teilen (Port von `PromptLibraryView`).
class PromptLibraryScreen extends ConsumerWidget {
  const PromptLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    void open(PromptTemplate template) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PromptDetailScreen(template: template)));
    return Scaffold(
      appBar: AppBar(title: const Text('Prompt-Bibliothek')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Vorlagen',
            footer: 'Jede Vorlage hängt die passenden Daten und Arbeitsregeln an: nur aus den Daten, Lücken benennen.',
            children: [
              for (final template in PromptLibrary.builtIn)
                ListTile(title: Text(template.title), trailing: const DisclosureChevron(), onTap: () => open(template)),
            ],
          ),
          FormSection(
            header: 'Eigene Prompts',
            children: [
              for (final template in settings.customPrompts)
                ListTile(
                  title: Text(template.title),
                  onTap: () => open(template),
                  trailing: IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => settings.customPrompts = [
                      for (final item in settings.customPrompts)
                        if (item.id != template.id) item,
                    ],
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Neuer Prompt'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => PromptEditor(
                      template: PromptTemplate(
                        title: '',
                        text: '',
                        categories: const [ExportCategory.gym, ExportCategory.endurance],
                        days: 30,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ein Prompt mit Vorschau, Zeitraum, Datenauswahl und Format (Port von `PromptDetailView`).
class PromptDetailScreen extends ConsumerStatefulWidget {
  const PromptDetailScreen({super.key, required this.template});

  final PromptTemplate template;

  @override
  ConsumerState<PromptDetailScreen> createState() => _PromptDetailScreenState();
}

class _PromptDetailScreenState extends ConsumerState<PromptDetailScreen> {
  late final ExportRange _range = () {
    final days = widget.template.days;
    final preset = CoachExport.presets.any((preset) => preset.days == days);
    return preset
        ? ExportRange(presetDays: days)
        : ExportRange(presetDays: null, from: CalendarDay.today().adding(-(days - 1)));
  }();
  late final Set<ExportCategory> _categories = {...widget.template.categories};
  ExportFormat _format = ExportFormat.markdown;
  bool _copied = false;
  CoachExportInput? _input;

  @override
  void initState() {
    super.initState();
    loadExportInput(ref).then((input) {
      if (mounted) setState(() => _input = input);
    });
  }

  PromptTemplate get _current => ref
      .read(coachSettingsProvider)
      .customPrompts
      .firstWhere((item) => item.id == widget.template.id, orElse: () => widget.template);

  /// Der Prompt mit den gewählten Daten.
  PromptTemplate get _selected {
    final current = _current;
    return PromptTemplate(
      id: current.id,
      title: current.title,
      text: current.text,
      categories: [
        for (final category in ExportCategory.values)
          if (_categories.contains(category)) category,
      ],
      days: current.days,
      isCustom: current.isCustom,
    );
  }

  void _reset() => setState(() => _copied = false);

  String _composed(CoachExportInput input) =>
      PromptLibrary.compose(_selected, input: input, from: _range.start, to: _range.end, format: _format);

  void _edit(PromptTemplate template) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => PromptEditor(template: template)));

  @override
  Widget build(BuildContext context) {
    ref.watch(coachSettingsProvider);
    final current = _current;
    final prompt = _selected;
    final input = _input;
    final counts = input == null
        ? const <ExportCategory, int>{}
        : DataExport.counts(input, from: _range.start, to: _range.end);
    final empty = [
      for (final category in prompt.categories)
        if ((counts[category] ?? 0) == 0) category.label,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(current.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Prompt',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  PromptLibrary.filled(
                    prompt,
                    profile: ref.read(coachSettingsProvider).coachingProfile,
                    from: _range.start,
                    to: _range.end,
                  ),
                ),
              ),
            ],
          ),
          ExportRangeSection(range: _range, onChanged: _reset),
          FormSection(
            header: 'Angehängte Daten',
            footer: input != null && empty.isNotEmpty
                ? 'Ohne Daten im Zeitraum: ${empty.join(', ')}. Die KI soll das als fehlend behandeln.'
                : null,
            children: [
              for (final category in ExportCategory.values)
                SwitchListTile.adaptive(
                  title: Text('${category.label} (${counts[category] ?? 0})'),
                  value: _categories.contains(category),
                  onChanged: (on) {
                    on ? _categories.add(category) : _categories.remove(category);
                    _reset();
                  },
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ExportFormat>(
                    segments: const [
                      ButtonSegment(value: ExportFormat.markdown, label: Text('Markdown')),
                      ButtonSegment(value: ExportFormat.json, label: Text('JSON')),
                    ],
                    selected: {_format},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      _format = selection.first;
                      _reset();
                    },
                  ),
                ),
              ),
            ],
          ),
          FormSection(
            footer: 'In ChatGPT, Gemini, Claude oder ein lokales Modell einfügen. Enthält Gesundheitsdaten.',
            children: [
              ListTile(
                enabled: input != null,
                leading: Icon(_copied ? Icons.check : Icons.copy),
                title: Text(_copied ? 'Kopiert' : 'Prompt mit Daten kopieren'),
                onTap: input == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _composed(input)));
                        setState(() => _copied = true);
                      },
              ),
              ListTile(
                enabled: input != null,
                leading: const Icon(Icons.ios_share),
                title: const Text('Als Datei teilen'),
                onTap: input == null
                    ? null
                    : () async {
                        final id = prompt.id.length > 12 ? prompt.id.substring(0, 12) : prompt.id;
                        final files = await writeExportFiles([
                          ExportFile(name: 'IronLudi-Prompt-$id.md', content: _composed(input)),
                        ]);
                        await SharePlus.instance.share(ShareParams(files: files));
                      },
              ),
            ],
          ),
          FormSection(
            children: [
              if (current.isCustom)
                ListTile(leading: const Icon(Icons.edit), title: const Text('Bearbeiten'), onTap: () => _edit(current))
              else
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('Als eigenen Prompt speichern'),
                  onTap: () => _edit(
                    PromptTemplate(
                      title: '${current.title} (eigen)',
                      text: current.text,
                      categories: prompt.categories,
                      days: current.days,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eigenen Prompt anlegen oder ändern (Port von `PromptEditor`).
class PromptEditor extends ConsumerStatefulWidget {
  const PromptEditor({super.key, required this.template});

  final PromptTemplate template;

  @override
  ConsumerState<PromptEditor> createState() => _PromptEditorState();
}

class _PromptEditorState extends ConsumerState<PromptEditor> {
  late final _title = TextEditingController(text: widget.template.title)..addListener(() => setState(() {}));
  late final _text = TextEditingController(text: widget.template.text)..addListener(() => setState(() {}));
  late final Set<ExportCategory> _categories = {...widget.template.categories};
  late int _days = widget.template.days;

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final settings = ref.read(coachSettingsProvider);
    final saved = PromptTemplate(
      id: widget.template.id,
      title: _title.text.trim(),
      text: _text.text,
      categories: [
        for (final category in ExportCategory.values)
          if (_categories.contains(category)) category,
      ],
      days: _days,
    );
    final list = [...settings.customPrompts];
    final index = list.indexWhere((item) => item.id == saved.id);
    if (index >= 0) {
      list[index] = saved;
    } else {
      list.add(saved);
    }
    settings.customPrompts = list;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _title.text.trim().isNotEmpty && _text.text.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.text.isEmpty ? 'Neuer Prompt' : _title.text),
        leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop()),
        leadingWidth: 100,
        actions: [TextButton(onPressed: canSave ? _save : null, child: const Text('Sichern'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Titel',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(hintText: 'z. B. Laufanalyse vor dem Wettkampf'),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Prompt',
            footer: 'Platzhalter: {zeitraum}, {tage}, {ziel}, {sportarten} – die App setzt sie ein.',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _text,
                  minLines: 6,
                  maxLines: 16,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Daten',
            children: [
              for (final category in ExportCategory.values)
                SwitchListTile.adaptive(
                  title: Text(category.label),
                  value: _categories.contains(category),
                  onChanged: (on) => setState(() => on ? _categories.add(category) : _categories.remove(category)),
                ),
              ListTile(
                title: Text('Zeitraum: $_days Tage'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Weniger',
                      icon: const Icon(Icons.remove),
                      onPressed: _days > 7 ? () => setState(() => _days = (_days - 7).clamp(7, 365)) : null,
                    ),
                    IconButton(
                      tooltip: 'Mehr',
                      icon: const Icon(Icons.add),
                      onPressed: _days < 365 ? () => setState(() => _days = (_days + 7).clamp(7, 365)) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
