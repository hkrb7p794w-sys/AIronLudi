import 'dart:math' as math;

import '../calendar/calendar_day.dart';

/// Parameter einer Anfrage.
final class GarminQueryItem {
  const GarminQueryItem(this.name, this.value);

  final String name;
  final String value;

  @override
  bool operator ==(Object other) => other is GarminQueryItem && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);

  @override
  String toString() => '$name=$value';
}

/// HTTP-Anfrage, unabhängig vom HTTP-Client.
final class GarminRequest {
  const GarminRequest({required this.method, required this.path, required this.query, required this.accept});

  final String method;
  final String path;
  final List<GarminQueryItem> query;
  final String accept;

  /// Vollständige URL relativ zur Basis-URL.
  Uri? url({String base = GarminEndpoint.baseURL}) {
    final uri = Uri.tryParse(base + path);
    if (uri == null) return null;
    if (query.isEmpty) return uri;
    // Wie `URLComponents.queryItems`: Reihenfolge bleibt, Werte werden prozentkodiert.
    final encoded = query
        .map((item) => '${Uri.encodeQueryComponent(item.name)}=${Uri.encodeQueryComponent(item.value)}')
        .join('&');
    return Uri.tryParse('${uri.toString()}?$encoded');
  }

  @override
  bool operator ==(Object other) =>
      other is GarminRequest &&
      other.method == method &&
      other.path == path &&
      other.accept == accept &&
      other.query.length == query.length &&
      Iterable<int>.generate(query.length).every((index) => other.query[index] == query[index]);

  @override
  int get hashCode => Object.hash(method, path, accept, Object.hashAll(query));

  @override
  String toString() => 'GarminRequest($method $path $query)';
}

/// Endpunkte der Garmin Connect Personal API.
///
/// Pfade und Parameter aus Garmins offiziellem Client
/// (github.com/garmin/connect-personal-api-python, `client.py`, `constants.py`, Stand 21.10.2026).
/// Bereichsgrenzen je Aufruf: was Garmins Server am 21.10.2026 akzeptierten
/// (github.com/Shape-Calendar/garmin-personal-mcp, README). Darüber antwortet Garmin mit 400/500.
sealed class GarminEndpoint {
  const GarminEndpoint();

  static const baseURL = 'https://personal.connectapi.garmin.com';
  static const tokenPath = '/personalapitoken-service/personal-api/personal-api-key/token';

  /// Garmins Suche liefert oberhalb von ca. 60 Einträgen je Seite HTTP 500.
  static const maxActivitiesPerPage = 50;

  static const tokenExchange = _Simple('tokenExchange');
  static const profileSettings = _Simple('profileSettings');
  static const heartRateZones = _Simple('heartRateZones');

  const factory GarminEndpoint.dailySummaries(DateRange range) = _Range.dailySummaries;
  const factory GarminEndpoint.sleepSummaries(DateRange range) = _Range.sleepSummaries;
  const factory GarminEndpoint.hrvSummaries(DateRange range) = _Range.hrvSummaries;
  const factory GarminEndpoint.bodyBattery(DateRange range) = _Range.bodyBattery;
  const factory GarminEndpoint.dailyStress(DateRange range) = _Range.dailyStress;
  const factory GarminEndpoint.weight(DateRange range) = _Range.weight;
  const factory GarminEndpoint.dailySleep(CalendarDay day) = _Day.dailySleep;
  const factory GarminEndpoint.hrv(CalendarDay day) = _Day.hrv;
  const factory GarminEndpoint.dailyHeartRate(CalendarDay day) = _Day.dailyHeartRate;
  const factory GarminEndpoint.spo2(CalendarDay day) = _Day.spo2;
  const factory GarminEndpoint.fitnessAge(CalendarDay day) = _Day.fitnessAge;
  const factory GarminEndpoint.activities({required int start, required int limit}) = _Activities;
  const factory GarminEndpoint.activity(int id) = _ActivityID.activity;
  const factory GarminEndpoint.activityFile(int id) = _ActivityID.activityFile;

  /// Größter erlaubter Datumsbereich je Aufruf (`null` = einzelner Tag oder kein Bereich).
  int? get maxDays => null;

  GarminRequest get request;
}

const _json = 'application/json';

GarminRequest _get(String path, [List<GarminQueryItem> query = const []]) =>
    GarminRequest(method: 'GET', path: path, query: query, accept: _json);

final class _Simple extends GarminEndpoint {
  const _Simple(this.name);

  final String name;

  @override
  GarminRequest get request => switch (name) {
    'tokenExchange' => const GarminRequest(method: 'POST', path: GarminEndpoint.tokenPath, query: [], accept: '*/*'),
    'profileSettings' => _get('/userprofile-service/userprofile/settings'),
    _ => _get('/biometric-service/heartRateZones/v2'),
  };

