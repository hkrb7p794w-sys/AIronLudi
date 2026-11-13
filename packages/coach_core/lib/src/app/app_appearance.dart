/// Darstellung der App: dem System folgen oder fest hell bzw. dunkel. Gilt nur in der App; Widgets und
/// Live-Aktivität folgen immer dem System.
enum AppAppearance {
  system('Wie System'),
  light('Hell'),
  dark('Dunkel');

  const AppAppearance(this.title);

  final String title;

  static const storageKey = 'appAppearance';

  /// Unbekannte oder fehlende Werte fallen auf „Wie System“ zurück.
  static AppAppearance fromStored(String? stored) =>
      AppAppearance.values.where((value) => value.name == stored).firstOrNull ?? AppAppearance.system;
}
