import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../gym/gym_screen.dart';
import '../plan/my_week_screen.dart';

/// Daten der App für Export und Prompts (Port von `ExportInput.make`).
Future<CoachExportInput> loadExportInput(WidgetRef ref) async {
  final settings = ref.read(coachSettingsProvider);
  final results = await (
    ref.read(metricsRepositoryProvider).all(),
    ref.read(activityRepositoryProvider).all(),
    ref.read(gymRepositoryProvider).all(),
    ref.read(mealRepositoryProvider).all(),
  ).wait;
  final metrics = [...results.$1]..sort((a, b) => a.day.compareTo(b.day));
  final activities = [...results.$2]..sort((a, b) => (a.startLocal ?? '').compareTo(b.startLocal ?? ''));
  final gym = [for (final record in results.$3) record.session]..sort((a, b) => a.start.compareTo(b.start));
  final meals = [...results.$4]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return CoachExportInput(
    profile: settings.coachingProfile,
    schedule: settings.schedule(CalendarDay.today()),
    routines: settings.gym.routines,
    custom: settings.gym.customExercises,
    equipment: settings.gym.equipment,
    metrics: metrics,
    activities: activities,
    gym: gym,
    meals: [
      for (final meal in meals)
        if (!meal.isWater)
          ExportMeal(day: meal.day, category: meal.category.label, title: meal.title, items: meal.items),
    ],
    weights: ref.read(appModelProvider).allWeights,
    userSources: settings.userSources,
    reports: ref.read(garminSyncServiceProvider).reportStore.load().values.toList(),
    insights: settings.insights,
    now: DateTime.now(),
  );
}

/// Schreibt die Dateien in einen eigenen temporären Ordner (alte Exporte werden ersetzt).
Future<List<XFile>> writeExportFiles(List<ExportFile> files) async {
  final folder = Directory(p.join((await getTemporaryDirectory()).path, 'ki-export'));
  if (folder.existsSync()) folder.deleteSync(recursive: true);
  folder.createSync(recursive: true);
  return [
    for (final file in files)
      () {
        final path = p.join(folder.path, file.name);
        File(path).writeAsStringSync(file.content);
        return XFile(path, mimeType: file.name.endsWith('.json') ? 'application/json' : 'text/plain');
      }(),
  ];
}

/// Zeitraum eines Exports: Vorgabe (7, 30, 90, 365 Tage) oder eigene Daten.
final class ExportRange {
  ExportRange({this.presetDays = 30, CalendarDay? from, CalendarDay? to})
    : from = from ?? CalendarDay.today().adding(-29),
      to = to ?? CalendarDay.today();

  int? presetDays;
  CalendarDay from;
  CalendarDay to;

  CalendarDay get start {
    if (presetDays case final days?) return CalendarDay.today().adding(-(days - 1));
    return from <= to ? from : to;
  }

  CalendarDay get end => presetDays == null ? (from <= to ? to : from) : CalendarDay.today();
}

class ExportRangeSection extends StatelessWidget {
  const ExportRangeSection({super.key, required this.range, required this.onChanged});

  final ExportRange range;
  final VoidCallback onChanged;

  Future<void> _pick(BuildContext context, {required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? range.from : range.to).referenceDate,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      locale: const Locale('de', 'DE'),
    );
    if (picked == null) return;
    if (from) {
      range.from = CalendarDay.fromDate(picked);
    } else {
      range.to = CalendarDay.fromDate(picked);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) => FormSection(
    footer: 'Zeitraum: ${range.start.iso} bis ${range.end.iso}',
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<int?>(
          initialValue: range.presetDays,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Zeitraum'),
          items: [
            for (final preset in CoachExport.presets) DropdownMenuItem(value: preset.days, child: Text(preset.label)),
            const DropdownMenuItem(child: Text('Eigener')),
          ],
          onChanged: (days) {
            range.presetDays = days;
            onChanged();
          },
        ),
      ),
      if (range.presetDays == null) ...[
        ListTile(
          title: const Text('Von'),
          trailing: Text(GermanFormat.date(range.from)),
          onTap: () => _pick(context, from: true),
        ),
        ListTile(
          title: const Text('Bis'),
          trailing: Text(GermanFormat.date(range.to)),
          onTap: () => _pick(context, from: false),
        ),
      ],
    ],
  );
}

