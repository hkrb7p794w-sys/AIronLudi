import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/routing/routing_providers.dart';
import '../../services/routing/watch_export.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';

/// „Karte auf die Uhr“ (Garmin-Datenfeld `garmin/`): Route mit Varianten und Wegenetz für die Uhr bereitlegen, damit
/// sie unterwegs ohne Handy navigiert. Dazu einmalig die Uhr mit dem Code aus dem Datenfeld koppeln.
class WatchMapTile extends ConsumerStatefulWidget {
  const WatchMapTile({super.key, required this.route});

  final PlannedRoute route;

  @override
  ConsumerState<WatchMapTile> createState() => _WatchMapTileState();
}

class _WatchMapTileState extends ConsumerState<WatchMapTile> {
  bool _busy = false;
  String? _progress;
  String? _message;
  bool _failed = false;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      final result = await ref
          .read(watchExportProvider)
          .export(
            widget.route,
            onProgress: (message) {
              if (mounted) setState(() => _progress = message);
            },
          );
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(
        () => _message =
            'Liegt für die Uhr bereit (${(result.bytes / 1024).ceil()} KB'
            '${result.variants > 0 ? ', ${result.variants} Varianten' : ''}). Öffne auf der Uhr „Laufen“ mit dem '
            'AIronLudi-Datenfeld, solange das Handy in der Nähe ist – danach brauchst du es nicht mehr.',
      );
    } on WatchExportFailed catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _failed = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _pair() async {
    final code = await showDialog<String>(context: context, builder: (_) => const _PairDialog());
    if (code == null || !mounted) return;
    try {
      await ref.read(watchExportProvider).pair(code);
      if (!mounted) return;
      setState(() {
        _message = 'Uhr gekoppelt. Lade jetzt eine Route auf die Uhr.';
        _failed = false;
      });
    } on WatchExportFailed catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(watchExportProvider).isAvailable;
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: _busy
              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Icon(Icons.map_outlined, color: Theme.of(context).colorScheme.primary),
          title: const Text('Karte auf die Uhr (Garmin)'),
          subtitle: Text(
            _progress ??
                (available
                    ? 'Route, Varianten und Wegenetz für das AIronLudi-Datenfeld – unterwegs ohne Handy.'
                    : 'Dafür ist der eigene Worker nötig (Ich › KI › Worker).'),
          ),
          isThreeLine: true,
          enabled: available && !_busy,
          onTap: () => unawaited(_export()),
        ),
        if (_message case final message?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LiquidCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Icon(_failed ? Icons.info_outline : Icons.check_circle, color: _failed ? colors.alert : colors.good),
                  Expanded(child: Text(message)),
                ],
              ),
            ),
          ),
        if (available)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton.icon(
                onPressed: _busy ? null : () => unawaited(_pair()),
                icon: const Icon(Icons.link),
                label: const Text('Uhr koppeln'),
              ),
            ),
          ),
        const Divider(indent: 16, endIndent: 16),
      ],
    );
  }
}

class _PairDialog extends StatefulWidget {
  const _PairDialog();

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Uhr koppeln'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        const Text(
          'Öffne auf der Uhr „Laufen“ und blättere zur AIronLudi-Karte. Sie zeigt einen Code mit sechs Zeichen.',
        ),
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'Code von der Uhr'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Koppeln')),
    ],
  );
}
