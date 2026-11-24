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

/// Benannte Kategorie- und Zierfarben (Sportarten, Lebensmittel-Arten, Abzeichen, Chips, Zonen). Gleiche Werte wie
/// die Material-Farben, die vorher direkt in `lib/features` standen – an einem Ort, damit sie sich gemeinsam ändern
/// lassen. Für Bewertungen (gut/eingeschränkt/handeln) gilt `AppColors`, nicht diese Palette.
abstract final class AppPalette {
  static const green = Colors.green;
  static const orange = Colors.orange;
  static const red = Colors.red;
  static const blue = Colors.blue;
  static const teal = Colors.teal;
  static const tealLight = Color(0xFF4DB6AC); // Colors.teal.shade300
  static const amber = Colors.amber;
  static const pink = Colors.pink;
  static const purple = Colors.purple;
  static const indigo = Colors.indigo;
  static const cyan = Colors.cyan;
  static const deepOrange = Colors.deepOrange;
  static const lightBlue = Colors.lightBlue;
  static const brown = Colors.brown;
  static const grey = Colors.grey;

  /// Schrift und Symbole auf farbigen Flächen (Sport-Symbole, Löschen-Hintergrund, gefüllte Knöpfe).
  static const onColor = Colors.white;

  // Karten: Routenvarianten, Orte, eigener Standort und Schatten der Marker (bleiben auf jeder Karte gleich).
  static const mapBlue = Color(0xFF0A84FF);
  static const mapOrange = Color(0xFFFF6B35);
  static const mapGreen = Color(0xFF30C26B);
  static const mapGrey = Color(0xFF8E8E93);
  static const mapShadow = Color(0x33000000);
  static const mapShadowStrong = Color(0x40000000);

  /// Abdunkelung hinter einem Foto (Kühlschrank-Foto).
  static const scrim = Color(0x33000000);

  // Drei Reihen in Diagrammen (Verpflegung: Kohlenhydrate, Flüssigkeit, Natrium), hell und dunkel.
  static const seriesBlueLight = Color(0xFF2A78D6);
  static const seriesBlueDark = Color(0xFF3987E5);
  static const seriesOrangeLight = Color(0xFFEB6834);
  static const seriesOrangeDark = Color(0xFFD95926);
  static const seriesGreenLight = Color(0xFF1BAF7A);
  static const seriesGreenDark = Color(0xFF199E70);
}
