import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/user_providers.dart';
import '../../data/storage.dart';
import '../../services/ai/ai_client.dart';
import '../../services/nutrition/cook_share_service.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../nutrition/meal_editor.dart';
import '../nutrition/nutrition_controller.dart';
import 'cook_plan_controller.dart';
import 'recipe_controller.dart';

int _rounded(double? value) => (value ?? 0).round();

String _macros(NutrientValues values) =>
    '${_rounded(values[Nutrient.kcal])} kcal · ${_rounded(values[Nutrient.protein])} g Protein · '
    '${_rounded(values[Nutrient.carbs])} g KH · ${_rounded(values[Nutrient.fat])} g Fett';

String _amount(double grams) =>
    grams >= 1000 ? '${GermanFormat.number((grams / 100).round() / 10)} kg' : '${grams.toInt()} g';

/// Kurzfassung einer Freigabe: genau das, was die andere Person sieht.
String cookShareSummary(CookShare share) => [
  if (share.kcal case final kcal?)
    '${kcal.toInt()} kcal, ${(share.protein ?? 0).toInt()} g Protein am Tag'
  else
    'keine Kalorienziele',
  ?share.diet?.label,
  if (share.allergens.isNotEmpty) ([for (final allergen in share.allergens) allergen.label]..sort()).join(', '),
  if (share.dislikes.isNotEmpty) 'mag nicht: ${share.dislikes}',
].join(' · ');

/// Mengenauswahl wie in der iPhone-App.
enum _Preset {
  one('1 Portion'),
  two('2 Portionen'),
  four('4 Portionen'),
  six('6 Portionen'),
  twoDays('2 Tage'),
  threeDays('3 Tage'),
  custom('Eigene Anzahl');

  const _Preset(this.label);

  final String label;
}

/// Rezeptideen für eine oder zwei Personen, frisch oder zum Vorkochen (Port von `CookPlanView`).
class CookPlanScreen extends ConsumerStatefulWidget {
  const CookPlanScreen({super.key, required this.recipes, required this.favorites, this.controller});

  /// Liefert die eigenen Tagesziele (dieselben wie in den Rezeptideen).
  final RecipeController recipes;
  final List<String> favorites;

  /// Für Tests; sonst ein eigener.
  final CookPlanController? controller;

  @override
  ConsumerState<CookPlanScreen> createState() => _CookPlanScreenState();
}

class _CookPlanScreenState extends ConsumerState<CookPlanScreen> {
  late final CookPlanController _controller =
      (widget.controller ?? CookPlanController(folder: ref.read(userDirectoryProvider)))..addListener(_changed);
  CookAudience _audience = CookAudience.me;
  String? _partnerCode;
  MealCategory _meal = MealCategory.dinner;
  _Preset _preset = _Preset.two;
  bool _days = false;
  int _customCount = 3;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  CookPartner? _partner(List<CookPartner> partners) =>
      partners.where((partner) => partner.code == _partnerCode).firstOrNull ?? partners.firstOrNull;

  CookAmount get _amount => switch (_preset) {
    _Preset.one => const CookPortions(1),
    _Preset.two => const CookPortions(2),
    _Preset.four => const CookPortions(4),
    _Preset.six => const CookPortions(6),
    _Preset.twoDays => const CookDays(2),
    _Preset.threeDays => const CookDays(3),
    _Preset.custom => _days ? CookDays(_customCount) : CookPortions(_customCount),
  };

  /// Der Plan in einem Satz, damit Portionen und Tage nicht verwechselt werden.
  String get _summary {
    final both = _audience == CookAudience.both;
    return switch (_amount) {
      CookPortions(:final count) =>
        both
            ? '$count Teller, auf euch beide verteilt.'
            : count == 1
            ? 'Ein Teller.'
            : '$count Teller für mehrere Mahlzeiten.',
      CookDays(:final count) =>
        'Einmal kochen, $count Tage essen: je Tag ${both ? 'ein Teller pro Person' : 'ein Teller'}.',
    };
  }

  Future<void> _create(CookPartner? partner) => _controller.createCookPlans(
    audience: _audience,
    partner: partner,
    meal: _meal,
    amount: _amount,
    targets: widget.recipes.targets,
    ai: ref.read(aiClientProvider),
    settings: ref.read(coachSettingsProvider),
    garminProfile: ref.read(garminSyncServiceProvider).profile,
    favorites: widget.favorites,
  );

