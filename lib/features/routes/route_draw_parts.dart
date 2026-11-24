part of 'route_draw_screen.dart';

class _ToolSwitch extends StatelessWidget {
  const _ToolSwitch({required this.tool, required this.onChanged});

  final DrawTool tool;
  final ValueChanged<DrawTool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: LiquidSurface(
      radius: LiquidRadii.pill,
      strong: true,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<DrawTool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide.none),
          segments: const [
            ButtonSegment(value: DrawTool.points, icon: Icon(Icons.touch_app_outlined), label: Text('Punkte')),
            ButtonSegment(value: DrawTool.freehand, icon: Icon(Icons.gesture), label: Text('Zeichnen')),
          ],
          selected: {tool},
          onSelectionChanged: (selection) => onChanged(selection.single),
        ),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: LiquidSurface(
      radius: LiquidRadii.pill,
      strong: true,
      shadow: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppText.footnote(context).copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    ),
  );
}

/// Schwebende Glasleiste: Live-Werte und Werkzeuge.
class _TelemetryBar extends StatelessWidget {
  const _TelemetryBar({
    required this.distance,
    required this.ascent,
    required this.duration,
    required this.pendingMeters,
    required this.busy,
    required this.surroundings,
    required this.followPaths,
    required this.onToggleFollow,
    required this.onUndo,
    required this.onClose,
    required this.onReset,
    required this.onSave,
  });

  final double distance;
  final double? ascent;
  final Duration duration;
  final double? pendingMeters;
  final bool busy;
  final String surroundings;

  /// Neue Abschnitte auf Wegen (sonst Luftlinie).
  final bool followPaths;
  final VoidCallback? onToggleFollow;
  final VoidCallback? onUndo;
  final VoidCallback? onClose;
  final VoidCallback? onReset;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => LiquidCard(
    strong: true,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Semantics(
          liveRegion: true,
          label:
              'Distanz ${RouteFormat.distance(distance)}, '
              '${ascent == null ? 'Höhe unbekannt' : 'Anstieg ${RouteFormat.elevation(ascent!)}'}, '
              'Dauer ${RouteFormat.duration(duration)}',
          excludeSemantics: true,
          child: Row(
            children: [
              Expanded(
                child: _Value(
                  value: RouteFormat.distance(distance),
                  label: pendingMeters == null ? 'Distanz' : '+ ${RouteFormat.distance(pendingMeters!)} Entwurf',
                ),
              ),
              Expanded(
                child: _Value(value: ascent == null ? '–' : '↑ ${ascent!.round()} hm', label: 'Anstieg'),
              ),
              Expanded(
                child: _Value(value: RouteFormat.duration(duration), label: 'geschätzt'),
              ),
              if (busy) const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ],
          ),
        ),
        Text(surroundings, style: LiquidText.label(context), maxLines: 1, overflow: TextOverflow.ellipsis),
        Row(
          children: [
            IconButton(tooltip: 'Rückgängig', onPressed: onUndo, icon: const Icon(Icons.undo)),
            IconButton(tooltip: 'Rundweg schließen', onPressed: onClose, icon: const Icon(Icons.loop)),
            IconButton(tooltip: 'Zurücksetzen', onPressed: onReset, icon: const Icon(Icons.delete_sweep_outlined)),
            IconButton(
              tooltip: followPaths ? 'Nächste Punkte als Luftlinie verbinden' : 'Nächste Punkte wieder auf Wegen',
              isSelected: !followPaths,
              onPressed: onToggleFollow,
              icon: const Icon(Icons.straight),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onSave,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Icon(Icons.bookmark_add_outlined, size: 18),
                      Flexible(child: Text('Speichern', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Value extends StatelessWidget {
  const _Value({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: LiquidText.kpi(context, size: 20)),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: LiquidText.label(context)),
    ],
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.icon, this.selected = false});

  final Color color;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: selected ? AppPalette.amber : AppPalette.onColor, width: selected ? 3 : 2),
      boxShadow: const [BoxShadow(color: AppPalette.mapShadowStrong, blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 16, color: AppPalette.onColor),
    ),
  );
}

/// Griff eines Wegpunkts (gewählt: größer, gelber Rand).
class _Handle extends StatelessWidget {
  const _Handle({required this.color, required this.selected});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppPalette.onColor,
      shape: BoxShape.circle,
      border: Border.all(color: selected ? AppPalette.amber : color, width: selected ? 4 : 3),
      boxShadow: const [BoxShadow(color: AppPalette.mapShadowStrong, blurRadius: 4, offset: Offset(0, 1))],
    ),
  );
}

/// Werkzeuge für den gewählten Wegpunkt.
class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.label,
    required this.moving,
    required this.direct,
    required this.onToggleDirect,
    required this.onMove,
    required this.onDelete,
    required this.onDone,
  });

  final String label;
  final bool moving;

  /// Abschnitt bis zu diesem Punkt als Luftlinie (`null` beim Start).
  final bool? direct;
  final VoidCallback? onToggleDirect;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => LiquidSurface(
    radius: LiquidRadii.pill,
    strong: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: moving ? 'Verschieben abbrechen' : 'Punkt verschieben',
            isSelected: moving,
            onPressed: onMove,
            icon: const Icon(Icons.open_with),
          ),
          if (direct != null)
            IconButton(
              tooltip: direct! ? 'Abschnitt bis hier wieder auf Wege legen' : 'Abschnitt bis hier als Luftlinie',
              isSelected: direct,
              onPressed: onToggleDirect,
              icon: const Icon(Icons.straight),
            ),
          IconButton(tooltip: 'Punkt löschen', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
          IconButton(tooltip: 'Fertig', onPressed: onDone, icon: const Icon(Icons.check)),
        ],
      ),
    ),
  );
}
