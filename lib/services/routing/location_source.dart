import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:geolocator/geolocator.dart';

/// Aktueller Standort als Startpunkt – nur auf Wunsch und nur im Vordergrund.
abstract interface class LocationSource {
  /// Wirft [LocationProblem] mit einer verständlichen Meldung.
  Future<GeoPoint> current();

  /// Laufende Positionen, solange jemand zuhört; Fehler als [LocationProblem]. [background]: auch bei gesperrtem
  /// Bildschirm (iOS mit blauer Standortanzeige, Android als Vordergrunddienst mit Mitteilung).
  Stream<GeoPoint> watch({bool background = false});
}

final class LocationProblem implements Exception {
  const LocationProblem(this.message, {this.canOpenSettings = false});

  final String message;
  final bool canOpenSettings;

  @override
  String toString() => message;
}

final class DeviceLocationSource implements LocationSource {
  const DeviceLocationSource();

  @override
  Future<GeoPoint> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationProblem('Ortungsdienste sind ausgeschaltet. Setze den Start alternativ auf der Karte.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw const LocationProblem('Ohne Standortfreigabe: Setze den Start mit einem Pin auf der Karte.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationProblem(
        'Der Standort ist für AIronLudi gesperrt. Du kannst ihn in den Einstellungen freigeben oder den Start auf der '
        'Karte setzen.',
        canOpenSettings: true,
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return GeoPoint(position.latitude, position.longitude);
    } on Object {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return GeoPoint(last.latitude, last.longitude);
      throw const LocationProblem('Der Standort ließ sich gerade nicht bestimmen. Setze den Start auf der Karte.');
    }
  }

  @override
  Stream<GeoPoint> watch({bool background = false}) async* {
    // Freigabe wie bei [current] prüfen (wirft verständliche Meldungen).
    await current();
    yield* Geolocator.getPositionStream(locationSettings: settings(background: background))
        .map((position) => GeoPoint(position.latitude, position.longitude));
  }

  /// Einstellungen je Plattform: im Hintergrund unter iOS mit Standortanzeige und ohne automatische Pause (Ampeln),
  /// unter Android als Vordergrunddienst mit dauerhafter Mitteilung.
  static LocationSettings settings({required bool background}) {
    if (!background) return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5);
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Route folgen',
          notificationText: 'AIronLudi zeigt dir den Weg – auch bei gesperrtem Bildschirm.',
          notificationChannelName: 'Route folgen (Ortung)',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5);
  }

  static Future<void> openSettings() => Geolocator.openAppSettings();
}
