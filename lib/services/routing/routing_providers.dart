import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/storage.dart';
import '../../data/users/current_user.dart';
import '../http/http_transport.dart';
import '../providers.dart';
import 'exploration_import.dart';
import 'garmin_course_service.dart';
import 'location_source.dart';
import 'route_stores.dart';
import 'routing_service.dart';

/// Routen, Gebiete und Planer-Einstellungen des aktiven Benutzers (je Benutzer ein eigener Container).
final routeStoreProvider = ChangeNotifierProvider<RouteStore>(
  (ref) => RouteStore(ref.watch(settingsStoreProvider), username: ref.watch(currentUserProvider).username),
);

/// Router mit Ausweichen (Valhalla → BRouter); in Tests überschreibbar.
final routingBackendProvider = Provider<RoutingBackend>((ref) {
  final transport = DioTransport();
  ref.onDispose(transport.close);
  return FallbackRoutingBackend.standard(transport);
});

/// Wege der gewünschten Art (Wald, Wasser, Radwege) aus OSM über Overpass; in Tests überschreibbar.
final routeFeatureSourceProvider = Provider<RouteFeatureSource?>((ref) {
  final transport = DioTransport();
  ref.onDispose(transport.close);
  return OverpassFeatureSource(transport);
});

/// Adresssuche für Start und Ziel (Photon, Nominatim); in Tests überschreibbar.
final placeSearchProvider = Provider<PlaceSearch>((ref) {
  final transport = DioTransport();
  ref.onDispose(transport.close);
  return OsmPlaceSearch(transport);
});

/// Punkte unterwegs (Trinkbrunnen, Hundewiesen, Kotbeutel); in Tests überschreibbar.
final routePoiSourceProvider = Provider<RoutePoiSource>((ref) {
  final transport = DioTransport();
  ref.onDispose(transport.close);
  return OverpassPoiSource(transport);
});

/// Punkte unterwegs für eine Route (leer, wenn der Dienst nicht antwortet – sie sind nur eine Ergänzung).
final routePoisProvider = FutureProvider.autoDispose.family<List<RoutePoi>, PlannedRoute>((ref, route) async {
  try {
    return await ref
        .read(routePoiSourceProvider)
        .pois(route.points, kinds: PoiFormat.kindsFor(walk: route.discipline == RouteDiscipline.walk));
  } on Object {
    return const [];
  }
});

final locationSourceProvider = Provider<LocationSource>((ref) => const DeviceLocationSource());

final explorationImportProvider = Provider<ExplorationImport>(
  (ref) => ExplorationImport(store: ref.watch(routeStoreProvider), sync: ref.watch(garminSyncServiceProvider)),
);

/// Kurse direkt in Garmin Connect anlegen (Garmin-Konto aus den Einstellungen); in Tests überschreibbar.
final garminCourseTargetProvider = Provider<GarminCourseTarget>((ref) {
  final connect = ref.watch(garminConnectProvider);
  return GarminCourseTarget(isLoggedIn: () => connect.isLoggedIn, sender: connect.sendJson);
});
