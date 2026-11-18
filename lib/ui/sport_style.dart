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

/// Symbol und Farbe je feinerer Sportart (Bouldern, Yoga …), wo die Grobeinteilung nur „Anderes“ kennt.
extension ActivityKindStyle on ActivityKind {
  String get symbol => switch (this) {
    ActivityKind.running => 'figure.run',
    ActivityKind.cycling => 'figure.outdoor.cycle',
    ActivityKind.swimming => 'figure.pool.swim',
    ActivityKind.strength => 'figure.strengthtraining.traditional',
    ActivityKind.bouldering => 'figure.bouldering',
    ActivityKind.climbing => 'figure.climbing',
    ActivityKind.hiking => 'figure.hiking',
    ActivityKind.rowing => 'figure.rower',
    ActivityKind.paddling => 'figure.kayaking',
    ActivityKind.yoga => 'figure.yoga',
    ActivityKind.mobility => 'figure.flexibility',
    ActivityKind.hiit => 'figure.hiit',
    ActivityKind.cardio => 'figure.elliptical',
    ActivityKind.dance => 'figure.dance',
    ActivityKind.winter => 'figure.skiing.downhill',
    ActivityKind.racket => 'figure.tennis',
    ActivityKind.team => 'figure.soccer',
    ActivityKind.martialArts => 'figure.boxing',
    ActivityKind.walking => 'figure.walk',
    ActivityKind.other => 'figure.mixed.cardio',
  };

  Color get color => switch (this) {
    ActivityKind.running => Colors.green,
    ActivityKind.cycling => Colors.orange,
    ActivityKind.swimming => Colors.blue,
    ActivityKind.strength || ActivityKind.hiit || ActivityKind.martialArts => Colors.purple,
    ActivityKind.bouldering || ActivityKind.climbing => Colors.brown,
    ActivityKind.yoga || ActivityKind.mobility => Colors.indigo,
    _ => Colors.teal,
  };
}
