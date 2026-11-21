import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';

import '../garmin/garmin_sync_service.dart';
import 'route_stores.dart';

/// Übernimmt abgeschlossene Aktivitäten mit GPS-Strecke in die Erkundung: aus den zwischengespeicherten FIT-Dateien
/// (Garmin) – ohne neue Downloads. Jede Aktivität zählt einmal (`a<ID>`).
final class ExplorationImport {
  ExplorationImport({required this.store, required this.sync});

  final RouteStore store;
  final GarminSyncService sync;

  static bool counts(GarminActivity activity) =>
      activity.sport == ActivitySport.run ||
      activity.sport == ActivitySport.bike ||
      (activity.typeKey?.contains('hik') ?? false) ||
      (activity.typeKey?.contains('walk') ?? false);

  static String sourceID(GarminActivity activity) => 'a${activity.id}';

  static ExplorationTrack? track(GarminActivity activity, FitActivity fit) {
    final day = activity.day;
    if (day == null) return null;
    final points = [
      for (final point in ActivityDetails.route(fit, maxPoints: 3000)) GeoPoint(point.latitude, point.longitude),
    ];
    if (points.length < 2) return null;
    return ExplorationTrack(sourceID: sourceID(activity), name: activity.name ?? 'Aktivität', day: day, points: points);
  }

  /// Eine gerade geladene Aktivität (Detailseite) aufnehmen.
  Future<ExplorationGain?> record(GarminActivity activity, FitActivity fit) async {
    if (!store.settings.explorationEnabled || !counts(activity) || store.isExplored(sourceID(activity))) return null;
    final track = ExplorationImport.track(activity, fit);
    if (track == null) return null;
    return (await store.explore([track])).firstOrNull;
  }

  /// Alle zwischengespeicherten Aktivitäten durchgehen; Ergebnis: Anzahl aufgenommener Strecken und Zugewinn.
  Future<({int tracks, int newTiles, int territories})> importCached(List<GarminActivity> activities) async {
    final tracks = <ExplorationTrack>[];
    for (final activity in activities) {
      if (!counts(activity) || store.isExplored(sourceID(activity))) continue;
      final Uint8List? data = sync.reportStore.cachedFile(activity.id);
      if (data == null) continue;
      try {
        final fit = await GarminSyncService.decodeFit(data);
        if (track(activity, fit) case final track?) tracks.add(track);
      } on Object {
        // Kaputte Datei: überspringen.
      }
    }
    final gains = await store.explore(tracks);
    return (
      tracks: tracks.length,
      newTiles: gains.fold<int>(0, (sum, gain) => sum + gain.newTiles),
      territories: gains.where((gain) => gain.territory != null).length,
    );
  }
}