  void _push(WidgetBuilder builder) => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)));

  @override
  Widget build(BuildContext context) {
    final partners = ref.watch(coachSettingsProvider).cookPartners;
    // Alle Verbindungen gelöst: wieder nur für mich.
    if (partners.isEmpty && _audience != CookAudience.me) _audience = CookAudience.me;
    final partner = _partner(partners);
    final controller = _controller;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final maxCount = _days ? CookAmount.maxDays : CookAmount.maxPortions;
    return Scaffold(
      appBar: AppBar(title: const Text('Kochen planen')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Für wen',
            children: [
              _Dropdown<CookAudience>(
                label: 'Für wen',
                value: _audience,
                items: {
                  CookAudience.me: 'Nur für mich',
                  if (partner != null) ...{
                    CookAudience.partner: 'Nur für ${partner.share.name}',
                    CookAudience.both: 'Für uns beide',
                  },
                },
                onChanged: (value) => setState(() => _audience = value),
              ),
              if (partners.length > 1 && _audience != CookAudience.me && partner != null)
                _Dropdown<String>(
                  label: 'Person',
                  value: partner.code,
                  items: {for (final partner in partners) partner.code: partner.share.name},
                  onChanged: (value) => setState(() => _partnerCode = value),
                ),
              ListTile(
                title: const Text('Gemeinsam kochen: Personen und Freigaben'),
                trailing: const DisclosureChevron(),
                onTap: () => _push((_) => CookPartnersScreen(controller: controller, recipes: widget.recipes)),
              ),
            ],
          ),
          FormSection(
            header: 'Was und wie viel',
            children: [
              _Dropdown<MealCategory>(
                label: 'Mahlzeit',
                value: _meal,
                items: {
                  for (final meal in const [
                    MealCategory.breakfast,
                    MealCategory.lunch,
                    MealCategory.dinner,
                    MealCategory.snack,
                  ])
                    meal: meal.label,
                },
                onChanged: (value) => setState(() => _meal = value),
              ),
              _Dropdown<_Preset>(
                label: 'Menge',
                value: _preset,
                items: {for (final preset in _Preset.values) preset: preset.label},
                onChanged: (value) => setState(() => _preset = value),
              ),
              if (_preset == _Preset.custom) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Portionen')),
                      ButtonSegment(value: true, label: Text('Tage')),
                    ],
                    selected: {_days},
                    onSelectionChanged: (selection) => setState(() {
                      _days = selection.first;
                      _customCount = _customCount.clamp(1, _days ? CookAmount.maxDays : CookAmount.maxPortions);
                    }),
                  ),
                ),
                ListTile(
                  title: Text('Anzahl: $_customCount'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Weniger',
                        icon: const Icon(Icons.remove),
                        onPressed: _customCount > 1 ? () => setState(() => _customCount--) : null,
                      ),
                      IconButton(
                        tooltip: 'Mehr',
                        icon: const Icon(Icons.add),
                        onPressed: _customCount < maxCount ? () => setState(() => _customCount++) : null,
                      ),
                    ],
                  ),
                ),
              ],
              ListTile(
                dense: true,
                title: Text(_summary, style: TextStyle(color: secondary)),
              ),
            ],
          ),
          FormSection(
            footer: 'Gericht und Nährwerte schlägt die KI vor; Tellergrößen, Mengen und Haltbarkeit rechnet und prüft die App.',
            children: [
              ListTile(
                enabled: !controller.isCooking,
                leading: const Icon(Icons.auto_awesome),
                title: Text(controller.isCooking ? 'Rezepte werden erstellt …' : 'Rezepte vorschlagen'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: () => _create(partner),
              ),
              if (controller.cookError case final error?)
                ListTile(
                  leading: Icon(Icons.warning_amber, color: AppColors.of(context).alert),
                  title: Text(error, style: AppText.footnote(context).copyWith(color: AppColors.of(context).alert)),
                ),
            ],
          ),
          if (controller.cookNotes.isNotEmpty)
            FormSection(
              header: 'Prüfung',
              children: [
                for (final note in controller.cookNotes)
                  ListTile(dense: true, leading: const Icon(Icons.verified_user_outlined), title: Text(note)),
              ],
            ),
          if (controller.cookPlans.isNotEmpty)
            FormSection(
              header: 'Vorschläge',
              children: [
                for (final plan in controller.cookPlans)
                  Dismissible(
                    key: ValueKey(plan.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: AppColors.of(context).alert,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: AppPalette.onColor),
                    ),
                    onDismissed: (_) => controller.delete(plan),
                    child: ListTile(
                      title: Text(plan.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${plan.amount.label} · ${plan.people.map((person) => person.name).join(' und ')} · '
                        '${plan.minutes} min',
                      ),
                      trailing: const DisclosureChevron(),
                      onTap: () => _push((_) => CookPlanDetailScreen(controller: controller, planID: plan.id)),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Auswahlfeld in voller Breite (wie `Picker` in einer Liste).
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label-$value-${items.length}'),
      initialValue: items.containsKey(value) ? value : items.keys.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final MapEntry(:key, :value) in items.entries)
          DropdownMenuItem(
            value: key,
            child: Text(value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
}

/// Mengen je Person, Gesamtmengen und Nährwerte; Zutaten lassen sich ändern, alles rechnet sich daraus neu (Port von
/// `CookPlanDetailView`).
class CookPlanDetailScreen extends ConsumerStatefulWidget {
  const CookPlanDetailScreen({super.key, required this.controller, required this.planID});

  final CookPlanController controller;
  final String planID;

  @override
  ConsumerState<CookPlanDetailScreen> createState() => _CookPlanDetailScreenState();
}

class _CookPlanDetailScreenState extends ConsumerState<CookPlanDetailScreen> {
  /// Erst beim Eintragen angelegt (nicht in `dispose`, dort ist `ref` nicht mehr nutzbar).
  NutritionController? _nutritionController;

  NutritionController get _nutrition => _nutritionController ??= NutritionController(
    meals: ref.read(mealRepositoryProvider),
    settings: ref.read(coachSettingsProvider),
    ai: ref.read(aiClientProvider),
    openFoodFacts: ref.read(openFoodFactsProvider),
  );
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _nutritionController?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _log(CookPlan plan, CookPortion mine) async {
    final draft = MealDraft(
      title: plan.title,
      category: plan.meal,
      hint: 'Aus Rezeptidee (Nährwerte KI-geschätzt)',
      items: mine.items,
    );
    _nutrition.present(draft);
    final foods = await ref.read(mealRepositoryProvider).foods();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MealEditorScreen(draft: draft, controller: _nutrition, foods: foods),
      ),
    );
  }

  void _change(CookPlan plan, void Function(CookPlan plan) edit) {
    edit(plan);
    widget.controller.update(plan);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.controller.plan(widget.planID);
    return Scaffold(
      appBar: AppBar(
        title: Text(plan?.title ?? 'Rezept'),
        actions: [
          if (plan != null)
            TextButton(
              onPressed: () => setState(() => _editing = !_editing),
              child: Text(_editing ? 'Fertig' : 'Bearbeiten'),
            ),
        ],
      ),
      body: plan == null ? const Center(child: Text('Rezept nicht mehr vorhanden')) : _content(context, plan),
    );
  }

  Widget _content(BuildContext context, CookPlan plan) {
    final secondary = AppText.caption(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final mine = plan.portions.where((portion) => portion.person.id == CookPerson.meID).firstOrNull;
    final storage = plan.storagePlan;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        FormSection(
          header: 'Wer isst wie viel',
          children: [
            for (final portion in plan.portions)
              ListTile(
                title: Text(portion.person.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      '${portion.plates} × ${portion.grams.round()} g roh · ${portion.sharePercent.round()} % des '
                      'Gerichts je Teller',
                    ),
                    Text('Je Teller: ${_macros(portion.nutrients)}', style: secondary),
                    if (portion.target case final target?)
                      Text(
                        'Ziel: ${target.kcal.round()} kcal, ${(target.protein ?? 0).round()} g Protein',
                        style: secondary,
                      ),
                    for (final note in portion.notes)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          const Icon(Icons.info_outline, size: 14),
                          Expanded(child: Text(note, style: secondary)),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
        FormSection(
          header: 'Ganzes Gericht',
          children: [
            ListTile(title: Text(_macros(plan.wholeNutrients))),
            if (plan.compromise.isNotEmpty)
              ListTile(dense: true, leading: const Icon(Icons.balance), title: Text(plan.compromise)),
          ],
        ),
        FormSection(
          header: _editing ? 'Zutaten einer Basisportion' : 'Zutaten insgesamt (roh)',
          footer: _editing ? 'Portionen, Gesamtmengen und Nährwerte rechnen sich aus diesen Mengen neu.' : null,
          children: [
            if (_editing)
              for (final item in plan.base)
                Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: AppColors.of(context).alert,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: AppPalette.onColor),
                  ),
                  onDismissed: (_) => _change(plan, (plan) => plan.remove(itemID: item.id)),
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: Text('${item.grams.round()} g'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Weniger',
                          icon: const Icon(Icons.remove),
                          onPressed: item.grams > 5
                              ? () => _change(
                                  plan,
                                  (plan) => plan.setGrams((item.grams - 5).clamp(5, 1000), itemID: item.id),
                                )
                              : null,
                        ),
                        IconButton(
                          tooltip: 'Mehr',
                          icon: const Icon(Icons.add),
                          onPressed: item.grams < 1000
                              ? () => _change(
                                  plan,
                                  (plan) => plan.setGrams((item.grams + 5).clamp(5, 1000), itemID: item.id),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                )
            else
              for (final item in plan.totalIngredients) LabeledRow(label: item.name, value: _amount(item.grams)),
          ],
        ),
        if (plan.mealsPerPerson > 1)
          FormSection(
            header: 'Lagerung',
            footer: 'Gekochtes höchstens ${CookPlanner.maxFridgeDays} Tage im Kühlschrank (BfR), danach einfrieren.',
            children: [
              if (storage != null)
                for (var index = 0; index < storage.length; index++)
                  LabeledRow(label: 'Tag ${index + 1}', value: storage[index].label)
              else
                ListTile(
                  leading: Icon(Icons.warning_amber, color: AppColors.of(context).caution),
                  title: Text(
                    'Nach deiner Änderung reicht die Haltbarkeit nicht für alle Tage.',
                    style: TextStyle(color: AppColors.of(context).caution),
                  ),
                ),
              if (plan.storageHint.isNotEmpty) ListTile(dense: true, title: Text(plan.storageHint)),
              if (plan.reheatHint.isNotEmpty) ListTile(dense: true, title: Text('Aufwärmen: ${plan.reheatHint}')),
            ],
          ),
        if (plan.steps.isNotEmpty)
          FormSection(
            header: 'Zubereitung',
            children: [
              for (var index = 0; index < plan.steps.length; index++)
                ListTile(dense: true, title: Text('${index + 1}. ${plan.steps[index]}')),
            ],
          ),
        if (mine != null)
          FormSection(
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Meine Portion eintragen …'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: () => _log(plan, mine),
              ),
            ],
          ),
        FormSection(
          footer: 'Quelle: ${plan.source}. Nährwerte sind KI-Schätzungen wie bei der Mahlzeiten-Analyse.',
          children: const [],
        ),
      ],
    );
  }
}

/// Eigene Freigabe erteilen, ändern, zurückziehen; andere Personen verbinden (Port von `CookPartnersView`).
class CookPartnersScreen extends ConsumerStatefulWidget {
  const CookPartnersScreen({super.key, this.controller, this.recipes, this.initialCode});

  final CookPlanController? controller;
  final RecipeController? recipes;

  /// Code aus einem Link `coach://cook/<code>`: wird gleich abgerufen.
  final String? initialCode;

  @override
  ConsumerState<CookPartnersScreen> createState() => _CookPartnersScreenState();
}

class _CookPartnersScreenState extends ConsumerState<CookPartnersScreen> {
  late final CookPlanController _plans =
      widget.controller ?? CookPlanController(folder: ref.read(userDirectoryProvider));
  late final RecipeController _recipes =
      widget.recipes ??
      RecipeController(store: ref.read(settingsStoreProvider), folder: ref.read(userDirectoryProvider));
  final _name = TextEditingController();
  final _code = TextEditingController();
  CookShareFields _fields = CookShareFields();
  ({String code, CookShare share})? _preview;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(coachSettingsProvider);
    if (_recipes.targets.isEmpty) {
      _recipes.update(settings: settings, garminProfile: ref.read(garminSyncServiceProvider).profile, meals: const []);
    }
    unawaited(_plans.load());
    if (settings.cookRelease case final release?) {
      _name.text = release.share.name;
      _fields = CookShareFields(
        targets: release.fields.targets,
        diet: release.fields.diet,
        allergens: release.fields.allergens,
        dislikes: release.fields.dislikes,
      );
    }
    _code.addListener(() => setState(() {}));
    if (widget.initialCode case final code?) {
      _code.text = code;
      unawaited(_lookUp());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    if (widget.controller == null) _plans.dispose();
    if (widget.recipes == null) _recipes.dispose();
    super.dispose();
  }

  CookShareService get _service => ref.read(cookShareServiceProvider);

  /// Genau das, was gespeichert würde.
  CookShare _draft() {
    final settings = ref.read(coachSettingsProvider);
    final body = settings.nutrition.profile(
      ref.read(garminSyncServiceProvider).profile,
      on: CalendarDay.fromDate(DateTime.now()),
    );
    return CookPlanner.share(
      name: _name.text,
      week: _recipes.targets,
      diet: settings.nutrition.diet,
      preferences: settings.recipes,
      fields: _fields,
      safety: GoalRules.weightGuard(settings.nutrition, body),
    );
  }

  Future<void> _busyWith(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookUp() => _busyWith(() async {
    final code = CookPlanner.code(_code.text);
    if (code == null) return;
    try {
      final share = await _service.fetch(code);
      if (!mounted) return;
      setState(() {
        _preview = (code: code, share: share);
        _message = null;
      });
    } on AIHttpError catch (error) {
      if (!mounted) return;
      setState(
        () => _message = error.status == 404
            ? 'Diese Freigabe gibt es nicht mehr. Bitte um einen neuen Link.'
            : error.message,
      );
    } on AIClientError catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  });

  void _connect(({String code, CookShare share}) preview) {
    final settings = ref.read(coachSettingsProvider);
    settings.cookPartners = [
      for (final partner in settings.cookPartners)
        if (partner.code != preview.code) partner,
      CookPartner(code: preview.code, share: preview.share),
    ];
    setState(() {
      _preview = null;
      _code.clear();
    });
  }

  Future<void> _publish() => _busyWith(() async {
    final settings = ref.read(coachSettingsProvider);
    final share = _draft();
    try {
      if (settings.cookRelease case final current?) {
        final expiresAt = await _service.update(share, code: current.code);
        settings.cookRelease = CookRelease(code: current.code, fields: _fields, share: share, expiresAt: expiresAt);
      } else {
        final created = await _service.publish(share);
        settings.cookRelease = CookRelease(
          code: created.code,
          fields: _fields,
          share: share,
          expiresAt: created.expiresAt,
        );
      }
      _message = 'Freigabe gespeichert.';
    } on AIHttpError catch (error) {
      if (error.status == 404) {
        // Abgelaufen: neu anlegen, damit ein gültiger Link entsteht.
        settings.cookRelease = null;
        _message = 'Die alte Freigabe war abgelaufen. Bitte noch einmal freigeben.';
      } else {
        _message = error.message;
      }
    } on AIClientError catch (error) {
      _message = error.message;
    }
  });

  Future<void> _revoke(CookRelease release) => _busyWith(() async {
    try {
      await _service.revoke(release.code);
      ref.read(coachSettingsProvider).cookRelease = null;
      _message =
          'Freigabe zurückgezogen. Beim nächsten Abruf werden deine Angaben auch bei der anderen Person gelöscht.';
    } on AIClientError catch (error) {
      _message = error.message;
    }
  });

  void _setField(void Function(CookShareFields fields) edit) => setState(() {
    final fields = CookShareFields(
      targets: _fields.targets,
      diet: _fields.diet,
      allergens: _fields.allergens,
      dislikes: _fields.dislikes,
    );
    edit(fields);
    _fields = fields;
  });

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final release = settings.cookRelease;
    final invite = _service.inviteLink();
    final releaseLink = release == null ? null : _service.link(release.code);
    final secondary = AppText.footnote(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Gemeinsam kochen')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Verbundene Personen',
            footer:
                'Verbunden sind nur die Angaben, die die andere Person freigegeben hat. Sie kann das jederzeit '
                'zurückziehen.',
            children: [
              for (final partner in settings.cookPartners)
                ListTile(
                  title: Text(partner.share.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(cookShareSummary(partner.share)),
                  trailing: TextButton(
                    onPressed: () => unawaited(_plans.forget(partner, settings: settings)),
                    style: TextButton.styleFrom(foregroundColor: AppColors.of(context).alert),
                    child: const Text('Lösen'),
                  ),
                ),
              if (_preview case final preview?)
                ListTile(
                  title: Text('${preview.share.name} gibt frei:', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Text(cookShareSummary(preview.share)),
                      FilledButton.icon(
                        onPressed: () => _connect(preview),
                        icon: const Icon(Icons.link),
                        label: const Text('Verbinden'),
                      ),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _code,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(hintText: 'Code oder Link der anderen Person'),
                  ),
                ),
                ListTile(
                  enabled: !_busy && CookPlanner.code(_code.text) != null,
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('Freigabe abrufen'),
                  onTap: _lookUp,
                ),
              ],
            ],
          ),
          FormSection(
            header: 'Meine Freigabe',
            footer:
                'Nur diese Angaben werden gespeichert, höchstens 90 Tage. Körperdaten, Gesundheitsangaben und dein '
                'Tagebuch bleiben auf deinem Gerät. Für Rezepte gehen Ziele, Ernährungsweise und Allergene ohne deinen '
                'Namen an den KI-Anbieter.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Dein Name für die andere Person'),
                ),
              ),
              SwitchListTile.adaptive(
                title: const Text('Tagesziele (Kalorien, Makros)'),
                value: _fields.targets,
                onChanged: (value) => _setField((fields) => fields.targets = value),
              ),
              SwitchListTile.adaptive(
                title: const Text('Ernährungsweise'),
                value: _fields.diet,
                onChanged: (value) => _setField((fields) => fields.diet = value),
              ),
              SwitchListTile.adaptive(
                title: const Text('Allergene und Unverträglichkeiten'),
                value: _fields.allergens,
                onChanged: (value) => _setField((fields) => fields.allergens = value),
              ),
              SwitchListTile.adaptive(
                title: const Text('Was ich nicht mag'),
                value: _fields.dislikes,
                onChanged: (value) => _setField((fields) => fields.dislikes = value),
              ),
              ListTile(dense: true, title: Text('Wird freigegeben: ${cookShareSummary(_draft())}', style: secondary)),
              ListTile(
                enabled: !_busy && _name.text.trim().isNotEmpty,
                leading: const Icon(Icons.ios_share),
                title: Text(release == null ? 'Freigeben' : 'Freigabe aktualisieren'),
                textColor: Theme.of(context).colorScheme.primary,
                onTap: _publish,
              ),
              if (release != null) ...[
                if (releaseLink != null)
                  ListTile(
                    leading: const Icon(Icons.send_outlined),
                    title: const Text('Link senden'),
                    onTap: () => SharePlus.instance.share(
                      ShareParams(text: 'Meine Freigabe für gemeinsame Rezepte: $releaseLink'),
                    ),
                  ),
                ListTile(
                  enabled: !_busy,
                  leading: Icon(Icons.cancel_outlined, color: AppColors.of(context).alert),
                  title: const Text('Freigabe zurückziehen'),
                  textColor: AppColors.of(context).alert,
                  onTap: () => _revoke(release),
                ),
              ],
            ],
          ),
          FormSection(
            footer: 'Die Person braucht die App und einen KI-Zugang, zum Beispiel über eine Einladung der Rangliste.',
            children: [
              if (invite != null)
                ListTile(
                  leading: const Icon(Icons.person_add_alt),
                  title: const Text('Person einladen'),
                  onTap: () => SharePlus.instance.share(
                    ShareParams(
                      text:
                          'Magst du Rezepte mit mir zusammen planen? Du entscheidest selbst, was du freigibst: $invite',
                    ),
                  ),
                ),
            ],
          ),
          if (_message case final message?) FormSection(children: [ListTile(dense: true, title: Text(message))]),
        ],
      ),
    );
  }
}
