import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// „Clean Liquid Design“: zentrale Werte für Radien, Abstände, Bewegung, Glas und Hintergrund. Alle Bausteine der App
/// (Karten, Abschnitte, Ringe, Tab-Leiste, Knöpfe) lesen von hier – so wirkt die App wie aus einem Guss.
abstract final class LiquidRadii {
  /// Hauptkarten, Widgets, Abschnitte.
  static const double card = 24;

  /// Innere Flächen (Kacheln in Karten, Felder, Symbole).
  static const double inner = 14;

  /// Dialoge und Sheets.
  static const double sheet = 28;

  /// Pillen: Knöpfe, Marken, Tab-Auswahl.
  static const double pill = 999;

  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius innerAll = BorderRadius.all(Radius.circular(inner));
}

/// Abstände („Clean & Airy“): Raster aus 4.
abstract final class LiquidSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 28;

  /// Außenabstand der Karten zum Bildschirmrand.
  static const double page = 16;

  /// Innenabstand der Karten.
  static const EdgeInsets card = EdgeInsets.all(18);
}

/// Bewegung: weiche Federn und Ease-Out. Bei „Bewegung reduzieren“ laufen alle Übergänge sofort.
abstract final class LiquidMotion {
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 380);
  static const Duration slow = Duration(milliseconds: 700);

  /// Feder mit leichtem Überschwingen – für Anzeigen, Auswahl und Erscheinen.
  static const Curve spring = LiquidSpringCurve();

  /// Feder ohne sichtbares Überschwingen – für Füllungen von Ringen und Balken.
  static const Curve settle = LiquidSpringCurve(dampingRatio: 0.92);

  static const Curve easeOut = Curves.easeOutCubic;

  /// Dauer unter Beachtung von „Bewegung reduzieren“.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : duration;
}

/// Kurve aus einer echten Federsimulation (Masse 1), auf 0…1 gestreckt: natürlicher als feste Bezier-Kurven.
class LiquidSpringCurve extends Curve {
  const LiquidSpringCurve({this.dampingRatio = 0.72, this.stiffness = 170});

  final double dampingRatio;
  final double stiffness;

  /// Zeit (s), auf die der Kurvenverlauf 0…1 abgebildet wird; danach ist die Feder praktisch in Ruhe.
  double get _settleTime => 5.5 / (dampingRatio * math.sqrt(stiffness));

  @override
  double transformInternal(double t) {
    final simulation = SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: stiffness, ratio: dampingRatio),
      0,
      1,
      0,
    );
    return simulation.x(t * _settleTime);
  }
}

/// Farben und Materialien des Liquid-Designs als Theme-Erweiterung (`LiquidTheme.of(context)`).
@immutable
class LiquidTheme extends ThemeExtension<LiquidTheme> {
  const LiquidTheme({
    required this.brightness,
    required this.base,
    required this.baseEnd,
    required this.glows,
    required this.glassFill,
    required this.glassFillStrong,
    required this.edgeTop,
    required this.edgeBottom,
    required this.shadow,
    required this.track,
    required this.blurSigma,
  });

  final Brightness brightness;

  /// Grundton des Hintergrunds (oben) und Verlaufsende (unten).
  final Color base;
  final Color baseEnd;

  /// Weiche Lichtflecken unter den Glasflächen: Farbe, Mittelpunkt (−1…1) und Radius (Anteil der Breite).
  final List<LiquidGlow> glows;

  /// Glasfüllung für Karten und für Leisten/Sheets (deckender).
  final Color glassFill;
  final Color glassFillStrong;

  /// Lichtkante: Verlauf von halbtransparentem Weiß zu fast transparent.
  final Color edgeTop;
  final Color edgeBottom;

  /// Weicher, großflächiger Umgebungsschatten.
  final Color shadow;

  /// Spur von Ringen und Balken.
  final Color track;
  final double blurSigma;

  bool get isDark => brightness == Brightness.dark;

