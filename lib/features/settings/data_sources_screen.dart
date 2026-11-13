import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';

/// „vor 3 Stunden“ wie `.relative(presentation: .named)`.
String relativeTime(DateTime date, {DateTime? now}) {
  final difference = (now ?? DateTime.now()).difference(date);
  if (difference.inMinutes < 1) return 'gerade eben';
  if (difference.inHours < 1) return 'vor ${difference.inMinutes} Minuten';
  if (difference.inDays < 1) return difference.inHours == 1 ? 'vor 1 Stunde' : 'vor ${difference.inHours} Stunden';
  if (difference.inDays == 1) return 'gestern';
  return 'vor ${difference.inDays} Tagen';
}

/// Datenquellen: verbundene Anbieter mit Synchronisierungsstatus, primäres Gerät, bevorzugte Quelle je Datenart und
/// woher die Werte von heute stammen. Anbieter ohne eingebaute Anbindung werden ehrlich als solche gezeigt.
class DataSourcesScreen extends ConsumerStatefulWidget {
  const DataSourcesScreen({super.key});

  @override
  ConsumerState<DataSourcesScreen> createState() => _DataSourcesScreenState();
}

class _DataSourcesScreenState extends ConsumerState<DataSourcesScreen> {
  bool _syncing = false;
  Map<DataKind, DataProvider> _today = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadToday());
  }

  Future<void> _loadToday() async {
    final today = await ref.read(appModelProvider).sources.sources(CalendarDay.today());
    if (mounted) setState(() => _today = today);
  }

  Future<void> _changePreferences(SourcePreferences preferences) async {
    final model = ref.read(appModelProvider);
    model.settings.sources = preferences;
    await model.applySourcePreferences();
    await _loadToday();
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appModelProvider);
    final settings = ref.watch(coachSettingsProvider);
    final connected = model.connectedSources;
    final states = model.sources.syncStates;
    final choosable = DataKind.values
        .where((kind) => connected.where((provider) => provider.capabilities.contains(kind)).length > 1)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Datenquellen')),
      body: ListView(
        children: [
          FormSection(
            header: 'Anbieter',
            footer:
                'Automatisch beim Öffnen der App und im Hintergrund (das System entscheidet wann). Nach Fehlern wartet '
                'der automatische Abruf länger; „Jetzt abrufen“ geht immer und holt verpasste Tage nach.',
            children: [
              for (final provider in DataProvider.values)
                _ProviderRow(provider: provider, connected: connected.contains(provider), state: states[provider]),
              ListTile(
                leading: const Icon(Icons.sync),
                title: Text(_syncing ? 'Wird abgerufen …' : 'Jetzt alle abrufen'),
                enabled: !_syncing && connected.isNotEmpty,
                onTap: () async {
                  setState(() => _syncing = true);
                  await model.syncNow();
                  await _loadToday();
                  if (mounted) setState(() => _syncing = false);
                },
              ),
            ],
          ),
          if (connected.length > 1) ...[
            FormSection(
              footer:
                  'Das primäre Gerät gewinnt nur bei seinen Stärken (Garmin: Training, Belastung, Body Battery; WHOOP: '
                  'Schlaf, HRV, Recovery). Für alles andere gilt die bewährte Reihenfolge – oder deine Wahl unten.',
              children: [
                ListTile(
                  title: const Text('Primäres Gerät'),
                  trailing: DropdownButton<DataProvider?>(
                    value: settings.sources.primary,
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(child: Text('Keins')),
                      for (final provider in DataProvider.values.where(connected.contains))
                        DropdownMenuItem(value: provider, child: Text(provider.label)),
                    ],
                    onChanged: (provider) => _changePreferences(
                      SourcePreferences(primary: provider, overrides: {...settings.sources.overrides}),
                    ),
                  ),
                ),
              ],
            ),
            FormSection(
              header: 'Bevorzugte Quelle je Datenart',
              footer:
                  'Je Datenart zählt genau eine Quelle – keine doppelten Aktivitäten, Kalorien oder Belastungen und '
                  'keine gemischten Werte. Fehlen bei der bevorzugten Quelle Werte für einen Tag, springt die nächste '
                  'ein.',
              children: [
                for (final kind in choosable)
                  ListTile(
                    title: Text(kind.label),
                    trailing: DropdownButton<DataProvider?>(
                      value: settings.sources.overrides[kind],
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(
                          child: Text(
                            'Automatisch (${SourcePreferences(primary: settings.sources.primary).preferred(kind, connected: connected)?.label ?? '–'})',
                          ),
                        ),
                        for (final provider in DataProvider.values.where(
                          (provider) => connected.contains(provider) && provider.capabilities.contains(kind),
                        ))
                          DropdownMenuItem(value: provider, child: Text(provider.label)),
                      ],
                      onChanged: (provider) {
                        final overrides = {...settings.sources.overrides};
                        if (provider == null) {
                          overrides.remove(kind);
                        } else {
                          overrides[kind] = provider;
                        }
                        _changePreferences(SourcePreferences(primary: settings.sources.primary, overrides: overrides));
                      },
                    ),
                  ),
              ],
            ),
          ],
          if (_today.isNotEmpty)
            FormSection(
              header: 'Herkunft der Werte von heute',
              children: [
                for (final kind in MetricsMerge.dailyKinds.where(_today.containsKey))
                  LabeledRow(label: kind.label, value: _today[kind]?.label ?? '–'),
              ],
            ),
          FormSection(
            children: [
              ListTile(
                title: const Text('Welche Anbieter gehen?'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const IntegrationMatrixScreen())),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider, required this.connected, required this.state});

  final DataProvider provider;
  final bool connected;
  final ProviderSyncState? state;

  @override
  Widget build(BuildContext context) {
    final error = state?.lastError;
    final status = connected
        ? (error == null ? 'verbunden' : 'Fehler')
        : switch (provider.availability) {
            ProviderAvailability.available => 'nicht verbunden',
            ProviderAvailability.planned => 'noch nicht eingebaut',
            ProviderAvailability.unavailable => 'nicht verfügbar',
          };
    final color = connected
        ? (error == null ? Colors.green : Colors.orange)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final small = Theme.of(context).textTheme.bodySmall;
    return ListTile(
      title: Text(provider.label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Text(status, style: small?.copyWith(color: color)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (connected && state != null) ...[
            if (error != null)
              Text(
                'Letzter Fehler: $error',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: small?.copyWith(color: Colors.orange),
              ),
            if (state!.lastSuccess case final success?) Text('Zuletzt erfolgreich ${relativeTime(success)}'),
          ] else if (!connected)
            Text(provider.availabilityNote),
        ],
      ),
    );
  }
}

/// Integrationsmatrix: was die Anbieter offiziell anbieten und was davon in der App ist.
class IntegrationMatrixScreen extends StatelessWidget {
  const IntegrationMatrixScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Anbieter')),
    body: ListView(
      children: [
        for (final provider in DataProvider.values)
          FormSection(
            header: provider.label,
            children: [
              ListTile(title: Text(provider.availabilityNote)),
              LabeledRow(
                label: 'Datenarten',
                value: DataKind.values.where(provider.capabilities.contains).map((kind) => kind.label).join(', '),
              ),
            ],
          ),
        const FormSection(footer: 'Ausführlich mit Quellen: docs/integrationen.md im Repository.', children: []),
      ],
    ),
  );
}
