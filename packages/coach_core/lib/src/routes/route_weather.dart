import 'dart:math' as math;

import '../calendar/calendar_day.dart';
import 'geo.dart';
import 'planned_route.dart';

/// Wetter einer Stunde (Open-Meteo, Ortszeit am Start).
final class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.temperature,
    required this.windSpeed,
    required this.windFrom,
    this.windGusts,
    this.precipitationProbability,
    this.precipitation,
    this.weatherCode,
  });

  /// Ortszeit als „Wanduhrzeit“ (ohne Zeitzone).
  final DateTime time;
  final double temperature;

  /// km/h; Richtung, aus der der Wind kommt (Grad, 0 = Nord).
  final double windSpeed;
  final double windFrom;
  final double? windGusts;
  final int? precipitationProbability;

  /// mm in der Stunde.
  final double? precipitation;

  /// WMO-Wettercode.
  final int? weatherCode;
}

/// Vorhersage von Open-Meteo (frei, ohne Schlüssel): stündlich für einen Tag am Startpunkt.
abstract final class OpenMeteoFormat {
  /// So weit reicht die Vorhersage (Tage ab heute).
  static const maxDaysAhead = 15;

  static bool covers(CalendarDay day, {required CalendarDay today}) =>
      day >= today && today.daysUntil(day) <= maxDaysAhead;

  static Uri uri(GeoPoint point, CalendarDay day) => Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': point.latitude.toStringAsFixed(3),
    'longitude': point.longitude.toStringAsFixed(3),
    'hourly':
        'temperature_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_direction_10m,'
        'wind_gusts_10m',
    'wind_speed_unit': 'kmh',
    'timezone': 'auto',
    'start_date': day.iso,
    'end_date': day.iso,
  });

  /// Stunden aus der Antwort; unvollständige Stunden fallen weg. Wirft [FormatException] ohne `hourly`.
  static List<WeatherHour> parse(Object? json) {
    if (json case {'hourly': final Map<String, Object?> hourly}) {
      List<Object?> series(String key) => hourly[key] is List ? hourly[key]! as List<Object?> : const [];
      final times = series('time');
      final temperature = series('temperature_2m');
      final speed = series('wind_speed_10m');
      final direction = series('wind_direction_10m');
      final gusts = series('wind_gusts_10m');
      final probability = series('precipitation_probability');
      final precipitation = series('precipitation');
      final code = series('weather_code');
      double? at(List<Object?> values, int index) =>
          index < values.length && values[index] is num ? (values[index]! as num).toDouble() : null;
      return [
        for (var index = 0; index < times.length; index++)
          if ((times[index], at(temperature, index), at(speed, index), at(direction, index)) case (
            final String time,
            final double temp,
            final double wind,
            final double from,
          ))
            if (DateTime.tryParse(time) case final parsed?)
              WeatherHour(
                time: parsed,
                temperature: temp,
                windSpeed: wind,
                windFrom: from,
                windGusts: at(gusts, index),
                precipitationProbability: at(probability, index)?.round(),
                precipitation: at(precipitation, index),
                weatherCode: at(code, index)?.round(),
              ),
      ];
    }
    throw const FormatException('Keine Stundenwerte');
  }

  /// Kurzer Text zum WMO-Code.
  static String describe(int? code) => switch (code) {
    null => '',
    0 => 'klar',
    1 || 2 => 'leicht bewölkt',
    3 => 'bewölkt',
    45 || 48 => 'Nebel',
    51 || 53 || 55 || 56 || 57 => 'Niesel',
    61 || 63 || 80 || 81 => 'Regen',
    65 || 82 || 66 || 67 => 'starker Regen',
    71 || 73 || 75 || 77 || 85 || 86 => 'Schnee',
    95 || 96 || 99 => 'Gewitter',
    _ => '',
  };
}

/// Wind entlang der Route: Gegenwind-Anteil je Hälfte (positiv = Gegenwind, km/h, nach Streckenlänge gewichtet).
abstract final class RouteWind {
  static ({double firstHalf, double secondHalf}) halves(
    List<GeoPoint> points, {
    required double windFrom,
    required double windSpeed,
  }) {
    final thinned = Geo.thin(points, 400);
    final total = Geo.length(thinned);
    if (thinned.length < 2 || total <= 0) return (firstHalf: 0, secondHalf: 0);
    var walked = 0.0;
    var first = 0.0, second = 0.0, firstLength = 0.0, secondLength = 0.0;
    for (var index = 1; index < thinned.length; index++) {
      final a = thinned[index - 1];
      final b = thinned[index];
      final length = Geo.distance(a, b);
      if (length <= 0) continue;
      // Fährt man dorthin, woher der Wind kommt, ist es Gegenwind.
      final angle = (Geo.bearing(a, b) - windFrom) * math.pi / 180;
      final headwind = windSpeed * math.cos(angle) * length;
      if (walked + length / 2 <= total / 2) {
        first += headwind;
        firstLength += length;
      } else {
        second += headwind;
        secondLength += length;
      }
      walked += length;
    }
    return (
      firstHalf: firstLength == 0 ? 0 : first / firstLength,
      secondHalf: secondLength == 0 ? 0 : second / secondLength,
    );
  }

