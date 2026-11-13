import 'package:flutter/material.dart';

import '../../ui/placeholder_view.dart';

/// Reiter „Ernährung“. Inhalt folgt in Phase 3 (Checkliste: docs/migrationsplan.md).
class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ernährung')),
      body: const PlaceholderView(),
    );
  }
}
