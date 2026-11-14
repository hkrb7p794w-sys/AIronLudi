import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Erlaubnis für Mitteilungen.
enum NotificationPermission { unknown, allowed, denied }

/// Eine aktionsfähige Kategorie (wie `UNNotificationCategory`).
abstract final class NotificationCategories {
  static const adjustable = 'coach.training.adjustable';
  static const plain = 'coach.training';
  static const planning = 'coach.weekPlanning';
  static const doneAction = 'coach.done';
  static const moveAction = 'coach.move';
  static const skipAction = 'coach.skip';
}

/// Geplante lokale Mitteilung zu einer Uhrzeit des Geräts (wie ein `UNCalendarNotificationTrigger`).
final class LocalNotification {
  const LocalNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.day,
    required this.hour,
    required this.minute,
    this.second = 0,
    this.category,
    this.info = const {},
    this.exact = false,
    this.silent = false,
    this.soundFile,
    this.repeatsDaily = false,
  });

  final String id;
  final String title;
  final String body;
  final CalendarDay day;
  final int hour;
  final int minute;
  final int second;
  final String? category;
  final Map<String, String> info;

  /// Sekundengenau (Pause vorbei); sonst darf das System bündeln.
  final bool exact;

  /// Ohne Ton.
  final bool silent;

  /// Eigener Ton (Dateiname, iOS aus `Library/Sounds`); `null` = Standardton.
  final String? soundFile;

  /// Jeden Tag zur selben Uhrzeit (wie `UNCalendarNotificationTrigger` mit Stunde und Minute, `repeats: true`).
  final bool repeatsDaily;
}

/// Antwort auf eine Mitteilung (Antippen oder Aktion).
final class NotificationAnswer {
  const NotificationAnswer({required this.action, required this.info});

  /// Kennung der Aktion; Antippen ohne Aktion: leer.
  final String action;
  final Map<String, String> info;
}

/// Mitteilungszentrale des Geräts; in Tests durch [FakeNotificationCenter] ersetzt.
abstract interface class NotificationCenterBridge {
  /// Aktueller Stand; `requestIfNeeded`: beim ersten Mal nach der Erlaubnis fragen.
  Future<NotificationPermission> permission({required bool requestIfNeeded});

  Future<List<String>> pendingIdentifiers();

  Future<void> removePending(List<String> identifiers);

  Future<void> removeDelivered(List<String> identifiers);

  Future<void> add(LocalNotification notification);
}

