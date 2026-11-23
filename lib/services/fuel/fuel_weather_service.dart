import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routing/location_source.dart';
import '../routing/route_stores.dart';
import '../routing/route_weather_service.dart';
import '../routing/routing_providers.dart';

/// Wetter für den Plan: Ort = Start einer Route, die zur Einheit gehört, sonst der Favorit „Zuhause“ (bzw. der erste
/// Favorit), sonst der aktuelle Standort. Vorhersage von Open-Meteo wie beim Routenplaner (bis 15 Tage voraus).
final class FuelWeatherService {
  const FuelWeatherService({required this.routes, required this.location, required this.weather});

  final RouteStore routes;
  final LocationSource location;
  final WeatherSource weather;

  Future<GeoPoint> _place(FuelScenario scenario) async {
    final slot = scenario.slotID;
    if (slot != null) {
      for (final route in [...routes.openRoutes, ...routes.archive]) {
        if (route.slotID == slot && route.points.isNotEmpty) return route.points.first;
      }
    }
    final favorites = routes.favorites;
    final home = favorites.where((place) => place.name.toLowerCase().contains('zuhause')).firstOrNull;
    if (home != null) return home.point;
    if (favorites.isNotEmpty) return favorites.first.point;
    return location.current();
  }

  /// Szenario mit Temperatur und Luftfeuchte der Vorhersage und eine kurze Meldung. Wirft [FuelWeatherProblem].
  Future<(FuelScenario, String)> apply(FuelScenario scenario, {CalendarDay? today}) async {
    final now = today ?? CalendarDay.today();
    final day = scenario.day ?? now;
    if (!OpenMeteoFormat.covers(day, today: now)) {
      throw const FuelWeatherProblem('Die Vorhersage reicht nur 15 Tage voraus.');
    }
    final GeoPoint point;
    try {
      point = await _place(scenario);
    } on LocationProblem catch (problem) {
      throw FuelWeatherProblem(problem.message);
    }
    final List<WeatherHour> hours;
    try {
      hours = await weather.forecast(point, day);
    } on Object {
      throw const FuelWeatherProblem('Die Vorhersage ist gerade nicht erreichbar.');
    }
    final start = scenario.startMinuteOfDay ?? FuelWeather.defaultStartMinute;
    final result = FuelWeather.of(hours, startMinuteOfDay: start, minutes: scenario.minutes);
    if (result == null) throw const FuelWeatherProblem('Für diese Zeit gibt es keine Vorhersage.');
    final humidity = result.relativeHumidity == null ? '' : ', ${result.relativeHumidity} % Luftfeuchte';
    return (
      scenario.copyWith(temperatureCelsius: result.temperature, humidity: result.humidity),
      'Wetter ab ${start ~/ 60} Uhr: ${GermanFormat.decimal(result.temperature)} °C$humidity',
    );
  }
}

final class FuelWeatherProblem implements Exception {
  const FuelWeatherProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// In Tests überschreibbar (Ort und Vorhersage kommen von den Providern des Routenplaners).
final fuelWeatherServiceProvider = Provider<FuelWeatherService>(
  (ref) => FuelWeatherService(
    routes: ref.read(routeStoreProvider),
    location: ref.watch(locationSourceProvider),
    weather: ref.watch(weatherSourceProvider),
  ),
);
