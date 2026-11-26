import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_model.dart';
import '../../app/user_providers.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/large_title.dart';
import '../../ui/platform_names.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../../ui/tokens.dart';
import '../account/account_views.dart';
import '../ai/coach_exchange.dart';
import '../evidence/evidence_views.dart';
import '../me/me_screen.dart';
import '../motivation/motivation_views.dart';
import '../onboarding/onboarding_screen.dart';
import '../onboarding/schedule_editor.dart';
import '../training/sleep_coach_screen.dart';
import 'ai_settings.dart';
import 'backup_screen.dart';
import 'data_sources_screen.dart';
import 'demo_section.dart';
import 'diagnostics_screens.dart';
import 'discipline_settings.dart';
import 'lock_screen_settings.dart';
import 'nutrition_settings_screen.dart';
import 'settings_controller.dart';
import 'settings_sections.dart';
import 'users_screen.dart';
import 'whoop_section.dart';

/// Einstellungen: Profil, dann die Bereiche als eigene Seiten (wie `SettingsView.swift`).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.isTab = false});

  /// Als Reiter „Ich“ (Stufe 4 des Roasts): großer Titel, kein „Fertig“, oben Freunde & Liga und KI.
  final bool isTab;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final SettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SettingsController(
      model: ref.read(appModelProvider),
      ai: ref.read(aiClientProvider),
      settings: ref.read(settingsStoreProvider),
    );
  }

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
    trailing: const DisclosureChevron(),
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
      appBar: widget.isTab
          ? AppBar(title: const CollapsingTitle(child: Text('Ich')))
          : AppBar(
              title: const Text('Einstellungen'),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (widget.isTab) ...[const LargeTitleHeader('Ich'), const MeShortcutsSection()],
          FormSection(
            children: [
              ListTile(
                leading: const Icon(Icons.switch_account),
                title: Text(ref.watch(currentUserProvider).title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Benutzer dieses Geräts: wechseln, hinzufügen'),
                trailing: const DisclosureChevron(),
                onTap: () => _push(const UsersScreen()),
              ),
            ],
          ),
          const AccountSettingsSection(),
          FormSection(
            header: 'Profil',
            footer: season
                ? 'Mit einem persönlichen Profil wählst du Sportarten, Ziel und Wochenplan selbst; der Saisonplan wird '
                      'dann nicht mehr verwendet. Werte deiner Datenquellen, Gym-Einheiten und Mahlzeiten bleiben erhalten.'
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
                  // Sicherung unter „Allgemein“ wie bei iOS (vorher versteckt unter „KI und Automatisierung“).
                  FormSection(
                    header: 'Daten',
                    footer: 'Alles dieses Benutzers sichern oder einspielen, z. B. beim Wechsel auf ein neues Gerät.',
                    children: [
                      ListTile(
                        title: const Text('Datensicherung'),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const BackupScreen()),
                      ),
                    ],
                  ),
                  FormSection(
                    header: 'Motivation',
                    children: [
                      ListTile(
                        title: const Text('Begleiter & Rangliste'),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const MotivationSettingsScreen()),
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
                  const DisciplineSettingsSection(),
                  const TrainingBreakSection(),
                  if (ref.read(coachSettingsProvider).profile.mode == ProfileMode.season)
                    FormSection(
                      header: 'Saison',
                      children: [
                        ListTile(
                          title: const Text('Saison & Rennen'),
                          trailing: const DisclosureChevron(),
                          onTap: () => _push(const SeasonSettingsScreen()),
                        ),
                      ],
                    ),
                  _ConnectSection(controller: _controller),
                  const WhoopSection(),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.restaurant),
                title: const Text('Ernährung'),
                trailing: const DisclosureChevron(),
                onTap: () => _push(const NutritionSettingsScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.phone_iphone),
                title: const Text('Sperrbildschirm'),
                subtitle: const Text('Live-Aktivitäten für Gym und Ernährung'),
                trailing: const DisclosureChevron(),
                onTap: () => _push(const LockScreenSettingsScreen()),
              ),
              _area(
                'Health und Erholung',
                'heart.text.square',
                Icons.monitor_heart_outlined,
                () => [
                  FormSection(
                    children: [
                      ListTile(
                        title: const Text('Schlaf'),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const SleepCoachScreen()),
                      ),
                    ],
                  ),
                  const HealthImportSection(),
                  FormSection(
                    footer: 'Mehrere Geräte: welche Quelle für Schlaf, HRV, Aktivitäten usw. zählt.',
                    children: [
                      ListTile(
                        title: const Text('Datenquellen und Vorrang'),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const DataSourcesScreen()),
                      ),
                    ],
                  ),
                ],
              ),
              _area(
                'KI und Automatisierung',
                'sparkles',
                Icons.auto_awesome,
                () => [
                  const AISettingsSection(),
                  FormSection(
                    header: 'Eigene Quellen und Austausch',
                    children: [
                      ListTile(
                        title: const Text('Eigene Quellen'),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const UserSourcesScreen()),
                      ),
                      ListTile(
                        title: const Text('Daten für KI exportieren'),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const CoachExportScreen()),
                      ),
                      ListTile(
                        title: const Text('KI-Antwort importieren'),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const CoachImportScreen()),
                      ),
                    ],
                  ),
                ],
              ),
              _area(
                'Technik',
                'wrench.and.screwdriver',
                Icons.build_outlined,
                () => [
                  _AISection(controller: _controller),
                  _GarminKeySection(controller: _controller),
                  const DemoSection(),
                  FormSection(
                    header: 'Diagnose',
                    children: [
                      ListTile(
                        title: const Text('Garmin-Diagnose'),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const GarminDiagnosticsScreen()),
                      ),
                      ListTile(
                        title: Text(healthStoreName),
                        trailing: const DisclosureChevron(),
                        onTap: () => _push(const HealthDiagnosticsScreen()),
                      ),
                    ],
                  ),
                ],
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
            leading: Icon(Icons.verified_user, color: AppColors.of(context).good),
            title: Text(
              model.garmin.connect?.email ?? 'Angemeldet',
              style: TextStyle(color: AppColors.of(context).good),
            ),
          ),
          ListTile(title: const Text('Jetzt abrufen'), onTap: () => unawaited(model.syncNow())),
          ListTile(
            title: Text('Abmelden', style: TextStyle(color: AppColors.of(context).alert)),
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
            leading: Icon(Icons.call_split, color: AppColors.of(context).caution),
            title: Text(
              'Personal API ist eingesprungen: $problem',
              style: TextStyle(color: AppColors.of(context).caution),
            ),
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
          ListTile(
            leading: Icon(Icons.verified, color: AppColors.of(context).good),
            title: Text('Key hinterlegt', style: TextStyle(color: AppColors.of(context).good)),
          ),
        if (controller.expiryWarning case final warning?)
          ListTile(
            leading: Icon(Icons.schedule, color: AppColors.of(context).caution),
            title: Text(warning, style: TextStyle(color: AppColors.of(context).caution)),
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
            title: Text('Key entfernen', style: TextStyle(color: AppColors.of(context).alert)),
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
