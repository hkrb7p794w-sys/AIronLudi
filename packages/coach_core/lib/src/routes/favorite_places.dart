// Favorisierte Orte des Routenplaners (neu in AIronLudi): Zuhause, Hundewiese, Treffpunkt … – als Start oder Ziel mit
// einem Tipp. Gehören genau einem Benutzer (Schlüssel `coach.favoritePlaces`).
import '../util/swift_date.dart';
import 'geo.dart';
import 'geocoding.dart';

final class FavoritePlace {
  const FavoritePlace({
    required this.id,
    required this.name,
    required this.point,
    required this.createdAt,
    this.address,
  });

  final String id;
  final String name;
  final GeoPoint point;
  final DateTime createdAt;

  /// Gesuchte Adresse, falls der Ort aus der Adresszeile stammt.
  final String? address;

  FavoritePlace renamed(String value) =>
      FavoritePlace(id: id, name: value, point: point, createdAt: createdAt, address: address);

  /// Als Treffer der Adresssuche (Start oder Ziel).
  Place get place => Place(title: name, detail: address ?? '', point: point);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'point': point.toJson(),
    'createdAt': swiftDateToJson(createdAt),
    'address': ?address,
  };

  static FavoritePlace? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final point = GeoPoint.fromJson(json['point']);
    final created = swiftDateFromJson(json['createdAt']);
    if (id is! String || name is! String || name.trim().isEmpty || point == null || created == null) return null;
    final address = json['address'];
    return FavoritePlace(
      id: id,
      name: name,
      point: point,
      createdAt: created,
      address: address is String && address.isNotEmpty ? address : null,
    );
  }
}

/// Alle favorisierten Orte eines Benutzers.
final class FavoritePlaces {
  FavoritePlaces({required this.username, List<FavoritePlace>? places}) : places = places ?? [];

  final String username;
  final List<FavoritePlace> places;

  static const maxPlaces = 40;

  /// Gleich genug, um als derselbe Ort zu gelten (30 m).
  static const sameDistance = 30.0;

  FavoritePlace? near(GeoPoint point) =>
      places.where((place) => Geo.distance(place.point, point) <= sameDistance).firstOrNull;

  /// Neu vorn; liegt schon ein Favorit an derselben Stelle, wird er ersetzt (neuer Name).
  void save(FavoritePlace place) {
    places
      ..removeWhere((item) => item.id == place.id || Geo.distance(item.point, place.point) <= sameDistance)
      ..insert(0, place);
    if (places.length > maxPlaces) places.removeRange(maxPlaces, places.length);
  }

  void rename(String id, String name) {
    final index = places.indexWhere((place) => place.id == id);
    if (index >= 0 && name.trim().isNotEmpty) places[index] = places[index].renamed(name.trim());
  }

  void delete(String id) => places.removeWhere((place) => place.id == id);

  /// Favoriten, deren Name oder Adresse den Text enthält (für die Adresszeile).
  List<FavoritePlace> matching(String query) {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return [...places];
    return [
      for (final place in places)
        if (place.name.toLowerCase().contains(text) || (place.address?.toLowerCase().contains(text) ?? false)) place,
    ];
  }

  Map<String, Object?> toJson() => {
    'username': username,
    'places': [for (final place in places) place.toJson()],
  };

  /// Gehört die Liste einem anderen Benutzer, `null` (wird nicht geladen und nicht überschrieben).
  static FavoritePlaces? fromJson(Object? json, {required String username}) {
    if (json is! Map || json['username'] != username) return null;
    final list = json['places'];
    return FavoritePlaces(
      username: username,
      places: [
        if (list is List)
          for (final item in list) ?FavoritePlace.fromJson(item),
      ],
    );
  }
}
