import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Hört auf `coach://`-Links. `coach://open/<route>` wählt den Reiter; Einladungen, geteilte Mahlzeiten und
/// Kochpartner-Links folgen mit ihren Bereichen (Phase 3).
final deepLinkListenerProvider = Provider<void>((ref) {
  void handle(Uri uri) {
    final route = AppRoute.fromUri(uri);
    if (route == null) return;
    ref.read(pendingRouteProvider.notifier).open(PendingRoute(route, mealCategory: AppRoute.mealCategoryFrom(uri)));
    ref.read(routerProvider).go(tabPath(route.tab));
  }

  final StreamSubscription<Uri> subscription = AppLinks().uriLinkStream.listen(handle);
  ref.onDispose(subscription.cancel);
});