/// Umsetzung mit `flutter_local_notifications`. Die Kennungen der Swift-App (Text) stehen in der Nutzlast; das Plugin
/// braucht Zahlen, dafür dient ein stabiler 31-Bit-Hash der Kennung.
final class DeviceNotificationCenter implements NotificationCenterBridge {
  DeviceNotificationCenter._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channel = AndroidNotificationDetails(
    'coach.reminders',
    'Erinnerungen',
    channelDescription: 'Training, Mahlzeiten, Wochenplanung und Morning Report',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Richtet das Plugin samt Zeitzone und Aktionen ein; [onAnswer] bekommt Antippen und Aktionen.
  static Future<DeviceNotificationCenter> create({required void Function(NotificationAnswer answer) onAnswer}) async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      // Unbekannte Zone: UTC bleibt (Erinnerungen dann evtl. verschoben, aber vorhanden).
    }
    final plugin = FlutterLocalNotificationsPlugin();
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          NotificationCategories.adjustable,
          actions: [
            DarwinNotificationAction.plain(NotificationCategories.doneAction, 'Erledigt'),
            DarwinNotificationAction.plain(
              NotificationCategories.moveAction,
              'Verschieben …',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              NotificationCategories.skipAction,
              'Diese Woche auslassen',
              options: {DarwinNotificationActionOption.destructive},
            ),
          ],
        ),
        DarwinNotificationCategory(
          NotificationCategories.plain,
          actions: [DarwinNotificationAction.plain(NotificationCategories.doneAction, 'Erledigt')],
        ),
        const DarwinNotificationCategory(NotificationCategories.planning),
      ],
    );
    void handle(NotificationResponse response) =>
        onAnswer(NotificationAnswer(action: response.actionId ?? '', info: _info(response.payload)));
    await plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
      ),
      onDidReceiveNotificationResponse: handle,
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      if (launch!.notificationResponse case final response?) handle(response);
    }
    return DeviceNotificationCenter._(plugin);
  }

  static Map<String, String> _info(String? payload) {
    if (payload == null) return const {};
    try {
      final json = jsonDecode(payload);
      return json is Map ? {for (final MapEntry(:key, :value) in json.entries) '$key': '$value'} : const {};
    } on FormatException {
      return const {};
    }
  }

  /// Stabile Zahl zur Kennung (FNV-1a, 31 Bit).
  static int numericID(String identifier) => (fnv1a64Text(identifier) & BigInt.from(0x7fffffff)).toInt();

  @override
  Future<NotificationPermission> permission({required bool requestIfNeeded}) async {
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    var enabled = (await ios?.checkPermissions())?.isEnabled ?? await android?.areNotificationsEnabled() ?? false;
    if (enabled) return NotificationPermission.allowed;
    if (!requestIfNeeded) return NotificationPermission.unknown;
    enabled =
        await ios?.requestPermissions(alert: true, sound: true, badge: true) ??
        await android?.requestNotificationsPermission() ??
        false;
    return enabled ? NotificationPermission.allowed : NotificationPermission.denied;
  }

  @override
  Future<List<String>> pendingIdentifiers() async => [
    for (final request in await _plugin.pendingNotificationRequests()) _info(request.payload)['id'] ?? '${request.id}',
  ];

  @override
  Future<void> removePending(List<String> identifiers) async {
    for (final identifier in identifiers) {
      await _plugin.cancel(id: numericID(identifier));
    }
  }

  @override
  Future<void> removeDelivered(List<String> identifiers) => removePending(identifiers);

  @override
  Future<void> add(LocalNotification notification) async {
    final day = notification.day;
    var date = tz.TZDateTime(
      tz.local,
      day.year,
      day.month,
      day.day,
      notification.hour,
      notification.minute,
      notification.second,
    );
    final now = tz.TZDateTime.now(tz.local);
    if (date.isBefore(now)) {
      // Tägliche Wiederholung: nächstes Vorkommen dieser Uhrzeit (das Plugin verlangt einen Zeitpunkt in der Zukunft).
      if (!notification.repeatsDaily) return;
      date = date.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: numericID(notification.id),
      scheduledDate: date,
      title: notification.title,
      body: notification.body,
      payload: jsonEncode({'id': notification.id, ...notification.info}),
      notificationDetails: NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(
          categoryIdentifier: notification.category,
          presentSound: !notification.silent,
          sound: notification.silent ? null : notification.soundFile,
        ),
      ),
      matchDateTimeComponents: notification.repeatsDaily ? DateTimeComponents.time : null,
      androidScheduleMode: notification.exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

/// Mitteilungszentrale im Arbeitsspeicher (Tests).
final class FakeNotificationCenter implements NotificationCenterBridge {
  FakeNotificationCenter({this.granted = true});

  bool granted;
  bool asked = false;
  final Map<String, LocalNotification> pending = {};
  final List<String> removedDelivered = [];

  @override
  Future<NotificationPermission> permission({required bool requestIfNeeded}) async {
    if (granted) return NotificationPermission.allowed;
    if (!requestIfNeeded) return NotificationPermission.unknown;
    asked = true;
    return NotificationPermission.denied;
  }

  @override
  Future<List<String>> pendingIdentifiers() async => pending.keys.toList();

  @override
  Future<void> removePending(List<String> identifiers) async => identifiers.forEach(pending.remove);

  @override
  Future<void> removeDelivered(List<String> identifiers) async => removedDelivered.addAll(identifiers);

  @override
  Future<void> add(LocalNotification notification) async => pending[notification.id] = notification;
}
