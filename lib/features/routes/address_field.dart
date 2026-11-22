import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../services/routing/routing_providers.dart';
import '../../ui/liquid.dart';

/// Adresszeile für Start oder Ziel: Favoriten beim Antippen, Vorschläge beim Tippen (nach kurzer Pause, ab drei
/// Zeichen, nach Nähe sortiert), Eingabetaste sucht ausdrücklich (dann auch über Nominatim), Koordinaten
/// („52.52, 13.40“) gehen direkt. Der Stern speichert den gewählten Punkt als Favorit (bzw. entfernt ihn).
class AddressField extends ConsumerStatefulWidget {
  const AddressField({
    super.key,
    required this.hint,
    required this.icon,
    required this.color,
    required this.onSelected,
    this.value,
    this.point,
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

  /// Gewählter Punkt (für den Stern „als Favorit speichern“).
  final GeoPoint? point;

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
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

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
    setState(() {});
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
      final favorites = ref.read(routeStoreProvider).favoritesMatching(text);
      setState(() {
        _places = places;
        _problem = places.isEmpty && favorites.isEmpty && !typing
            ? 'Nichts gefunden. Versuche Straße und Ort, z. B. „Hauptstraße 5, Berlin“.'
            : null;
      });
      // Ausdrückliche Suche mit genau einem Treffer: gleich übernehmen.
      if (!typing && places.length == 1 && favorites.isEmpty) _choose(places.single);
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

  /// Stern: gewählten Punkt als Favorit speichern (mit Namen) bzw. wieder entfernen.
  Future<void> _toggleFavorite(GeoPoint point) async {
    final store = ref.read(routeStoreProvider);
    if (store.favoriteNear(point) case final existing?) {
      await store.deleteFavorite(existing.id);
      if (mounted) _say('„${existing.name}“ aus den Favoriten entfernt.');
      return;
    }
    final address = widget.value;
    final suggestion = address == null ? '' : address.split(', ').first;
    final name = await askFavoriteName(context, initial: suggestion);
    if (name == null || !mounted) return;
    await store.saveFavorite(
      FavoritePlace(id: const Uuid().v4(), name: name, point: point, createdAt: DateTime.now(), address: address),
    );
    if (mounted) _say('„$name“ als Favorit gespeichert.');
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final store = ref.watch(routeStoreProvider);
    // Favoriten zeigen, sobald das Feld aktiv ist (leer: alle, sonst passende).
    final favorites = _focus.hasFocus
        ? store.favoritesMatching(_controller.text).take(6).toList()
        : const <FavoritePlace>[];
    final point = widget.point;
    final isFavorite = point != null && store.favoriteNear(point) != null;
    final rows = <Widget>[
      if (_problem case final problem?)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(problem, style: TextStyle(fontSize: 13, color: secondary)),
        ),
      for (final favorite in favorites)
        ListTile(
          dense: true,
          leading: const Icon(Icons.star_rounded, color: Colors.amber),
          title: Text(favorite.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: favorite.address == null
              ? null
              : Text(favorite.address!, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: switch (GeocodingFormat.distanceLabel(favorite.place, widget.near)) {
            final distance? => Text(distance, style: TextStyle(fontSize: 12, color: secondary)),
            null => null,
          },
          onTap: () => _choose(favorite.place),
        ),
      for (final place in _places)
        ListTile(
          dense: true,
          leading: Icon(Icons.place_outlined, color: widget.color),
          title: Text(place.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: place.detail.isEmpty ? null : Text(place.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: switch (GeocodingFormat.distanceLabel(place, widget.near)) {
            final distance? => Text(distance, style: TextStyle(fontSize: 12, color: secondary)),
            null => null,
          },
          onTap: () => _choose(place),
        ),
    ];
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
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_controller.text.isNotEmpty && _focus.hasFocus)
                    IconButton(tooltip: 'Leeren', icon: const Icon(Icons.cancel, size: 18), onPressed: _clear),
                  if (point != null && !_focus.hasFocus)
                    IconButton(
                      tooltip: isFavorite ? 'Aus Favoriten entfernen' : 'Als Favorit speichern',
                      icon: Icon(
                        isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: isFavorite ? Colors.amber : secondary,
                      ),
                      onPressed: widget.enabled ? () => unawaited(_toggleFavorite(point)) : null,
                    ),
                ],
              ),
            ),
          ),
        ),
        LiquidSwitcher(
          child: rows.isEmpty
              ? const SizedBox.shrink(key: ValueKey('leer'))
              : Padding(
                  key: ValueKey('${favorites.length}${_places.map((place) => place.label).join()}${_problem ?? ''}'),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: LiquidSurface(
                    radius: LiquidRadii.inner,
                    shadow: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, row) in rows.indexed) ...[
                          if (index > 0) const Divider(height: 0.5, thickness: 0.5, indent: 48),
                          row,
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

/// Name für einen Favoriten erfragen (z. B. „Zuhause“, „Hundewiese“); `null` bei Abbruch.
Future<String?> askFavoriteName(BuildContext context, {String initial = ''}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _FavoriteNameDialog(initial: initial),
  );
  return name == null || name.isEmpty ? null : name;
}

/// Eigenes Widget, damit das Textfeld erst nach dem Ausblenden des Dialogs freigegeben wird.
class _FavoriteNameDialog extends StatefulWidget {
  const _FavoriteNameDialog({required this.initial});

  final String initial;

  @override
  State<_FavoriteNameDialog> createState() => _FavoriteNameDialogState();
}

class _FavoriteNameDialogState extends State<_FavoriteNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Als Favorit speichern'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(hintText: 'z. B. Zuhause, Hundewiese, Treffpunkt'),
      onSubmitted: (text) => Navigator.pop(context, text.trim()),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Speichern')),
    ],
  );
}
