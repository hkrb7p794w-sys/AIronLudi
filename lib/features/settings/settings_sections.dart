import 'dart:async';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/settings/appearance.dart';
import '../../platform/notifications.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../onboarding/personalization_widgets.dart';
import 'data_sources_screen.dart';

final _dateFormat = DateFormat('d. MMM y', 'de_DE');

/// Uhrzeit wählen (wie `DatePicker` mit `.hourAndMinute`).
Future<TimeOfDay?> pickTime(BuildContext context, int hour, int minute) => showTimePicker(
  context: context,
  initialTime: TimeOfDay(hour: hour, minute: minute),
);

String timeText(BuildContext context, int hour, int minute) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay(hour: hour, minute: minute), alwaysUse24HourFormat: true);

/// Darstellung: Wie System, Hell, Dunkel.
class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider);
    return FormSection(
      footer: '„Wie System“ folgt dem Dunkelmodus des Geräts. Widgets richten sich immer nach dem System.',
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<AppAppearance>(
            segments: [
              for (final appearance in AppAppearance.values)
                ButtonSegment(value: appearance, label: Text(appearance.title)),
            ],
            selected: {current},
            onSelectionChanged: (selection) => ref.read(appearanceProvider.notifier).select(selection.first),
          ),
        ),
      ],
    );
  }
}

/// Erinnerung an geplante Einheiten: an/aus, Uhrzeit, Status der Mitteilungen.
class ReminderSettingsSection extends ConsumerWidget {
  const ReminderSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final permission = ref.watch(reminderServiceProvider).permission;
    final reminders = settings.reminders;
    void change(void Function(ReminderSettings value) update) => settings.reminders = reminders.copy()..let(update);
    return FormSection(
      header: 'Erinnerungen',
      footer: [
        if (permission == NotificationPermission.denied)
          'Mitteilungen sind ausgeschaltet. Die Erinnerung erscheint dann nur unter „Heute“.'
        else if (settings.profile.mode == ProfileMode.personal)
          'In der Mitteilung kannst du die Einheit verschieben oder diese Woche auslassen. Der Wochenplan selbst bleibt '
              'dabei unverändert.'
        else
          'Erinnert an die festen Einheiten des Saisonplans.',
        'Erinnerungen zu einer Disziplin (Schwimm-Ausrüstung, Tag auswerten, Schlafenszeit) stehen dort.',
      ].join('\n'),
      children: [
        SwitchListTile(
          title: const Text('An Trainingstagen erinnern'),
          value: reminders.enabled,
          onChanged: (on) => change((value) => value.enabled = on),
        ),
        if (reminders.enabled)
          ListTile(
            title: const Text('Uhrzeit'),
            trailing: Text(timeText(context, reminders.hour, reminders.minute)),
            onTap: () async {
              final time = await pickTime(context, reminders.hour, reminders.minute);
              if (time != null) {
                change(
                  (value) => value
                    ..hour = time.hour
                    ..minute = time.minute,
                );
              }
            },
          ),
        SwitchListTile(
          title: const Text('Morgens um 8 Uhr Morning Report'),
          value: reminders.morningReport,
          onChanged: (on) => change((value) => value.morningReport = on),
        ),
        SwitchListTile(
          title: const Text('Sonntags „Nächste Woche planen“'),
          value: reminders.weekPlanning,
          onChanged: (on) => change((value) => value.weekPlanning = on),
        ),
        if (reminders.weekPlanning)
          ListTile(
            title: const Text('Uhrzeit am Sonntag'),
            trailing: Text(timeText(context, reminders.planningHour, reminders.planningMinute)),
            onTap: () async {
              final time = await pickTime(context, reminders.planningHour, reminders.planningMinute);
              if (time != null) {
                change(
                  (value) => value
                    ..planningHour = time.hour
                    ..planningMinute = time.minute,
                );
              }
            },
          ),
        if (permission == NotificationPermission.denied && Platform.isIOS)
          ListTile(
            title: const Text('Mitteilungen in den Einstellungen erlauben'),
            onTap: () => launchUrl(Uri.parse('app-settings:')),
          ),
      ],
    );
  }
}

