// Vorlagen des Routenplaners (neu in AIronLudi), z. B. „Gassi 3 km ab Zuhause“: Disziplin, Form, Distanz, Wegarten und
// Start – mit einem Tipp geplant. Gehören genau einem Benutzer (Schlüssel `coach.routeTemplates`).
import '../util/enum_codec.dart';
import 'geo.dart';
import 'route_planning.dart';

final class RouteTemplate {
  const RouteTemplate({
    required this.id,
    required this.name,
    required this.discipline,
    required this.shape,
    required this.kilometers,
    required this.start,
    this.startLabel,
    this.preferences = const {},
  });

  final String id;
  final String name;
  final RouteDiscipline discipline;

  /// Rundweg oder Richtung (zum festen Ziel braucht es ein Ziel – das fragt der Planer).
  final RouteShape shape;
  final double kilometers;
  final GeoPoint start;
  final String? startLabel;
  final Set<RoutePreference> preferences;

  /// „Spazieren · 3 km · Rundweg · Hundewiese“.
  String get summary => [
    discipline.label,
    '${kilometers == kilometers.roundToDouble() ? kilometers.round() : kilometers.toStringAsFixed(1).replaceAll('.', ',')} km',
    shape.label,
    if (preferences.isNotEmpty) RoutePreference.describe(preferences),
  ].join(' · ');

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'discipline': discipline.rawValue,
    'shape': shape.rawValue,
    'kilometers': kilometers,
    'start': start.toJson(),
    'startLabel': ?startLabel,
    'preferences': [
      for (final preference in RoutePreference.values)
        if (preferences.contains(preference)) preference.rawValue,
    ],
  };

  static RouteTemplate? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final discipline = enumFromRaw(RouteDiscipline.values, json['discipline']);
    final shape = enumFromRaw(RouteShape.generated, json['shape']);
    final kilometers = json['kilometers'];
    final start = GeoPoint.fromJson(json['start']);
    if (id is! String || name is! String || discipline == null || shape == null || kilometers is! num) return null;
    if (start == null || shape == RouteShape.toDestination) return null;
    final label = json['startLabel'];
    return RouteTemplate(
      id: id,
      name: name,
      discipline: discipline,
      shape: shape,
      kilometers: kilometers.toDouble(),
      start: start,
      startLabel: label is String ? label : null,
      preferences: {...enumListFromRaw(RoutePreference.values, json['preferences'])},
    );
  }
}

/// Alle Vorlagen eines Benutzers.
final class RouteTemplates {
  RouteTemplates({required this.username, List<RouteTemplate>? templates}) : templates = templates ?? [];

  final String username;
  final List<RouteTemplate> templates;

  static const maxTemplates = 20;

  void save(RouteTemplate template) {
    templates
      ..removeWhere((item) => item.id == template.id)
      ..insert(0, template);
    if (templates.length > maxTemplates) templates.removeRange(maxTemplates, templates.length);
  }

  void delete(String id) => templates.removeWhere((template) => template.id == id);

  Map<String, Object?> toJson() => {
    'username': username,
    'templates': [for (final template in templates) template.toJson()],
  };

  /// Gehört die Liste einem anderen Benutzer, `null` (wird nicht geladen und nicht überschrieben).
  static RouteTemplates? fromJson(Object? json, {required String username}) {
    if (json is! Map || json['username'] != username) return null;
    final list = json['templates'];
    return RouteTemplates(
      username: username,
      templates: [
        if (list is List)
          for (final item in list) ?RouteTemplate.fromJson(item),
      ],
    );
  }
}
