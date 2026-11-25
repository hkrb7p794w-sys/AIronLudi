// Nachgebaute WHOOP-API für Durchläufe: Profil, Körperdaten, Erholung und Schlaf der letzten Nacht, ein Lauf von heute.
// Formate wie im Diensttest `test/services/whoop_service_test.dart`.
import 'dart:convert';

import 'package:aironludi/services/http/http_transport.dart';

final class FakeWhoop {
  final requests = <String>[];

  late final transport = FakeHttpTransport(_handle);

  HttpResponse _json(Object body) => HttpResponse(200, utf8.encode(jsonEncode(body)));

  HttpResponse _handle(HttpRequest request) {
    final path = request.url.path;
    requests.add('${request.method} $path');
    final now = DateTime.now().toUtc();
    String iso(DateTime time) => time.toIso8601String();
    final wake = DateTime.now().copyWith(hour: 6, minute: 30, second: 0, millisecond: 0, microsecond: 0).toUtc();
    final bed = wake.subtract(const Duration(hours: 8));
    if (path.endsWith('/v2/user/profile/basic')) {
      return _json({'user_id': 7, 'email': 'lena@example.com', 'first_name': 'Lena', 'last_name': 'T'});
    }
    if (path.endsWith('/v2/user/measurement/body')) {
      return _json({'height_meter': 1.7, 'weight_kilogram': 62, 'max_heart_rate': 188});
    }
    if (path.endsWith('/v2/recovery')) {
      return _json({
        'records': [
          {
            'cycle_id': 1,
            'sleep_id': 's1',
            'user_id': 7,
            'created_at': iso(wake),
            'updated_at': iso(wake),
            'score_state': 'SCORED',
            'score': {
              'user_calibrating': false,
              'recovery_score': 23,
              'resting_heart_rate': 51,
              'hrv_rmssd_milli': 38.0,
            },
          },
        ],
        'next_token': null,
      });
    }
    if (path.endsWith('/v2/activity/sleep')) {
      return _json({
        'records': [
          {
            'id': 's1',
            'cycle_id': 1,
            'user_id': 7,
            'created_at': iso(wake),
            'updated_at': iso(wake),
            'start': iso(bed),
            'end': iso(wake),
            'timezone_offset': '+01:00',
            'nap': false,
            'score_state': 'SCORED',
            'score': {
              'stage_summary': {
                'total_in_bed_time_milli': 28800000,
                'total_awake_time_milli': 1800000,
                'total_light_sleep_time_milli': 12600000,
                'total_slow_wave_sleep_time_milli': 7200000,
                'total_rem_sleep_time_milli': 7200000,
              },
              'sleep_performance_percentage': 88,
            },
          },
        ],
      });
    }
    if (path.endsWith('/v2/activity/workout')) {
      final start = now.subtract(const Duration(hours: 2));
      return _json({
        'records': [
          {
            'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
            'user_id': 7,
            'created_at': iso(start),
            'updated_at': iso(start),
            'start': iso(start),
            'end': iso(start.add(const Duration(minutes: 45))),
            'timezone_offset': '+01:00',
            'sport_name': 'running',
            'score_state': 'SCORED',
            'score': {'strain': 9.1, 'average_heart_rate': 145, 'max_heart_rate': 172, 'kilojoule': 2100},
          },
        ],
      });
    }
    return _json({'records': <Object>[]});
  }
}
