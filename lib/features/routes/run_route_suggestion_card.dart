import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/routing/location_source.dart';
import '../../services/routing/routing_providers.dart';
import '../../services/routing/run_route_suggester.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'route_detail_screen.dart';
import 'route_parts.dart';

/// Routenvorschlag zu einer geplanten Laufeinheit: Karte, Kennzahlen und Begründung (aus dem Training), annehmen oder
/// ablehnen. Abgelehnte Strecken kommen nicht wieder; „Für diese Einheit keine Route“ blendet den Vorschlag aus.
class RunRouteSuggestionCard extends ConsumerStatefulWidget {
  const RunRouteSuggestionCard({super.key, required this.unit});

  final RunRouteUnit unit;

  @override
  ConsumerState<RunRouteSuggestionCard> createState() => _RunRouteSuggestionCardState();
}

class _RunRouteSuggestionCardState extends ConsumerState<RunRouteSuggestionCard> {
  final _map = MapController();
  Future<PlannedRoute>? _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final suggester = ref.read(runRouteSuggesterProvider);
    if (suggester.status(widget.unit.unitID) == RunSuggestionStatus.declined) return;
    _future = suggester.suggest(widget.unit);
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    final route = await ref.read(runRouteSuggesterProvider).accept(widget.unit);
    if (!mounted) return;
    setState(() => _busy = false);
    if (route == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Route für „${widget.unit.title}“ übernommen.'),
        action: SnackBarAction(
          label: 'Öffnen',
          onPressed: () => unawaited(
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RouteDetailScreen(routeID: route.id))),
          ),
        ),
      ),
    );
  }

  Future<void> _decline({required bool another}) async {
    setState(() => _busy = true);
    await ref.read(runRouteSuggesterProvider).decline(widget.unit, another: another);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _future = null;
      if (another) _load();
    });
  }

  Future<void> _reopen() async {
    await ref.read(runRouteSuggesterProvider).reopen(widget.unit);
    if (!mounted) return;
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(_reopen()),
            icon: const Icon(Icons.route),
            label: const Text('Doch eine Route vorschlagen'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 8, LiquidSpacing.page, 0),
      child: LiquidCard(
        child: FutureBuilder<PlannedRoute>(
          future: future,
          builder: (context, snapshot) {
            final header = Row(
              spacing: 8,
              children: [
                Icon(Icons.route, color: AppColors.of(context).info),
                Expanded(child: Text('Routenvorschlag', style: AppText.headline(context))),
              ],
            );
            if (snapshot.connectionState != ConnectionState.done) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  header,
                  Text('Passende Runde wird gesucht …', style: LiquidText.label(context)),
                  const LinearProgressIndicator(),
                ],
              );
            }
            if (snapshot.error case final error?) {
              final message = switch (error) {
                RunRouteNoStart(:final message) || LocationProblem(:final message) => message,
                NoRouteFound(:final message) || RoutingUnavailable(:final message) => message,
                _ => 'Der Vorschlag hat nicht geklappt.',
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  header,
                  Text(message),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(_load),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut versuchen'),
                    ),
                  ),
                ],
              );
            }
            final route = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                header,
                PlannerMap(
                  controller: _map,
                  start: route.points.first,
                  routes: [route],
                  selected: route,
                  height: 180,
                  onTap: (_) => unawaited(
                    FullscreenRouteMap.open(
                      context,
                      start: route.points.first,
                      routes: [route],
                      title: widget.unit.title,
                    ),
                  ),
                  routingSource: route.engine.isEmpty ? null : route.engine,
                ),
                RouteStatsRow(route: route),
                Text(widget.unit.brief.reason, style: LiquidText.label(context)),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => unawaited(_accept()),
                        icon: const Icon(Icons.check),
                        label: const Text('Annehmen'),
                      ),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => unawaited(_decline(another: true)),
                        icon: const Icon(Icons.close),
                        label: const Text('Ablehnen'),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: _busy ? null : () => unawaited(_decline(another: false)),
                    child: const Text('Für diese Einheit keine Route'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
