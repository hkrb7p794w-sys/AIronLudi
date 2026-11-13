import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

/// Farbe und Kurzname je Sportart – einheitlich in Plan, Training und Gym (wie `SportStyle.swift`).
extension TrainingSportStyle on TrainingSport {
  Color get color => switch (this) {
    TrainingSport.run => Colors.green,
    TrainingSport.strength => Colors.purple,
    TrainingSport.bike => Colors.orange,
    TrainingSport.swim => Colors.blue,
    TrainingSport.other => Colors.teal,
  };

  String get shortLabel => switch (this) {
    TrainingSport.run => 'Laufen',
    TrainingSport.strength => 'Kraft',
    TrainingSport.bike => 'Rad',
    TrainingSport.swim => 'Schwimmen',
    TrainingSport.other => 'Anderes',
  };
}

extension SessionSlotStyle on SessionSlot {
  /// Kurzbeschriftung für Chips: „Laufen · Locker“.
  String get chipLabel => sport == TrainingSport.other ? sport.shortLabel : '${sport.shortLabel} · ${intensity.label}';
}
