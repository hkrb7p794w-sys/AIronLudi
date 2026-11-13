import 'gym_session.dart';

/// Zustand einer gespeicherten, noch nicht beendeten Einheit. Erst der erste abgehakte Satz macht aus „geöffnet“ ein
/// echtes Training: Vorher gibt es keine Live-Aktivität, die Einheit zählt nicht als gemacht, und Erinnerungen bleiben
/// nur kurz aus (für den Fall, dass man gerade loslegt).
enum ActiveSessionState {
  /// Keine Einheit offen.
  none,

  /// Gestartet, aber noch kein Satz abgehakt – und vor höchstens [startGrace] heute.
  notStarted,

  /// Mindestens ein Satz abgehakt, seit Beginn höchstens [runningHours].
  running,

  /// Mit Sätzen, aber länger her (vergessen zu beenden): nicht verwerfen, beim Öffnen zum Speichern anbieten.
  unfinished,

  /// Ohne Satz und alt (z. B. gestern nur geöffnet): kann verworfen werden.
  abandoned;

  /// So lange gilt eine Einheit ohne Satz als „gerade gestartet“.
  static const startGrace = Duration(hours: 2);

  /// So lange gilt eine Einheit mit Sätzen als laufend.
  static const runningHours = Duration(hours: 5);

  /// Zustand in der Zeitzone des Geräts (wie `Calendar.current` in Swift) oder mit festem Abstand zu UTC.
  static ActiveSessionState of(GymSession? session, {required DateTime now, Duration? utcOffset}) {
    if (session == null) return none;
    final ageSeconds = now.difference(session.start).inMicroseconds / 1e6;
    DateTime wall(DateTime date) => utcOffset == null ? date.toLocal() : date.toUtc().add(utcOffset);
    final start = wall(session.start);
    final local = wall(now);
    final sameDay = start.year == local.year && start.month == local.month && start.day == local.day;
    if (session.doneSetCount == 0) {
      return sameDay && ageSeconds >= -60 && ageSeconds <= startGrace.inSeconds ? notStarted : abandoned;
    }
    return ageSeconds <= runningHours.inSeconds ? running : unfinished;
  }

  /// Live-Aktivität und Dynamic Island nur während eines echten Trainings.
  bool get showsLiveActivity => this == running;

  /// Keine Trainingserinnerung für heute, solange man in der Einheit ist (auch kurz vor dem ersten Satz).
  bool get suppressesReminders => this == running || this == notStarted;

  /// Zählt als heute trainiert (Wochenübersicht, Erinnerungen), bevor die Einheit gespeichert ist.
  bool get countsAsTrained => this == running;
}
