import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../util/enum_codec.dart';

/// Karte im Ernährungsreiter.
enum NutritionCard implements RawEnum {
  /// Kalorienring (übrig) und Protein/KH/Fett.
  budget,

  /// Kennzahlen: gegessen, Ziel, verbleibend, Fortschritt, Zahl der Mahlzeiten.
  summary,
  water,

  /// „Was esse ich jetzt?“
  ideas,

  /// Schnell-Leiste (häufig, wie gestern, Rezepte mit Vorrat).
  quick,
  meals,

  /// Alle Nährstoffe mit Ziel.
  nutrients;

  @override
  String get rawValue => name;

  String get id => rawValue;

  String get label => switch (this) {
    budget => 'Kalorien und Makros',
    summary => 'Tagesübersicht',
    water => 'Wasser',
    ideas => 'Was esse ich jetzt?',
    quick => 'Schnell eintragen',
    meals => 'Mahlzeiten',
    nutrients => 'Alle Nährstoffe',
  };

  String get symbol => switch (this) {
    budget => 'chart.pie',
    summary => 'square.grid.2x2',
    water => 'drop',
    ideas => 'sparkles',
    quick => 'bolt',
    meals => 'list.bullet',
    nutrients => 'list.bullet.rectangle',
  };
}

/// Karten im Ernährungsreiter: Reihenfolge und Sichtbarkeit wählt die Person selbst.
final class NutritionDashboard {
  NutritionDashboard({List<NutritionCard> order = standardOrder, Set<NutritionCard>? hidden})
    : order = complete(order),
      hidden = hidden ?? {NutritionCard.summary};

  /// Alle Karten in der gewählten Reihenfolge (auch ausgeblendete).
  List<NutritionCard> order;
  Set<NutritionCard> hidden;

  static const standardOrder = [
    NutritionCard.budget,
    NutritionCard.summary,
    NutritionCard.water,
    NutritionCard.ideas,
    NutritionCard.quick,
    NutritionCard.meals,
    NutritionCard.nutrients,
  ];

  /// Unbekannte entfernen, Doppelte entfernen, neue Karten hinten anhängen.
  static List<NutritionCard> complete(List<NutritionCard> order) {
    final seen = <NutritionCard>{};
    final known = order.where(seen.add).toList();
    return [...known, ...NutritionCard.values.where((card) => !seen.contains(card))];
  }

  List<NutritionCard> get visible => order.where((card) => !hidden.contains(card)).toList();

  /// Wie `move(fromOffsets:toOffset:)` in SwiftUI-Listen: [toOffset] zählt in der Liste vor dem Verschieben.
  void move({required Set<int> fromOffsets, required int toOffset}) {
    final sorted = fromOffsets.toList()..sort();
    final moving = [for (final index in sorted) order[index]];
    final rest = [
      for (var index = 0; index < order.length; index++)
        if (!fromOffsets.contains(index)) order[index],
    ];
    final target = toOffset - fromOffsets.where((index) => index < toOffset).length;
    rest.insertAll(math.min(math.max(target, 0), rest.length), moving);
    order = rest;
  }

  void setVisible(NutritionCard card, {required bool visible}) {
    if (visible) {
      hidden.remove(card);
    } else {
      hidden.add(card);
    }
  }

  Map<String, Object?> toJson() => {
    'order': [for (final card in order) card.rawValue],
    'hidden': [for (final card in hidden) card.rawValue]..sort(),
  };

  /// Tolerant: unbekannte Karten fallen weg, fehlende kommen hinten dazu.
  static NutritionDashboard fromJson(Object? json) {
    List<NutritionCard> cards(Object? raw) => raw is List
        ? [
            for (final value in raw)
              if (value is String) ?enumFromRaw(NutritionCard.values, value),
          ]
        : const [];
    final map = json is Map ? json : const <String, Object?>{};
    final order = map['order'] is List && (map['order'] as List).every((value) => value is String)
        ? cards(map['order'])
        : const <NutritionCard>[];
    final hidden = map['hidden'] is List && (map['hidden'] as List).every((value) => value is String)
        ? cards(map['hidden']).toSet()
        : <NutritionCard>{};
    return NutritionDashboard(order: order, hidden: hidden);
  }

  @override
  bool operator ==(Object other) =>
      other is NutritionDashboard &&
      const ListEquality<NutritionCard>().equals(other.order, order) &&
      const SetEquality<NutritionCard>().equals(other.hidden, hidden);

  @override
  int get hashCode => Object.hash(Object.hashAll(order), Object.hashAllUnordered(hidden));
}

/// Kennzahlen der Tagesübersicht.
final class NutritionDaySummary {
  const NutritionDaySummary({required this.eaten, required this.goal, required this.meals});

  final double eaten;
  final double? goal;
  final int meals;

  double? get remaining => goal == null ? null : goal! - eaten;

  /// Anteil des Ziels in Prozent (gerundet).
  int? get percent {
    final value = goal;
    if (value == null || value <= 0) return null;
    return (eaten / value * 100).round();
  }
}
