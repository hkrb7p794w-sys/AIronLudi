import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/liquid.dart';

/// iOS-Systemfarben wie in der Swift-App (UIKit-Standard, ohne eigene Akzentfarbe → `systemBlue`).
/// Quelle: Apple Human Interface Guidelines, „Color“ (Systemfarben und Hintergründe für gruppierte Listen).
@immutable
final class IOSColors {
  const IOSColors._({
    required this.accent,
    required this.groupedBackground,
    required this.secondaryGroupedBackground,
    required this.tertiaryGroupedBackground,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.opaqueSeparator,
    required this.fill,
    required this.tabBar,
    required this.red,
    required this.green,
    required this.orange,
  });

  final Color accent;

  /// Hintergrund von Listen und Formularen (`systemGroupedBackground`).
  final Color groupedBackground;

  /// Zeilen und Karten auf dem Hintergrund (`secondarySystemGroupedBackground`).
  final Color secondaryGroupedBackground;

  /// Flächen in Karten (`tertiarySystemGroupedBackground`).
  final Color tertiaryGroupedBackground;
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color separator;
  final Color opaqueSeparator;

  /// Füllung für Felder und Marken (`tertiarySystemFill`, deckend auf dem Hintergrund).
  final Color fill;
  final Color tabBar;
  final Color red;
  final Color green;
  final Color orange;

  static const light = IOSColors._(
    accent: Color(0xFF007AFF),
    groupedBackground: Color(0xFFF2F2F7),
    secondaryGroupedBackground: Color(0xFFFFFFFF),
    tertiaryGroupedBackground: Color(0xFFF2F2F7),
    label: Color(0xFF000000),
    secondaryLabel: Color(0x993C3C43),
    tertiaryLabel: Color(0x4D3C3C43),
    separator: Color(0x4A3C3C43),
    opaqueSeparator: Color(0xFFC6C6C8),
    fill: Color(0xFFE3E3E8),
    tabBar: Color(0xF0F9F9F9),
    red: Color(0xFFFF3B30),
    green: Color(0xFF34C759),
    orange: Color(0xFFFF9500),
  );

  static const dark = IOSColors._(
    accent: Color(0xFF0A84FF),
    groupedBackground: Color(0xFF000000),
    secondaryGroupedBackground: Color(0xFF1C1C1E),
    tertiaryGroupedBackground: Color(0xFF2C2C2E),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x99EBEBF5),
    tertiaryLabel: Color(0x4DEBEBF5),
    separator: Color(0x99545458),
    opaqueSeparator: Color(0xFF38383A),
    fill: Color(0xFF2C2C2E),
    tabBar: Color(0xF0161616),
    red: Color(0xFFFF453A),
    green: Color(0xFF30D158),
    orange: Color(0xFFFF9F0A),
  );

  static IOSColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Designsystem der App: „Clean Liquid Design“ (docs/decisions.md, 18.11.2026) – transluzente Glasflächen mit