  @override
  bool operator ==(Object other) => other is _Simple && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

enum _RangeKind { dailySummaries, sleepSummaries, hrvSummaries, bodyBattery, dailyStress, weight }

final class _Range extends GarminEndpoint {
  const _Range.dailySummaries(this.range) : kind = _RangeKind.dailySummaries;
  const _Range.sleepSummaries(this.range) : kind = _RangeKind.sleepSummaries;
  const _Range.hrvSummaries(this.range) : kind = _RangeKind.hrvSummaries;
  const _Range.bodyBattery(this.range) : kind = _RangeKind.bodyBattery;
  const _Range.dailyStress(this.range) : kind = _RangeKind.dailyStress;
  const _Range.weight(this.range) : kind = _RangeKind.weight;

  final _RangeKind kind;
  final DateRange range;

  @override
  int? get maxDays => switch (kind) {
    _RangeKind.dailySummaries || _RangeKind.hrvSummaries => 180,
    _RangeKind.sleepSummaries || _RangeKind.bodyBattery => 28,
    _RangeKind.dailyStress => 7,
    _RangeKind.weight => 365,
  };

  @override
  GarminRequest get request {
    final (start, end) = (range.start.iso, range.end.iso);
    final dates = [GarminQueryItem('startDate', start), GarminQueryItem('endDate', end)];
    return switch (kind) {
      _RangeKind.dailySummaries => _get('/usersummary-service/v2/dailysummaries', dates),
      _RangeKind.sleepSummaries => _get('/sleep-service/sleep/dailySleepSummariesByDate', dates),
      _RangeKind.hrvSummaries => _get('/hrv-service/hrv/daily/$start/$end'),
      _RangeKind.bodyBattery => _get('/wellness-service/wellness/bodyBattery/reports/daily', dates),
      _RangeKind.dailyStress => _get('/usersummary-service/stats/stress/daily/$start/$end'),
      _RangeKind.weight => _get('/weight-service/weight/range/$start/$end', const [
        GarminQueryItem('includeAll', 'true'),
      ]),
    };
  }

  @override
  bool operator ==(Object other) => other is _Range && other.kind == kind && other.range == range;

  @override
  int get hashCode => Object.hash(kind, range);
}

enum _DayKind { dailySleep, hrv, dailyHeartRate, spo2, fitnessAge }

final class _Day extends GarminEndpoint {
  const _Day.dailySleep(this.day) : kind = _DayKind.dailySleep;
  const _Day.hrv(this.day) : kind = _DayKind.hrv;
  const _Day.dailyHeartRate(this.day) : kind = _DayKind.dailyHeartRate;
  const _Day.spo2(this.day) : kind = _DayKind.spo2;
  const _Day.fitnessAge(this.day) : kind = _DayKind.fitnessAge;

  final _DayKind kind;
  final CalendarDay day;

  @override
  GarminRequest get request => switch (kind) {
    _DayKind.dailySleep => _get('/sleep-service/sleep/dailySleep', [GarminQueryItem('date', day.iso)]),
    _DayKind.hrv => _get('/hrv-service/hrv/${day.iso}'),
    _DayKind.dailyHeartRate => _get('/wellness-service/wellness/dailyHeartRate', [GarminQueryItem('date', day.iso)]),
    _DayKind.spo2 => _get('/wellness-service/wellness/daily/spo2acclimation/${day.iso}'),
    _DayKind.fitnessAge => _get('/fitnessage-service/fitnessage/v2/${day.iso}'),
  };

  @override
  bool operator ==(Object other) => other is _Day && other.kind == kind && other.day == day;

  @override
  int get hashCode => Object.hash(kind, day);
}

final class _Activities extends GarminEndpoint {
  const _Activities({required this.start, required this.limit});

  final int start;
  final int limit;

  @override
  GarminRequest get request => _get('/activitylist-service/activities/search/activities', [
    GarminQueryItem('start', '$start'),
    GarminQueryItem('limit', '${math.min(limit, GarminEndpoint.maxActivitiesPerPage)}'),
  ]);

  @override
  bool operator ==(Object other) => other is _Activities && other.start == start && other.limit == limit;

  @override
  int get hashCode => Object.hash(start, limit);
}

final class _ActivityID extends GarminEndpoint {
  const _ActivityID.activity(this.id) : file = false;
  const _ActivityID.activityFile(this.id) : file = true;

  final int id;
  final bool file;

  @override
  GarminRequest get request => file
      ? GarminRequest(
          method: 'GET',
          path: '/download-service/files/activity/$id',
          query: const [],
          accept: 'application/zip, application/x-zip-compressed, application/octet-stream',
        )
      : _get('/activity-service/activity/$id');

  @override
  bool operator ==(Object other) => other is _ActivityID && other.id == id && other.file == file;

  @override
  int get hashCode => Object.hash(id, file);
}
