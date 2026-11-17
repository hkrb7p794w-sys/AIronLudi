// Alle Symbolnamen, die die App verwendet, haben ein eigenes Icon (kein neutraler Punkt).
import 'package:aironludi/ui/symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Symbole der Trainingsübersicht', () {
    for (final name in [
      'calendar',
      'figure.run',
      'dumbbell.fill',
      'heart.text.square.fill',
      'bed.double.fill',
      'heart.fill',
      'chart.bar.xaxis',
      'moon.stars.fill',
      'chart.line.uptrend.xyaxis',
      'doc.text.magnifyingglass',
      'figure.pool.swim',
      'figure.outdoor.cycle',
      'flag.checkered',
      'medal.fill',
    ]) {
      expect(AppSymbols.of(name), isNot(Icons.circle), reason: name);
    }
  });
}