extension<T> on T {
  T let(void Function(T value) action) {
    action(this);
    return this;
  }
}

/// Datenschutz: Was an die KI geht.
class PrivacySettingsSection extends ConsumerWidget {
  const PrivacySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    return FormSection(
      header: 'Datenschutz',
      children: [
        RadioGroup<PrivacyMode>(
          groupValue: settings.privacy,
          onChanged: (mode) {
            if (mode != null) settings.privacy = mode;
          },
          child: const Column(
            children: [
              RadioListTile(value: PrivacyMode.reduced, title: Text('Nur Einordnungen (empfohlen)')),
              RadioListTile(value: PrivacyMode.full, title: Text('Auch Messwerte')),
            ],
          ),
        ),
      ],
    );
  }
}

/// Urlaub oder Trainingspause: Zeitraum ohne Erinnerungen und ohne „verpasst“ (`TrainingBreak`).
class TrainingBreakSection extends ConsumerStatefulWidget {
  const TrainingBreakSection({super.key});

  @override
  ConsumerState<TrainingBreakSection> createState() => _TrainingBreakSectionState();
}

class _TrainingBreakSectionState extends ConsumerState<TrainingBreakSection> {
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 7));

  Future<DateTime?> _pick(DateTime initial, DateTime first) => showDatePicker(
    context: context,
    initialDate: initial.isBefore(first) ? first : initial,
    firstDate: first,
    lastDate: DateTime(DateTime.now().year + 3),
  );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final pause = settings.activeBreak(CalendarDay.today());
    return FormSection(
      header: 'Urlaub oder Pause',
      footer:
          'Im Zeitraum keine Erinnerungen an Einheiten, nichts gilt als verpasst, und Begleiter und Rangliste zählen '
          'die Tage nicht. Training, das du trotzdem machst, wird normal erfasst.',
      children: pause != null
          ? [
              LabeledRow(label: 'Pause', value: pause.label),
              ListTile(
                title: const Text('Pause beenden', style: TextStyle(color: Colors.red)),
                onTap: () => settings.trainingBreak = null,
              ),
            ]
          : [
              ListTile(
                title: const Text('Von'),
                trailing: Text(_dateFormat.format(_start)),
                onTap: () async {
                  final date = await _pick(_start, DateTime(2000));
                  if (date != null) setState(() => _start = date.isAfter(_end) ? (_end = date) : date);
                },
              ),
              ListTile(
                title: const Text('Bis'),
                trailing: Text(_dateFormat.format(_end)),
                onTap: () async {
                  final date = await _pick(_end, _start);
                  if (date != null) setState(() => _end = date);
                },
              ),
              ListTile(
                leading: const Icon(Icons.luggage_outlined),
                title: const Text('Pause eintragen'),
                onTap: () {
                  settings.trainingBreak = TrainingBreak(CalendarDay.fromDate(_start), CalendarDay.fromDate(_end));
                  unawaited(ref.read(appModelProvider).refreshReminders());
                },
              ),
            ],
    );
  }
}

