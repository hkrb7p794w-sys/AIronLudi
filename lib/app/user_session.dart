import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/secure/secret_store.dart';
import '../data/storage.dart';
import '../data/users/user_storage.dart';
import '../platform/notifications.dart';
import '../services/widgets/widget_providers.dart';

/// Öffnet den Container eines Benutzers (`createAppContainer`); in Tests ersetzbar.
typedef OpenUserContainer = Future<ProviderContainer> Function(LocalUser user, UserSession session);

/// Benutzer dieses Geräts und der Container des aktiven (zentrales Benutzer-Management). Gehört dem Gerät, nicht
/// einem Benutzer, und hält selbst keine Nutzerdaten – nur das Verzeichnis (Namen, Kennungen) und den einen offenen
/// Container. Beim Wechsel ([switchTo]):
/// 1. Der bisherige Benutzer räumt auf: Wasser aus dem Widget übernimmt noch seine Datenbank, Live-Aktivitäten enden,
///    geplante Mitteilungen werden entfernt, die Widgets vergessen seinen Stand.
/// 2. Sein Container wird verworfen (alle Controller, Zwischenspeicher, Geheimnisse im Arbeitsspeicher) und seine
///    Datenbank geschlossen; der Bild-Zwischenspeicher wird geleert.
/// 3. Der neue Benutzer wird aktiv und gespeichert, sein Container frisch geöffnet. Die Oberfläche baut sich mit
///    neuem Schlüssel komplett neu auf (`UserScope`).
/// Spät eintreffende Antworten (KI, Garmin) des alten Containers landen nirgends: Seine Datenbank ist geschlossen.
final class UserSession extends ChangeNotifier {
  UserSession({
    required this.directory,
    required this.store,
    required this._open,
    required this.folders,
    this.notificationCenter,
    SecretStore Function(String prefix)? secrets,
    Future<void> Function()? waitForFrame,
  }) : _secrets = secrets ?? ((prefix) => DeviceSecretStore(prefix: prefix)),
       _waitForFrame = waitForFrame ?? (() => SchedulerBinding.instance.endOfFrame);

  final UserDirectory directory;
  final UserDirectoryStore store;
  final OpenUserContainer _open;
  final ({String? documents, String? support, String? cache}) folders;
  final NotificationCenterBridge? notificationCenter;
  final SecretStore Function(String prefix) _secrets;

  /// Erst wenn die Oberfläche den alten Container losgelassen hat (Ladebild), wird er verworfen.
  final Future<void> Function() _waitForFrame;

  ProviderContainer? _container;

  /// Steigt mit jedem Wechsel; Schlüssel der Oberfläche.
  int generation = 0;
  bool isSwitching = false;

  LocalUser get user => directory.active;

  List<LocalUser> get users => directory.users;

  ProviderContainer get container => _container ?? (throw StateError('UserSession.start fehlt'));

  /// Erster Container (beim App-Start).
  Future<void> start() async {
    _container ??= await _open(user, this);
  }

  /// Neuen Benutzer mit leerem Speicher anlegen; [activate]: gleich wechseln.
  Future<LocalUser> add({required String username, String displayName = '', bool activate = true}) async {
    final created = directory.add(username: username, displayName: displayName);
    await store.save(directory);
    notifyListeners();
    if (activate) await switchTo(created.id);
    return created;
  }

  Future<void> rename(String id, String displayName) async {
    directory.rename(id, displayName);
    await store.save(directory);
    notifyListeners();
  }

  /// Benutzer und seinen gesamten Speicher löschen (nicht den aktiven, nicht den ursprünglichen).
  Future<void> remove(String id) async {
    final removed = directory.remove(id);
    await store.save(directory);
    await deleteUserStorage(
      UserLocation(removed),
      documents: folders.documents,
      support: folders.support,
      cache: folders.cache,
      secrets: _secrets,
    );
    notifyListeners();
  }

  Future<void> switchTo(String id) async {
    if (isSwitching || id == user.id) return;
    if (directory.byID(id) == null) throw const UserDirectoryError('Diesen Benutzer gibt es nicht.');
    isSwitching = true;
    notifyListeners();
    try {
      await _waitForFrame();
      final old = _container;
      if (old != null) {
        await leave(old, notificationCenter: notificationCenter);
        _container = null;
        await _close(old);
      }
      // Bilder (z. B. Begleiter-Foto, Mahlzeit-Fotos) des bisherigen Benutzers nicht im Speicher lassen.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      directory.activate(id);
      await store.save(directory);
      _container = await _open(user, this);
      generation++;
    } finally {
      isSwitching = false;
      notifyListeners();
    }
  }

  /// Container verwerfen: Einstellungen nehmen nichts mehr an, dann alle Provider weg, zuletzt die Datenbank zu.
  static Future<void> _close(ProviderContainer container) async {
    final storage = container.read(appStorageProvider);
    await storage.settings.close().catchError((Object _) {});
    container.dispose();
    await storage.database.close().catchError((Object _) {});
  }

  /// Aufräumen, bevor der Container eines Benutzers verworfen wird (auch für Tests).
  static Future<void> leave(ProviderContainer container, {NotificationCenterBridge? notificationCenter}) async {
    Future<void> attempt(Future<void> Function() step) async {
      try {
        await step();
      } on Object {
        // Ein Schritt darf den Wechsel nicht aufhalten.
      }
    }

    final publisher = container.read(widgetPublisherProvider);
    final host = container.read(liveActivityHostProvider);
    // Wasser aus dem Widget gehört noch dem bisherigen Benutzer.
    await attempt(() async => publisher.takeQueuedActions());
    await attempt(() => host.updateWorkout(null, title: ''));
    await attempt(() => host.updateMeals(null, now: DateTime.now()));
    await attempt(() => container.read(widgetStoreProvider).clear());
    final center = notificationCenter;
    if (center != null) {
      await attempt(() async => center.removePending(await center.pendingIdentifiers()));
    }
  }

  @override
  void dispose() {
    final current = _container;
    _container = null;
    if (current != null) unawaited(_close(current));
    super.dispose();
  }
}
