import 'dart:async';
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';

/// KI-Stufe und bevorzugter Anbieter; darunter Anbieter im Worker und das Nutzungsprotokoll.
class AISettingsSection extends ConsumerWidget {
  const AISettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final ai = settings.ai;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return FormSection(
      header: 'KI',
      footer:
          'Empfehlungen, Ampel und Ziele kommen immer aus den Regeln der App; die KI formuliert und fasst nur '
          'zusammen. Fällt sie aus oder ist sie aus, bleibt alles nutzbar – auch Importe und der Export.',
      children: [
        ListTile(
          title: const Text('KI nutzen'),
          trailing: DropdownButton<AIMode>(
            value: ai.mode,
            underline: const SizedBox.shrink(),
            items: [for (final mode in AIMode.values) DropdownMenuItem(value: mode, child: Text(mode.label))],
            onChanged: (mode) => settings.ai = ai.copyWith(mode: mode),
          ),
          subtitle: Text(ai.mode.detail, style: muted),
        ),
        if (ai.mode != AIMode.off)
          ListTile(
            title: const Text('Anbieter'),
            trailing: DropdownButton<AIProviderChoice>(
              value: ai.provider,
              underline: const SizedBox.shrink(),
              items: [
                for (final provider in AIProviderChoice.values)
                  DropdownMenuItem(value: provider, child: Text(provider.label)),
              ],
              onChanged: (provider) => settings.ai = ai.copyWith(provider: provider),
            ),
            subtitle: Text(ai.provider.detail, style: muted),
          ),
        ListTile(
          title: const Text('Anbieter und Nutzung'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AIUsageScreen())),
        ),
      ],
    );
  }
}

/// Ein im Worker eingerichteter Anbieter (`/v1/health`).
final class WorkerProviderStatus {
  const WorkerProviderStatus({
    required this.id,
    required this.label,
    required this.enabled,
    this.model,
    required this.usesInputsForTraining,
  });

  final String id;
  final String label;
  final bool enabled;
  final String? model;
  final bool usesInputsForTraining;

  static WorkerProviderStatus? fromJson(Object? json) => switch (json) {
    {
      'id': final String id,
      'label': final String label,
      'enabled': final bool enabled,
      'usesInputsForTraining': final bool training,
    } =>
      WorkerProviderStatus(
        id: id,
        label: label,
        enabled: enabled,
        model: json['model'] is String ? json['model'] as String : null,
        usesInputsForTraining: training,
      ),
    _ => null,
  };
}

/// Eingerichtete Anbieter im Worker und internes Protokoll: Anfragen, Tokens, Listenpreis, Fehler.
class AIUsageScreen extends ConsumerStatefulWidget {
  const AIUsageScreen({super.key});

  static String dollars(double value) => value < 0.01 && value > 0 ? '< 0,01 \$' : '${GermanFormat.number(value)} \$';

  static String taskLabel(String task) => switch (task) {
    'daily_note' || 'personal_note' => 'Tagesnotiz',
    'meal_analyze' => 'Mahlzeit auswerten',
    'nutrition_label' => 'Etikett lesen',
    'nutrition_review' => 'Ernährung auswerten',
    'gym_hints' => 'Gym-Tipps',
    'gym_plan' => 'Trainingsplan',
    'coach_chat' => 'Chat',
    'meal_now' => 'Was jetzt?',
    'weekly_recipes' => 'Rezeptideen',
    'cook_plan' => 'Gemeinsam kochen',
    'ai_insights' => 'KI-Analyse',
    'ping' => 'Verbindungstest',
    _ => task,
  };

  @override
  ConsumerState<AIUsageScreen> createState() => _AIUsageScreenState();
}

