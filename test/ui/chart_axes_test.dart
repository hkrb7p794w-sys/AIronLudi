// Gemeinsame Diagramm-Achsen (Roast B-30): deutsches Zahlenformat, keine krummen Randwerte.
import 'package:aironludi/ui/chart_axes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Zahlen mit Komma, ganze Zahlen ab Rasterweite 1', () {
    expect(axisNumber(1.35, interval: 0.01), '1,35');
    expect(axisNumber(1.4, interval: 0.1), '1,4');
    expect(axisNumber(300, interval: 100), '300');
    expect(axisNumber(299.6, interval: 50), '300');
  });

  test('Randwerte außerhalb des Rasters entfallen, Rasterwerte bleiben', () {
    // Maximum 467 bei Raster 100 („467“ über „400“): weg.
    expect(isOffGridEdge(467, min: 0, max: 467, interval: 100), isTrue);
    expect(isOffGridEdge(400, min: 0, max: 467, interval: 100), isFalse);
    expect(isOffGridEdge(0, min: 0, max: 467, interval: 100), isFalse);
    // Minimum 1,37 bei Raster 0,02 liegt nicht auf dem Raster … 1,36 schon.
    expect(isOffGridEdge(1.37, min: 1.37, max: 1.5, interval: 0.02), isTrue);
    expect(isOffGridEdge(1.36, min: 1.36, max: 1.5, interval: 0.02), isFalse);
  });
}