  static const light = LiquidTheme(
    brightness: Brightness.light,
    base: Color(0xFFF3F6FB),
    baseEnd: Color(0xFFE9EEF6),
    glows: [
      LiquidGlow(Color(0x557AB8FF), Alignment(-1.1, -0.95), 0.95),
      LiquidGlow(Color(0x40C3A6FF), Alignment(1.15, -0.35), 0.8),
      LiquidGlow(Color(0x3384E8D0), Alignment(-0.6, 0.75), 0.9),
      LiquidGlow(Color(0x26FFB9A8), Alignment(1.0, 1.05), 0.75),
    ],
    // Karten fast deckend (Roast F-3): ruhiger, besserer Kontrast, weniger GPU-Last; Glas nur für Leisten und Sheets.
    glassFill: Color(0xF2FFFFFF),
    glassFillStrong: Color(0xE6FBFCFE),
    edgeTop: Color(0xE6FFFFFF),
    edgeBottom: Color(0x33FFFFFF),
    shadow: Color(0x142A3B5C),
    track: Color(0x1A3C4B66),
    blurSigma: 24,
  );

  static const dark = LiquidTheme(
    brightness: Brightness.dark,
    base: Color(0xFF070A12),
    baseEnd: Color(0xFF03040A),
    glows: [
      LiquidGlow(Color(0x592C6BFF), Alignment(-1.1, -1.0), 0.95),
      LiquidGlow(Color(0x407B3CFF), Alignment(1.2, -0.3), 0.85),
      LiquidGlow(Color(0x3314C8A8), Alignment(-0.8, 0.8), 0.9),
      LiquidGlow(Color(0x26FF4D8D), Alignment(1.0, 1.1), 0.7),
    ],
    glassFill: Color(0xF21C1F27),
    glassFillStrong: Color(0xD9161A24),
    edgeTop: Color(0x40FFFFFF),
    edgeBottom: Color(0x08FFFFFF),
    shadow: Color(0x59000000),
    track: Color(0x1FFFFFFF),
    blurSigma: 28,
  );

  static LiquidTheme of(BuildContext context) =>
      Theme.of(context).extension<LiquidTheme>() ??
      (Theme.of(context).brightness == Brightness.dark ? LiquidTheme.dark : LiquidTheme.light);

  /// Glasfüllung; bei „Kontrast erhöhen“ deckender, damit Text sicher lesbar bleibt.
  Color fillFor(BuildContext context, {bool strong = false}) {
    final fill = strong ? glassFillStrong : glassFill;
    if (!(MediaQuery.maybeHighContrastOf(context) ?? false)) return fill;
    return isDark ? const Color(0xFF1C1F27) : Colors.white;
  }