  /// Ab diesem Unterschied der Hälften lohnt der Hinweis „andersherum“ (km/h Gegenwind).
  static const reverseThreshold = 6.0;

  /// Rundweg mit Rückenwind zuerst und Gegenwind zum Schluss: andersherum wäre es angenehmer.
  static bool suggestsReverse(({double firstHalf, double secondHalf}) halves) =>
      halves.secondHalf - halves.firstHalf >= reverseThreshold && halves.secondHalf > 3;
}

/// Wetter für eine Route zu einer Startzeit: Spanne über die geschätzte Dauer, Wind-Hinweis je Hälfte.
final class RouteWeather {
  const RouteWeather({
    required this.hours,
    required this.minTemperature,
    required this.maxTemperature,
    required this.maxPrecipitationProbability,
    required this.precipitationSum,
    required this.windSpeed,
    required this.windFrom,
    required this.maxGusts,
    required this.wind,
    required this.weatherCode,
  });

  final List<WeatherHour> hours;
  final double minTemperature;
  final double maxTemperature;
  final int maxPrecipitationProbability;
  final double precipitationSum;
  final double windSpeed;
  final double windFrom;
  final double? maxGusts;
  final ({double firstHalf, double secondHalf}) wind;
  final int? weatherCode;

  bool get suggestsReverse => RouteWind.suggestsReverse(wind);

  /// Stunden ab [startHour] über [duration] (mindestens eine). `null`, wenn die Vorhersage sie nicht enthält.
  static RouteWeather? of(
    PlannedRoute route,
    List<WeatherHour> forecast, {
    required int startHour,
    required Duration duration,
  }) {
    final endHour = startHour + math.max(1, (duration.inMinutes / 60).ceil());
    final hours = [
      for (final hour in forecast)
        if (hour.time.hour >= startHour && hour.time.hour < endHour) hour,
    ];
    if (hours.isEmpty) return null;
    final speed = hours.map((hour) => hour.windSpeed).reduce((a, b) => a + b) / hours.length;
    // Mittlere Windrichtung als Vektor (350° und 10° ergeben 0°, nicht 180°).
    var x = 0.0, y = 0.0;
    for (final hour in hours) {
      x += math.sin(hour.windFrom * math.pi / 180) * hour.windSpeed;
      y += math.cos(hour.windFrom * math.pi / 180) * hour.windSpeed;
    }
    final from = (math.atan2(x, y) * 180 / math.pi + 360) % 360;
    final gusts = [for (final hour in hours) ?hour.windGusts];
    final codes = [for (final hour in hours) ?hour.weatherCode];
    return RouteWeather(
      hours: hours,
      minTemperature: hours.map((hour) => hour.temperature).reduce(math.min),
      maxTemperature: hours.map((hour) => hour.temperature).reduce(math.max),
      maxPrecipitationProbability: hours.map((hour) => hour.precipitationProbability ?? 0).reduce(math.max),
      precipitationSum: hours.fold(0, (sum, hour) => sum + (hour.precipitation ?? 0)),
      windSpeed: speed,
      windFrom: from,
      maxGusts: gusts.isEmpty ? null : gusts.reduce(math.max),
      wind: RouteWind.halves(route.points, windFrom: from, windSpeed: speed),
      // Der „schlechteste“ Code der Spanne (höhere WMO-Codes = mehr Niederschlag).
      weatherCode: codes.isEmpty ? null : codes.reduce(math.max),
    );
  }

  /// Himmelsrichtung, aus der der Wind kommt.
  static String compass(double degrees) =>
      const ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'][((degrees % 360) / 45).round() % 8];

  /// „12–15 °C · bewölkt · Regen 40 %“.
  String get headline {
    final temperature = minTemperature.round() == maxTemperature.round()
        ? '${maxTemperature.round()} °C'
        : '${minTemperature.round()}–${maxTemperature.round()} °C';
    return [
      temperature,
      if (OpenMeteoFormat.describe(weatherCode) case final text when text.isNotEmpty) text,
      if (maxPrecipitationProbability >= 20) 'Regen $maxPrecipitationProbability %',
    ].join(' · ');
  }

  /// „Wind 18 km/h aus SW, Böen 35“.
  String get windLine {
    final gusts = maxGusts;
    return 'Wind ${windSpeed.round()} km/h aus ${compass(windFrom)}'
        '${gusts != null && gusts >= windSpeed + 10 ? ', Böen ${gusts.round()}' : ''}';
  }

  /// Hinweis zum Wind auf der Strecke (ab 10 km/h), sonst `null`.
  String? get windAdvice {
    if (windSpeed < 10) return null;
    String part(double headwind) => headwind >= 3
        ? 'Gegenwind'
        : headwind <= -3
        ? 'Rückenwind'
        : 'Seitenwind';
    final first = part(wind.firstHalf);
    final second = part(wind.secondHalf);
    if (suggestsReverse) {
      return 'Erst $first, zum Schluss $second – andersherum hättest du den Gegenwind, solange du frisch bist.';
    }
    return first == second ? 'Überwiegend $first.' : 'Erste Hälfte $first, zweite Hälfte $second.';
  }
}
