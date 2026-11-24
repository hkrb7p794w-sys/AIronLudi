// WHOOP: Verbinden über den Worker, Abruf mit Seiten, Übernahme in Herkunftsverzeichnis und Aktivitäten, Token-
// Erneuerung mit Rotation, Trennen.
import 'dart:convert';

import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/repositories/metrics_repository.dart';
import 'package:aironludi/data/repositories/source_store.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/ai/ai_client.dart';
import 'package:aironludi/services/http/http_transport.dart';
import 'package:aironludi/services/whoop/whoop_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

HttpResponse _json(Object value, {int status = 200}) => HttpResponse(status, utf8.encode(jsonEncode(value)));

Map<String, Object?> _sleep(String id, String start, String end) => {
  'id': id,
  'cycle_id': 1,
  'user_id': 7,
  'created_at': end,
  'updated_at': end,
  'start': start,
  'end': end,
  'timezone_offset': '+01:00',
  'nap': false,
  'score_state': 'SCORED',
  'score': {
    'stage_summary': {
      'total_in_bed_time_milli': 28800000,
      'total_awake_time_milli': 1800000,
      'total_no_data_time_milli': 0,
      'total_light_sleep_time_milli': 14400000,
      'total_slow_wave_sleep_time_milli': 5400000,
      'total_rem_sleep_time_milli': 5400000,
      'sleep_cycle_count': 4,
      'disturbance_count': 3,
    },
    'sleep_needed': {
      'baseline_milli': 27000000,
      'need_from_sleep_debt_milli': 0,
      'need_from_recent_strain_milli': 0,
      'need_from_recent_nap_milli': 0,
    },
    'sleep_performance_percentage': 93,
  },
};

