import 'dart:math' as math;
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';

part 'body_map_art.dart';

/// Fläche aus der Zeichnung (Umriss, Haut); [mirror]: nur links gezeichnet, rechts gespiegelt.
final class _ArtShape {
  const _ArtShape(this.data, {this.mirror = false, this.lines = const []});

  final String data;
  final bool mirror;
  final List<String> lines;
}

/// Faserrichtung: parallel unter einem Winkel oder strahlenförmig von einem Punkt (Sehnenansatz).
final class _Fibre {
  const _Fibre.angle(double degrees) : angle = degrees, x = null, y = null;
  const _Fibre.fan(double this.x, double this.y) : angle = null;

  final double? angle;
  final double? x;
  final double? y;
}

/// Ein gezeichneter Muskel; [muscle] null heißt: ohne eigenen Wert, immer grau.
final class _ArtMuscle {
  const _ArtMuscle(
    this.name,
    this.muscle,
    this.data, {
    this.fibre,
    this.mirror = true,
    this.plain = false,
    this.lines = const [],
  });

  final String name;
  final Muscle? muscle;
  final String data;
  final _Fibre? fibre;
  final bool mirror;

  /// Knochen und Sehnen: flach, ohne Fasern.
  final bool plain;
  final List<String> lines;
}

/// Ansicht der Körperkarte.
enum BodySide {
  front('Vorderseite'),
  back('Rückseite');

  const BodySide(this.label);

  final String label;
}

/// Zeichenfläche der Vektordaten (`tool/body_map_art.py`).
const _artWidth = 200.0;
const _artHeight = 400.0;

/// Spiegelung an der Körpermitte (x → 200 − x).
final _mirror = Float64List.fromList([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, _artWidth, 0, 0, 1]);

