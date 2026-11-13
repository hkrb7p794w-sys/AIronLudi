import 'package:flutter/material.dart';

import '../../ui/placeholder_view.dart';

/// Reiter „Training“. Inhalt folgt in Phase 3 (Checkliste: docs/migrationsplan.md).
class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Training')),
      body: const PlaceholderView(),
    );
  }
}
