import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/routing/routing_providers.dart';
import '../../ui/liquid.dart';

/// Adresszeile für Start oder Ziel: Vorschläge beim Tippen (nach kurzer Pause, ab drei Zeichen, nach Nähe sortiert),
/// Eingabetaste sucht ausdrücklich (dann auch über Nominatim), Koordinaten („52.52, 13.40“) gehen direkt.
class AddressField extends ConsumerStatefulWidget {
  const AddressField({
    super.key,
    required this.hint,
    required this.icon,
    required this.color,
    required this.onSelected,
    this.value,
    this.near,
    this.enabled = true,
    this.autofocus = false,
  });

  final String hint;
  final IconData icon;
  final Color color;
  final ValueChanged<Place> onSelected;

  /// Angezeigte Adresse des gewählten Punkts (`null`: Punkt kam von Karte oder Standort).
  final String? value;

  /// Bevorzugt Treffer in der Nähe (Start, Kartenmitte).
  final GeoPoint? near;
  final bool enabled;
  final bool autofocus;

  /// Pause nach dem letzten Tastendruck, bevor gesucht wird.
  static const debounce = Duration(milliseconds: 450);

  @override
  ConsumerState<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends ConsumerState<AddressField> {
  late final _controller = TextEditingController(text: widget.value ?? '');
  final _focus = FocusNode();
  Timer? _timer;
  int _generation = 0;
  List<Place> _places = const [];
  bool _searching = false;
  String? _problem;

  @override
  void didUpdateWidget(AddressField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && !_focus.hasFocus) _controller.text = widget.value ?? '';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _timer?.cancel();
    if (GeocodingFormat.normalized(text) == null && GeocodingFormat.coordinates(text) == null) {
      setState(() {
        _places = const [];
        _problem = null;
        _searching = false;
      });
      return;
    }
    _timer = Timer(AddressField.debounce, () => unawaited(_search(text, typing: true)));
  }

  Future<void> _search(String text, {required bool typing}) async {
    _timer?.cancel();
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _problem = null;
    });
    try {
      final places = await ref.read(placeSearchProvider).search(text, near: widget.near, typing: typing);
      if (!mounted || generation != _generation) return;
      setState(() {
        _places = places;
        _problem = places.isEmpty && !typing
            ? 'Nichts gefunden. Versuche Straße und Ort, z. B. „Hauptstraße 5, Berlin“.'
            : null;
      });
      // Ausdrückliche Suche mit genau einem Treffer: gleich übernehmen.
      if (!typing && places.length == 1) _choose(places.single);
    } on RoutingUnavailable catch (error) {
      if (mounted && generation == _generation) setState(() => _problem = error.message);
    } finally {
      if (mounted && generation == _generation) setState(() => _searching = false);
    }
  }

  void _choose(Place place) {
    unawaited(HapticFeedback.selectionClick());
    _timer?.cancel();
    _generation++;
    _controller.text = place.label;
    setState(() {
      _places = const [];
      _problem = null;
      _searching = false;
    });
    _focus.unfocus();
    widget.onSelected(place);
  }

  void _clear() {
    _timer?.cancel();
    _generation++;
    _controller.clear();
    setState(() {
      _places = const [];
      _problem = null;
      _searching = false;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.streetAddress,
            autocorrect: false,
            onChanged: _changed,
            onSubmitted: (text) => unawaited(_search(text, typing: false)),
            decoration: InputDecoration(
              hintText: widget.hint,
              border: InputBorder.none,
              prefixIcon: Icon(widget.icon, color: widget.color),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (_controller.text.isEmpty
                        ? null
                        : IconButton(tooltip: 'Leeren', icon: const Icon(Icons.cancel, size: 18), onPressed: _clear)),
            ),
          ),
        ),
        LiquidSwitcher(
          child: _places.isEmpty && _problem == null
              ? const SizedBox.shrink(key: ValueKey('leer'))
              : Padding(
                  key: ValueKey(_places.map((place) => place.label).join() + (_problem ?? '')),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: LiquidSurface(
                    radius: LiquidRadii.inner,
                    shadow: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_problem case final problem?)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(problem, style: TextStyle(fontSize: 13, color: secondary)),
                          ),
                        for (final (index, place) in _places.indexed) ...[
                          if (index > 0) const Divider(height: 0.5, thickness: 0.5, indent: 48),
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.place_outlined, color: widget.color),
                            title: Text(place.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: place.detail.isEmpty
                                ? null
                                : Text(place.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: switch (GeocodingFormat.distanceLabel(place, widget.near)) {
                              final distance? => Text(distance, style: TextStyle(fontSize: 12, color: secondary)),
                              null => null,
                            },
                            onTap: () => _choose(place),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