/// Liest die Pfade der Zeichnung (nur absolute M, L, C, Z – so schreibt sie das Werkzeug).
Path _parse(String data) {
  final path = Path();
  final tokens = RegExp(r'[MLCZ]|-?\d*\.?\d+').allMatches(data).map((match) => match.group(0)!).toList();
  var index = 0;
  double next() => double.parse(tokens[index++]);
  while (index < tokens.length) {
    switch (tokens[index++]) {
      case 'M':
        path.moveTo(next(), next());
      case 'L':
        path.lineTo(next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
      case 'Z':
        path.close();
    }
  }
  return path;
}

/// Fasern als Linien in Zeichnungskoordinaten (werden auf den Muskel beschnitten).
Path _fibres(_Fibre fibre, Rect bounds) {
  final path = Path();
  final reach = bounds.longestSide;
  if (fibre.angle case final angle?) {
    final radians = angle * math.pi / 180;
    final direction = Offset(math.cos(radians), math.sin(radians));
    final normal = Offset(-direction.dy, direction.dx);
    final center = bounds.center;
    for (var offset = -reach; offset <= reach; offset += 1.6) {
      final base = center + normal * offset;
      path
        ..moveTo((base - direction * reach).dx, (base - direction * reach).dy)
        ..lineTo((base + direction * reach).dx, (base + direction * reach).dy);
    }
  } else {
    final focus = Offset(fibre.x!, fibre.y!);
    final length = (bounds.center - focus).distance + reach;
    for (var degrees = 0; degrees < 360; degrees += 5) {
      final radians = degrees * math.pi / 180;
      final end = focus + Offset(math.cos(radians), math.sin(radians)) * length;
      path
        ..moveTo(focus.dx, focus.dy)
        ..lineTo(end.dx, end.dy);
    }
  }
  return path;
}

/// Vorbereitete Geometrie einer Fläche (je Seite einmal, gespiegelt bei Bedarf).
final class _Piece {
  _Piece(this.muscle, this.path, this.fibres, this.lines, {required this.plain});

  final Muscle? muscle;
  final Path path;
  final Path? fibres;
  final List<Path> lines;
  final bool plain;
}

List<_Piece> _pieces(List<_ArtMuscle> art) => [
  for (final item in art)
    for (final flip in item.mirror ? [false, true] : [false])
      () {
        Path place(Path path) => flip ? path.transform(_mirror) : path;
        final path = place(_parse(item.data));
        return _Piece(
          item.muscle,
          path,
          item.fibre == null ? null : place(_fibres(item.fibre!, _parse(item.data).getBounds())),
          [for (final line in item.lines) place(_parse(line))],
          plain: item.plain,
        );
      }(),
];

List<Path> _shapes(List<_ArtShape> art) => [
  for (final item in art)
    for (final flip in item.mirror ? [false, true] : [false])
      flip ? _parse(item.data).transform(_mirror) : _parse(item.data),
];

/// Geometrie einmal je App-Lauf.
final class _Art {
  _Art._();

  static final instance = _Art._();

  late final silhouette = _shapes(_silhouette);
  late final skin = [
    for (final item in _skin)
      for (final flip in item.mirror ? [false, true] : [false])
        (
          path: flip ? _parse(item.data).transform(_mirror) : _parse(item.data),
          lines: [for (final line in item.lines) flip ? _parse(line).transform(_mirror) : _parse(line)],
        ),
  ];
  late final hair = _parse(_hair);
  late final front = _pieces(_front);
  late final back = _pieces(_back);

  List<_Piece> side(BodySide side) => side == BodySide.front ? front : back;
}

/// Muskeln, die auf einer Seite zu sehen sind.
Set<Muscle> bodySideMuscles(BodySide side) => {
  for (final item in side == BodySide.front ? _front : _back) ?item.muscle,
};

/// Streckt den runden Verlauf auf die Form des Muskels (sonst wären lange Muskeln an den Enden zu dunkel).
final class _Stretch extends GradientTransform {
  const _Stretch();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    if (bounds.shortestSide <= 0) return null;
    final center = bounds.center;
    return Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(bounds.width / bounds.shortestSide, bounds.height / bounds.shortestSide, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }
}

/// Farben der Zeichnung für hell und dunkel.
final class _Palette {
  const _Palette({
    required this.outline,
    required this.groove,
    required this.light,
    required this.shade,
    required this.skinLight,
    required this.skinShade,
    required this.hair,
    required this.ink,
  });

  factory _Palette.of(Brightness brightness) => brightness == Brightness.dark
      ? const _Palette(
          outline: Color(0xFF0A0A0A),
          groove: Color(0xFF2C2C2E),
          light: Color(0xFF8E8E93),
          shade: Color(0xFF48484A),
          skinLight: Color(0xFF9A9A9E),
          skinShade: Color(0xFF5A5A5E),
          hair: Color(0xFF3A3A3C),
          ink: Color(0xFF000000),
        )
      : const _Palette(
          outline: Color(0xFF2A2A2A),
          groove: Color(0xFFC4C4C4),
          light: Color(0xFFEFEFEF),
          shade: Color(0xFFABABAB),
          skinLight: Color(0xFFF3F3F3),
          skinShade: Color(0xFFCBCBCB),
          hair: Color(0xFF8A8A8A),
          ink: Color(0xFF1E1E1E),
        );

  final Color outline;
  final Color groove;
  final Color light;
  final Color shade;
  final Color skinLight;
  final Color skinShade;
  final Color hair;
  final Color ink;
}

/// Zeichnet eine Seite der anatomischen Figur; [color] liefert die Farbe je Muskel (null = grau).
class _FigurePainter extends CustomPainter {
  _FigurePainter({required this.side, required this.palette, required this.color, required this.signature});

  final BodySide side;
  final _Palette palette;
  final Color? Function(Muscle muscle) color;

  /// Werte und Farben als Vergleich für [shouldRepaint].
  final String signature;

  Shader _shading(Rect bounds, Color light, Color shade) => RadialGradient(
    center: const Alignment(0, -0.1),
    radius: 0.62,
    colors: [light, shade],
    transform: const _Stretch(),
  ).createShader(bounds);

  @override
  void paint(Canvas canvas, Size size) {
    final art = _Art.instance;
    final scale = math.min(size.width / _artWidth, size.height / _artHeight);
    canvas
      ..save()
      ..translate((size.width - _artWidth * scale) / 2, (size.height - _artHeight * scale) / 2)
      ..scale(scale);

    // Umriss: alle Teile breit umrandet, dann gefüllt – übrig bleibt nur die Außenkante.
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = palette.outline;
    final groove = Paint()..color = palette.groove;
    for (final path in art.silhouette) {
      canvas.drawPath(path, outline);
    }
    for (final path in art.silhouette) {
      canvas.drawPath(path, groove);
    }

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.45
      ..color = palette.ink.withValues(alpha: 0.55);
    final detail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = palette.ink.withValues(alpha: 0.35);
    final fibre = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.35
      ..color = palette.ink.withValues(alpha: 0.16);

    for (final skin in art.skin) {
      final bounds = skin.path.getBounds();
      canvas
        ..drawPath(skin.path, Paint()..shader = _shading(bounds, palette.skinLight, palette.skinShade))
        ..drawPath(skin.path, edge);
      for (final line in skin.lines) {
        canvas.drawPath(line, detail);
      }
    }
    if (side == BodySide.back) {
      canvas
        ..drawPath(art.hair, Paint()..color = palette.hair)
        ..drawPath(art.hair, edge);
    }

    for (final piece in art.side(side)) {
      final bounds = piece.path.getBounds();
      if (piece.plain) {
        canvas.drawPath(piece.path, Paint()..shader = _shading(bounds, palette.skinLight, palette.skinShade));
      } else {
        canvas.drawPath(piece.path, Paint()..shader = _shading(bounds, palette.light, palette.shade));
        final tint = piece.muscle == null ? null : color(piece.muscle!);
        if (tint != null) {
          final strong = Color.lerp(tint.withValues(alpha: 1), Colors.black, 0.18)!.withValues(alpha: tint.a);
          final soft = Color.lerp(tint.withValues(alpha: 1), Colors.white, 0.18)!.withValues(alpha: tint.a);
          canvas.drawPath(piece.path, Paint()..shader = _shading(bounds, soft, strong));
        }
        if (piece.fibres case final fibres?) {
          canvas
            ..save()
            ..clipPath(piece.path)
            ..drawPath(fibres, fibre)
            ..restore();
        }
      }
      for (final line in piece.lines) {
        canvas.drawPath(line, detail);
      }
      canvas.drawPath(piece.path, edge);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FigurePainter old) =>
      old.side != side || old.signature != signature || old.palette.groove != palette.groove;
}

/// Anatomische Körperkarte (vorn und hinten zum Blättern) mit Farbe je Muskel: grau = nicht beansprucht, gelb bis
/// rot = mehr. Eigene Zeichnung; die Zuordnung der Muskeln bleibt eine Übersicht (Port von `BodyMapView`).
class BodyMap extends StatefulWidget {
  const BodyMap({super.key, required this.values, required this.full, this.colors = const {}, this.height = 320});

  /// Wert je Muskel; ab [full] volle Farbe.
  final Map<Muscle, double> values;
  final double full;

  /// Eigene Farbe je Muskel (z. B. Regeneration); überschreibt die Heatmap-Farbe.
  final Map<Muscle, Color> colors;

  /// Höhe der Figur.
  final double height;

  /// Gelb → Orange → Rot je nach Anteil an [full]; ohne Last null (grau).
  static Color? heat(double value, {required double full}) {
    final level = MuscleLoad.intensity(value, full: full);
    if (level <= 0) return null;
    return HSVColor.fromAHSV(0.55 + 0.45 * level, 360 * (0.15 - 0.15 * level), 0.85, 0.95).toColor();
  }

  /// Seite mit mehr Last zuerst (Zugübungen zeigen den Rücken). Es zählen nur Muskeln, die allein auf einer Seite zu
  /// sehen sind – Schultern, Arme und Waden sind auf beiden.
  static BodySide preferredSide(Map<Muscle, double> values, double full) {
    final front = bodySideMuscles(BodySide.front);
    final back = bodySideMuscles(BodySide.back);
    double load(Set<Muscle> muscles) =>
        muscles.fold(0.0, (sum, muscle) => sum + MuscleLoad.intensity(values[muscle] ?? 0, full: full));
    return load(back.difference(front)) > load(front.difference(back)) ? BodySide.back : BodySide.front;
  }

  @override
  State<BodyMap> createState() => _BodyMapState();
}

class _BodyMapState extends State<BodyMap> {
  late BodySide _side = BodyMap.preferredSide(widget.values, widget.full);
  late final PageController _pages = PageController(initialPage: _side.index);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  String get _semantics {
    final shown = widget.values.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final prefix = 'Muskelkarte, ${_side.label}';
    if (shown.isEmpty) return '$prefix: keine Muskeln beansprucht';
    return '$prefix: ${[for (final entry in shown) '${entry.key.label} ${GermanFormat.decimal(entry.value)} Sätze'].join(', ')}';
  }

  void _show(BodySide side) =>
      _pages.animateToPage(side.index, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  Color? _color(Muscle muscle) => widget.colors[muscle] ?? BodyMap.heat(widget.values[muscle] ?? 0, full: widget.full);

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(Theme.of(context).brightness);
    final signature = [for (final muscle in Muscle.values) '${_color(muscle)?.toARGB32() ?? 0}'].join(',');
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget chevron(BodySide target, IconData icon, Alignment alignment) => Align(
      alignment: alignment,
      child: IconButton(
        tooltip: '${target.label} zeigen',
        icon: Icon(icon, color: secondary.withValues(alpha: 0.7)),
        onPressed: () => _show(target),
      ),
    );
    return Semantics(
      label: _semantics,
      hint: 'Wischen für ${_side == BodySide.front ? BodySide.back.label : BodySide.front.label}',
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            ExcludeSemantics(
              child: PageView(
                controller: _pages,
                onPageChanged: (index) => setState(() => _side = BodySide.values[index]),
                children: [
                  for (final side in BodySide.values)
                    CustomPaint(
                      painter: _FigurePainter(side: side, palette: palette, color: _color, signature: signature),
                      size: Size.infinite,
                    ),
                ],
              ),
            ),
            if (_side == BodySide.front)
              chevron(BodySide.back, Icons.chevron_right, Alignment.centerRight)
            else
              chevron(BodySide.front, Icons.chevron_left, Alignment.centerLeft),
          ],
        ),
      ),
    );
  }
}
