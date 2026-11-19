import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aktueller Kalendertag; meldet einen neuen Tag, auch wenn die App über Mitternacht offen bleibt oder aus dem
/// Hintergrund kommt (Port von `onDayChange`). Heute, Ernährung und Gym laden dann neu.
final currentDayProvider = NotifierProvider<CurrentDay, CalendarDay>(CurrentDay.new);

/// Zeitgeber der App (bis Mitternacht, regelmäßiger Abruf im Vordergrund); in Widget-Tests aus (dort darf kein
/// Zeitgeber offen bleiben).
final midnightTimerProvider = Provider<bool>((ref) => true);

class CurrentDay extends Notifier<CalendarDay> {
  Timer? _timer;

  @override
  CalendarDay build() {
    ref.onDispose(() => _timer?.cancel());
    if (ref.watch(midnightTimerProvider)) _schedule();
    return CalendarDay.today();
  }

  /// Kurz nach Mitternacht erneut prüfen.
  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    _timer = Timer(midnight.difference(now), () {
      check();
      _schedule();
    });
  }

  /// Beim Zurückkehren in die App aufrufen.
  void check() {
    final today = CalendarDay.today();
    if (today != state) state = today;
  }
}