/// KI-Export: Zeitraum, Daten und Format wählen; als Datei teilen oder kopieren. Mit „Antwortformat beilegen“ ist es
/// Teil 1 des manuellen KI-Coachs (Port von `CoachExportView`).
class CoachExportScreen extends ConsumerStatefulWidget {
  const CoachExportScreen({super.key});

  @override
  ConsumerState<CoachExportScreen> createState() => _CoachExportScreenState();
}

class _CoachExportScreenState extends ConsumerState<CoachExportScreen> {
  final _range = ExportRange();
  final _categories = {...ExportCategory.values};
  ExportFormat _format = ExportFormat.markdown;
  bool _withImportFormat = true;
  CoachExportInput? _input;
  List<ExportFile> _files = const [];
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    loadExportInput(ref).then((input) {
      if (mounted) setState(() => _input = input);
    });
  }

  void _reset() => setState(() {
    _files = const [];
    _copied = false;
  });

  String get _formatNote => switch (_format) {
    ExportFormat.markdown =>
      'Lesbar für Menschen und jede KI. Mit Antwortformat schlägt die KI Planänderungen so vor, dass die App sie '
          'prüfen und übernehmen kann.',
    ExportFormat.json => 'Strukturiert mit festen Feldnamen; fehlende Werte sind null. Gut für längere Analysen.',
    ExportFormat.csv => 'Eine Tabelle je Bereich – gut für Tabellenkalkulationen und Datenanalyse-Werkzeuge.',
  };

  void _make(CoachExportInput input) {
    final (from, to) = (_range.start, _range.end);
    final stem = 'IronLudi-${from.iso}-bis-${to.iso}';
    setState(() {
      _files = switch (_format) {
        ExportFormat.markdown => [
          ExportFile(
            name: '$stem.md',
            content: DataExport.markdown(
              input,
              from: from,
              to: to,
              categories: _categories,
              withImportFormat: _withImportFormat,
            ),
          ),
        ],
        ExportFormat.json => [
          ExportFile(
            name: '$stem.json',
            content: DataExport.json(input, from: from, to: to, categories: _categories),
          ),
        ],
        ExportFormat.csv => DataExport.csv(input, from: from, to: to, categories: _categories),
      };
      _copied = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final input = _input;
    final counts = input == null
        ? const <ExportCategory, int>{}
        : DataExport.counts(input, from: _range.start, to: _range.end);
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Daten für KI exportieren')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ExportRangeSection(range: _range, onChanged: _reset),
          FormSection(
            header: 'Daten',
            footer: 'Profil und Ziel sind immer dabei. Ohne Einträge im Zeitraum bleibt ein Bereich leer.',
            children: [
              for (final category in ExportCategory.values)
                SwitchListTile.adaptive(
                  title: Text(category.label),
                  subtitle: Text('${counts[category] ?? 0} Einträge · ${category.detail}'),
                  value: _categories.contains(category),
                  onChanged: (on) {
                    on ? _categories.add(category) : _categories.remove(category);
                    _reset();
                  },
                ),
            ],
          ),
          FormSection(
            footer: _formatNote,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<ExportFormat>(
                  initialValue: _format,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Format'),
                  items: [
                    for (final format in ExportFormat.values)
                      DropdownMenuItem(value: format, child: Text(format.label)),
                  ],
                  onChanged: (format) {
                    _format = format ?? _format;
                    _reset();
                  },
                ),
              ),
              if (_format == ExportFormat.markdown)
                SwitchListTile.adaptive(
                  title: const Text('Antwortformat für den Import beilegen'),
                  subtitle: switch (input?.openInsights.length ?? 0) {
                    0 => null,
                    final count => Text(
                      'Mit Prüfauftrag für $count offene Empfehlung${count == 1 ? '' : 'en'} aus „AI“ – die externe '
                      'KI bestätigt, verbessert oder verwirft sie.',
                    ),
                  },
                  value: _withImportFormat,
                  onChanged: (on) {
                    _withImportFormat = on;
                    _reset();
                  },
                ),
            ],
          ),
          FormSection(
            footer:
                'Die Dateien enthalten Gesundheitsdaten. Teile sie nur mit Diensten, denen du sie anvertrauen willst – '
                'oder nutze ein lokales Modell.',
            children: [
              ListTile(
                enabled: input != null && _categories.isNotEmpty,
                leading: const Icon(Icons.upload_file),
                title: const Text('Export erstellen'),
                onTap: input == null ? null : () => _make(input),
              ),
              if (_files.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: Text(_files.length == 1 ? 'Datei teilen' : '${_files.length} Dateien teilen'),
                  onTap: () async {
                    final files = await writeExportFiles(_files);
                    await SharePlus.instance.share(ShareParams(files: files));
                  },
                ),
                if (_format != ExportFormat.csv)
                  ListTile(
                    leading: Icon(_copied ? Icons.check : Icons.copy),
                    title: Text(_copied ? 'Kopiert' : 'Als Text kopieren'),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: _files.first.content));
                      setState(() => _copied = true);
                    },
                  ),
              ],
              if (input == null)
                ListTile(
                  title: Text('Daten werden geladen …', style: TextStyle(color: secondary)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Manueller KI-Coach, Teil 2: die Antwort der KI einfügen, von den Regeln prüfen lassen und übernehmen (Port von
/// `CoachImportView`).
class CoachImportScreen extends ConsumerStatefulWidget {
  const CoachImportScreen({super.key});

  @override
  ConsumerState<CoachImportScreen> createState() => _CoachImportScreenState();
}

class _CoachImportScreenState extends ConsumerState<CoachImportScreen> {
  final _text = TextEditingController();
  ImportPreview? _preview;
  ImportSelection _selection = ImportSelection();
  String? _error;
  bool _applied = false;

  final _scroll = ScrollController();

  /// Was beim letzten Übernehmen dabei war (für die Wege dorthin).
  ({bool routines, bool schedule, bool notes, bool insights})? _appliedParts;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (_preview != null || _error != null || _applied) {
        setState(() {
          _preview = null;
          _error = null;
          _applied = false;
        });
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  CalendarDay get _nextMonday => PlanAdjustments.monday(CalendarDay.today()).adding(7);

  /// Plan, mit dem der Vorschlag verglichen wird (dauerhaft bzw. nächste Woche).
  WeekSchedule get _currentSchedule {
    final settings = ref.read(coachSettingsProvider);
    return switch (_selection.scheduleScope) {
      ScheduleScope.permanent => settings.profile.schedule,
      ScheduleScope.nextWeek => settings.schedule(_nextMonday),
    };
  }

  static String _slots(List<SessionSlot> slots) => slots.isEmpty ? 'frei' : slots.map((slot) => slot.title).join(', ');

  static String _itemText(RoutineItem item) {
    final weight = item.weightKg == null ? '' : ', ${GermanFormat.number(item.weightKg!)} kg';
    return '${item.name}: ${item.sets} × ${item.lowerReps}–${item.upperReps}, Pause ${item.restSeconds} s$weight';
  }

  /// Antwort als Datei (z. B. aus Claude heruntergeladen oder über „Teilen“ gesichert): Text übernehmen und prüfen.
  Future<void> _loadFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'txt', 'json', 'markdown'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null || !mounted) return;
    final bytes = await File(path).readAsBytes();
    _text.text = utf8.decode(bytes, allowMalformed: true);
    _check();
  }

  void _check() {
    final settings = ref.read(coachSettingsProvider);
    try {
      final checked = CoachImport.preview(
        _text.text,
        profile: settings.profile,
        equipment: settings.gym.equipment,
        custom: settings.gym.customExercises,
        now: DateTime.now(),
      );
      setState(() {
        _selection = ImportSelection.defaults(
          checked,
          existing: settings.gym.routines,
          existingInsights: settings.insights,
          currentSchedule: checked.scheduleScope == ScheduleScope.nextWeek
              ? settings.schedule(_nextMonday)
              : settings.profile.schedule,
        );
        _preview = checked;
        _applied = false;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _preview = null;
        _error = '$error';
      });
    }
  }

  void _apply(ImportPreview preview) {
    final settings = ref.read(coachSettingsProvider);
    _appliedParts = (
      routines:
          _selection.replaceAllRoutines ||
          preview.routines.any((routine) => _selection.choice(routine) != RoutineChoice.skip),
      schedule: CoachImport.schedule(preview, selection: _selection, current: _currentSchedule) != null,
      notes: _selection.notes.isNotEmpty,
      insights:
          preview.insights.any((insight) => _selection.insights.contains(insight.id)) ||
          preview.dismiss.any(_selection.dismiss.contains),
    );
    if (preview.routines.isNotEmpty) {
      final gym = settings.gym;
      gym.routines = CoachImport.routines(preview, selection: _selection, existing: gym.routines);
      settings.gym = gym;
    }
    if (CoachImport.schedule(preview, selection: _selection, current: _currentSchedule) case final schedule?) {
      switch (_selection.scheduleScope) {
        case ScheduleScope.permanent:
          settings.profile = settings.profile..schedule = schedule;
        case ScheduleScope.nextWeek:
          settings.planAdjustments = settings.planAdjustments
            ..setWeekPlan(schedule, base: settings.profile.schedule, inWeekOf: _nextMonday);
      }
    }
    final notes = CoachImport.notes(preview, selection: _selection);
    if (notes.isNotEmpty) settings.importedNotes = ImportedNotes(day: CalendarDay.today(), texts: notes);
    if (preview.insights.isNotEmpty || preview.dismiss.isNotEmpty) {
      final updated = CoachImport.applyInsights(
        preview,
        selection: _selection,
        existing: settings.insights,
        now: DateTime.now(),
      );
      if (!listEquals(updated, settings.insights)) settings.insights = updated;
    }
    setState(() => _applied = true);
    // Nach oben zu „Übernommen“ mit den Wegen zum Plan.
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final canApply = preview != null && !_applied && CoachImport.hasChanges(preview, selection: _selection);
    return Scaffold(
      appBar: AppBar(title: const Text('KI-Antwort importieren')),
      // Übernehmen bleibt sichtbar, auch wenn die Vorschau lang ist – sonst bleibt es leicht beim „Prüfen“.
      bottomNavigationBar: preview == null || _applied
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  onPressed: canApply ? () => _apply(preview) : null,
                  icon: const Icon(Icons.download),
                  label: Text(canApply ? 'Auswahl übernehmen' : 'Nichts ausgewählt'),
                ),
              ),
            ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (_applied) ..._appliedSections(),
          FormSection(
            header: 'Antwort der KI',
            footer:
                'Die ganze Antwort einfügen oder als Datei laden (z. B. aus Claude heruntergeladen). Die App findet den '
                'Plan auch, wenn die KI vom Format abweicht – was sie übernimmt, siehst du vor dem Übernehmen.',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _text,
                  minLines: 6,
                  maxLines: 14,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Antwort einfügen'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: const Text('Aus Zwischenablage einfügen'),
                onTap: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  _text.text = data?.text ?? '';
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: const Text('Aus Datei laden'),
                subtitle: const Text('.md, .txt oder .json'),
                onTap: () => unawaited(_loadFile()),
              ),
              ListTile(
                enabled: _text.text.trim().isNotEmpty,
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Prüfen'),
                onTap: _check,
              ),
              if (_error case final error?)
                ListTile(
                  title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.red)),
                ),
            ],
          ),
          if (preview != null) ..._previewSections(preview),
        ],
      ),
    );
  }

  /// Nach dem Übernehmen: was übernommen wurde und wo es zu finden ist.
  List<Widget> _appliedSections() {
    final parts = _appliedParts;
    void open(Widget screen) => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));
    return [
      FormSection(
        header: 'Übernommen',
        children: [
          const ListTile(
            leading: Icon(Icons.check_circle, color: Colors.green),
            title: Text(
              'Übernommen',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
            ),
          ),
          if (parts?.routines ?? false)
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: const Text('Trainingspläne ansehen'),
              subtitle: const Text('Training › Gym'),
              trailing: const DisclosureChevron(),
              onTap: () => open(const GymScreen()),
            ),
          if (parts?.schedule ?? false)
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(
                _selection.scheduleScope == ScheduleScope.nextWeek
                    ? 'Plan der nächsten Woche ansehen'
                    : 'Wochenplan ansehen',
              ),
              subtitle: const Text('Training › Plan'),
              trailing: const DisclosureChevron(),
              onTap: () => open(const MyWeekScreen()),
            ),
          if (parts?.notes ?? false)
            const ListTile(
              leading: Icon(Icons.sticky_note_2_outlined),
              title: Text('Hinweise'),
              subtitle: Text('Heute › „Diese Woche, Ziele und Verlauf“'),
            ),
          if (parts?.insights ?? false)
            const ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text('Empfehlungen'),
              subtitle: Text('Heute › AI-Empfehlungen'),
            ),
        ],
      ),
    ];
  }

  List<Widget> _previewSections(ImportPreview preview) {
    final settings = ref.watch(coachSettingsProvider);
    final schedule = preview.schedule;
    final current = _currentSchedule;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return [
      if (preview.routines.isNotEmpty)
        FormSection(
          header: 'Trainingspläne',
          footer: _selection.replaceAllRoutines
              ? 'Achtung: Deine bisherigen Trainingspläne werden gelöscht; übrig bleiben nur die übernommenen.'
              : 'Für jeden Trainingsplan einzeln: bestehende gleichnamige ersetzen, zusätzlich anlegen oder weglassen.',
          children: [
            SwitchListTile.adaptive(
              title: const Text('Alle bisherigen Trainingspläne löschen'),
              value: _selection.replaceAllRoutines,
              onChanged: (on) => setState(() => _selection.replaceAllRoutines = on),
            ),
            for (final routine in preview.routines)
              () {
                final exists = settings.gym.routines.any((item) => item.name == routine.name);
                final choice = _selection.choice(routine);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(routine.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      for (final item in routine.items)
                        Text(_itemText(item), style: TextStyle(fontSize: 12, color: secondary)),
                      DropdownButton<RoutineChoice>(
                        value: choice,
                        isExpanded: true,
                        items: [
                          for (final option in RoutineChoice.values)
                            if (option != RoutineChoice.replace || exists || _selection.replaceAllRoutines)
                              DropdownMenuItem(value: option, child: Text(option.label)),
                        ],
                        onChanged: (value) => setState(() => _selection.routines[routine.id] = value ?? choice),
                      ),
                      if (exists && !_selection.replaceAllRoutines)
                        Text(
                          choice == RoutineChoice.replace
                              ? 'Ersetzt deinen Trainingsplan „${routine.name}“.'
                              : 'Dein Trainingsplan „${routine.name}“ bleibt erhalten.',
                          style: const TextStyle(fontSize: 11, color: Colors.orange),
                        ),
                    ],
                  ),
                );
              }(),
          ],
        ),
      if (schedule != null)
        FormSection(
          header: 'Wochenplan',
          footer: 'Nur die Tage mit Änderungen; abgewählte Tage bleiben wie bisher.',
          children: [
            SwitchListTile.adaptive(
              title: const Text('Wochenplan übernehmen'),
              value: _selection.schedule,
              onChanged: (on) => setState(() => _selection.schedule = on),
            ),
            if (_selection.schedule) ...[
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ScheduleScope>(
                    segments: const [
                      ButtonSegment(value: ScheduleScope.permanent, label: Text('Dauerhaft')),
                      ButtonSegment(value: ScheduleScope.nextWeek, label: Text('Nur nächste Woche')),
                    ],
                    selected: {_selection.scheduleScope},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => setState(() => _selection.scheduleScope = selection.first),
                  ),
                ),
              ),
              for (final weekday in Weekday.values)
                if (schedule.slots(weekday) case final proposed
                    when !const ListEquality<SessionSlot>().equals(proposed, current.slots(weekday)))
                  CheckboxListTile(
                    value: _selection.scheduleDays.contains(weekday),
                    onChanged: (on) => setState(
                      () =>
                          on ?? false ? _selection.scheduleDays.add(weekday) : _selection.scheduleDays.remove(weekday),
                    ),
                    title: Text(weekday.long, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('bisher: ${_slots(current.slots(weekday))}\nneu: ${_slots(proposed)}'),
                  ),
            ],
          ],
        ),
      if (preview.notes.isNotEmpty)
        FormSection(
          header: 'Hinweise der KI',
          footer: 'Ausgewählte Hinweise ersetzen die Hinweise des letzten Imports.',
          children: [
            for (final (index, note) in preview.notes.indexed)
              CheckboxListTile(
                value: _selection.notes.contains(index),
                onChanged: (on) =>
                    setState(() => on ?? false ? _selection.notes.add(index) : _selection.notes.remove(index)),
                title: Text(note),
              ),
          ],
        ),
      if (preview.insights.isNotEmpty) _insightSection(preview, settings.insights),
      if (preview.dismiss.isNotEmpty) _dismissSection(preview, settings.insights),
      if (preview.corrections.isNotEmpty || preview.ruleNotes.isNotEmpty)
        FormSection(
          header: 'Geprüft von den Regeln',
          children: [
            for (final correction in preview.corrections)
              ListTile(dense: true, leading: const Icon(Icons.cancel_outlined), title: Text(correction)),
            for (final note in preview.ruleNotes)
              ListTile(dense: true, leading: const Icon(Icons.info_outline), title: Text(note)),
          ],
        ),
      FormSection(
        footer: preview.isEmpty
            ? 'Im Block war nichts, was die App übernehmen kann – die Gründe stehen unter „Geprüft von den Regeln“.'
            : 'Trainingspläne und Wochenplan lassen sich danach wie gewohnt bearbeiten; die Hinweise stehen unter '
                  '„Heute“ › „Diese Woche, Ziele und Verlauf“.',
        children: const [],
      ),
    ];
  }

  static String _origin(Insight insight) => insight.origin == InsightOrigin.rules
      ? 'Regeln der App'
      : 'KI${insight.model == null ? '' : ' (${insight.model})'}';

  /// Empfehlungen der externen KI: je Eintrag übernehmen oder nicht; ersetzt sie eine bestehende, steht diese dabei.
  Widget _insightSection(ImportPreview preview, List<Insight> existing) {
    final byID = {for (final insight in existing) insight.id: insight};
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return FormSection(
      header: 'Empfehlungen von ${preview.model}',
      footer:
          'Angehakte Empfehlungen erscheinen im Bereich „AI“; eine bestehende mit gleichem Thema wird überschrieben. '
          'Empfehlungen der Regeln sind nicht vorausgewählt – sie beruhen auf festen, geprüften Regeln.',
      children: [
        for (final insight in preview.insights)
          CheckboxListTile(
            value: _selection.insights.contains(insight.id),
            onChanged: (on) => setState(
              () => on ?? false ? _selection.insights.add(insight.id) : _selection.insights.remove(insight.id),
            ),
            title: Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(insight.text),
                if (byID[insight.id] case final old?)
                  Text(
                    'Überschreibt: „${old.title}“ (${_origin(old)})',
                    style: TextStyle(
                      fontSize: 12,
                      color: old.origin == InsightOrigin.rules ? Colors.orange : secondary,
                    ),
                  )
                else
                  Text('Neu', style: TextStyle(fontSize: 12, color: secondary)),
              ],
            ),
          ),
      ],
    );
  }

  /// Bestehende Empfehlungen, die die externe KI für falsch oder überholt hält.
  Widget _dismissSection(ImportPreview preview, List<Insight> existing) {
    final byID = {for (final insight in existing) insight.id: insight};
    final known = [for (final id in preview.dismiss) ?byID[id]];
    return FormSection(
      header: 'Als falsch oder überholt markiert',
      footer: known.isEmpty
          ? 'Keine dieser Empfehlungen gibt es (noch) in der App.'
          : 'Angehakte Empfehlungen werden verworfen; du findest sie unter „Umgesetzt und verworfen“.',
      children: [
        for (final insight in known)
          CheckboxListTile(
            value: _selection.dismiss.contains(insight.id),
            onChanged: (on) => setState(
              () => on ?? false ? _selection.dismiss.add(insight.id) : _selection.dismiss.remove(insight.id),
            ),
            title: Text(insight.title),
            subtitle: Text(_origin(insight)),
          ),
      ],
    );
  }
}
