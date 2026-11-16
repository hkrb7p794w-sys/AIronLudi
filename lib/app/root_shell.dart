import 'dart:async';

import 'package:coach_core/coach_core.dart'
    show
        AccountInvite,
        AndroidConnectLink,
        CookLink,
        CookPartnerLink,
        CookReleaseLink,
        InviteDecision,
        LeagueInvite,
        MealShare,
        RoutineLink,
        TrainingSport;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/storage.dart';
import '../features/account/account_views.dart';
import '../features/gym/gym_controller.dart';
import '../features/gym/gym_providers.dart';
import '../features/gym/gym_share_views.dart';
import '../features/motivation/motivation_views.dart';
import '../features/nutrition/meal_share_views.dart';
import '../features/plan/my_week_screen.dart';
import '../features/recipes/cook_plan_views.dart';
import '../features/today/plan_day_actions.dart';
import '../services/activities/live_activities.dart';
import '../services/background/background_refresh.dart';
import '../services/providers.dart';
import '../services/reminders/reminder_service.dart';
import '../services/whoop/whoop_service.dart';
import '../services/widgets/widget_providers.dart';
import 'day_change.dart';
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
      if (!mounted) return;
      final gym = ref.read(gymControllerProvider);
      _updateWorkoutActivity(gym);
      _updateScreenAwake(gym);
      unawaited(_updateQuickActions());
    });
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_refresh()), onHide: () => unawaited(_leave()));
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

  /// App verlässt den Vordergrund (wie `.background` in `CoachApp`): Hintergrundabruf planen, höchstens einmal am Tag
  /// in den gewählten Ordner sichern, Widgets versorgen, Schnellaktionen am App-Icon anpassen.
  Future<void> _leave() async {
    final model = ref.read(appModelProvider);
    if (!model.isDemo) {
      await BackgroundRefresh.schedule();
      await ref.read(backupServiceProvider).backupToFolder();
    }
    await ref.read(widgetPublisherProvider).publish();
    await _updateQuickActions();
  }

  Future<void> _updateQuickActions() {
    final profile = ref.read(coachSettingsProvider).profile;
    return ref
        .read(quickActionsProvider)
        .update(
          trainsStrength: profile.onboardingDone && profile.trains(TrainingSport.strength),
          aiAvailable: ref.read(aiClientProvider).allows('ai_insights'),
        );
  }

  bool? _screenAwake;

  /// Bildschirm an, solange eine Einheit läuft – auch wenn sie gerade ausgeblendet ist (wie `RootView`).
  void _updateScreenAwake(GymController gym) {
    final on = gym.active != null && ref.read(coachSettingsProvider).gym.keepsScreenOn;
    if (on == _screenAwake) return;
    _screenAwake = on;
    unawaited(ref.read(screenAwakeProvider)(on));
  }

  WorkoutLiveState? _workoutState;
  bool _workoutShown = false;

  /// Live-Aktivität der laufenden Einheit: Pause und nächster Satz auf dem Sperrbildschirm (wie `RootView`).
  void _updateWorkoutActivity(GymController gym) {
    final settings = ref.read(coachSettingsProvider).gym;
    final state = settings.liveActivity ? gym.liveState()?.withLayout(settings.liveActivityLayout) : null;
    if (state == _workoutState && _workoutShown == (state != null)) return;
    final changed = _workoutShown != (state != null);
    _workoutState = state;
    _workoutShown = state != null;
    final host = ref.read(liveActivityHostProvider);
    // Vorrang der Einheit: „Mahlzeiten heute“ endet, bevor die Einheit startet, und kommt nach ihr zurück.
    if (changed && state != null) {
      unawaited(ref.read(widgetPublisherProvider).publish().then((_) => host.updateWorkout(state, title: _title(gym))));
      return;
    }
    unawaited(host.updateWorkout(state, title: _title(gym)));
    if (changed) unawaited(ref.read(widgetPublisherProvider).publish());
  }

  static String _title(GymController gym) => gym.active?.title ?? '';

  /// Wasser aus dem Homescreen-Widget übernehmen, Widgets versorgen, abrufen, Widgets mit neuem Stand versorgen.
  Future<void> _refresh() async {
    ref.read(currentDayProvider.notifier).check();
    final model = ref.read(appModelProvider);
    final widgets = ref.read(widgetPublisherProvider);
    // Android: Knöpfe der laufenden Mitteilung, während die App nicht lief.
    final gym = ref.read(gymControllerProvider);
    for (final action in await ref.read(liveActivityHostProvider).takePendingActions()) {
      gym.perform(action);
    }
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
    // Rücksprung von WHOOP nach der Freigabe: coach://whoop?code=…&state=… (über die Seite /w/whoop des Workers).
    if (uri.scheme == 'coach' && uri.host == 'whoop') {
      ref.read(incomingLinkProvider.notifier).consume();
      unawaited(_completeWhoop(uri));
      return;
    }
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
    // Geteilter Trainingsplan coach://routine/<daten>.
    if (RoutineLink.decode(uri.toString()) case final routine?) {
      ref.read(incomingLinkProvider.notifier).consume();
      _presentSheet((_) => ImportRoutineScreen(routine: routine));
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
    // „In der App verbinden“ von der Android-Download-Seite: ironludi://connect?worker=…&token=… (nur KI-Zugang).
    if (AndroidConnectLink.fromUri(uri) case final connect?) {
      ref.read(incomingLinkProvider.notifier).consume();
      unawaited(_connectWorker(connect));
      return;
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

  Future<void> _connectWorker(AndroidConnectLink link) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ai = ref.read(aiClientProvider);
    final String message;
    switch (link.decision(currentURL: ai.workerURL, currentToken: ai.storedToken)) {
      case InviteDecision.useInviteToken:
        await ai.configure(url: link.workerURL, token: link.token);
        message = 'KI-Zugang verbunden.';
      case InviteDecision.keepCurrentToken:
        message = 'KI-Zugang ist schon verbunden.';
      case InviteDecision.rejectOtherServer:
        message =
            'Dieser Link gehört zu einem anderen Server (${link.host}). Dein eigener KI-Zugang bleibt unverändert.';
    }
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _completeWhoop(Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(whoopServiceProvider).complete(uri);
      messenger?.showSnackBar(const SnackBar(content: Text('WHOOP verbunden – Daten werden abgerufen.')));
      await ref.read(appModelProvider).syncNow();
    } on WhoopError catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
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
    ref.listen(gymControllerProvider, (_, gym) {
      _updateWorkoutActivity(gym);
      _updateScreenAwake(gym);
    });
    // Ansicht oder Schalter der Live-Aktivität geändert: sofort übernehmen.
    ref.listen(coachSettingsProvider, (_, _) => _updateWorkoutActivity(ref.read(gymControllerProvider)));
    final storage = ref.watch(appStorageProvider);
    final showsStorageWarning = storage.isTemporary && !ref.read(appModelProvider).isDemo;
    return Scaffold(
      body: showsStorageWarning
          ? Column(
              children: [
                const _StorageWarningBanner(),
                Expanded(child: shell),
              ],
            )
          : shell,
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

/// Warnung, wenn der Datenspeicher nicht geöffnet werden konnte (`AppStorage.isTemporary`).
class _StorageWarningBanner extends StatelessWidget {
  const _StorageWarningBanner();

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(10),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18),
          Expanded(
            child: Text(
              'Gespeicherte Daten konnten nicht geöffnet werden. Neue Einträge gehen beim Schließen verloren – bitte '
              'nichts erfassen und auf ein Update warten. Deine bisherigen Daten bleiben erhalten.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}
