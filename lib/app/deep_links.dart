import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart' as plugin;

import 'router.dart';

/// Ziel von außen, das die Zielansicht einmal übernimmt (z. B. „Mahlzeit erfassen“ öffnet das Erfassen).
/// Wie `AppRouter.pending` in der iPhone-App: erst nach dem Onboarding ausführen (Phase 3).
class PendingRoute {
  const PendingRoute(this.route, {this.mealCategory});

  final AppRoute route;
  final MealCategory? mealCategory;
}

final pendingRouteProvider = NotifierProvider<PendingRouteController, PendingRoute?>(PendingRouteController.new);

class PendingRouteController extends Notifier<PendingRoute?> {
  @override
  PendingRoute? build() => null;

  void open(PendingRoute pending) => state = pending;

  /// Die Zielansicht hat die Aktion ausgeführt.
  void consume() => state = null;
}

/// Link von außen, den `RootShell` übernimmt: Konto-Einladung, Liga, geteilte Mahlzeit und Kochpartner.
final incomingLinkProvider = NotifierProvider<IncomingLinkController, Uri?>(IncomingLinkController.new);

class IncomingLinkController extends Notifier<Uri?> {
  @override
  Uri? build() => null;

  void open(Uri uri) => state = uri;

  void consume() => state = null;
}

/// Hört auf `coach://`-Links. `coach://open/<route>` wählt den Reiter; Einladungen, geteilte Mahlzeiten und
/// Kochpartner-Links gehen an `RootShell`.
final deepLinkListenerProvider = Provider<void>((ref) {
  void handle(Uri uri) {
    // Kochpartner-Links zuerst: `coach://open/cookShare` ist kein Reiter-Ziel (wie in `RootView`).
    final route = CookLink.fromUri(uri) == null ? AppRoute.fromUri(uri) : null;
    if (route == null) {
      ref.read(incomingLinkProvider.notifier).open(uri);
      return;
    }
    openRoute(ref, route, mealCategory: AppRoute.mealCategoryFrom(uri));
  }

  final StreamSubscription<Uri> subscription = AppLinks().uriLinkStream.listen(handle);
  ref.onDispose(subscription.cancel);
});

/// Ziel anspringen: Reiter wählen, die Zielansicht übernimmt die Aktion (Links, Schnellaktionen, Widgets).
void openRoute(Ref ref, AppRoute route, {MealCategory? mealCategory}) {
  ref.read(pendingRouteProvider.notifier).open(PendingRoute(route, mealCategory: mealCategory));
  ref.read(routerProvider).go(tabPath(route.tab));
}

/// Schnellaktionen am App-Icon (Port von `AppRouter.updateQuickActions` und `handle(_:)`): Antippen springt wie ein
/// Link `coach://open/<route>` an; welche angeboten werden, entscheidet `QuickActions.routes`.
final quickActionsProvider = Provider<QuickActionsService>((ref) {
  final service = PluginQuickActionsService();
  service.initialize((route) => openRoute(ref, route));
  return service;
});

abstract interface class QuickActionsService {
  void initialize(void Function(AppRoute route) onSelect);

  Future<void> update({required bool trainsStrength, required bool aiAvailable});
}

final class PluginQuickActionsService implements QuickActionsService {
  final _plugin = const plugin.QuickActions();

  @override
  void initialize(void Function(AppRoute route) onSelect) {
    try {
      unawaited(
        _plugin
            .initialize((type) {
              if (AppRoute.values.where((route) => route.name == type).firstOrNull case final route?) onSelect(route);
            })
            .catchError((Object _) {}),
      );
    } on Object {
      // Ohne Plattformteil (Tests) keine Schnellaktionen.
    }
  }

  @override
  Future<void> update({required bool trainsStrength, required bool aiAvailable}) async {
    try {
      await _plugin.setShortcutItems([
        for (final route in QuickActions.routes(trainsStrength: trainsStrength, aiAvailable: aiAvailable))
          plugin.ShortcutItem(type: route.name, localizedTitle: route.title, localizedSubtitle: route.subtitle),
      ]);
    } on Object {
      // Ohne Plattformteil (Tests) keine Schnellaktionen.
    }
  }
}

/// Für Tests.
final class FakeQuickActionsService implements QuickActionsService {
  void Function(AppRoute route)? onSelect;
  List<AppRoute> routes = const [];

  @override
  void initialize(void Function(AppRoute route) onSelect) => this.onSelect = onSelect;

  @override
  Future<void> update({required bool trainsStrength, required bool aiAvailable}) async =>
      routes = QuickActions.routes(trainsStrength: trainsStrength, aiAvailable: aiAvailable);
}
