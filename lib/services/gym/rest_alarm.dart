import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../platform/notifications.dart';

/// Mitteilung „Pause vorbei“, falls die App im Hintergrund ist (Port von `RestAlarm`).
abstract interface class RestAlarm {
  /// [end] `null` entfernt eine geplante Mitteilung. [body] nennt die nächste Übung.
  Future<void> schedule(DateTime? end, {String? body, RestSound sound});
}

/// Pausenton bei geöffneter App (Port von `RestSoundPlayer`).
abstract interface class RestSoundPlaying {
  Future<void> play(RestSound sound);
}

final class NotificationRestAlarm implements RestAlarm {
  NotificationRestAlarm(this._center, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const identifier = 'coach.rest';

  /// Die Einheit ist auf dem Bildschirm und gibt das Signal selbst.
  static bool workoutIsOpen = false;

  static bool isHandledByOpenWorkout(String id) => id == identifier && workoutIsOpen;

  final NotificationCenterBridge? _center;
  final DateTime Function() _clock;

  @override
  Future<void> schedule(DateTime? end, {String? body, RestSound sound = RestSound.system}) async {
    final center = _center;
    if (center == null) return;
    await center.removePending(const [identifier]);
    if (end == null || end.difference(_clock()).inMilliseconds <= 1000) return;
    final local = end.toLocal();
    await center.add(
      LocalNotification(
        id: identifier,
        title: 'Pause vorbei',
        body: body == null ? 'Weiter mit dem nächsten Satz.' : '$body.',
        day: CalendarDay.fromDate(local),
        hour: local.hour,
        minute: local.minute,
        second: local.second,
        exact: true,
        silent: sound == RestSound.off,
        soundFile: sound.fileName,
      ),
    );
  }
}

/// Spielt die Töne aus den Assets; `ambient` folgt Stummschalter und Lautstärke und unterbricht keine Musik.
final class AssetRestSoundPlayer implements RestSoundPlaying {
  AudioPlayer? _player;

  @override
  Future<void> play(RestSound sound) async {
    if (sound == RestSound.off) return;
    final name = sound.fileName;
    if (name == null) {
      await SystemSound.play(SystemSoundType.alert);
      return;
    }
    try {
      final player = _player ??= AudioPlayer();
      await player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notificationEvent,
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
      await player.play(AssetSource('sounds/$name'));
    } on Object {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  /// iOS spielt eigene Mitteilungstöne nur aus dem App-Bundle oder `Library/Sounds`: einmal dorthin kopieren.
  static Future<void> installNotificationSounds() async {
    if (!Platform.isIOS) return;
    try {
      final folder = Directory(p.join((await getLibraryDirectory()).path, 'Sounds'));
      await folder.create(recursive: true);
      for (final sound in RestSound.values) {
        final name = sound.fileName;
        if (name == null) continue;
        final file = File(p.join(folder.path, name));
        if (file.existsSync()) continue;
        final data = await rootBundle.load('assets/sounds/$name');
        await file.writeAsBytes(data.buffer.asUint8List());
      }
    } on Object {
      // Ohne eigene Töne klingt die Mitteilung mit dem Standardton.
    }
  }
}

/// Für Tests: merkt sich Planungen und Töne.
final class FakeRestAlarm implements RestAlarm, RestSoundPlaying {
  final List<DateTime?> scheduled = [];
  final List<String?> bodies = [];
  final List<RestSound> played = [];

  @override
  Future<void> schedule(DateTime? end, {String? body, RestSound sound = RestSound.system}) async {
    scheduled.add(end);
    bodies.add(body);
  }

  @override
  Future<void> play(RestSound sound) async => played.add(sound);
}
