import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/routing/routing_providers.dart';
import '../../ui/liquid.dart';

/// Wetter und Wind für den geplanten Tag (sonst heute) am Start der Route, für eine wählbare Startzeit über die
/// geschätzte Dauer. Bei Rundwegen mit Rückenwind zuerst und Gegenwind zum Schluss: „Richtung umkehren“.
class RouteWeatherCard extends ConsumerStatefulWidget {
  const RouteWeatherCard({super.key, required this.route, this.onReverse});

  final PlannedRoute route;

  /// Route andersherum übernehmen (nur angeboten, wenn gesetzt).
  final void Function(PlannedRoute reversed)? onReverse;

  /// Wählbare Startzeiten.
  static const startHours = [7, 10, 13, 16, 19];

  @override
  ConsumerState<RouteWeatherCard> createState() => _RouteWeatherCardState();
}

class _RouteWeatherCardState extends ConsumerState<RouteWeatherCard> {
  late int _startHour = _defaultHour();

  CalendarDay get _day => widget.route.plannedDay ?? CalendarDay.today();

  int _defaultHour() {
    if (_day != CalendarDay.today()) return 10;
    final next = DateTime.now().hour + 1;
    return RouteWeatherCard.startHours.firstWhere(
      (hour) => hour >= next,
      orElse: () => RouteWeatherCard.startHours.last,
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final day = _day;
    final today = CalendarDay.today();
    final dayLabel = day == today
        ? 'heute'
        : day == today.adding(1)
        ? 'morgen'
        : 'am ${GermanFormat.date(day)}';
    final scheme = Theme.of(context).colorScheme;
    if (!OpenMeteoFormat.covers(day, today: today)) {
      if (day < today) return const SizedBox.shrink();
      return LiquidCard(
        child: Row(
          spacing: 10,
          children: [
            Icon(Icons.wb_cloudy_outlined, color: scheme.onSurfaceVariant),
            const Expanded(child: Text('Wetter und Wind gibt es ab 15 Tage vor dem geplanten Tag.')),
          ],
        ),
      );
    }
    final forecast = ref.watch(routeForecastProvider((route.points.first, day)));
    final weather = forecast.value == null
        ? null
        : RouteWeather.of(route, forecast.value!, startHour: _startHour, duration: route.duration);
    return LiquidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(Icons.air, color: scheme.primary),
              Expanded(child: Text('Wetter $dayLabel', style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 6,
              children: [
                for (final hour in RouteWeatherCard.startHours)
                  ChoiceChip(
                    label: Text('$hour Uhr'),
                    selected: hour == _startHour,
                    onSelected: (_) => setState(() => _startHour = hour),
                  ),
              ],
            ),
          ),
          if (forecast.isLoading)
            const LinearProgressIndicator()
          else if (forecast.hasError)
            Text('Die Vorhersage ist gerade nicht erreichbar.', style: LiquidText.label(context))
          else if (weather == null)
            Text('Für diese Zeit gibt es keine Vorhersage.', style: LiquidText.label(context))
          else ...[
            Text(weather.headline, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Row(
              spacing: 8,
              children: [
                Transform.rotate(
                  // Pfeil zeigt, wohin der Wind weht.
                  angle: (weather.windFrom + 180) * math.pi / 180,
                  child: Icon(Icons.navigation, size: 18, color: scheme.onSurfaceVariant),
                ),
                Expanded(child: Text(weather.windLine)),
              ],
            ),
            if (weather.windAdvice case final advice?) Text(advice, style: LiquidText.label(context)),
            if (weather.suggestsReverse && route.isLoop && widget.onReverse != null)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => widget.onReverse!(route.reversed()),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Richtung umkehren'),
                ),
              ),
          ],
          Text('Wetter: Open-Meteo', style: LiquidText.label(context).copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

/// Speichert die umgekehrte Route und meldet es kurz.
Future<void> saveReversedRoute(BuildContext context, WidgetRef ref, PlannedRoute reversed) async {
  await ref.read(routeStoreProvider).save(reversed);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Route umgekehrt – Gegenwind jetzt zuerst.')));
  }
}
