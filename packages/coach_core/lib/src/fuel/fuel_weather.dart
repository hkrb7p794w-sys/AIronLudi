// Fuel Planner: Temperatur und Luftfeuchte aus der Vorhersage (Open-Meteo, wie beim Routenplaner) für die Stunden
// der Einheit. Die Stufen der Luftfeuchte sind eine eigene Festlegung (Spezifikation 9).
import 'package:collection/collection.dart';

import '../routes/route_weather.dart';
import 'fuel_scenario.dart';

abstract final class FuelWeather {
  /// Ohne Startzeit: 9 Uhr.
  static const defaultStartMinute = 9 * 60;

  /// Schwül ab 70 % bei mindestens 20 °C (darunter kühlt der Schweiß trotz Feuchte), trocken bis 40 %.
  static const humidFrom = 70;
  static const humidMinTemperature = 20.0;
  static const dryUpTo = 40;

  /// Mittel über die Stunden von Start bis Ende; `null`, wenn die Vorhersage diese Stunden nicht enthält.
  static ({double temperature, FuelHumidity humidity, int? relativeHumidity})? of(
    List<WeatherHour> hours, {
    required int startMinuteOfDay,
    required int minutes,
  }) {
    final from = startMinuteOfDay ~/ 60;
    final to = (startMinuteOfDay + minutes - 1) ~/ 60;
    final inside = [
      for (final hour in hours)
        if (hour.time.hour >= from && hour.time.hour <= to) hour,
    ];
    if (inside.isEmpty) return null;
    final temperature = (inside.map((hour) => hour.temperature).average).roundToDouble();
    final values = inside.map((hour) => hour.humidity).nonNulls.toList();
    final relative = values.isEmpty ? null : values.average.round();
    final humidity = switch (relative) {
      null => FuelHumidity.normal,
      final value when value >= humidFrom && temperature >= humidMinTemperature => FuelHumidity.humid,
      final value when value <= dryUpTo => FuelHumidity.dry,
      _ => FuelHumidity.normal,
    };
    return (temperature: temperature, humidity: humidity, relativeHumidity: relative);
  }

  /// Szenario mit dem Wetter der Vorhersage (unverändert, wenn die Stunden fehlen).
  static FuelScenario apply(FuelScenario scenario, List<WeatherHour> hours) {
    final weather = of(
      hours,
      startMinuteOfDay: scenario.startMinuteOfDay ?? defaultStartMinute,
      minutes: scenario.minutes,
    );
    if (weather == null) return scenario;
    return scenario.copyWith(temperatureCelsius: weather.temperature, humidity: weather.humidity);
  }
}
