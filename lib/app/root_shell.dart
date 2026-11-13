import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Vier Reiter wie in der iPhone-App: Heute · Aktivitäten · Training · Ernährung. Der Zähler für
/// Freundschaftsanfragen am Reiter „Aktivitäten“ folgt mit dem Social-Bereich (Phase 3).
class RootShell extends StatelessWidget {
  const RootShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Erneutes Tippen auf den aktiven Reiter springt an den Anfang seines Stapels.
        onDestinationSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Heute'),
          NavigationDestination(icon: Icon(Icons.directions_run), label: 'Aktivitäten'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'Training'),
          NavigationDestination(icon: Icon(Icons.restaurant), label: 'Ernährung'),
        ],
      ),
    );
  }
}
