import 'dart:convert';

import 'package:coach_core/coach_core.dart';

import '../http/http_transport.dart';
import 'routing_service.dart';

/// Stündliche Vorhersage für Start und Tag (Open-Meteo, frei, ohne Schlüssel); in Tests überschreibbar.
abstract interface class WeatherSource {
  /// Wirft bei Netz- oder Formatfehlern.
  Future<List<WeatherHour>> forecast(GeoPoint point, CalendarDay day);
}

final class OpenMeteoWeather implements WeatherSource {
  OpenMeteoWeather(this._transport, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final HttpTransport _transport;
  final DateTime Function() _now;

  /// Gleiche Anfrage innerhalb einer halben Stunde: aus dem Speicher.
  final _cache = <Uri, (DateTime, List<WeatherHour>)>{};

  @override
  Future<List<WeatherHour>> forecast(GeoPoint point, CalendarDay day) async {
    final uri = OpenMeteoFormat.uri(point, day);
    if (_cache[uri] case (final at, final hours) when _now().difference(at) < const Duration(minutes: 30)) {
      return hours;
    }
    final response = await sendWithRetry(
      _transport,
      HttpRequest(
        method: 'GET',
        url: uri,
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(seconds: 12),
      ),
    );
    if (!response.isSuccess) throw HttpTransportException('Open-Meteo antwortet ${response.status}');
    final hours = OpenMeteoFormat.parse(jsonDecode(utf8.decode(response.body)));
    _cache[uri] = (_now(), hours);
    return hours;
  }
}
