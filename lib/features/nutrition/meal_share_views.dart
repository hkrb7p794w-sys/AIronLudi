import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repositories/meal_repository.dart';
import '../../data/storage.dart';
import '../../services/ai/ai_client.dart';
import '../../services/nutrition/meal_share_service.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import 'nutrition_controller.dart';

String _errorText(Object error) => error is AIClientError ? error.message : '$error';

/// Teilen einer Mahlzeit: legt den Code an und bietet die Nachricht zum Weitergeben an (Port von `ShareMealSheet`).
class ShareMealScreen extends ConsumerStatefulWidget {
  const ShareMealScreen({super.key, required this.title, required this.items});

  final String title;
  final List<MealItem> items;

  @override
  ConsumerState<ShareMealScreen> createState() => _ShareMealScreenState();
}

class _ShareMealScreenState extends ConsumerState<ShareMealScreen> {
  late final SharedMeal _meal = SharedMeal(title: widget.title, items: widget.items);
  MealShareCreated? _created;
  String? _error;
  bool _revoked = false;

  MealShareService get _service => ref.read(mealShareServiceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_create());
  }

  Future<void> _create() async {
    try {
      final created = await _service.share(_meal);
      if (mounted) setState(() => _created = created);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = _created;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mahlzeit teilen'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        children: [
          FormSection(
            footer:
                'Geteilt werden nur Titel, Mengen und Nährwerte – kein Name, kein Datum, keine Gesundheitsdaten. '
                'Abrufen kann nur, wer AIronLudi über denselben Zugang nutzt.',
            children: [
              ListTile(
                title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${_meal.items.length} Positionen · ${_meal.kilocalories.round()} kcal'),
              ),
            ],
          ),
          if (created != null && !_revoked)
            FormSection(
              footer: 'Gültig 7 Tage. Zurückziehen löscht die Mahlzeit sofort beim Worker.',
              children: [
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Nachricht teilen'),
                  onTap: () => SharePlus.instance.share(
                    ShareParams(
                      text: MealShare.message(
                        title: widget.title,
                        kilocalories: _meal.kilocalories,
                        link: _service.link(created.code),
                        code: created.code,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Code'),
                  trailing: SelectableText(created.code),
                  onLongPress: () => Clipboard.setData(ClipboardData(text: created.code)),
                ),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: const Text('Freigabe zurückziehen', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    try {
                      await _service.revoke(created.code);
                    } on Object {
                      // Wie in Swift: Fehler beim Zurückziehen werden nicht gemeldet.
                    }
                    if (mounted) setState(() => _revoked = true);
                  },
                ),
              ],
            )
          else if (_revoked)
            FormSection(
              children: [
                ListTile(
                  title: Text('Freigabe zurückgezogen.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            )
          else if (_error case final error?)
            FormSection(
              children: [
                ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.orange),
                  title: Text(error, style: const TextStyle(color: Colors.orange)),
                ),
              ],
            )
          else
            const FormSection(
              children: [
                ListTile(
                  leading: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text('Freigabe wird erstellt …'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Empfangene Mahlzeit: Vorschau und Übernahme als neuer Eintrag (nie überschreibend) oder als Favorit.
class ReceivedMealScreen extends ConsumerStatefulWidget {
  const ReceivedMealScreen({super.key, this.code, this.preloaded});

  final String? code;

  /// Aus dem Feed: Mahlzeit liegt schon vor, kein Code nötig.
  final SharedMeal? preloaded;

  @override
  ConsumerState<ReceivedMealScreen> createState() => _ReceivedMealScreenState();
}

class _ReceivedMealScreenState extends ConsumerState<ReceivedMealScreen> {
  final _input = TextEditingController();
  SharedMeal? _meal;
  String? _error;
  MealCategory _category = NutritionController.category(DateTime.now());
  String? _done;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _meal = widget.preloaded;
    if (_meal == null && widget.code != null) unawaited(_load(widget.code!));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load(String text) async {
    final code = MealShare.code(text);
    if (code == null) return;
    try {
      final meal = await ref.read(mealShareServiceProvider).fetch(code);
      if (mounted) {
        setState(() {
          _meal = meal;
          _error = null;
        });
      }
    } on AIHttpError catch (error) {
      if (mounted) setState(() => _error = error.status == 404 ? 'Code unbekannt oder abgelaufen.' : error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  /// Immer ein neuer Eintrag – vorhandene Mahlzeiten bleiben unberührt.
  Future<void> _addToDiary(SharedMeal meal) async {
    await ref
        .read(mealRepositoryProvider)
        .save(
          StoredMeal(
            day: CalendarDay.today(),
            createdAt: DateTime.now(),
            category: _category,
            title: meal.title,
            hint: 'Geteilt',
            items: meal.mealItems,
          ),
        );
    if (mounted) setState(() => _done = 'Eingetragen unter ${_category.label}.');
  }

  void _addFavorite(SharedMeal meal) {
    final settings = ref.read(coachSettingsProvider);
    settings.favoriteMeals = [
      ...settings.favoriteMeals,
      FavoriteMeal(title: meal.title, items: meal.mealItems, category: _category),
    ];
    setState(() => _done = 'Als Favorit gespeichert.');
  }

  @override
  Widget build(BuildContext context) {
    final meal = _meal;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geteilte Mahlzeit'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        children: [
          if (meal == null)
            FormSection(
              footer: 'Code oder Link aus der Nachricht einfügen.',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _input,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(hintText: 'Code, z. B. k7m2q9xa4b'),
                  ),
                ),
                ListTile(
                  title: const Text('Öffnen'),
                  enabled: MealShare.code(_input.text) != null,
                  onTap: () => _load(_input.text),
                ),
                if (_error case final error?)
                  ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.orange),
                    title: Text(error, style: const TextStyle(color: Colors.orange)),
                  ),
              ],
            ),
          if (meal != null) ...[
            FormSection(
              header: '${meal.title} · ${meal.kilocalories.round()} kcal',
              footer: 'Mengen und Nährwerte so, wie sie geteilt wurden – nach dem Übernehmen kannst du alles anpassen.',
              children: [
                for (final item in meal.mealItems)
                  LabeledRow(
                    label: item.name,
                    value:
                        '${GermanFormat.number(item.grams.roundToDouble())} ${item.isDrink ? 'ml' : 'g'} · '
                        '${(item.amounts[Nutrient.kcal] ?? 0).round()} kcal',
                  ),
              ],
            ),
            FormSection(
              children: [
                ListTile(
                  title: const Text('Mahlzeit'),
                  trailing: DropdownButton<MealCategory>(
                    value: _category,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final category in MealCategory.values)
                        DropdownMenuItem(value: category, child: Text(category.label)),
                    ],
                    onChanged: (category) => setState(() => _category = category ?? _category),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle),
                  title: const Text('In mein Tagebuch (heute)'),
                  enabled: _done == null,
                  onTap: () => _addToDiary(meal),
                ),
                ListTile(
                  leading: const Icon(Icons.star_border),
                  title: const Text('Als Favorit merken'),
                  enabled: _done == null,
                  onTap: () => _addFavorite(meal),
                ),
                if (_done case final done?)
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                    title: Text(done, style: const TextStyle(color: Colors.green)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
