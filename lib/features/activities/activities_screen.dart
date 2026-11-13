import 'package:flutter/material.dart';

import '../../ui/placeholder_view.dart';

/// Reiter „Aktivitäten“. Inhalt folgt in Phase 3 (Checkliste: docs/migrationsplan.md).
class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aktivitäten')),
      body: const PlaceholderView(),
    );
  }
}
