import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/settings/settings_store.dart';

/// Gestellter Wecker (gleiches JSON wie `WakeAlarmService.Stored` in Swift).
final class StoredWakeAlarm {
  const StoredWakeAlarm({required this.id, required this.time, required this.repeats});

  final String id;
  final WakeTime time;
  final WakeRepeat repeats;

  Map<String, Object?> toJson() => {'id': id, 'time': time.toJson(), 'repeats': repeats.rawValue};

  static StoredWakeAlarm? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, time, repeats) = (json['id'], WakeTime.fromJson(json['time']), WakeRepeat.fromRaw(json['repeats']));
    if (id is! String || time == null || repeats == null) return null;
    return StoredWakeAlarm(id: id, time: time, repeats: repeats);
  }

  @override
  bool operator ==(Object other) =>
      other is StoredWakeAlarm && other.id == id && other.time == time && other.repeats == repeats;

  @override
  int get hashCode => Object.hash(id, time, repeats);
}

enum WakeAlarmState { unsupported, notDetermined, denied, authorized }

/// Systemwecker der Plattform (iOS: AlarmKit ab iOS 26; Android: `AlarmManager.setAlarmClock`).
abstract interface class WakeAlarmBridge {
  Future<WakeAlarmState> state();

  /// Ids der noch gestellten Wecker der App.
  Future<List<String>> alarms();

  /// Fragt beim ersten Mal nach der Erlaubnis; `false`, wenn sie fehlt.
  Future<bool> schedule({required String id, required WakeTime time, required WakeRepeat repeats});

  Future<void> cancel(String id);
}

/// Brücke über einen `MethodChannel`. Ohne native Gegenseite (ältere Builds, Tests) gilt „nicht unterstützt“.
final class ChannelWakeAlarmBridge implements WakeAlarmBridge {
  const ChannelWakeAlarmBridge();

  static const _channel = MethodChannel('aironludi/alarm');

  @override
  Future<WakeAlarmState> state() async {
    try {
      final raw = await _channel.invokeMethod<String>('state');
      return WakeAlarmState.values.where((state) => state.name == raw).firstOrNull ?? WakeAlarmState.unsupported;
    } on MissingPluginException {
      return WakeAlarmState.unsupported;
    } on PlatformException {
      return WakeAlarmState.unsupported;
    }
  }

  @override
  Future<List<String>> alarms() async {
    try {
      return (await _channel.invokeListMethod<String>('alarms')) ?? const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<bool> schedule({required String id, required WakeTime time, required WakeRepeat repeats}) async =>
      await _channel.invokeMethod<bool>('schedule', {
        'id': id,
        'hour': time.hour,
        'minute': time.minute,
        'repeats': repeats.rawValue,
        // Kalender-Wochentage wie in Swift: 1 = Sonntag … 7 = Samstag.
        'weekdays': repeats.calendarWeekdays,
      }) ??
      false;

  @override
  Future<void> cancel(String id) async {
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on MissingPluginException {
      // Nichts gestellt.
    }
  }
}

/// Wecker zur Aufstehzeit: ein echter Systemwecker, der auch lautlos und im Fokus klingelt. Ohne Unterstützung oder
/// Erlaubnis gibt es nur den Hinweis auf die Uhr-App. Es gibt immer höchstens einen Wecker der App: ein neuer ersetzt
/// den alten (Port von `WakeAlarmService`).
final class WakeAlarmService extends ChangeNotifier {
  WakeAlarmService({required SettingsStore store, this._bridge = const ChannelWakeAlarmBridge()})
    : _store = store,
      stored = store.read(storedKey, StoredWakeAlarm.fromJson, null);

  static const storedKey = 'coach.wakeAlarm';

  final SettingsStore _store;
  final WakeAlarmBridge _bridge;
  StoredWakeAlarm? stored;
  WakeAlarmState state = WakeAlarmState.unsupported;
  String? lastError;

  bool get isSupported => state != WakeAlarmState.unsupported;

  Future<void> refreshState() async {
    state = await _bridge.state();
    // Vom System gelöschte oder abgelaufene einmalige Wecker nicht mehr als gestellt anzeigen.
    final current = stored;
    if (isSupported && current != null && !(await _bridge.alarms()).contains(current.id)) await _clear();
    notifyListeners();
  }

  Future<bool> schedule(WakeTime time, {required WakeRepeat repeats}) async {
    lastError = null;
    final id = newUuid();
    try {
      if (stored case final old?) await _bridge.cancel(old.id);
      final ok = await _bridge.schedule(id: id, time: time, repeats: repeats);
      state = await _bridge.state();
      if (!ok) {
        lastError = 'Wecker sind nicht erlaubt.';
        notifyListeners();
        return false;
      }
      stored = StoredWakeAlarm(id: id, time: time, repeats: repeats);
      await _store.setJson(storedKey, stored!.toJson());
      notifyListeners();
      return true;
    } on Object catch (error) {
      lastError = 'Wecker konnte nicht gestellt werden: $error';
      notifyListeners();
      return false;
    }
  }

  Future<void> cancel() async {
    if (stored case final current?) await _bridge.cancel(current.id);
    await _clear();
    notifyListeners();
  }

  Future<void> _clear() async {
    stored = null;
    await _store.remove(storedKey);
  }
}
