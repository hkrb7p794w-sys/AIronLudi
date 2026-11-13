import 'package:flutter/material.dart';

import '../../ui/placeholder_view.dart';

/// Reiter „Heute“. Inhalt folgt in Phase 3 (Checkliste: docs/migrationsplan.md).
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Heute')),
      body: const PlaceholderView(),
    );
  }
}
