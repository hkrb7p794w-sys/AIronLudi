import 'package:coach_core/coach_core.dart';

import '../../data/repositories/gym_repository.dart';
import '../../data/repositories/metrics_repository.dart';
import '../../data/settings/settings_store.dart';
import 'social_service.dart';

/// „Trainings automatisch mit Freunden teilen“: neue Trainings (Uhr und Gym) erscheinen von selbst im Feed der Freunde
/// – ohne Körperwerte, wie beim Teilen von Hand (`WorkoutShare`). Standard: aus (Port von `SocialAutoShare`).
final class SocialAutoShare {
  SocialAutoShare({required this._settings, required this._social, required this._activities, required this._gym});

  static const enabledKey = SettingsKeys.socialAutoShare;

  /// Zeitpunkt des Einschaltens: Ältere Trainings bleiben privat.
  static const sinceKey = SettingsKeys.socialAutoShareSince;

  final SettingsStore _settings;
  final SocialService _social;
  final ActivityRepository _activities;
  final GymRepository _gym;
  bool _running = false;

  bool get isEnabled => _settings.boolValue(enabledKey);

  /// Beim Umschalten in den Einstellungen bzw. im Reiter.
  Future<void> setEnabled(bool enabled, {DateTime? now}) async {
    await _settings.setBool(enabledKey, enabled);
    if (enabled) {
      await _settings.setDouble(sinceKey, (now ?? DateTime.now()).millisecondsSinceEpoch / 1000);
    }
  }

  /// Nach dem Abgleich und beim Öffnen des Reiters. Fehler (offline, abgemeldet) bleiben still; der nächste Durchlauf
  /// holt es nach.
  Future<void> run({DateTime? now, bool isDemo = false}) async {
    if (!isEnabled || _running || isDemo || !_social.isAvailable) return;
    final since = _settings.doubleValue(sinceKey) ?? 0;
    if (since <= 0) return;
    _running = true;
    try {
      final time = now ?? DateTime.now();
      final today = CalendarDay.fromDate(time);
      final activities = await _activities.range(from: today.adding(-4), to: today);
      final sessions = ([
        for (final record in await _gym.all()) record.session,
      ]..sort((a, b) => b.start.compareTo(a.start))).take(20).toList();
      final entries = ActivityFeed.entries(
        activities: activities,
        gym: [for (final session in sessions) GymItem.fromSession(session)],
      );
      final candidates = SocialTimeline.autoShareCandidates(
        entries: entries,
        shared: SharedPostStore(_settings).load(),
        since: DateTime.fromMillisecondsSinceEpoch((since * 1000).round()),
        now: time,
      );
      for (final entry in candidates) {
        final gym = entry.gym;
        final session = gym == null ? null : sessions.where((session) => session.id == gym.id).firstOrNull;
        final WorkoutShare share;
        if (session != null) {
          share = WorkoutShare.gym(session, now: time);
        } else if (entry.activity case final activity?) {
          share = WorkoutShare.activity(activity);
        } else {
          continue;
        }
        try {
          await _social.shareWorkout(share, localKeys: SocialTimeline.keys(entry));
        } on Object {
          return;
        }
      }
    } finally {
      _running = false;
    }
  }
}
