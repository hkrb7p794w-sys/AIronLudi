import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/plan/my_week_screen.dart';
import '../features/today/plan_day_actions.dart';
import '../services/providers.dart';
import '../services/reminders/reminder_service.dart';

/// Vier Reiter wie in der iPhone-App: Heute · Aktivitäten · Training · Ernährung. Beim ersten Anzeigen startet der
/// App-Zustand und ruft bei Bedarf Daten ab (wie `.task { await model.syncIfDue() }` in `RootView`).
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  @override
  void initState() {
    super.initState();
    final model = ref.read(appModelProvider);
    unawaited(model.start().then((_) => model.syncIfDue()));
    // Schon vor dem ersten Bild beantwortete Mitteilungen (App aus einer Mitteilung gestartet).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _presentReminder(ref.read(reminderServiceProvider));
    });
  }

  /// Aus einer Mitteilung: „Nächste Woche planen“ bzw. Einheit verschieben (wie die Sheets in `RootView`).
  void _presentReminder(ReminderService reminders) {
    if (reminders.showsWeekPlanning) {
      reminders.showsWeekPlanning = false;
      unawaited(
        Navigator.of(context)
            .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const NextWeekPlanScreen())),
      );
    }
    if (reminders.pendingDay case final day?) {
      reminders.pendingDay = null;
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => AdjustDaySheet(day: day),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final incoming = ref.watch(socialServiceProvider).incomingCount;
    ref.listen(reminderServiceProvider, (_, reminders) => _presentReminder(reminders));
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Erneutes Tippen auf den aktiven Reiter springt an den Anfang seines Stapels.
        onDestinationSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'Heute'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: incoming > 0,
              label: Text('$incoming'),
              child: const Icon(Icons.directions_run),
            ),
            label: 'Aktivitäten',
          ),
          const NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'Training'),
          const NavigationDestination(icon: Icon(Icons.restaurant), label: 'Ernährung'),
        ],
      ),
    );
  }
}