/// Apple Health / Health Connect als zweite Quelle neben Garmin.
class HealthImportSection extends ConsumerWidget {
  const HealthImportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthImportServiceProvider);
    final garminConfigured = ref.read(appModelProvider).garmin.isConfigured;
    return FutureBuilder<bool>(
      future: health.isAvailable,
      builder: (context, snapshot) {
        final available = snapshot.data ?? false;
        return FormSection(
          header: Platform.isAndroid ? 'Health Connect' : 'Apple Health / Apple Watch',
          footer:
              'Übernimmt Schlaf mit Phasen, Ruhepuls, Schritte, Kalorien, Atemfrequenz, Sauerstoff, Gewicht und '
              'Workouts. Garmin hat Vorrang: Health füllt nur Lücken, Workouts, die Garmin schon kennt, kommen nicht '
              'doppelt. Die HRV übernimmt die App nur ohne Garmin, weil Apple sie anders misst (SDNN statt RMSSD).',
          children: available
              ? [
                  SwitchListTile(
                    title: Text(
                      Platform.isAndroid ? 'Daten aus Health Connect übernehmen' : 'Daten aus Apple Health übernehmen',
                    ),
                    value: health.isEnabled,
                    onChanged: (on) {
                      health.isEnabled = on;
                      if (on) unawaited(health.importNow(garminConnected: garminConfigured));
                    },
                  ),
                  if (health.isEnabled)
                    ListTile(
                      title: const Text('Jetzt importieren'),
                      enabled: !health.isImporting,
                      onTap: () => health.importNow(garminConnected: garminConfigured),
                    ),
                  if (health.isImporting)
                    const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
                  else if (health.lastResult case final result?)
                    ListTile(title: Text(result, style: Theme.of(context).textTheme.bodySmall)),
                ]
              : [
                  const ListTile(
                    title: Text('Gesundheitsdaten sind in dieser Installation nicht verfügbar (siehe Diagnose).'),
                  ),
                ],
        );
      },
    );
  }
}

/// Saison & Rennen: Renntermine und Saisonphasen. Phasen, Wochen-Soll und Plantexte rechnen sich daraus.
class SeasonSettingsScreen extends ConsumerWidget {
  const SeasonSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final season = settings.season;
    void change(void Function(SeasonConfig config) update) => settings.season = season.copy()..let(update);
    Widget text(String label, String value, void Function(SeasonConfig config, String text) update, {int lines = 1}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextFormField(
            initialValue: value,
            minLines: 1,
            maxLines: lines,
            decoration: InputDecoration(labelText: label),
            onChanged: (text) => change((config) => update(config, text)),
          ),
        );
    Widget day(String label, CalendarDay value, void Function(SeasonConfig config, CalendarDay day) update) => ListTile(
      title: Text(label),
      trailing: Text(GermanFormat.date(value)),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime(value.year, value.month, value.day),
          firstDate: DateTime(2020),
          lastDate: DateTime(2040),
        );
        if (date != null) change((config) => update(config, CalendarDay.fromDate(date)));
      },
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Saison & Rennen')),
      body: ListView(
        key: ValueKey(season.toJson().toString().hashCode),
        children: [
          FormSection(
            header: 'Hauptrennen',
            children: [
              text('Name', season.mainRaceName, (config, text) => config.mainRaceName = text),
              text(
                'Beschreibung',
                season.mainRaceDescription,
                (config, text) => config.mainRaceDescription = text,
                lines: 4,
              ),
              day('Datum', season.mainRaceDate, (config, day) => config.mainRaceDate = day),
              text('Ziel', season.raceGoal, (config, text) => config.raceGoal = text),
            ],
          ),
          FormSection(
            header: 'Saison',
            footer:
                'Daraus ergeben sich die Phasen: Marathon-Taper 3 Wochen, danach 2 Wochen Regeneration; Peak 3 Wochen '
                'und Taper ab dem Montag der vorletzten Rennwoche.',
            children: [
              day('Marathon', season.marathonDate, (config, day) => config.marathonDate = day),
              day('Grundlage ab', season.baseStart, (config, day) => config.baseStart = day),
              day('Marathonblock ab', season.marathonBlockStart, (config, day) => config.marathonBlockStart = day),
            ],
          ),
          const FormSection(
            footer:
                'FTP, CSS, Paces und Herzfrequenz stehen unter Einstellungen › Disziplinen (Laufen, Rad, Schwimmen).',
            children: [],
          ),
          FormSection(
            children: [
              ListTile(
                title: const Text('Auf Standardwerte zurücksetzen', style: TextStyle(color: Colors.red)),
                onTap: () => settings.season = SeasonConfig.standard,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Einstellungen › Ziele & Prioritäten: jederzeit änderbar, gilt ab heute (frühere Zeiträume behalten ihre Ziele).
class PersonalGoalsSettingsScreen extends ConsumerStatefulWidget {
  const PersonalGoalsSettingsScreen({super.key});

  @override
  ConsumerState<PersonalGoalsSettingsScreen> createState() => _PersonalGoalsSettingsScreenState();
}

class _PersonalGoalsSettingsScreenState extends ConsumerState<PersonalGoalsSettingsScreen> {
  late PersonalGoals _goals;
  late TrackerSetup _tracker;
  final _today = CalendarDay.today();

  @override
  void initState() {
    super.initState();
    final profile = ref.read(coachSettingsProvider).profile;
    _goals = profile.effectiveGoals(_today);
    _tracker = profile.tracker;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          PersonalizationApply.apply(
            goals: _goals,
            tracker: _tracker,
            model: ref.read(appModelProvider),
            today: _today,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Ziele & Prioritäten')),
        body: ListView(
          children: [
            FormSection(
              header: 'Ziele',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GoalsPicker(goals: _goals, onChanged: (goals) => setState(() => _goals = goals)),
                ),
              ],
            ),
            FormSection(
              header: 'Was dir besonders wichtig ist',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: PrioritiesPicker(goals: _goals, onChanged: (goals) => setState(() => _goals = goals)),
                ),
              ],
            ),
            FormSection(
              header: 'Fitness-Tracker',
              footer: 'Garmin verbindest du unter Einstellungen › Garmin, Apple Health unter „Apple Health“.',
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TrackerPicker(setup: _tracker, onChanged: (setup) => setState(() => _tracker = setup)),
                ),
                ListTile(
                  title: const Text('Datenquellen und Vorrang'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DataSourcesScreen())),
                ),
              ],
            ),
            const FormSection(
              footer:
                  'Änderungen gelten ab heute für Empfehlungen, Plan-Vorschläge und KI. Frühere Wochen behalten die '
                  'Ziele, die damals galten.',
              children: [],
            ),
          ],
        ),
      ),
    );
  }
}