class _AIUsageScreenState extends ConsumerState<AIUsageScreen> {
  int _days = 30;
  List<WorkerProviderStatus> _providers = const [];
  String? _providerError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(aiClientProvider).send('v1/health', method: 'GET');
      final json = jsonDecode(utf8.decode(data));
      final list = json is Map && json['providerList'] is List
          ? listStrict(json['providerList'], WorkerProviderStatus.fromJson) ?? const <WorkerProviderStatus>[]
          : const <WorkerProviderStatus>[];
      if (!mounted) return;
      setState(() {
        _providers = list;
        if (list.isEmpty) _providerError = 'Der Worker meldet keine Anbieterliste (ältere Version).';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _providerError = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(coachSettingsProvider).aiUsage;
    final since = DateTime.now().subtract(Duration(days: _days));
    final summary = AIUsageLog.summary(usage, since: since);
    final failures = usage.where((entry) => !entry.ok && !entry.date.isBefore(since)).take(5).toList();
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('KI-Anbieter und Nutzung')),
      body: ListView(
        children: [
          FormSection(
            header: 'Im Worker eingerichtet',
            footer:
                'Anbieter und Modelle stellst du im Worker ein (docs/ki-modelle.md). Fällt einer aus, nimmt der '
                'Worker den nächsten.',
            children: [
              if (_providers.isEmpty) ListTile(title: Text(_providerError ?? 'Wird geladen …', style: muted)),
              for (final provider in _providers)
                ListTile(
                  title: Text(provider.label),
                  trailing: Icon(
                    provider.enabled ? Icons.check_circle : Icons.remove_circle_outline,
                    color: provider.enabled ? Colors.green : Theme.of(context).colorScheme.outline,
                    semanticLabel: provider.enabled ? 'eingerichtet' : 'nicht eingerichtet',
                  ),
                  subtitle: provider.enabled && provider.model != null
                      ? Text(
                          provider.model! +
                              (provider.usesInputsForTraining ? ' · kostenloses Kontingent wertet Eingaben aus' : ''),
                        )
                      : null,
                ),
            ],
          ),
          FormSection(
            header: 'Nutzung',
            footer:
                'Listenpreis = was die Anfragen bei bezahlter Nutzung kosten würden. In den kostenlosen Kontingenten '
                '(Gemini, Cerebras, Groq, Mistral, GitHub Models, Workers AI bis 10.000 Neurons am Tag) und auf dem '
                'eigenen Server zahlst du nichts je Anfrage. Protokolliert werden nur Aufgabe, Anbieter, Modell, '
                'Tokens und Dauer – keine Inhalte.',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 Tage')),
                    ButtonSegment(value: 30, label: Text('30 Tage')),
                    ButtonSegment(value: 180, label: Text('180 Tage')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (selection) => setState(() => _days = selection.first),
                ),
              ),
              LabeledRow(label: 'Anfragen', value: '${summary.requests}'),
              LabeledRow(label: 'davon automatisch', value: '${summary.automatic}'),
              LabeledRow(label: 'fehlgeschlagen', value: '${summary.failures}'),
              LabeledRow(label: 'Listenpreis', value: AIUsageScreen.dollars(summary.listPriceUsd)),
            ],
          ),
          if (summary.lines.isNotEmpty) ...[
            FormSection(
              header: 'Je Anbieter und Modell',
              children: [
                for (final line in summary.lines)
                  ListTile(
                    title: Text('${AIUsageLog.providerLabel(line.provider)} · ${line.model}', maxLines: 2),
                    subtitle: Text(
                      '${line.requests} Anfragen · ${line.failures} Fehler · '
                      '${line.inputTokens + line.outputTokens} Tokens · '
                      'Ø ${GermanFormat.decimal(line.averageSeconds)} s · ${AIUsageScreen.dollars(line.listPriceUsd)}',
                    ),
                  ),
              ],
            ),
            FormSection(
              header: 'Je Aufgabe',
              children: [
                for (final item in summary.byTask)
                  LabeledRow(label: AIUsageScreen.taskLabel(item.task), value: '${item.count}'),
              ],
            ),
          ],
          if (failures.isNotEmpty)
            FormSection(
              header: 'Letzte Fehler',
              children: [
                for (final entry in failures)
                  ListTile(
                    title: Text(
                      '${AIUsageScreen.taskLabel(entry.task)} · '
                      '${DateFormat('d. MMM y, HH:mm', 'de_DE').format(entry.date.toLocal())}',
                    ),
                    subtitle: Text(entry.error ?? 'unbekannt'),
                  ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
