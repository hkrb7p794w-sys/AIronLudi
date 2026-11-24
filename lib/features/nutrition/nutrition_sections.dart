part of 'nutrition_screen.dart';

/// Abschnitte und Aktionen der Ernährungsseite: Aktionen je Mahlzeit, Warteschlange, Check-in, KI-Auswertung, Suche.
extension _NutritionSections on _NutritionScreenState {
  Future<void> _mealActions(StoredMeal meal) async {
    final settings = ref.read(coachSettingsProvider);
    final favorite = MealShortcuts.favorite(meal.items, favorites: settings.favoriteMeals);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('Erneut eintragen'),
              onTap: () {
                Navigator.of(sheet).pop();
                _after(_controller.repeatMeal(meal));
              },
            ),
            for (final target in MealCategory.values.where((category) => category != meal.category))
              ListTile(
                leading: const Icon(Icons.swap_vert),
                title: Text('Verschieben nach ${target.label}'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _after(_controller.move(meal, target));
                },
              ),
            ListTile(
              leading: const Icon(Icons.pie_chart_outline),
              title: const Text('Gegessene Menge anpassen'),
              onTap: () {
                Navigator.of(sheet).pop();
                _controller.edit(meal);
              },
            ),
            if (favorite != null)
              ListTile(
                leading: const Icon(Icons.star_border),
                title: const Text('Aus Favoriten entfernen'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  settings.favoriteMeals = settings.favoriteMeals.where((other) => other.id != favorite.id).toList();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text('Als Favorit merken'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  settings.favoriteMeals = [
                    ...settings.favoriteMeals,
                    FavoriteMeal(title: meal.title, items: meal.items, category: meal.category),
                  ];
                },
              ),
            if (ref.read(aiClientProvider).isConfigured)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Teilen …'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _push((_) => ShareMealScreen(title: meal.title, items: meal.items), fullscreen: true);
                },
              ),
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: const Text('Als eigenes Rezept speichern'),
              onTap: () async {
                Navigator.of(sheet).pop();
                final save = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Als eigenes Rezept speichern'),
                    content: const Text(
                      'Unter „Eigene Rezepte“ kannst du Portionen und gekochtes Gewicht für Meal-Prep festlegen.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Abbrechen')),
                      TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Speichern')),
                    ],
                  ),
                );
                if (save ?? false) {
                  settings.ownRecipes = [...settings.ownRecipes, OwnRecipe.fromMeal(meal.title, meal.items)];
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.of(context).alert),
              title: Text('Löschen', style: TextStyle(color: AppColors.of(context).alert)),
              onTap: () {
                Navigator.of(sheet).pop();
                _after(_controller.delete(meal));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingSection() => FormSection(
    header: 'Wartet auf Netz',
    footer: 'Ohne Netz gespeichert. Wird automatisch ausgewertet, sobald die App wieder online ist.',
    children: [
      for (final item in _controller.pending)
        Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(color: AppColors.of(context).alert),
          onDismissed: (_) => _controller.removePending(item),
          child: ListTile(
            leading: Icon(item.hasPhoto ? Icons.photo_outlined : Icons.chat_bubble_outline),
            title: Text(item.text.isEmpty ? 'Foto' : item.text, maxLines: 1),
            trailing: Text(DateFormat.Hm('de_DE').format(item.created.toLocal())),
          ),
        ),
      ListTile(
        leading: const Icon(Icons.refresh),
        title: const Text('Jetzt auswerten'),
        onTap: () => _after(_controller.retryPending(_foods)),
      ),
    ],
  );

  Widget _checkInSection() => FormSection(
    header: 'Wochen-Check-in',
    footer:
        'Einmal pro Woche: Passt dein Verlauf zum Ziel? Falls nicht, schlägt die App eine Anpassung der Tagesziele vor '
        '– sie ändert nichts ohne dein OK.',
    children: [
      ListTile(
        leading: const Icon(Icons.event_available),
        title: const Text('Gewichtstrend und Verbrauch ansehen'),
        trailing: const DisclosureChevron(),
        onTap: () => _push((_) => const WeightTrendScreen()),
      ),
      ListTile(
        title: const Text('Diese Woche überspringen'),
        onTap: () {
          final settings = ref.read(coachSettingsProvider);
          settings.nutrition = settings.nutrition.copy()..lastCheckInDay = _controller.today;
        },
      ),
    ],
  );

  Widget _reviewSection() {
    final ai = ref.read(aiClientProvider);
    final controller = _controller;
    return FormSection(
      header: 'KI-Auswertung',
      footer: controller.reviewModel != null
          ? 'KI · ${controller.reviewModel}. Schätzungen – Nährwerte aus Fotos können deutlich abweichen.'
          : (!ai.isConfigured ? 'Dafür den KI-Worker in den Einstellungen einrichten.' : null),
      children: [
        for (final point in controller.reviewPoints) ListTile(title: Text(point)),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Ernährung und Training auswerten'),
          enabled: !controller.isWorking && ai.allows('nutrition_review'),
          onTap: () => controller.review(meals: _meals, activities: _activities, recovery: _recoveryText),
        ),
        if (controller.reviewPoints.isNotEmpty)
          EvidenceDisclosure(ruleIDs: [...controller.reviewSources, ...NutritionController.reviewEvidence]),
      ],
    );
  }

  // Suche

  /// Eigene Lebensmittel und frühere Mahlzeiten; Antippen öffnet den Entwurf, „+“ trägt sofort ein.
  List<Widget> _searchResults() {
    final query = _query.text;
    final entries = MealRepository.entries(_meals);
    final groups = <String, List<MealEntry>>{};
    for (final entry in entries.where((entry) => entry.items.length > 1)) {
      (groups[FoodSearch.normalized(entry.title)] ??= []).add(entry);
    }
    MealEntry latest(List<MealEntry> group) => group.reduce((a, b) => b.date.isAfter(a.date) ? b : a);
    final mealCandidates = [
      for (final MapEntry(:key, value: group) in groups.entries)
        FoodSearchCandidate(
          id: 'meal:$key',
          title: latest(group).title,
          useCount: group.length,
          lastUsed: latest(group).date,
        ),
    ];
    final foundFoods = FoodSearch.rank([for (final food in _foods) food.candidate], query: query);
    final foundMeals = FoodSearch.rank(mealCandidates, query: query, limit: 6);
    final foundBLS = query.runes.length >= 3 ? BLS.search(query, limit: 8) : const <BLSFood>[];
    final category = NutritionController.category(DateTime.now());
    void done() => _closeSearch();
    return [
      // Ohne lokale Treffer und zu kurz für die Online-Suche: Hinweis; sonst sagen die Markenprodukte, was es gibt.
      if (foundFoods.isEmpty &&
          foundMeals.isEmpty &&
          foundBLS.isEmpty &&
          FoodSearch.normalized(query).length < ProductSearch.onlineMinimumLength)
        const FormSection(children: [ListTile(title: Text('Nichts gefunden. Über „+“ eintragen.'))]),
      if (foundMeals.isNotEmpty)
        FormSection(
          header: 'Frühere Mahlzeiten',
          children: [
            for (final candidate in foundMeals)
              if (groups[candidate.id.substring(5)] case final group?)
                _QuickRow(
                  title: latest(group).title,
                  detail: mealSummary(latest(group).items),
                  onAdd: () {
                    _after(_controller.log(title: latest(group).title, category: category, items: latest(group).items));
                    done();
                  },
                ),
          ],
        ),
      if (foundFoods.isNotEmpty)
        FormSection(
          header: 'Lebensmittel',
          children: [
            for (final candidate in foundFoods)
              if (_foods.where((food) => food.candidate.id == candidate.id).firstOrNull?.item case final item?)
                _QuickRow(
                  title: item.name,
                  detail: mealSummary([item]),
                  onAdd: () {
                    _after(_controller.log(title: item.name, category: category, items: [item]));
                    done();
                  },
                  onOpen: () {
                    _controller.draftWithItem(item);
                    done();
                  },
                ),
          ],
        ),
      if (foundBLS.isNotEmpty)
        FormSection(
          header: 'Bundeslebensmittelschlüssel',
          footer: 'Öffnet den Entwurf mit 100 g. Quelle: ${BLS.attribution}.',
          children: [
            for (final food in foundBLS)
              _QuickRow(
                title: food.name,
                detail: blsSummary(food.per100g),
                onAdd: () {
                  _controller.draftWithItem(food.item());
                  done();
                },
              ),
          ],
        ),
      // Markenprodukte (Open Food Facts) unter den eigenen und den BLS-Treffern; eingetragene merkt sich die App als
      // eigenes Lebensmittel, beim nächsten Mal stehen sie oben.
      BrandProductResults(
        query: query,
        onAdd: (item) {
          _after(_controller.log(title: item.name, category: category, items: [item]));
          done();
        },
        onOpen: (item) {
          _controller.draftWithItem(item);
          done();
        },
      ),
    ];
  }
}
