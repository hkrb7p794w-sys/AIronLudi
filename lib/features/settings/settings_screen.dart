import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_model.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../evidence/evidence_views.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/schedule_editor.dart';
import 'backup_screen.dart';
import 'settings_controller.dart';
import 'settings_sections.dart';

/// Einstellungen: Profil, dann die Bereiche als eigene Seiten (wie `SettingsView.swift`).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final SettingsController _controller = SettingsController(
    model: ref.read(appModelProvider),
    ai: ref.read(aiClientProvider),
    settings: ref.read(settingsStoreProvider),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _push(Widget screen, {bool fullscreen = false}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: fullscreen, builder: (_) => screen));

  /// Eine Kategorie: eigene Seite mit denselben Abschnitten wie zuvor.
  Widget _area(String title, String symbol, IconData icon, List<Widget> Function() sections) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _push(_AreaScreen(title: title, controller: _controller, sections: sections)),
  );

  List<InputIssue> _profileIssues(AppModel model) {
    final today = CalendarDay.today();
    final body = model.settings.nutrition.profile(model.sync.profile, on: today);
    return [
      ...InputCheck.body(body),
      ...InputCheck.goals(
        profile: model.settings.profile,
        body: body,
        predictions: model.sync.racePredictions,
        today: today,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final model = ref.watch(appModelProvider);
    final profile = settings.profile;
    final season = profile.mode == ProfileMode.season;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
      ),
      body: ListView(
        children: [
          FormSection(
            header: 'Profil',
            footer: season
                ? 'Mit einem persönlichen Profil wählst du Sportarten, Ziel und Wochenplan selbst; der Saisonplan wird '
                      'dann nicht mehr verwendet. Garmin-Daten, Gym-Einheiten und Mahlzeiten bleiben erhalten.'
                : 'Plan, Ernährung und Empfehlungen passen sich an dein Profil an.',
            children: [
              if (season) ...[
                ListTile(
                  leading: Icon(AppSymbols.of('flag.checkered')),
                  title: Text('Du nutzt den Saisonplan (${settings.season.mainRaceName}).'),
                ),
                ListTile(
                  title: const Text('Zu persönlichem Profil wechseln'),
                  onTap: () => _push(
                    OnboardingScreen(isEditing: true, initial: UserProfile.personalDraft(settings.season)),
                    fullscreen: true,
                  ),
                ),
              ] else ...[
                ListTile(
                  leading: Icon(AppSymbols.of(profile.goal == FitnessGoal.loseWeight ? 'flame.fill' : 'heart.fill')),
                  title: Text('Ernährung: ${settings.coachingProfile.goal.label}'),
                ),
                ListTile(
                  leading: Icon(AppSymbols.of('figure.mixed.cardio')),
                  title: Text(profile.sports.map((sport) => sport.shortLabel).join(', ')),
                ),
                ListTile(
                  title: const Text('Sportarten, Ziel, Körperdaten ändern'),
                  onTap: () => _push(OnboardingScreen(isEditing: true, initial: profile), fullscreen: true),
                ),
              ],
              ListTile(
                title: const Text('Ziele & Prioritäten'),
                trailing: Text(profile.effectiveGoals(CalendarDay.today()).primary.label),
                onTap: () => _push(const PersonalGoalsSettingsScreen()),
              ),
            ],
          ),
          if (!season) InputIssuesSection(issues: _profileIssues(model)),
          FormSection(
            children: [
              _area(
                'Allgemein',
                'gearshape',
                Icons.settings_outlined,
                () => [
                  const AppearanceSettingsSection(),
                  const ReminderSettingsSection(),
                  const PrivacySettingsSection(),
                  FormSection(
                    header: 'Quellen',
                    children: [
                      SwitchListTile(
                        title: const Text('Quellen bei Empfehlungen zeigen'),
                        value: settings.showsEvidence,
                        onChanged: (on) => settings.showsEvidence = on,
                      ),
                      ListTile(
                        title: const Text('Quellen und Regeln'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _push(const EvidenceLibraryScreen()),
                      ),
                    ],
                  ),
                ],
              ),
              _area(
                'Training und Fitness',
                'figure.strengthtraining.traditional',
                Icons.sports_gymnastics,
                () => [
                  const TrainingBreakSection(),
                  if (ref.read(coachSettingsProvider).profile.mode == ProfileMode.season)
                    FormSection(
                      header: 'Saison',
                      children: [
                        ListTile(
                          title: const Text('Saison & Rennen'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _push(const SeasonSettingsScreen()),
                        ),
                      ],
                    ),
                  _ConnectSection(controller: _controller),
                ],
              ),
              _area(
                'Health und Erholung',
                'heart.text.square',
                Icons.monitor_heart_outlined,
                () => [const HealthImportSection()],
              ),
              _area(
                'KI und Automatisierung',
                'sparkles',
                Icons.auto_awesome,
                () => [
                  FormSection(
                    header: 'Eigene Daten und Quellen',
                    children: [
                      ListTile(
                        title: const Text('Datensicherung'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _push(const BackupScreen()),
                      ),
                      ListTile(
                        title: const Text('Eigene Quellen'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _push(const UserSourcesScreen()),
                      ),
                    ],
                  ),
                ],
              ),
              _area(
                'Technik',
                'wrench.and.screwdriver',
                Icons.build_outlined,
                () => [_AISection(controller: _controller), _GarminKeySection(controller: _controller)],
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Seite eines Bereichs; zeigt während Anmeldung oder Abruf einen Fortschritt.
class _AreaScreen extends StatelessWidget {
  const _AreaScreen({required this.title, required this.controller, required this.sections});

  final String title;
  final SettingsController controller;
  final List<Widget> Function() sections;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Stack(
        children: [
          AbsorbPointer(
            absorbing: controller.isBusy,
            child: Consumer(
              builder: (context, ref, _) {
                ref.watch(coachSettingsProvider);
                return ListView(children: [...sections(), const SizedBox(height: 24)]);
              },
            ),
          ),
          if (controller.isBusy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    ),
  );
}

/// Eingabefeld, das einen Wert des Controllers spiegelt.
class _ControllerField extends StatefulWidget {
  const _ControllerField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.obscure = false,
    this.keyboard,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool obscure;
  final TextInputType? keyboard;

  @override
  State<_ControllerField> createState() => _ControllerFieldState();
}

class _ControllerFieldState extends State<_ControllerField> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_ControllerField old) {
    super.didUpdateWidget(old);
    if (widget.value != _text.text) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: TextField(
      controller: _text,
      obscureText: widget.obscure,
      autocorrect: false,
      enableSuggestions: !widget.obscure,
      keyboardType: widget.keyboard,
      textCapitalization: TextCapitalization.none,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: widget.onChanged,
    ),
  );
}

Widget _status(BuildContext context, String? text) => text == null
    ? const SizedBox.shrink()
    : ListTile(
        title: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

/// Garmin-Konto (inoffizieller Zugang mit Bestätigungscode).
class _ConnectSection extends ConsumerWidget {
  const _ConnectSection({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(appModelProvider);
    final problem = model.lastReport?.connectProblem;
    return FormSection(
      header: 'Garmin-Konto',
      footer:
          'Inoffizieller Zugang wie die Garmin-Connect-App: mehr Werte (Training Readiness, Trainingsstatus, '
          'Endurance Score, Wettkampfprognosen). Das Passwort wird nicht gespeichert, nur das Anmelde-Token im '
          'sicheren Speicher. Fällt der Zugang aus, springt die Personal API ein, sofern ein Key hinterlegt ist.',
      children: [
        if (controller.connectLoggedIn) ...[
          ListTile(
            leading: const Icon(Icons.verified_user, color: Colors.green),
            title: Text(model.garmin.connect?.email ?? 'Angemeldet', style: const TextStyle(color: Colors.green)),
          ),
          ListTile(title: const Text('Jetzt abrufen'), onTap: () => unawaited(model.syncNow())),
          ListTile(
            title: const Text('Abmelden', style: TextStyle(color: Colors.red)),
            onTap: controller.logoutConnect,
          ),
        ] else if (controller.awaitingCodeVia != null) ...[
          _ControllerField(
            label: 'Bestätigungscode',
            value: controller.connectCode,
            keyboard: TextInputType.number,
            onChanged: controller.setConnectCode,
          ),
          ListTile(
            title: const Text('Code bestätigen'),
            enabled: controller.connectCode.length >= 4,
            onTap: controller.submitConnectCode,
          ),
        ] else ...[
          _ControllerField(
            label: 'E-Mail',
            value: controller.connectEmail,
            keyboard: TextInputType.emailAddress,
            onChanged: (text) => controller.connectEmail = text,
          ),
          _ControllerField(
            label: 'Passwort',
            value: controller.connectPassword,
            obscure: true,
            onChanged: (text) => controller.connectPassword = text,
          ),
          ListTile(title: const Text('Anmelden'), onTap: controller.loginConnect),
        ],
        _status(context, controller.connectStatus),
        if (problem != null && controller.connectLoggedIn)
          ListTile(
            leading: const Icon(Icons.call_split, color: Colors.orange),
            title: Text('Personal API ist eingesprungen: $problem', style: const TextStyle(color: Colors.orange)),
          ),
      ],
    );
  }
}

/// Garmin Personal API (Rückfall): Key, Ablaufdatum, Abruf.
class _GarminKeySection extends ConsumerWidget {
  const _GarminKeySection({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(appModelProvider);
    final expiry = controller.keyExpiry;
    return FormSection(
      header: 'Garmin Personal API (Rückfall)',
      footer:
          'Key erzeugen: Garmin Connect im Browser › Einstellungen › Personal API Key (Laufzeit 1 Jahr). Der Key '
          'bleibt nur im sicheren Speicher dieses Geräts.',
      children: [
        if (controller.hasGarminKey)
          const ListTile(
            leading: Icon(Icons.verified, color: Colors.green),
            title: Text('Key hinterlegt', style: TextStyle(color: Colors.green)),
          ),
        if (controller.expiryWarning case final warning?)
          ListTile(
            leading: const Icon(Icons.schedule, color: Colors.orange),
            title: Text(warning, style: const TextStyle(color: Colors.orange)),
          ),
        _ControllerField(
          label: controller.hasGarminKey ? 'Neuen Key einfügen' : 'Personal API Key',
          value: controller.garminKeyInput,
          obscure: true,
          onChanged: (text) => controller.garminKeyInput = text,
        ),
        ListTile(
          title: const Text('Gültig bis'),
          trailing: Text(GermanFormat.date(CalendarDay.fromDate(expiry))),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: expiry,
              firstDate: DateTime(2020),
              lastDate: DateTime(DateTime.now().year + 2),
            );
            if (date != null) await controller.saveExpiry(date);
          },
        ),
        ListTile(title: const Text('Speichern und verbinden'), onTap: controller.saveGarminKey),
        if (controller.hasGarminKey) ...[
          ListTile(title: const Text('Jetzt abrufen'), onTap: () => unawaited(model.syncNow())),
          ListTile(
            title: const Text('Key entfernen', style: TextStyle(color: Colors.red)),
            onTap: controller.removeGarminKey,
          ),
        ],
        _status(context, controller.garminStatus),
      ],
    );
  }
}

/// KI-Worker: Adresse, App-Token, Test, SideStore-Quelle und Android-Link.
class _AISection extends ConsumerWidget {
  const _AISection({required this.controller});

  final SettingsController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiClientProvider);
    return FormSection(
      header: 'KI-Worker',
      footer:
          'Adresse und App-Token aus der Einrichtung des Cloudflare Workers (siehe docs/einrichtung.md). '
          'SideStore-Quelle und Android-Link sind privat: Wer den Link hat, kann die App laden – nur an Vertraute '
          'weitergeben.',
      children: [
        _ControllerField(
          label: 'https://coach-ai.<name>.workers.dev',
          value: controller.workerURLInput,
          keyboard: TextInputType.url,
          onChanged: (text) => controller.workerURLInput = text,
        ),
        _ControllerField(
          label: controller.hasAIToken ? 'App-Token (gespeichert)' : 'App-Token',
          value: controller.appTokenInput,
          obscure: true,
          onChanged: (text) => controller.appTokenInput = text,
        ),
        ListTile(title: const Text('Speichern und testen'), onTap: controller.saveAndTestAI),
        _status(context, controller.aiStatus),
        if (ai.sideStoreSourceURL case final source?) SideStoreRows(source: source),
        if (ai.androidDownloadURL != null) const AndroidShareRow(),
      ],
    );
  }
}
