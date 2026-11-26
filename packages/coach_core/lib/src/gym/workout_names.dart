/// Einheitliche Namen der Krafteinheiten in der ganzen App: Push, Pull, Lower und Pull & Push (Wunsch vom
/// 25.11.2026). Ältere Namen aus GymBook, dem Saisonplan und früheren Versionen („Push A“, „Push & Pull B“,
/// „Push + Pull“, „Beine“) werden beim Lesen gespeicherter Einheiten und Routinen umbenannt.
abstract final class WorkoutNames {
  static const push = 'Push';
  static const pull = 'Pull';
  static const lower = 'Lower';
  static const pullPush = 'Pull & Push';

  static const Map<String, String> _legacy = {
    'Push A': push,
    'Pull A': pull,
    'Push & Pull B': pullPush,
    'Push & Pull': pullPush,
    'Push + Pull': pullPush,
    'Push+Pull': pullPush,
    'Beine': lower,
  };

  /// Heutiger Name zu einem gespeicherten; unbekannte Namen bleiben, wie sie sind.
  static String canonical(String name) => _legacy[name.trim()] ?? name;
}
