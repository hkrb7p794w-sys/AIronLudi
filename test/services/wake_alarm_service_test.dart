// Wecker zur Aufstehzeit: höchstens ein Wecker, Ersatz beim neuen, Aufräumen bei vom System gelöschten.
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/services/alarm/wake_alarm_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeBridge implements WakeAlarmBridge {
  WakeAlarmState current = WakeAlarmState.authorized;
  final active = <String>{};
  bool allow = true;

  @override
  Future<WakeAlarmState> state() async => current;

  @override
  Future<List<String>> alarms() async => active.toList();

  @override
  Future<bool> schedule({required String id, required WakeTime time, required WakeRepeat repeats}) async {
    if (!allow) {
      current = WakeAlarmState.denied;
      return false;
    }
    active.add(id);
    return true;
  }

  @override
  Future<void> cancel(String id) async => active.remove(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CoachDatabase db;
  late SettingsStore store;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
  });
  tearDown(() => db.close());

  test('neuer Wecker ersetzt den alten und bleibt gespeichert', () async {
    final bridge = _FakeBridge();
    final service = WakeAlarmService(store: store, bridge: bridge);
    await service.refreshState();
    expect(service.isSupported, isTrue);
    expect(await service.schedule(WakeTime(hour: 6, minute: 30), repeats: WakeRepeat.weekdays), isTrue);
    final first = service.stored!.id;
    expect(await service.schedule(WakeTime(hour: 7, minute: 0), repeats: WakeRepeat.once), isTrue);
    expect(bridge.active, {service.stored!.id});
    expect(bridge.active.contains(first), isFalse);
    expect(WakeAlarmService(store: store, bridge: bridge).stored?.time, WakeTime(hour: 7, minute: 0));
  });

  test('vom System gelöschter Wecker gilt nicht mehr als gestellt', () async {
    final bridge = _FakeBridge();
    final service = WakeAlarmService(store: store, bridge: bridge);
    await service.schedule(WakeTime(hour: 6, minute: 0), repeats: WakeRepeat.once);
    bridge.active.clear();
    await service.refreshState();
    expect(service.stored, isNull);
    expect(store.contains(WakeAlarmService.storedKey), isFalse);
  });

  test('ohne Erlaubnis kein Wecker, mit Hinweis', () async {
    final bridge = _FakeBridge()..allow = false;
    final service = WakeAlarmService(store: store, bridge: bridge);
    expect(await service.schedule(WakeTime(hour: 6, minute: 0), repeats: WakeRepeat.once), isFalse);
    expect(service.stored, isNull);
    expect(service.state, WakeAlarmState.denied);
    expect(service.lastError, isNotNull);
  });

  test('ohne native Brücke: nicht unterstützt', () async {
    final service = WakeAlarmService(store: store);
    await service.refreshState();
    expect(service.isSupported, isFalse);
  });

  test('JSON wie in Swift', () {
    final stored = StoredWakeAlarm(id: 'A', time: WakeTime(hour: 6, minute: 45), repeats: WakeRepeat.daily);
    expect(stored.toJson(), {
      'id': 'A',
      'time': {'hour': 6, 'minute': 45},
      'repeats': 'daily',
    });
    expect(StoredWakeAlarm.fromJson(stored.toJson()), stored);
  });
}
