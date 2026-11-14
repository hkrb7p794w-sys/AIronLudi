import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Karte der aufgezeichneten Strecke (statt MapKit): OpenStreetMap-Kacheln mit Quellenangabe, Start grün, Ziel rot.
class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.route, this.height = 240});

  final List<({double latitude, double longitude})> route;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = [for (final point in route) LatLng(point.latitude, point.longitude)];
    return Semantics(
      label: 'Karte der Strecke',
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(24),
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'io.github.hkrb7p794w.gym',
            ),
            PolylineLayer(
              polylines: [Polyline(points: points, color: Colors.orange, strokeWidth: 4)],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: points.first,
                  child: const Icon(Icons.flag, color: Colors.green),
                ),
                Marker(
                  point: points.last,
                  child: const Icon(Icons.sports_score, color: Colors.red),
                ),
              ],
            ),
            const SimpleAttributionWidget(source: Text('© OpenStreetMap-Mitwirkende')),
          ],
        ),
      ),
    );
  }
}
