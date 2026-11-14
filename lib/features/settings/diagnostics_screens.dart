import 'dart:async';
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/database.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';

/// Zeigt, was Garmin tatsächlich liefert: Fehler des letzten Abrufs, befüllte Tageswerte und die Feldnamen jeder
/// Rohantwort. Damit lässt sich die Zuordnung an echte Daten anpassen (Port von `GarminDiagnosticsView`).
class GarminDiagnosticsScreen extends ConsumerStatefulWidget {
  const GarminDiagnosticsScreen({super.key});

  @override
  ConsumerState<GarminDiagnosticsScreen> createState() => _GarminDiagnosticsScreenState();
}

class _GarminDiagnosticsScreenState extends ConsumerState<GarminDiagnosticsScreen> {
  List<RawResponseRow> _responses = const [];
  DailyMetrics? _latest;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final results = await (
      ref.read(rawResponseRepositoryProvider).all(),
      ref.read(metricsRepositoryProvider).all(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _responses = results.$1;
      _latest = results.$2.lastOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(appModelProvider).lastReport;
    final latest = _latest;
    final secondary = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final time = DateFormat('d. MMM, HH:mm', 'de_DE');
    return Scaffold(
      appBar: AppBar(title: const Text('Garmin-Diagnose')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (report != null)
            FormSection(
              header: 'Letzter Abruf',
              children: [
                ListTile(title: Text(report.summary)),
                for (final error in report.errors)
                  ListTile(
                    dense: true,
                    title: Text(error, style: const TextStyle(color: Colors.orange)),
                  ),
              ],
            ),
          if (latest != null)
            FormSection(
              header: 'Befüllte Werte (${latest.day.iso})',
              children: [
                ListTile(title: Text(latest.presentFields.isEmpty ? 'keine' : latest.presentFields.join(', '))),
              ],
            ),
          FormSection(
            header: 'Rohantworten',
            children: [
              if (_responses.isEmpty) ListTile(title: Text('Noch kein Abruf.', style: secondary)),
              for (final response in _responses)
                ListTile(
                  title: Text(response.endpoint, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  subtitle: Text('${response.body.length} Bytes · ${time.format(response.fetchedAt)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => RawResponseScreen(record: response))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Feldnamen einer Rohantwort, ohne Werte (zum Teilen bei Fehlersuche).
class RawResponseScreen extends StatelessWidget {
  const RawResponseScreen({super.key, required this.record});

  final RawResponseRow record;

  static List<String> keyPaths(List<int> body) {
    try {
      return JsonValue(jsonDecode(utf8.decode(body))).keyPaths(limit: 300);
    } on Object {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final paths = keyPaths(record.body);
    return Scaffold(
      appBar: AppBar(
        title: Text(record.endpoint),
        actions: [
          IconButton(
            tooltip: 'Feldliste teilen',
            icon: const Icon(Icons.ios_share),
            onPressed: () => SharePlus.instance.share(ShareParams(text: paths.join('\n'))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Felder (ohne Werte)',
            children: [
              if (paths.isEmpty) const ListTile(title: Text('Leere oder keine JSON-Antwort')),
              for (final path in paths)
                ListTile(
                  dense: true,
                  title: Text(path, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Prüft, ob Apple Health bzw. Health Connect in dieser Installation funktioniert (Port von `DiagnosticsView`).
class HealthDiagnosticsScreen extends ConsumerStatefulWidget {
  const HealthDiagnosticsScreen({super.key});

  @override
  ConsumerState<HealthDiagnosticsScreen> createState() => _HealthDiagnosticsScreenState();
}

class _HealthDiagnosticsScreenState extends ConsumerState<HealthDiagnosticsScreen> {
  HealthAccessDiagnosis _diagnosis = HealthAccessDiagnosis.notDetermined;
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final diagnosis = await ref.read(healthProbeProvider)();
    if (!mounted) return;
    setState(() {
      _diagnosis = diagnosis;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis = _diagnosis;
    final (icon, color) = switch (diagnosis) {
      HealthWorking() => (Icons.check_circle, Colors.green),
      _ when diagnosis == HealthAccessDiagnosis.notDetermined => (
        Icons.help_outline,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      _ => (Icons.warning_amber, Colors.orange),
    };
    final version = ref.watch(appVersionProvider).value ?? '?';
    return Scaffold(
      appBar: AppBar(title: const Text('HealthKit')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'HealthKit',
            footer: 'Fragt Lesezugriff auf Workouts, Schlaf und Herzfrequenz sowie Schreibzugriff für Workouts an.',
            children: [
              ListTile(
                title: const Text('Status'),
                subtitle: Row(
                  spacing: 6,
                  children: [
                    Icon(icon, color: color, size: 18),
                    Expanded(
                      child: Text(diagnosis.title, style: TextStyle(color: color)),
                    ),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                title: Text(diagnosis.detail, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ListTile(
                enabled: !_checking,
                title: _checking
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : const Text('HealthKit prüfen'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: _check,
              ),
            ],
          ),
          FormSection(
            header: 'App',
            children: [LabeledRow(label: 'Version', value: version)],
          ),
        ],
      ),
    );
  }
}
