import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/route_repository.dart';
import '../../data/settings/settings_store.dart';

/// Routen, Gebiete und Planer-Einstellungen im Speicher des aktiven Benutzers (dessen eigene Datenbank). Zusätzlich
/// trägt jeder Stand den `username`: Ein Stand eines anderen Benutzers (z. B. aus einer eingespielten Sicherung) wird
/// nicht geladen und nie überschrieben – so vermischt sich nichts zwischen Benutzern.
///
/// Routen liegen in der Tabelle `RouteRecords` (eine Zeile je Route und Benutzer). Ein Stand unter `coach.routes`
/// (bis Schema 2 bzw. aus einer eingespielten Sicherung) wird zusammengeführt – vorhandene Routen bleiben – und danach
/// entfernt. Gelesen wird aus dem Speicher; [ready] meldet, wann die Tabelle geladen ist.
final class RouteStore extends ChangeNotifier {
  RouteStore(this._store, {required this.username, required this._routes, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    // Bis die Tabelle geladen ist: ein noch nicht übernommener Stand aus den Einstellungen.
    _library =
        RouteLibrary.fromJson(_store.json(SettingsKeys.routes), username: username) ?? RouteLibrary(username: username);
    _exploration =
        ExplorationState.fromJson(_store.json(SettingsKeys.exploration), username: username) ??
        ExplorationState(username: username);
    _settings = _store.read(SettingsKeys.routePlanner, RoutePlannerSettings.fromJson, RoutePlannerSettings());
    _favorites =
        FavoritePlaces.fromJson(_store.json(SettingsKeys.favoritePlaces), username: username) ??
        FavoritePlaces(username: username);
    _templates =
        RouteTemplates.fromJson(_store.json(SettingsKeys.routeTemplates), username: username) ??
        RouteTemplates(username: username);
    ready = _load();
    _subscription = _store.changes.where((key) => key == SettingsKeys.routes).listen((_) {
      // Eingespielte Sicherung: übernehmen, sobald der Wert da ist.
      ready = ready.then((_) => _importLegacy()).then((imported) {
        if (imported) notifyListeners();
      });
    });
  }

  final SettingsStore _store;
  final RouteRepository _routes;
  final DateTime Function() _now;
  final String username;
  late RouteLibrary _library;

  /// Wann zuletzt gespeichert (Reihenfolge in der Tabelle).
  final _savedAt = <String, DateTime>{};
  StreamSubscription<String>? _subscription;

  /// Fertig, sobald die Routen aus der Tabelle geladen sind; Schreiben wartet darauf.
  late Future<void> ready;

  Future<void> _load() async {
    final rows = await _routes.all(username);
    _library = RouteLibrary(username: username, routes: [for (final (route, _) in rows) route]);
    _savedAt
      ..clear()
      ..addAll({for (final (route, savedAt) in rows) route.id: savedAt});
    await _importLegacy();
    notifyListeners();
  }

  /// Stand unter `coach.routes` übernehmen (nur fehlende Routen) und den Schlüssel entfernen. Gehört er einem anderen
  /// Benutzer, bleibt er unberührt.
  Future<bool> _importLegacy() async {
    if (!_store.contains(SettingsKeys.routes)) return false;
    final legacy = RouteLibrary.fromJson(_store.json(SettingsKeys.routes), username: username);
    if (legacy == null) return false;
    final known = {for (final route in _library.routes) route.id};
    final missing = [
      for (final route in legacy.routes)
        if (!known.contains(route.id)) route,
    ];
    // Ältere zuerst einreihen, damit die Reihenfolge der Ablage erhalten bleibt.
    final base = _now();
    final entries = [
      for (final (index, route) in missing.indexed) (route, base.subtract(Duration(seconds: index + 1))),
    ];
    await _routes.putAll(entries);
    for (final (route, savedAt) in entries) {
      _savedAt[route.id] = savedAt;
    }
    _library = RouteLibrary(username: username, routes: [..._library.routes, ...missing]);
    await _store.remove(SettingsKeys.routes);
    return missing.isNotEmpty;
  }

  /// Routenvorschläge für geplante Läufe (Einstellungen und Stand je Einheit).
  RunRouteSuggestions get runSuggestions =>
      RunRouteSuggestions.fromJson(_store.json(SettingsKeys.runRouteSuggestions), username: username) ??
      RunRouteSuggestions(username: username);

  Future<void> updateRunSuggestions(void Function(RunRouteSuggestions suggestions) change) async {
    final current = runSuggestions;
    change(current);
    current.prune(CalendarDay.today());
    notifyListeners();
    await _store.setJson(SettingsKeys.runRouteSuggestions, current.toJson());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  /// Geänderte bzw. weggefallene Routen in die Tabelle schreiben.
  Future<void> _persist({Iterable<PlannedRoute> changed = const [], Set<String> before = const {}}) async {
    final now = {for (final route in _library.routes) route.id};
    await _routes.delete(username, before.difference(now));
    await _routes.putAll([
      for (final route in changed)
        if (now.contains(route.id)) (route, _savedAt[route.id] ?? _now()),
    ]);
  }

  late ExplorationState _exploration;
  late RoutePlannerSettings _settings;
  late FavoritePlaces _favorites;
  late RouteTemplates _templates;

  /// Vorlagen („Gassi 3 km ab Zuhause“).
  List<RouteTemplate> get templates => List.unmodifiable(_templates.templates);

  bool get hasForeignTemplates =>
      _store.contains(SettingsKeys.routeTemplates) &&
      RouteTemplates.fromJson(_store.json(SettingsKeys.routeTemplates), username: username) == null;

  Future<void> saveTemplate(RouteTemplate template) async {
    if (hasForeignTemplates) throw StateError('Die Vorlagen gehören einem anderen Benutzer.');
    _templates.save(template);
    notifyListeners();
    await _store.setJson(SettingsKeys.routeTemplates, _templates.toJson());
  }

  Future<void> deleteTemplate(String id) async {
    if (hasForeignTemplates) return;
    _templates.delete(id);
    notifyListeners();
    await _store.setJson(SettingsKeys.routeTemplates, _templates.toJson());
  }

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

  /// Liegt unter `coach.routes` noch ein Stand eines anderen Benutzers (z. B. aus einer Sicherung)? Er wird weder
  /// übernommen noch entfernt; die eigenen Routen in der Tabelle betrifft das nicht.
  bool get hasForeignRoutes =>
      _store.contains(SettingsKeys.routes) &&
      RouteLibrary.fromJson(_store.json(SettingsKeys.routes), username: username) == null;

  bool get hasForeignExploration =>
      _store.contains(SettingsKeys.exploration) &&
      ExplorationState.fromJson(_store.json(SettingsKeys.exploration), username: username) == null;

  PlannedRoute? route(String id) => _library.route(id);

  List<PlannedRoute> plannedOn(CalendarDay day) => _library.plannedOn(day);

  /// Offene Routen (geplant oder gespeichert, noch nicht abgeschlossen).
  List<PlannedRoute> get openRoutes => _library.open;

  /// Archiv: abgeschlossene, vorab geplante Routen.
  List<PlannedRoute> get archive => _library.archive;

  /// Geplante Routen, für deren Tag eine passende Aktivität vorliegt, ins Archiv übernehmen; Anzahl der neuen.
  Future<int> completeFromActivities(List<GarminActivity> activities, {DateTime? now}) async {
    await ready;
    final changed = <PlannedRoute>[];
    final taken = {for (final route in _library.routes) ?route.activityID};
    var count = 0;
    for (final route in _library.routes) {
      final match = RouteCompletion.match(route, activities, taken: taken);
      if (match == null) continue;
      route
        ..completedAt = now ?? DateTime.now()
        ..activityID = match.id;
      taken.add(match.id);
      changed.add(route);
      count++;
    }
    if (count == 0) return 0;
    notifyListeners();
    await _persist(changed: changed);
    return count;
  }

  /// Von Hand abschließen bzw. zurück in die Planung holen.
  Future<void> setCompleted(PlannedRoute route, {required bool completed}) async {
    route
      ..completedAt = completed ? DateTime.now() : null
      ..activityID = completed ? route.activityID : null;
    await save(route);
  }

  Future<void> save(PlannedRoute route) async {
    if (route.username != username) throw StateError('Die Route gehört nicht dem angemeldeten Benutzer.');
    await ready;
    final before = {for (final route in _library.routes) route.id};
    _library.save(route);
    _savedAt[route.id] = _now();
    notifyListeners();
    // Über die Höchstzahl gefallene Routen verschwinden auch aus der Tabelle.
    await _persist(changed: [route], before: before);
  }

  Future<void> delete(String id) async {
    await ready;
    final before = {for (final route in _library.routes) route.id};
    _library.delete(id);
    _savedAt.remove(id);
    notifyListeners();
    await _persist(before: before);
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
