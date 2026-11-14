import 'package:flutter/material.dart';

/// Symbolnamen der Swift-App (SF Symbols, auch in `coach_core`) auf Material-Icons abgebildet. Unbekannte Namen zeigen
/// einen neutralen Punkt.
abstract final class AppSymbols {
  static const Map<String, IconData> _icons = {
    'figure.run': Icons.directions_run,
    'dumbbell.fill': Icons.fitness_center,
    'figure.outdoor.cycle': Icons.directions_bike,
    'figure.pool.swim': Icons.pool,
    'figure.yoga': Icons.self_improvement,
    'flame.fill': Icons.local_fire_department,
    'figure.strengthtraining.traditional': Icons.sports_gymnastics,
    'figure.mixed.cardio': Icons.sports,
    'bed.double.fill': Icons.bed,
    'heart.fill': Icons.favorite,
    'flag.checkered': Icons.sports_score,
    'speedometer': Icons.speed,
    'road.lanes': Icons.add_road,
    'applewatch.side.right': Icons.watch,
    'heart.text.square.fill': Icons.monitor_heart,
    'bolt.heart': Icons.electric_bolt,
    'heart.circle': Icons.favorite_border,
    'figure.walk.circle': Icons.directions_walk,
    'book.closed': Icons.menu_book,
    'exclamationmark.triangle.fill': Icons.warning_amber_rounded,
    'lightbulb.fill': Icons.lightbulb,
    'info.circle.fill': Icons.info,
    'checkmark.circle.fill': Icons.check_circle,
    'wand.and.stars': Icons.auto_awesome,
    'plus.circle.fill': Icons.add_circle,
    'person.fill': Icons.person,
    'pawprint.fill': Icons.pets,
    'calendar': Icons.calendar_month,
    'medal.fill': Icons.military_tech,
    'arrow.down.right.circle.fill': Icons.trending_down,
    'arrow.triangle.2.circlepath.circle.fill': Icons.autorenew,
    'arrow.up.right.circle.fill': Icons.trending_up,
    'heart.circle.fill': Icons.favorite,
    'equal.circle.fill': Icons.drag_handle,
  };

  static IconData of(String name) => _icons[name] ?? Icons.circle;
}