  /// Lichtkante als Verlauf von oben links nach unten rechts.
  Gradient edgeGradient({double glow = 0}) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(edgeTop, Colors.white, glow)!,
      Color.lerp(edgeBottom, edgeTop, glow * 0.6)!,
      Color.lerp(edgeTop, Colors.white, glow)!.withValues(alpha: edgeTop.a * 0.45),
    ],
    stops: const [0, 0.55, 1],
  );

  List<BoxShadow> get ambientShadow => [
    BoxShadow(color: shadow, blurRadius: 40, spreadRadius: -8, offset: const Offset(0, 18)),
  ];

  @override
  LiquidTheme copyWith({double? blurSigma}) => LiquidTheme(
    brightness: brightness,
    base: base,
    baseEnd: baseEnd,
    glows: glows,
    glassFill: glassFill,
    glassFillStrong: glassFillStrong,
    edgeTop: edgeTop,
    edgeBottom: edgeBottom,
    shadow: shadow,
    track: track,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  @override
  LiquidTheme lerp(LiquidTheme? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

/// Ein Lichtfleck im Hintergrund.
@immutable
class LiquidGlow {
  const LiquidGlow(this.color, this.center, this.radius);

  final Color color;
  final Alignment center;
  final double radius;
}

/// Leuchtende Verläufe für Statusfarben (Ampel, Makros, Strain): heller Anfang, satte Mitte, leicht dunkleres Ende.
abstract final class LiquidGradients {
  static List<Color> of(Color color) {
    final hsl = HSLColor.fromColor(color);
    final bright = hsl
        .withLightness((hsl.lightness + 0.16).clamp(0, 0.9))
        .withSaturation((hsl.saturation + 0.05).clamp(0, 1))
        .toColor();
    final deep = hsl.withLightness((hsl.lightness - 0.06).clamp(0.1, 1)).withHue((hsl.hue + 12) % 360).toColor();
    return [bright, color, deep];
  }

  static LinearGradient linear(Color color) =>
      LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: of(color));

  static LinearGradient accent(BuildContext context) => linear(Theme.of(context).colorScheme.primary);
}

/// Hintergrund jeder Seite: ruhiger Verlauf mit weichen Lichtflecken, die unter den Glasflächen durchschimmern.
class LiquidBackground extends StatelessWidget {
  const LiquidBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final liquid = LiquidTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [liquid.base, liquid.baseEnd],
        ),
      ),
      child: CustomPaint(
        painter: _GlowPainter(liquid.glows),
        // Mehrere Glasflächen teilen sich das Lesen des Hintergrunds (günstiger als je ein eigener Filter).
        child: BackdropGroup(child: child),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.glows);

  final List<LiquidGlow> glows;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = math.max(size.width, math.min(size.height, size.width * 1.6));
    for (final glow in glows) {
      final center = glow.center.withinRect(Offset.zero & size);
      final radius = extent * glow.radius;
      final paint = Paint()
        ..shader = ui.Gradient.radial(center, radius, [glow.color, glow.color.withValues(alpha: 0)], [0, 1]);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.glows != glows;
}

/// Transluzente Glasfläche mit Hintergrund-Unschärfe, hauchdünner Lichtkante und weichem Schatten. Mit [onTap]
/// reagiert sie auf Berührung: leichtes Einsinken (Feder) und aufleuchtende Kante.
class LiquidCard extends StatelessWidget {
  const LiquidCard({
    super.key,
    required this.child,
    this.padding = LiquidSpacing.card,
    this.margin = EdgeInsets.zero,
    this.radius = LiquidRadii.card,
    this.onTap,
    this.onLongPress,
    this.tint,
    this.blur = true,
    this.strong = false,
    this.shadow = true,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Leichte Färbung des Glases (z. B. Ampelfarbe einer Warnung).
  final Color? tint;
  final bool blur;

  /// Deckenderes Glas (Leisten, schwebende Flächen).
  final bool strong;
  final bool shadow;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final interactive = onTap != null || onLongPress != null;
    final surface = LiquidSurface(
      radius: radius,
      tint: tint,
      blur: blur,
      strong: strong,
      shadow: shadow,
      child: interactive
          ? Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onTap!();
                      },
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(radius),
                child: Padding(padding: padding, child: child),
              ),
            )
          : Padding(padding: padding, child: child),
    );
    return Padding(
      padding: margin,
      child: Semantics(
        label: semanticLabel,
        child: interactive ? LiquidPressable(child: surface) : surface,
      ),
    );
  }
}

/// Die eigentliche Glasfläche ohne Innenabstand – Grundlage von [LiquidCard], Abschnitten und Leisten.
class LiquidSurface extends StatelessWidget {
  const LiquidSurface({
    super.key,
    required this.child,
    this.radius = LiquidRadii.card,
    this.tint,
    this.blur = true,
    this.strong = false,
    this.shadow = true,
    this.glow = 0,
  });

  final Widget child;
  final double radius;
  final Color? tint;
  final bool blur;
  final bool strong;
  final bool shadow;

  /// 0…1: wie stark die Lichtkante aufleuchtet (Berührung, Auswahl).
  final double glow;

