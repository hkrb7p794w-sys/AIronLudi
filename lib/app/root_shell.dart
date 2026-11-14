import 'dart:async';

import 'package:coach_core/coach_core.dart'
    show AccountInvite, CookLink, CookPartnerLink, CookReleaseLink, LeagueInvite, MealShare;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_views.dart';
import '../features/gym/gym_controller.dart';
import '../features/gym/gym_providers.dart';
import '../features/motivation/motivation_views.dart';
import '../features/nutrition/meal_share_views.dart';
import '../features/plan/my_week_screen.dart';
import '../features/recipes/cook_plan_views.dart';
import '../features/today/plan_day_actions.dart';
import '../services/activities/live_activities.dart';
import '../services/providers.dart';
import '../services/reminders/reminder_service.dart';
import '../services/widgets/widget_providers.dart';
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
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final model = ref.read(appModelProvider);
    unawaited(model.start().then((_) => _refresh()));
    // Wie `scenePhase` in `CoachApp`: beim Zurückkehren Widget-Aktionen übernehmen und abrufen, beim Verlassen den
    // Stand für die Widgets schreiben.
    // Knöpfe der Live-Aktivität („Satz erledigt“, ±, „Pause überspringen“) an die laufende Einheit binden.
    ref.read(liveActivityHostProvider).onWorkoutAction = (action) => ref.read(gymControllerProvider).perform(action);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateWorkoutActivity(ref.read(gymControllerProvider));
    });
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_refresh()),
      onHide: () => unawaited(ref.read(widgetPublisherProvider).publish()),
    );
    // Schon vor dem ersten Bild beantwortete Mitteilungen (App aus einer Mitteilung gestartet).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _presentReminder(ref.read(reminderServiceProvider));
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  WorkoutLiveState? _workoutState;
  bool _workoutShown = false;

  /// Live-Aktivität der laufenden Einheit: Pause und nächster Satz auf dem Sperrbildschirm (wie `RootView`).
  void _updateWorkoutActivity(GymController gym) {
    final enabled = ref.read(coachSettingsProvider).gym.liveActivity;
    final state = enabled ? gym.liveState() : null;
    if (state == _workoutState && _workoutShown == (state != null)) return;
    _workoutState = state;
    _workoutShown = state != null;
    unawaited(ref.read(liveActivityHostProvider).updateWorkout(state, title: gym.active?.title ?? ''));
  }

  /// Wasser aus dem Homescreen-Widget übernehmen, Widgets versorgen, abrufen, Widgets mit neuem Stand versorgen.
  Future<void> _refresh() async {
    final model = ref.read(appModelProvider);
    final widgets = ref.read(widgetPublisherProvider);
    await widgets.takeQueuedActions();
    await widgets.publish();
    await model.syncIfDue();
    await model.refreshReminders();
    await widgets.publish();
    // Freundschaftsanfragen (Zahl am Reiter „Aktivitäten“) und neue Trainings für den Feed.
    await ref.read(socialServiceProvider).refresh();
    await ref.read(socialAutoShareProvider).run(isDemo: model.isDemo);
  }

  /// Link von außen: Konto-Einladung. Vorher entscheiden: Meldet sich die Person im Fenster an, darf es nicht mitten
  /// im Ablauf (vor dem Wiederherstellungscode) zu „Schon angemeldet“ wechseln.
  void _presentLink(Uri? uri) {
    if (uri == null) return;
    // Freigabe fürs gemeinsame Kochen coach://cook/<code> bzw. eigene Freigabe coach://cook/release.
    if (CookLink.fromUri(uri) case final link?) {
      ref.read(incomingLinkProvider.notifier).consume();
      final code = switch (link) {
        CookPartnerLink(:final code) => code,
        CookReleaseLink() => null,
      };
      _presentSheet((_) => CookPartnersScreen(initialCode: code));
      return;
    }
    // Geteilte Mahlzeit coach://meal/<code>.
    if (uri.scheme == 'coach' && uri.host == 'meal') {
      if (MealShare.code(uri.toString()) case final code?) {
        ref.read(incomingLinkProvider.notifier).consume();
        _presentSheet((_) => ReceivedMealScreen(code: code));
        return;
      }
    }
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

  void _presentSheet(WidgetBuilder builder) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: builder)));

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
    ref.listen(gymControllerProvider, (_, gym) => _updateWorkoutActivity(gym));
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
