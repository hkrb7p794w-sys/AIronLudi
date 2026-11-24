import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../services/routing/location_source.dart';
import '../../services/routing/routing_providers.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';

/// Knopf „Mein Standort“ wie bei Google Maps: bestimmt den Standort, zentriert die Karte darauf und meldet ihn
/// ([onLocated]) für den blauen Punkt. Setzt keinen Start – das bleibt „Aktueller Standort“ bzw. langes Drücken.
class LocateMeButton extends ConsumerStatefulWidget {
  const LocateMeButton({super.key, required this.map, required this.onLocated, this.zoom = 15});

  final MapController map;
  final ValueChanged<GeoPoint> onLocated;
  final double zoom;

  @override
  ConsumerState<LocateMeButton> createState() => _LocateMeButtonState();
}

class _LocateMeButtonState extends ConsumerState<LocateMeButton> {
  bool _locating = false;

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final point = await ref.read(locationSourceProvider).current();
      if (!mounted) return;
      unawaited(HapticFeedback.selectionClick());
      widget.onLocated(point);
      try {
        final zoom = widget.map.camera.zoom;
        widget.map.move(LatLng(point.latitude, point.longitude), zoom < widget.zoom ? widget.zoom : zoom);
      } on Object {
        // Karte noch nicht aufgebaut.
      }
    } on LocationProblem catch (problem) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(problem.message),
            action: problem.canOpenSettings
                ? SnackBarAction(label: 'Einstellungen', onPressed: DeviceLocationSource.openSettings)
                : null,
          ),
        );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) => LiquidSurface(
    radius: LiquidRadii.pill,
    strong: true,
    child: IconButton(
      tooltip: 'Mein Standort',
      onPressed: _locating ? null : () => unawaited(_locate()),
      icon: _locating
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Icon(Icons.my_location, color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// Blauer Punkt mit hellem Hof für den eigenen Standort.
class MyLocationLayer extends StatelessWidget {
  const MyLocationLayer({super.key, required this.point});

  final GeoPoint? point;

  @override
  Widget build(BuildContext context) {
    final point = this.point;
    if (point == null) return const SizedBox.shrink();
    return MarkerLayer(
      markers: [
        Marker(
          point: LatLng(point.latitude, point.longitude),
          width: 40,
          height: 40,
          child: IgnorePointer(
            child: Semantics(
              label: 'Dein Standort',
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppPalette.mapBlue.withValues(alpha: 0.18)),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppPalette.mapBlue,
                          border: Border.all(color: AppPalette.onColor, width: 3),
                          boxShadow: const [
                            BoxShadow(color: AppPalette.mapShadowStrong, blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                        child: const SizedBox.square(dimension: 18),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
