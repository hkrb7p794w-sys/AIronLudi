import 'package:coach_core/coach_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/activities/activities_screen.dart';
import '../features/me/me_screen.dart';
import '../features/nutrition/nutrition_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/today/today_screen.dart';
import '../features/training/training_screen.dart';
import '../services/providers.dart';
import '../ui/large_title.dart';
import 'root_shell.dart';

/// Pfad des Reiters; jeder Reiter hat einen eigenen Navigationsstapel (wie `TabView` + `NavigationStack`).
String tabPath(AppTab tab) => switch (tab) {
  AppTab.today => '/heute',
  AppTab.plan => '/plan',
  AppTab.history => '/verlauf',
  AppTab.nutrition => '/ernaehrung',
  AppTab.me => '/ich',
};

/// Frühere Pfade (vier Reiter bis zum Roast, Stufe 4) führen auf die neuen.
const legacyTabPaths = {'/aktivitaeten': '/verlauf', '/training': '/plan'};

/// Einrichtungsassistent beim ersten Start (in Swift ein `fullScreenCover`, bis das Profil fertig ist).
const onboardingPath = '/einrichtung';

StatefulShellBranch _branch(AppTab tab, Widget screen) => StatefulShellBranch(
  routes: [
    GoRoute(
      path: tabPath(tab),
      builder: (context, state) => LargeTitleScope(child: screen),
    ),
  ],
);

final routerProvider = Provider<GoRouter>((ref) {
  final settings = ref.read(coachSettingsProvider);
  final router = GoRouter(
    initialLocation: tabPath(AppTab.today),
    refreshListenable: settings,
    redirect: (context, state) {
      final done = settings.profile.onboardingDone;
      final onOnboarding = state.matchedLocation == onboardingPath;
      if (!done && !onOnboarding) return onboardingPath;
      if (done && onOnboarding) return tabPath(AppTab.today);
      return legacyTabPaths[state.matchedLocation];
    },
    routes: [
      GoRoute(path: onboardingPath, builder: (context, state) => const OnboardingScreen()),
      for (final legacy in legacyTabPaths.keys) GoRoute(path: legacy, redirect: (_, _) => legacyTabPaths[legacy]),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => RootShell(shell: shell),
        branches: [
          _branch(AppTab.today, const TodayScreen()),
          _branch(AppTab.plan, const TrainingScreen()),
          _branch(AppTab.history, const ActivitiesScreen()),
          _branch(AppTab.nutrition, const NutritionScreen()),
          _branch(AppTab.me, const MeScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