/// Lichtkante über einem ruhigen Hintergrund mit weichen Lichtflecken, große Radien, Pillen-Knöpfe, iOS-Schriftgrößen,
/// Akzent `systemBlue`, keine Material-Wellen. Werte für Radien, Bewegung und Glas: `lib/ui/liquid.dart`.
abstract final class AppTheme {
  static ThemeData light() => _theme(Brightness.light);

  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final ios = brightness == Brightness.dark ? IOSColors.dark : IOSColors.light;
    final liquid = brightness == Brightness.dark ? LiquidTheme.dark : LiquidTheme.light;
    final dark = brightness == Brightness.dark;
    // Deckende Fläche für Menüs und Dialoge (ohne eigene Unschärfe), leicht kühl getönt wie das Glas.
    final floating = dark ? const Color(0xF21A1E28) : const Color(0xF7FAFBFD);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: ios.accent,
      onPrimary: Colors.white,
      primaryContainer: ios.accent.withValues(alpha: 0.15),
      onPrimaryContainer: ios.accent,
      secondary: ios.accent,
      onSecondary: Colors.white,
      secondaryContainer: ios.accent.withValues(alpha: 0.18),
      onSecondaryContainer: ios.accent,
      tertiary: ios.green,
      onTertiary: Colors.white,
      error: ios.red,
      onError: Colors.white,
      errorContainer: ios.red.withValues(alpha: 0.15),
      onErrorContainer: ios.red,
      surface: liquid.base,
      onSurface: ios.label,
      onSurfaceVariant: ios.secondaryLabel,
      surfaceContainerLowest: liquid.glassFill,
      surfaceContainerLow: liquid.glassFill,
      surfaceContainer: liquid.glassFill,
      surfaceContainerHigh: floating,
      // Füllung für Felder, Spuren und Marken: transluzent, damit das Glas durchscheint.
      surfaceContainerHighest: dark ? const Color(0x24FFFFFF) : const Color(0x143C4B66),
      surfaceTint: Colors.transparent,
      outline: dark ? const Color(0x40FFFFFF) : const Color(0x333C4B66),
      outlineVariant: dark ? const Color(0x1FFFFFFF) : const Color(0x1F3C4B66),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: brightness == Brightness.dark ? Colors.white : const Color(0xFF1C1C1E),
      onInverseSurface: brightness == Brightness.dark ? Colors.black : Colors.white,
      inversePrimary: ios.accent,
    );
    final base = ThemeData(colorScheme: scheme, brightness: brightness, useMaterial3: true);
    final text = _textTheme(base.textTheme, ios);
    final cardShape = RoundedRectangleBorder(
      borderRadius: LiquidRadii.cardAll,
      side: BorderSide(color: liquid.edgeTop.withValues(alpha: liquid.edgeTop.a * 0.6), width: 1),
    );
    const buttonShape = StadiumBorder();
    // Knöpfe leuchten beim Drücken sanft auf statt Tintenwellen.
    final pressGlow = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.pressed) ? Colors.white.withValues(alpha: dark ? 0.12 : 0.22) : null,
    );
    const buttonText = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4);
    const plainButtonText = TextStyle(fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.4);
    return base.copyWith(
      extensions: [liquid],
      // Seiten sind durchsichtig: den Hintergrund mit Lichtflecken malt der Seitenübergang (LiquidBackground).
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: liquid.base,
      textTheme: text,
      // Keine Tintenwellen: Tippen hebt nur leicht hervor, wie bei iOS.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: ios.label.withValues(alpha: dark ? 0.08 : 0.05),
      hoverColor: Colors.transparent,
      dividerColor: liquid.track,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: LiquidPageTransitionsBuilder(),
          TargetPlatform.iOS: LiquidPageTransitionsBuilder(),
          TargetPlatform.linux: LiquidPageTransitionsBuilder(),
          TargetPlatform.macOS: LiquidPageTransitionsBuilder(),
          TargetPlatform.windows: LiquidPageTransitionsBuilder(),
          TargetPlatform.fuchsia: LiquidPageTransitionsBuilder(),
        },
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: ios.accent,
        scaffoldBackgroundColor: liquid.base,
        barBackgroundColor: liquid.glassFillStrong,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ios.accent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: ios.accent),
        actionsIconTheme: IconThemeData(color: ios.accent),
        titleTextStyle: text.titleMedium?.copyWith(color: ios.label, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: liquid.glassFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: cardShape,
        margin: const EdgeInsets.symmetric(horizontal: LiquidSpacing.page, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: ios.accent,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: ios.secondaryLabel),
        leadingAndTrailingTextStyle: text.bodyLarge?.copyWith(color: ios.secondaryLabel),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minTileHeight: 44,
        minVerticalPadding: 10,
        horizontalTitleGap: 14,
        minLeadingWidth: 28,
      ),
      dividerTheme: DividerThemeData(color: liquid.track, thickness: 0.5, space: 0.5),
      iconTheme: IconThemeData(color: ios.accent),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          textStyle: buttonText,
          minimumSize: const Size(44, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          elevation: 0,
        ).copyWith(overlayColor: pressGlow, backgroundBuilder: _sheen),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: buttonShape,
          textStyle: buttonText,
          backgroundColor: ios.accent.withValues(alpha: 0.15),
          foregroundColor: ios.accent,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(44, 44),
        ).copyWith(overlayColor: pressGlow),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        // SwiftUI `.bordered`: getönte Fläche statt Rahmen.
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          textStyle: plainButtonText,
          backgroundColor: ios.accent.withValues(alpha: 0.15),
          foregroundColor: ios.accent,
          side: BorderSide.none,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ).copyWith(overlayColor: pressGlow),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: plainButtonText, foregroundColor: ios.accent),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: ios.accent)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: ios.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? const Color(0x1AFFFFFF) : const Color(0x99FFFFFF),
        selectedColor: ios.accent.withValues(alpha: 0.2),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: text.bodyMedium,
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        // Wie `Picker(.segmented)`: graue Leiste, gewähltes Segment hell abgesetzt.
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? (dark ? const Color(0x47FFFFFF) : Colors.white)
                : (dark ? const Color(0x14FFFFFF) : const Color(0x0F3C4B66)),
          ),
          foregroundColor: WidgetStatePropertyAll(ios.label),
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          animationDuration: LiquidMotion.medium,
          textStyle: WidgetStatePropertyAll(text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          visualDensity: VisualDensity.compact,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? ios.green
              : (dark ? const Color(0x33FFFFFF) : const Color(0x293C4B66)),
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ios.accent : Colors.transparent,
        ),
        side: BorderSide(color: ios.tertiaryLabel, width: 1.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: ios.accent,
        linearTrackColor: liquid.track,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 6,
        borderRadius: const BorderRadius.all(Radius.circular(3)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: ios.accent,
        inactiveTrackColor: liquid.track,
        thumbColor: Colors.white,
        trackHeight: 4,
        overlayColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: ios.tertiaryLabel),
        labelStyle: TextStyle(color: ios.secondaryLabel),
        floatingLabelStyle: TextStyle(color: ios.secondaryLabel),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ios.accent,
        selectionColor: ios.accent.withValues(alpha: 0.3),
        selectionHandleColor: ios.accent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: dark ? 0.45 : 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(LiquidRadii.sheet)),
          side: BorderSide(color: liquid.edgeTop.withValues(alpha: liquid.edgeTop.a * 0.5)),
        ),
        titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: ios.tertiaryLabel,
        dragHandleSize: const Size(36, 5),
        modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.45 : 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(LiquidRadii.sheet)),
          side: BorderSide(color: liquid.edgeTop.withValues(alpha: liquid.edgeTop.a * 0.5)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: floating,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: liquid.shadow,
        shape: const RoundedRectangleBorder(borderRadius: LiquidRadii.innerAll),
        textStyle: text.bodyLarge,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(floating),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: LiquidRadii.innerAll)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xF22A2F3A) : const Color(0xF21C1F27),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        elevation: 0,
        shape: const StadiumBorder(),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ios.accent,
        unselectedLabelColor: ios.secondaryLabel,
        indicatorColor: ios.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      badgeTheme: BadgeThemeData(backgroundColor: ios.red, textColor: Colors.white),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: ios.tertiaryLabel,
        collapsedIconColor: ios.tertiaryLabel,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
    );
  }

  /// Glanz auf gefüllten Knöpfen: oben ein Hauch Weiß, wie Licht auf einer gewölbten Fläche.
  static Widget _sheen(BuildContext context, Set<WidgetState> states, Widget? child) => DecoratedBox(
    decoration: ShapeDecoration(
      shape: const StadiumBorder(),
      gradient: states.contains(WidgetState.disabled)
          ? null
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0)],
              stops: const [0, 0.6],
            ),
    ),
    child: child,
  );

  /// Schriftgrößen von iOS (Dynamic Type „Groß“): Fließtext 17, Unterzeile 15, Fußnote 13, Beschriftung 12.
  static TextTheme _textTheme(TextTheme base, IOSColors ios) {
    TextStyle? style(TextStyle? from, double size, FontWeight weight, double spacing) =>
        from?.copyWith(fontSize: size, fontWeight: weight, letterSpacing: spacing, height: 1.25, color: ios.label);
    return base.copyWith(
      // Große Zahlen und Titel eng gesetzt wie SF Pro Display.
      displayLarge: style(base.displayLarge, 48, FontWeight.w700, -1.2),
      displayMedium: style(base.displayMedium, 40, FontWeight.w700, -1),
      displaySmall: style(base.displaySmall, 34, FontWeight.w700, -0.8),
      headlineLarge: style(base.headlineLarge, 34, FontWeight.w700, -0.6),
      headlineMedium: style(base.headlineMedium, 28, FontWeight.w700, -0.5),
      headlineSmall: style(base.headlineSmall, 22, FontWeight.w700, -0.3),
      titleLarge: style(base.titleLarge, 20, FontWeight.w600, -0.4),
      titleMedium: style(base.titleMedium, 17, FontWeight.w600, -0.4),
      titleSmall: style(base.titleSmall, 15, FontWeight.w600, -0.2),
      bodyLarge: style(base.bodyLarge, 17, FontWeight.w400, -0.4),
      bodyMedium: style(base.bodyMedium, 15, FontWeight.w400, -0.2),
      bodySmall: style(base.bodySmall, 13, FontWeight.w400, -0.1),
      labelLarge: style(base.labelLarge, 15, FontWeight.w500, -0.2),
      labelMedium: style(base.labelMedium, 13, FontWeight.w500, -0.1),
      labelSmall: style(base.labelSmall, 12, FontWeight.w500, 0),
    );
  }
}
