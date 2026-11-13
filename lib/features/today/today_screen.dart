import 'package:flutter/material.dart';

import '../../ui/placeholder_view.dart';
import '../settings/settings_screen.dart';

/// Reiter „Heute“. Inhalt folgt in Phase 3 (Checkliste: docs/migrationsplan.md).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heute'),
        actions: [
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
              rootNavigator: true,
            ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: const PlaceholderView(),
    );
  }
}
