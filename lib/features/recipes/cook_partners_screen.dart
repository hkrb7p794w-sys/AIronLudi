part of 'cook_plan_views.dart';

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