void main() {
  late CoachDatabase db;
  late SettingsStore store;
  late Secrets secrets;
  late List<HttpRequest> worker;
  late List<HttpRequest> api;
  final now = DateTime.utc(2026, 11, 14, 8);

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
    secrets = Secrets.memory({SecretKey.aiAppToken: 'app'});
    await store.setString(AIClient.urlKey, 'https://coach.example.workers.dev');
    worker = [];
    api = [];
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  WhoopService service({
    required HttpResponse Function(HttpRequest request) workerRespond,
    required HttpResponse Function(HttpRequest request) apiRespond,
  }) {
    final ai = AIClient(
      secrets: secrets,
      settings: store,
      transport: FakeHttpTransport((request) {
        worker.add(request);
        return workerRespond(request);
      }),
    );
    return WhoopService(
      ai: ai,
      secrets: secrets,
      settings: store,
      activities: ActivityRepository(db),
      transport: FakeHttpTransport((request) {
        api.add(request);
        return apiRespond(request);
      }),
      clock: () => now,
    )..sources = SourceStore(db, store);
  }

  Future<void> connected({Duration expiresIn = const Duration(hours: 1)}) => secrets.set(
    SecretKey.whoopToken,
    jsonEncode(WhoopToken(accessToken: 'a1', refreshToken: 'r1', expiresAt: now.add(expiresIn)).toJson()),
  );

  test('Verbinden: state vom Worker, Rücksprung prüft ihn, Code getauscht, Profil gemerkt', () async {
    final whoop = service(
      workerRespond: (request) => request.url.path.endsWith('authorize')
          ? _json({'url': 'https://api.prod.whoop.com/oauth/oauth2/auth?state=abcdefgh12', 'state': 'abcdefgh12'})
          : _json({'access_token': 'a1', 'refresh_token': 'r1', 'expires_in': 3600}),
      apiRespond: (request) => request.url.path.endsWith('profile/basic')
          ? _json({'user_id': 7, 'email': 'x@example.com', 'first_name': 'Sam', 'last_name': 'L'})
          : _json({'height_meter': 1.8, 'weight_kilogram': 80, 'max_heart_rate': 190}),
    );
    final url = await whoop.beginConnect();
    expect(url.host, 'api.prod.whoop.com');
    await expectLater(whoop.complete(Uri.parse('coach://whoop?code=c1&state=falsch')), throwsA(isA<WhoopError>()));
    expect(whoop.isConnected, isFalse);
    await whoop.complete(Uri.parse('coach://whoop?code=c1&state=abcdefgh12'));
    expect(whoop.isConnected, isTrue);
    expect(jsonDecode(utf8.decode(worker.last.body!)), {'grant_type': 'authorization_code', 'code': 'c1'});
    expect(whoop.profile!.firstName, 'Sam');
    expect(whoop.body!.maxHeartRate, 190);
    expect(api.first.headers['Authorization'], 'Bearer a1');
    // Abgelehnte Freigabe.
    await expectLater(
      whoop.complete(Uri.parse('coach://whoop?error=access_denied')),
      throwsA(predicate((error) => '$error'.contains('abgelehnt'))),
    );
    // Fehlender Scope in der Developer-App (z. B. „offline“): verständlich, mit Weg zur Betreiberin bzw. zum Betreiber.
    await expectLater(
      whoop.complete(Uri.parse('coach://whoop?error=invalid_scope')),
      throwsA(predicate((error) => '$error'.contains('„offline“') && '$error'.contains('KI-Worker betreibt'))),
    );
  });

  test('Abruf: Seiten bis next_token leer, Tageswerte im Herkunftsverzeichnis, Training als Aktivität', () async {
    await connected();
    final whoop = service(
      workerRespond: (_) => _json({}),
      apiRespond: (request) {
        final path = request.url.path;
        final next = request.url.queryParameters['nextToken'];
        if (path.endsWith('/v2/recovery')) {
          return next == null
              ? _json({
                  'records': [
                    {
                      'cycle_id': 1,
                      'sleep_id': 's1',
                      'user_id': 7,
                      'created_at': '2026-11-14T06:00:00Z',
                      'updated_at': '2026-11-14T06:00:00Z',
                      'score_state': 'SCORED',
                      'score': {
                        'user_calibrating': false,
                        'recovery_score': 81,
                        'resting_heart_rate': 48,
                        'hrv_rmssd_milli': 72.5,
                      },
                    },
                  ],
                  'next_token': 'seite2',
                })
              : _json({'records': <Object>[], 'next_token': null});
        }
        if (path.endsWith('/v2/activity/sleep')) {
          return _json({
            'records': [_sleep('s1', '2026-11-13T22:00:00Z', '2026-11-14T06:00:00Z')],
          });
        }
        if (path.endsWith('/v2/cycle')) return _json({'records': <Object>[]});
        if (path.endsWith('/v2/activity/workout')) {
          return _json({
            'records': [
              {
                'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
                'user_id': 7,
                'created_at': '2026-11-13T17:00:00Z',
                'updated_at': '2026-11-13T17:00:00Z',
                'start': '2026-11-13T16:00:00Z',
                'end': '2026-11-13T17:00:00Z',
                'timezone_offset': '+01:00',
                'sport_name': 'weightlifting',
                'score_state': 'SCORED',
                'score': {
                  'strain': 9.1,
                  'average_heart_rate': 110,
                  'max_heart_rate': 150,
                  'kilojoule': 1200,
                  'percent_recorded': 100,
                  'zone_durations': {
                    'zone_zero_milli': 0,
                    'zone_one_milli': 1200000,
                    'zone_two_milli': 1200000,
                    'zone_three_milli': 1200000,
                    'zone_four_milli': 0,
                    'zone_five_milli': 0,
                  },
                },
              },
            ],
          });
        }
        return _json({}, status: 404);
      },
    );
    final result = await whoop.sync();
    expect(result, contains('1 neue Trainings'));
    final recoveryCalls = api.where((request) => request.url.path.endsWith('/v2/recovery')).toList();
    expect(recoveryCalls.map((request) => request.url.queryParameters['nextToken']), [null, 'seite2']);
    expect(recoveryCalls.first.url.queryParameters['limit'], '25');
    // Erster Abruf: 90 Tage zurück.
    expect(recoveryCalls.first.url.queryParameters['start'], startsWith('2026-08-16'));

    final day = (await MetricsRepository(db).day(const CalendarDay(2026, 11, 14)))!;
    expect(day.hrvLastNightAverage, 72.5);
    expect(day.restingHeartRate, 48);
    expect(day.trainingReadiness, 81);
    expect(day.sleepSeconds, 25200);
    expect(day.sleepScore, 93);
    final sources = await SourceStore(db, store).sources(const CalendarDay(2026, 11, 14));
    expect(sources[DataKind.hrv], DataProvider.whoop);

    final activity = (await ActivityRepository(db).all()).single;
    expect(activity.provider, DataProvider.whoop);
    expect(activity.sport, ActivitySport.strength);
    expect(activity.trainingEffectLabel, 'WHOOP-Strain 9,1');
    expect(whoop.lastSync!.isAtSameMomentAs(now), isTrue);

    // Zweiter Abruf: ab dem letzten mit zwei Tagen Überlappung, nichts doppelt.
    api.clear();
    await whoop.sync();
    expect(api.first.url.queryParameters['start'], startsWith('2026-11-12'));
    expect(await ActivityRepository(db).all(), hasLength(1));
  });

  test('abgelaufenes Token: genau ein Refresh über den Worker, neues Refresh-Token gespeichert', () async {
    await connected(expiresIn: Duration.zero);
    final whoop = service(
      workerRespond: (_) => _json({'access_token': 'a2', 'refresh_token': 'r2', 'expires_in': 3600}),
      apiRespond: (_) => _json({'records': <Object>[]}),
    );
    await whoop.sync();
    final refreshes = worker.where((request) => request.url.path.endsWith('/v1/whoop/token')).toList();
    expect(refreshes, hasLength(1));
    expect(jsonDecode(utf8.decode(refreshes.single.body!)), {'grant_type': 'refresh_token', 'refresh_token': 'r1'});
    final stored = WhoopToken.fromJson(jsonDecode(secrets.string(SecretKey.whoopToken)!))!;
    expect((stored.accessToken, stored.refreshToken), ('a2', 'r2'));
    expect(api.every((request) => request.headers['Authorization'] == 'Bearer a2'), isTrue);
  });

  test('401 von WHOOP: erneuern und wiederholen; verbrauchtes Refresh-Token heißt neu verbinden', () async {
    await connected();
    var first = true;
    final whoop = service(
      workerRespond: (_) => _json({'access_token': 'a2', 'refresh_token': 'r2', 'expires_in': 3600}),
      apiRespond: (request) {
        if (first) {
          first = false;
          return _json({}, status: 401);
        }
        return _json({'records': <Object>[]});
      },
    );
    await whoop.sync();
    expect(api.first.headers['Authorization'], 'Bearer a1');
    expect(api[1].headers['Authorization'], 'Bearer a2');

    await connected(expiresIn: Duration.zero);
    final rejected = service(
      workerRespond: (_) => _json({'error': 'abgelehnt', 'code': 'whoop_invalid_grant'}, status: 400),
      apiRespond: (_) => _json({'records': <Object>[]}),
    );
    await expectLater(rejected.sync(), throwsA(isA<WhoopError>().having((e) => e.reconnect, 'reconnect', isTrue)));
    expect(rejected.isConnected, isFalse);
  });

  test('Trennen widerruft bei WHOOP und löscht den Zugang', () async {
    await connected();
    await store.setJson(SettingsKeys.whoopProfile, {'user_id': 7, 'first_name': 'Sam'});
    final whoop = service(workerRespond: (_) => _json({}), apiRespond: (_) => HttpResponse(204, const []));
    await whoop.disconnect();
    expect(api.single.method, 'DELETE');
    expect(api.single.url.path, '/developer/v2/user/access');
    expect(whoop.isConnected, isFalse);
    expect(whoop.profile, isNull);
  });

  test('ohne Worker kein Verbinden', () async {
    await store.setString(AIClient.urlKey, null);
    final whoop = service(workerRespond: (_) => _json({}), apiRespond: (_) => _json({}));
    await expectLater(whoop.beginConnect(), throwsA(predicate((error) => '$error'.contains('KI-Worker'))));
  });
}