  @override
  Widget build(BuildContext context) {
    final liquid = LiquidTheme.of(context);
    final borderRadius = BorderRadius.circular(radius);
    final fill = liquid.fillFor(context, strong: strong);
    final color = tint == null ? fill : Color.alphaBlend(tint!.withValues(alpha: liquid.isDark ? 0.14 : 0.1), fill);
    Widget content = DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      position: DecorationPosition.background,
      child: CustomPaint(
        foregroundPainter: _EdgePainter(
          gradient: liquid.edgeGradient(glow: glow),
          radius: radius,
        ),
        // Eigenes (durchsichtiges) Material, damit Zeilen ihre Hervorhebung auf dem Glas zeigen.
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
    content = ClipRRect(
      borderRadius: borderRadius,
      // Unschärfe nur für deckendes Glas (Tab-Leiste, schwebende Leisten, Sheets); Karten sind deckend (Roast F-3).
      child: blur && strong && liquid.blurSigma > 0
          ? BackdropFilter.grouped(
              filter: ui.ImageFilter.blur(sigmaX: liquid.blurSigma, sigmaY: liquid.blurSigma),
              child: content,
            )
          : content,
    );
    if (!shadow) return content;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: liquid.ambientShadow),
      child: content,
    );
  }
}

/// Hauchdünne Lichtkante (1 px) mit Verlauf.
class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.gradient, required this.radius});

  final Gradient gradient;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, radius - 0.5))), paint);
  }

  @override
  bool shouldRepaint(_EdgePainter old) => old.gradient != gradient || old.radius != radius;
}

/// Taktile Rückmeldung: Inhalt sinkt bei Berührung leicht ein und federt zurück. Fängt keine Gesten ab – die
/// eigentliche Aktion bleibt beim Kind (Knopf, Zeile, InkWell).
class LiquidPressable extends StatefulWidget {
  const LiquidPressable({super.key, required this.child, this.scale = 0.975});

  final Widget child;
  final double scale;

  @override
  State<LiquidPressable> createState() => _LiquidPressableState();
}

class _LiquidPressableState extends State<LiquidPressable> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: LiquidMotion.of(context, _pressed ? LiquidMotion.quick : LiquidMotion.medium),
      curve: _pressed ? LiquidMotion.easeOut : LiquidMotion.spring,
      child: widget.child,
    ),
  );
}

/// Blendet Inhalt weich ein: von leicht unten mit Ausblenden, mit Feder. Für Module, die erscheinen.
class LiquidAppear extends StatelessWidget {
  const LiquidAppear({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final duration = LiquidMotion.of(context, LiquidMotion.slow + delay);
    if (duration == Duration.zero) return child;
    final start = delay.inMicroseconds / duration.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Interval(start, 1, curve: LiquidMotion.settle),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - value) * 14), child: child),
      ),
    );
  }
}

/// Wechselt Inhalt mit Überblendung und weicher Größenänderung (Module ein-/ausblenden).
class LiquidSwitcher extends StatelessWidget {
  const LiquidSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: LiquidMotion.of(context, LiquidMotion.medium),
    curve: LiquidMotion.settle,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: LiquidMotion.of(context, LiquidMotion.medium),
      switchInCurve: LiquidMotion.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    ),
  );
}

/// Große Kennzahl („KPI“): prägnante Zahl mit gleich breiten Ziffern, darunter ein dezentes Label.
class LiquidMetric extends StatelessWidget {
  const LiquidMetric({super.key, required this.value, required this.label, this.color, this.unit});

  final String value;
  final String label;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            text: value,
            children: [
              if (unit case final unit?)
                TextSpan(text: ' $unit', style: LiquidText.label(context).copyWith(fontSize: 15)),
            ],
          ),
          style: LiquidText.kpi(context).copyWith(color: color ?? theme.colorScheme.onSurface),
        ),
        Text(label, style: LiquidText.label(context)),
      ],
    );
  }
}

/// Typografie-Rollen des Liquid-Designs.
abstract final class LiquidText {
  /// Große Kennzahl.
  static TextStyle kpi(BuildContext context, {double size = 34}) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: -size * 0.03,
    height: 1.05,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: Theme.of(context).colorScheme.onSurface,
  );

  /// Dezentes Label in reduzierter Deckkraft.
  static TextStyle label(BuildContext context) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.05,
    height: 1.25,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  /// Überschrift über einem Abschnitt.
  static TextStyle sectionHeader(BuildContext context) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    height: 1.2,
    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
  );
}

