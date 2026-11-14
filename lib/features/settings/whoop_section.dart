import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/providers.dart';
import '../../services/whoop/whoop_service.dart';
import '../../ui/components.dart';

/// WHOOP verbinden, Stand und Trennen (Einstellungen › Training und Fitness).
class WhoopSection extends ConsumerStatefulWidget {
  const WhoopSection({super.key, this.openUrl});

  /// Für Tests; sonst der Browser.
  final Future<bool> Function(Uri url)? openUrl;

  @override
  ConsumerState<WhoopSection> createState() => _WhoopSectionState();
}

class _WhoopSectionState extends ConsumerState<WhoopSection> {
  String? _message;
  bool _busy = false;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final url = await ref.read(whoopServiceProvider).beginConnect();
      final open = widget.openUrl ?? (url) => launchUrl(url, mode: LaunchMode.externalApplication);
      if (!await open(url)) _message = 'Browser ließ sich nicht öffnen.';
    } on WhoopError catch (error) {
      _message = error.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WHOOP trennen?'),
        content: const Text(
          'Der Zugriff wird bei WHOOP widerrufen. Schon übernommene Werte und Trainings bleiben erhalten.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Trennen')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(whoopServiceProvider).disconnect();
    if (mounted) setState(() => _message = 'WHOOP getrennt.');
  }

  @override
  Widget build(BuildContext context) {
    final whoop = ref.watch(whoopServiceProvider);
    final syncing = ref.watch(appModelProvider.select((model) => model.isSyncing)) || whoop.isSyncing;
    final secondary = TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final time = DateFormat('d. MMM, HH:mm', 'de_DE');
    final profile = whoop.profile;
    final body = whoop.body;
    final last = whoop.lastSync;
    return FormSection(
      header: 'WHOOP',
      footer:
          'Recovery, HRV, Ruhepuls, Schlaf mit Phasen, Kalorien, Schritte und Trainings über die offizielle WHOOP-API. '
          'Welche Quelle bei Schlaf, HRV usw. zählt, steht unter Health und Erholung › Datenquellen und Vorrang. '
          'Einrichtung im Worker: docs/whoop.md (Coach-App).',
      children: [
        if (whoop.isConnected) ...[
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(
              profile == null || profile.firstName.isEmpty ? 'Verbunden' : 'Verbunden als ${profile.firstName}',
            ),
            subtitle: Text(
              last == null
                  ? 'Noch kein Abruf'
                  : 'Zuletzt ${time.format(last.toLocal())}${whoop.lastResult == null ? '' : ' · ${whoop.lastResult}'}',
            ),
          ),
          if (body != null)
            LabeledRow(
              label: 'Körperwerte laut WHOOP',
              value:
                  '${GermanFormat.number(body.heightMeters * 100)} cm · ${GermanFormat.decimal(body.weightKilograms)} kg · '
                  'HFmax ${body.maxHeartRate.round()}',
            ),
          ListTile(
            enabled: !syncing,
            leading: syncing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            title: Text(syncing ? 'Wird abgerufen …' : 'Jetzt abrufen'),
            onTap: () => unawaited(ref.read(appModelProvider).syncNow()),
          ),
          ListTile(
            leading: const Icon(Icons.link_off, color: Colors.red),
            title: const Text('Trennen', style: TextStyle(color: Colors.red)),
            onTap: _disconnect,
          ),
        ] else
          ListTile(
            enabled: !_busy,
            leading: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link),
            title: const Text('Mit WHOOP verbinden'),
            subtitle: Text('Anmeldung im Browser; danach geht es zurück in die App.', style: secondary),
            textColor: Theme.of(context).colorScheme.primary,
            onTap: _connect,
          ),
        if (_message case final message?) ListTile(dense: true, title: Text(message, style: secondary)),
      ],
    );
  }
}
