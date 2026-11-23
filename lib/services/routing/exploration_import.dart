import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';

import '../garmin/garmin_sync_service.dart';
import 'route_stores.dart';

/// Dateien der Uhr je Aktivität; in Tests ersetzbar.
abstract interface class ActivityFiles {
  /// Schon geladen (Zwischenspeicher), sonst `null`.
  Uint8List? cached(int id);

  /// Von Garmin laden (und zwischenspeichern); wirft bei Fehlern.
  Future<Uint8List> download(int id);
}

final class GarminActivityFiles implements ActivityFiles {
  const GarminActivityFiles(this._sync);

  final GarminSyncService _sync;

  @override
  Uint8List? cached(int id) => _sync.reportStore.cachedFile(id);

  @override
  Future<Uint8List> download(int id) => _sync.activityFile(id);
}

/// Ergebnis einer Übernahme in die Erkundung.
typedef ExplorationImportResult = ({int tracks, int newTiles, int territories, int remaining});

/// Übernimmt abgeschlossene Aktivitäten mit GPS-Strecke in die Erkundung. Jede Aktivität zählt einmal (`a<ID>`).
/// Schon geladene Dateien still nach jedem Abruf; fehlende der letzten Wochen auf Wunsch, mit Pause zwischen den
/// Downloads und begrenzt je Durchgang (Garmin drosselt sonst).
final class ExplorationImport {
  ExplorationImport({required this.store, required this.files, Future<void> Function(Duration)? sleep})
    : _sleep = sleep ?? Future<void>.delayed;

  final RouteStore store;
  final ActivityFiles files;
  final Future<void> Function(Duration) _sleep;

  /// Wie weit zurück fehlende Dateien geladen werden.
  static const recentWeeks = 12;

  /// Höchstens so viele Downloads je Durchgang, mit dieser Pause dazwischen.
  static const maxDownloads = 15;
  static const downloadPause = Duration(milliseconds: 1500);

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

  /// Noch nicht aufgenommene Garmin-Aktivitäten mit Strecke (jüngste zuerst), optional nur ab [since].
  List<GarminActivity> pending(List<GarminActivity> activities, {CalendarDay? since}) => [
    for (final activity in activities.reversed)
      if (activity.id >= 0 &&
          counts(activity) &&
          !store.isExplored(sourceID(activity)) &&
          (since == null || (activity.day != null && activity.day! >= since)))
        activity,
  ];

  /// Alle schon geladenen Dateien übernehmen (ohne Downloads) – still nach jedem Abruf.
  Future<ExplorationImportResult> importCached(List<GarminActivity> activities) =>
      _import(pending(activities), downloads: 0);

  /// Zusätzlich fehlende Dateien der letzten [recentWeeks] Wochen laden: höchstens [maxDownloads], mit Pause
  /// dazwischen. `remaining`: was noch fehlt (nächster Durchgang).
  Future<ExplorationImportResult> importRecent(
    List<GarminActivity> activities, {
    required CalendarDay today,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) => _import(
    pending(activities, since: today.adding(-recentWeeks * 7)),
    downloads: maxDownloads,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );

  Future<ExplorationImportResult> _import(
    List<GarminActivity> candidates, {
    required int downloads,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!store.settings.explorationEnabled) return (tracks: 0, newTiles: 0, territories: 0, remaining: 0);
    final tracks = <ExplorationTrack>[];
    var fetched = 0;
    var remaining = 0;
    var failures = 0;
    for (final (index, activity) in candidates.indexed) {
      if (isCancelled?.call() ?? false) {
        remaining += candidates.length - index;
        break;
      }
      var data = files.cached(activity.id);
      if (data == null) {
        // Nach zwei Fehlern in Folge (z. B. abgemeldet, gedrosselt) nicht weiter versuchen.
        if (fetched >= downloads || failures >= 2) {
          if (downloads > 0) remaining++;
          continue;
        }
        if (fetched > 0) await _sleep(downloadPause);
        fetched++;
        try {
          data = await files.download(activity.id);
          failures = 0;
        } on Object {
          failures++;
          remaining++;
          continue;
        }
      }
      onProgress?.call(index + 1, candidates.length);
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
      remaining: remaining,
    );
  }
}