/// Seitenübergang: jede Seite bekommt den Liquid-Hintergrund, der Übergang selbst bleibt der native von iOS.
class LiquidPageTransitionsBuilder extends PageTransitionsBuilder {
  const LiquidPageTransitionsBuilder();

  static const _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _cupertino.buildTransitions(route, context, animation, secondaryAnimation, LiquidBackground(child: child));
}

/// Ein Reiter der [LiquidTabBar].
@immutable
class LiquidTabItem {
  const LiquidTabItem({required this.icon, required this.label, this.badge});

  final IconData icon;
  final String label;

  /// Zahl am Symbol (z. B. neue Aufzeichnungen); 0 oder `null` blendet sie aus.
  final int? badge;
}

/// Schwebende Tab-Leiste aus Glas: Kapsel mit Unschärfe und Lichtkante, die Auswahl gleitet als leuchtende Pille mit
/// einer Feder zum gewählten Reiter.
class LiquidTabBar extends StatelessWidget {
  const LiquidTabBar({super.key, required this.items, required this.currentIndex, required this.onTap});

  final List<LiquidTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double height = 58;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liquid = LiquidTheme.of(context);
    final duration = LiquidMotion.of(context, LiquidMotion.medium);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, 2, LiquidSpacing.page, 0),
        child: LiquidSurface(
          radius: height / 2,
          strong: true,
          child: SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: duration,
                      curve: LiquidMotion.spring,
                      left: width * currentIndex + 5,
                      top: 5,
                      bottom: 5,
                      width: width - 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(LiquidRadii.pill),
                          color: scheme.primary.withValues(alpha: liquid.isDark ? 0.2 : 0.12),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.18), width: 0.5),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final (index, item) in items.indexed)
                          Expanded(
                            child: _LiquidTab(
                              item: item,
                              selected: index == currentIndex,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onTap(index);
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidTab extends StatelessWidget {
  const _LiquidTab({required this.item, required this.selected, required this.onTap});

  final LiquidTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Nicht gewählte Reiter kräftiger als `onSurfaceVariant` (Kontrast ≥ 4,5 : 1 auf dem Glas).
    final color = selected ? scheme.onPrimaryContainer : scheme.onSurface.withValues(alpha: 0.72);
    final duration = LiquidMotion.of(context, LiquidMotion.medium);
    final badge = item.badge ?? 0;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LiquidPressable(
          scale: 0.9,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 2,
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1,
                duration: duration,
                curve: LiquidMotion.spring,
                child: Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: color),
                    duration: duration,
                    builder: (context, color, _) => Icon(item.icon, size: 24, color: color),
                  ),
                ),
              ),
              AnimatedDefaultTextStyle(
                duration: duration,
                style: DefaultTextStyle.of(context).style.copyWith(
                  // 12 pt: Untergrenze des Designsystems (vorher 10,5 pt).
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.1,
                  color: color,
                ),
                // Große Schrift: lieber etwas kleiner als abgeschnitten (wie die Tab-Leiste von iOS).
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(item.label, maxLines: 1, softWrap: false)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fortschrittsbalken aus dem Liquid-Design: Pille mit leuchtendem Verlauf der Statusfarbe, die mit einer Feder auf
/// ihren Wert läuft. Ohne [color] in Akzentfarbe.
class LiquidProgressBar extends StatelessWidget {
  const LiquidProgressBar({super.key, required this.value, this.color, this.height = 6, this.semanticsLabel});

  final double value;
  final Color? color;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? Theme.of(context).colorScheme.primary;
    final target = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final radius = BorderRadius.circular(height / 2);
    return Semantics(
      label: semanticsLabel,
      value: '${(target * 100).round()} %',
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: LiquidTheme.of(context).track, borderRadius: radius),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: LiquidMotion.of(context, LiquidMotion.slow),
            curve: LiquidMotion.settle,
            builder: (context, fraction, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LiquidGradients.linear(color),
                  borderRadius: radius,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: height * 1.5)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