/// Link zur Android-App mit eigenem Gastzugang für die KI: Download-Seite plus `#zugang=<Gast-Token>` im Anker (geht
/// nie an den Server; die Seite baut daraus „In der App verbinden“). Jeder Link ist ein eigener Zugang.
class AndroidShareRow extends ConsumerStatefulWidget {
  const AndroidShareRow({super.key});

  @override
  ConsumerState<AndroidShareRow> createState() => _AndroidShareRowState();
}

class _AndroidShareRowState extends ConsumerState<AndroidShareRow> {
  Uri? _link;
  String? _error;
  bool _working = false;

  Future<void> _create() async {
    final ai = ref.read(aiClientProvider);
    final base = ai.androidDownloadURL;
    if (base == null) return;
    setState(() => _working = true);
    try {
      final token = await ai.createGuestToken();
      setState(() {
        _link = AndroidLink.url(base: base, guestToken: token);
        _error = null;
      });
    } on Object catch (error) {
      setState(() => _error = 'Link nicht erstellt: $error');
    } finally {
      setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_link case final link?)
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: const Text('Android-Link teilen'),
          onTap: () => SharePlus.instance.share(
            ShareParams(
              subject: 'IronLudi für Android',
              text: 'Hier kannst du IronLudi (Gym und Ernährung) für Android laden und mit der KI verbinden: $link',
            ),
          ),
        )
      else
        ListTile(
          leading: const Icon(Icons.add_link),
          title: const Text('Android-Link erstellen'),
          enabled: !_working,
          onTap: _create,
        ),
      if (_error case final error?)
        ListTile(
          title: Text(error, style: const TextStyle(color: Colors.red)),
        ),
    ],
  );
}

/// SideStore-Quelle teilen oder kopieren.
class SideStoreRows extends StatelessWidget {
  const SideStoreRows({super.key, required this.source});

  final Uri source;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        leading: const Icon(Icons.ios_share),
        title: const Text('SideStore-Quelle teilen'),
        onTap: () => SharePlus.instance.share(ShareParams(uri: source)),
      ),
      ListTile(
        leading: const Icon(Icons.copy),
        title: const Text('SideStore-Quelle kopieren'),
        onTap: () => Clipboard.setData(ClipboardData(text: '$source')),
      ),
    ],
  );
}
