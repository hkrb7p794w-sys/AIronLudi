import 'dart:async';

import 'package:coach_core/coach_core.dart' show AccountInvite, LeagueInvite;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_views.dart';
import '../features/motivation/motivation_views.dart';
import '../features/plan/my_week_screen.dart';
import '../features/today/plan_day_actions.dart';
import '../services/providers.dart';
import '../services/reminders/reminder_service.dart';
import 'deep_links.dart';

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
    unawaited(
      model.start().then((_) async {
        await model.syncIfDue();
        // Freundschaftsanfragen (Zahl am Reiter „Aktivitäten“) und neue Trainings für den Feed.
        await ref.read(socialServiceProvider).refresh();
        await ref.read(socialAutoShareProvider).run(isDemo: model.isDemo);
      }),
    );
    // Schon vor dem ersten Bild beantwortete Mitteilungen (App aus einer Mitteilung gestartet).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _presentReminder(ref.read(reminderServiceProvider));
    });
  }

  /// Link von außen: Konto-Einladung. Vorher entscheiden: Meldet sich die Person im Fenster an, darf es nicht mitten
  /// im Ablauf (vor dem Wiederherstellungscode) zu „Schon angemeldet“ wechseln.
  void _presentLink(Uri? uri) {
    if (uri == null) return;
    if (LeagueInvite.fromUri(uri) case final league?) {
      ref.read(incomingLinkProvider.notifier).consume();
      unawaited(
        Navigator.of(context)
            .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => JoinLeagueScreen(invite: league))),
      );
      return;
    }
    final invite = AccountInvite.fromUri(uri);
    if (invite == null) return;
    ref.read(incomingLinkProvider.notifier).consume();
    if (ref.read(accountServiceProvider).isSignedIn) {
      unawaited(
        Navigator.of(context)
            .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const AlreadySignedInScreen())),
      );
    } else {
      unawaited(presentAccountAuth(context, AccountAuthMode.register, invite: invite));
    }
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
    ref.listen(incomingLinkProvider, (_, uri) => _presentLink(uri));
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
