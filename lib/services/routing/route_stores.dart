import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/settings/settings_store.dart';

/// Routen, Gebiete und Planer-Einstellungen im Speicher des aktiven Benutzers (dessen eigene Datenbank). Zusätzlich
/// trägt jeder Stand den `username`: Ein Stand eines anderen Benutzers (z. B. aus einer eingespielten Sicherung) wird
/// nicht geladen und nie überschrieben – so vermischt sich nichts zwischen Benutzern.
final class RouteStore extends ChangeNotifier {
  RouteStore(this._store, {required this.username}) {
    _library =
        RouteLibrary.fromJson(_store.json(SettingsKeys.routes), username: username) ?? RouteLibrary(username: username);
    _exploration =
        ExplorationState.fromJson(_store.json(SettingsKeys.exploration), username: username) ??
        ExplorationState(username: username);
    _settings = _store.read(SettingsKeys.routePlanner, RoutePlannerSettings.fromJson, RoutePlannerSettings());
    _favorites =
        FavoritePlaces.fromJson(_store.json(SettingsKeys.favoritePlaces), username: username) ??
        FavoritePlaces(username: username);
  }

  final SettingsStore _store;
  final String username;
  late RouteLibrary _library;
  late ExplorationState _exploration;
  late RoutePlannerSettings _settings;
  late FavoritePlaces _favorites;

  /// Favorisierte Orte (Start/Ziel mit einem Tipp).
  List<FavoritePlace> get favorites => List.unmodifiable(_favorites.places);

  FavoritePlace? favoriteNear(GeoPoint point) => _favorites.near(point);

  List<FavoritePlace> favoritesMatching(String query) => _favorites.matching(query);

  bool get hasForeignFavorites =>
      _store.contains(SettingsKeys.favoritePlaces) &&
      FavoritePlaces.fromJson(_store.json(SettingsKeys.favoritePlaces), username: username) == null;

  Future<void> saveFavorite(FavoritePlace place) async {
    if (hasForeignFavorites) throw StateError('Die Favoriten gehören einem anderen Benutzer.');
    _favorites.save(place);
    notifyListeners();
    await _store.setJson(SettingsKeys.favoritePlaces, _favorites.toJson());
  }

  Future<void> renameFavorite(String id, String name) async {
    if (hasForeignFavorites) return;
    _favorites.rename(id, name);
    notifyListeners();
    await _store.setJson(SettingsKeys.favoritePlaces, _favorites.toJson());
  }

  Future<void> deleteFavorite(String id) async {
    if (hasForeignFavorites) return;
    _favorites.delete(id);
    notifyListeners();
    await _store.setJson(SettingsKeys.favoritePlaces, _favorites.toJson());
  }

  List<PlannedRoute> get routes => List.unmodifiable(_library.routes);
  ExplorationState get exploration => _exploration;
  RoutePlannerSettings get settings => _settings;

  /// Liegt unter dem Schlüssel ein Stand eines anderen Benutzers? Dann wird er beim Speichern nicht überschrieben.
  bool get hasForeignRoutes =>
      _store.contains(SettingsKeys.routes) &&
      RouteLibrary.fromJson(_store.json(SettingsKeys.routes), username: username) == null;

  bool get hasForeignExploration =>
      _store.contains(SettingsKeys.exploration) &&
      ExplorationState.fromJson(_store.json(SettingsKeys.exploration), username: username) == null;

  PlannedRoute? route(String id) => _library.route(id);

  List<PlannedRoute> plannedOn(CalendarDay day) => _library.plannedOn(day);

  Future<void> save(PlannedRoute route) async {
    if (route.username != username) throw StateError('Die Route gehört nicht dem angemeldeten Benutzer.');
    if (hasForeignRoutes) throw StateError('Die gespeicherten Routen gehören einem anderen Benutzer.');
    _library.save(route);
    notifyListeners();
    await _store.setJson(SettingsKeys.routes, _library.toJson());
  }

  Future<void> delete(String id) async {
    if (hasForeignRoutes) return;
    _library.delete(id);
    notifyListeners();
    await _store.setJson(SettingsKeys.routes, _library.toJson());
  }

  Future<void> updateSettings(void Function(RoutePlannerSettings settings) change) async {
    change(_settings);
    notifyListeners();
    await _store.setJson(SettingsKeys.routePlanner, _settings.toJson());
  }

  /// Nimmt Strecken in die Erkundung auf; gibt den Zugewinn zurück.
  Future<List<ExplorationGain>> explore(List<ExplorationTrack> tracks) async {
    if (!_settings.explorationEnabled || hasForeignExploration || tracks.isEmpty) return const [];
    final gains = [for (final track in tracks) _exploration.add(track)];
    if (gains.every((gain) => gain.isEmpty)) return gains;
    notifyListeners();
    await _store.setJson(SettingsKeys.exploration, _exploration.toJson());
    return gains;
  }

  bool isExplored(String sourceID) => _exploration.processed.contains(sourceID);

  Future<void> resetExploration() async {
    if (hasForeignExploration) return;
    _exploration = _exploration.cleared();
    notifyListeners();
    await _store.remove(SettingsKeys.exploration);
  }
}
