import 'package:flutter/material.dart';

/// Große Überschrift der Hauptseiten wie `navigationTitle` in SwiftUI (Anzeige „large“): Der Titel steht groß über
/// dem Inhalt und rollt mit; ist er weggerollt, erscheint er klein in der Leiste.
class LargeTitleScope extends StatefulWidget {
  const LargeTitleScope({super.key, required this.child});

  final Widget child;

  @override
  State<LargeTitleScope> createState() => _LargeTitleScopeState();
}

class _LargeTitleScopeState extends State<LargeTitleScope> {
  final _collapsed = ValueNotifier(false);

  /// Ab dieser Rollweite ist die große Überschrift unter der Leiste verschwunden.
  static const _threshold = 36.0;

  @override
  void dispose() {
    _collapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
        _collapsed.value = notification.metrics.pixels > _threshold;
      }
      return false;
    },
    child: _CollapsedNotifier(notifier: _collapsed, child: widget.child),
  );
}

class _CollapsedNotifier extends InheritedNotifier<ValueNotifier<bool>> {
  const _CollapsedNotifier({required super.notifier, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CollapsedNotifier>()?.notifier?.value ?? true;
}

/// Kleiner Titel in der Leiste: nur sichtbar, wenn die große Überschrift weggerollt ist.
class CollapsingTitle extends StatelessWidget {
  const CollapsingTitle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _CollapsedNotifier.of(context) ? 1 : 0,
    duration: const Duration(milliseconds: 150),
    child: child,
  );
}

/// Große Überschrift über dem Inhalt (34 pt, fett). Mit [collapsible] klappt sie beim Rollen weg – für Seiten, deren
/// Überschrift nicht selbst mitrollt.
class LargeTitleHeader extends StatelessWidget {
  const LargeTitleHeader(this.title, {super.key, this.collapsible = false});

  final String title;
  final bool collapsible;

  @override
  Widget build(BuildContext context) {
    final header = Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
      ),
    );
    if (!collapsible) return Align(alignment: Alignment.centerLeft, child: header);
    final collapsed = _CollapsedNotifier.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topLeft,
      child: collapsed ? const SizedBox(width: double.infinity) : Align(alignment: Alignment.centerLeft, child: header),
    );
  }
}
