import 'package:flutter/material.dart';

// Designsystem-Tokens (Roast 24.11.2026, docs/roast/design-konzept.md Abschnitt 3). In `lib/features` keine rohen
// Farben (`Colors.*`, `Color(0x…)`) und keine festen Schriftgrößen (`fontSize:`) mehr, sondern diese Rollen. Abstände:
// `LiquidSpacing`, Radien: `LiquidRadii` (lib/ui/liquid.dart). Ein Test (test/ui/ui_tokens_test.dart) achtet darauf,
// dass der Bestand an Rohwerten nur schrumpft.

/// Farben mit Bedeutung. Rot heißt „handeln“, Grün „gut“, Orange „eingeschränkt/Hinweis“, Akzent „Interaktion“.
/// Werte wie die iOS-Systemfarben, hell und dunkel.
@immutable
final class AppColors {
  const AppColors._({required this.good, required this.caution, required this.alert, required this.info});

  /// Gut, erledigt, im Zielbereich.
  final Color good;

  /// Eingeschränkt, Hinweis, Aufmerksamkeit.
  final Color caution;

  /// Handeln: Pause, Fehler, Löschen, über dem Limit.
  final Color alert;

  /// Neutral hervorgehoben, Information (= Akzent).
  final Color info;

  static const light = AppColors._(
    good: Color(0xFF34C759),
    caution: Color(0xFFFF9500),
    alert: Color(0xFFFF3B30),
    info: Color(0xFF007AFF),
  );

  static const dark = AppColors._(
    good: Color(0xFF30D158),
    caution: Color(0xFFFF9F0A),
    alert: Color(0xFFFF453A),
    info: Color(0xFF0A84FF),
  );

  static AppColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Nebeninformation (Fußtexte, Unterzeilen) mit ausreichendem Kontrast.
  static Color muted(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;
}

/// Textrollen (iOS-Größen bei Dynamic Type „Groß“). Alle skalieren mit der Systemschrift; nichts unter 12 pt.
abstract final class AppText {
  static TextTheme _t(BuildContext context) => Theme.of(context).textTheme;

  /// 34, fett – Reiter-Titel.
  static TextStyle largeTitle(BuildContext context) => _t(context).headlineLarge!;

  /// 22, halbfett – Seitentitel, große Kennzahl.
  static TextStyle title(BuildContext context) => _t(context).headlineSmall!;

  /// 17, halbfett – Kartentitel.
  static TextStyle headline(BuildContext context) => _t(context).titleMedium!;

  /// 17 – Fließtext, Zeilen.
  static TextStyle body(BuildContext context) => _t(context).bodyLarge!;

  /// 15 – Unterzeilen.
  static TextStyle callout(BuildContext context) => _t(context).bodyMedium!;

  /// 13 – Fußtexte, Quellen.
  static TextStyle footnote(BuildContext context) => _t(context).bodySmall!;

  /// 12 – Achsen, Abzeichen; die Untergrenze.
  static TextStyle caption(BuildContext context) => _t(context).labelSmall!;
}
