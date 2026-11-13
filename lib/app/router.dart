import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/activities/activities_screen.dart';
import '../features/nutrition/nutrition_screen.dart';
import '../features/today/today_screen.dart';
import '../features/training/training_screen.dart';
import 'root_shell.dart';

/// Pfad des Reiters; jeder Reiter hat einen eigenen Navigationsstapel (wie `TabView` + `NavigationStack`).
String tabPath(AppTab tab) => switch (tab) {
  AppTab.today => '/heute',
  AppTab.activities => '/aktivitaeten',
  AppTab.training => '/training',
  AppTab.nutrition => '/ernaehrung',
};

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: tabPath(AppTab.today),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => RootShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: tabPath(AppTab.today), builder: (context, state) => const TodayScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: tabPath(AppTab.activities), builder: (context, state) => const ActivitiesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: tabPath(AppTab.training), builder: (context, state) => const TrainingScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: tabPath(AppTab.nutrition), builder: (context, state) => const NutritionScreen())],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
