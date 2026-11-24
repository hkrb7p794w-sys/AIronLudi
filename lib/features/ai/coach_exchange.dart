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

import 'package:share_plus/share_plus.dart';

import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../services/share/export_folders.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../gym/gym_screen.dart';
import '../plan/my_week_screen.dart';

part 'coach_import_screen.dart';

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
  final folder = await ExportFolders.fresh(ExportFolders.aiExport);
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
                      'Mit Prüfauftrag für $count offene Empfehlung${count == 1 ? '' : 'en'} aus „KI“ – die externe '
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
