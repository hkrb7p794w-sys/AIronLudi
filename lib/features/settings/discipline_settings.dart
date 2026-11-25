import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/gym/gym_book_reader.dart';
import '../../services/providers.dart';
import '../../services/routing/routing_providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';
import '../../ui/tokens.dart';
import '../gym/gym_library.dart';
import '../gym/gym_providers.dart';
import '../routes/route_parts.dart';
import 'lock_screen_settings.dart';

void _push(BuildContext context, Widget screen) =>
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));

/// Einstellungen nach Disziplin: alles zu einer Sportart an einem Ort (Port von `DisciplineSettingsSection`).
class DisciplineSettingsSection extends ConsumerWidget {
  const DisciplineSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(coachSettingsProvider).profile;
    final season = profile.mode == ProfileMode.season;
    // Im Saisonplan alle drei Ausdauer-Disziplinen, sonst nur die gewählten Sportarten.
    final endurance = [
      for (final sport in const [TrainingSport.run, TrainingSport.bike, TrainingSport.swim])
        if (season || profile.sports.contains(sport)) sport,
    ];
    return FormSection(
      header: 'Disziplinen',
      children: [
        if (season || profile.sports.contains(TrainingSport.strength))
          ListTile(
            leading: Icon(AppSymbols.of('dumbbell.fill')),
            title: const Text('Gym'),
            trailing: const DisclosureChevron(),
            onTap: () => _push(context, const GymSettingsScreen()),
          ),
        for (final sport in endurance)
          ListTile(
            leading: Icon(AppSymbols.of(sport.symbol)),
            title: Text(sport.shortLabel),
            trailing: const DisclosureChevron(),
            onTap: () => _push(context, EnduranceSettingsScreen(sport: sport)),
          ),
      ],
    );
  }
}

/// Auswahlfeld in voller Breite (wie `Picker` in einem Formular).
class _Choice<T> extends StatelessWidget {
  const _Choice({required this.label, required this.value, required this.items, required this.onChanged});

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label-$value'),
      initialValue: value,
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

/// Pausenwahl aus `RestText.options`; ein Wert außerhalb der Liste bleibt wählbar.
Map<int, String> _restItems(int current) => {
  for (final seconds in {...RestText.options, current}.toList()..sort()) seconds: RestText.format(seconds),
};

/// Gym: Pausen, Aufwärmen, Abhaken, Übungen, Ausstattung, Sperrbildschirm, Garmin (Port von `GymSettingsView`).
class GymSettingsScreen extends ConsumerWidget {
  const GymSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final gym = settings.gym;
    void change(void Function(GymSettings gym) edit) {
      edit(gym);
      settings.gym = gym;
    }

    Widget rest(String title, int value, void Function(GymSettings gym, int seconds) set) => _Choice<int>(
      label: title,
      value: value,
      items: _restItems(value),
      onChanged: (seconds) => change((gym) => set(gym, seconds)),
    );

    final hours = GarminStrengthSync.fallbackDelay.inHours;
    return Scaffold(
      appBar: AppBar(title: const Text('Gym')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: 'Satzpausen',
            footer:
                'Vorrang: eigene Pause der Übung, dann eine bewusst andere Pause im Trainingsplan, dann diese Werte. '
                'Gilt ab der nächsten Einheit. Eine Pause je Übung stellst du unter „Pausen und Notizen je Übung“ oder '
                'während der Einheit im Menü der Übung ein. Ohne sofortigen Start erscheint nach dem Satz „Pause '
                'starten“.',
            children: [
              rest('Grundübungen', gym.restCompound, (gym, seconds) => gym.restCompound = seconds),
              rest('Isolationsübungen', gym.restIsolation, (gym, seconds) => gym.restIsolation = seconds),
              rest('Nach Aufwärmsätzen', gym.restWarmup, (gym, seconds) => gym.restWarmup = seconds),
              SwitchListTile.adaptive(
                title: const Text('Pause nach dem Satz sofort starten'),
                value: gym.autoStartsRest,
                onChanged: (value) => change((gym) => gym.autoStartsRest = value),
              ),
              ListTile(
                title: const Text('Pausen und Notizen je Übung'),
                trailing: const DisclosureChevron(),
                onTap: () => _push(context, const ExerciseSettingsScreen()),
              ),
              _Choice<RestSound>(
                label: 'Ton am Pausenende',
                value: gym.restSound,
                items: {for (final sound in RestSound.values) sound: sound.label},
                onChanged: (sound) {
                  change((gym) => gym.restSound = sound);
                  unawaited(ref.read(restSoundPlayerProvider).play(sound));
                },
              ),
              SwitchListTile.adaptive(
                title: const Text('Vibration am Pausenende'),
                value: gym.restHaptic,
                onChanged: (value) => change((gym) => gym.restHaptic = value),
              ),
            ],
          ),
          FormSection(
            header: 'Nach dem Eintippen',
            footer:
                'Wenn du Gewicht oder Wiederholungen über den Ziffernblock einträgst, hakt die App den Satz ab und '
                'startet die Pause – ein Tipp weniger. Die ±-Knöpfe haken nie ab.',
            children: [
              _Choice<CompleteOnEdit>(
                label: 'Satz abhaken',
                value: gym.completeOnEdit,
                items: {for (final mode in CompleteOnEdit.values) mode: mode.label},
                onChanged: (mode) => change((gym) => gym.completeOnEdit = mode),
              ),
            ],
          ),
          const GymBookImportSection(),
          FormSection(
            footer:
                'Grundübungen: leere Stange, dann etwa 50, 70 und 85 % des Arbeitsgewichts, Kurzhantel und Maschine 50 '
                'und 75 %. Schwere Isolationsübungen: ein Satz. Ist der Muskel schon gearbeitet, genügt ein '
                'Einstiegssatz. Aufwärmsätze zählen nicht zum Volumen.',
            children: [
              SwitchListTile.adaptive(
                title: const Text('Aufwärmsätze vorschlagen'),
                value: gym.suggestsWarmUp,
                onChanged: (value) => change((gym) => gym.suggestsWarmUp = value),
              ),
            ],
          ),
          FormSection(
            children: [
              ListTile(
                title: const Text('Ausstattung, Stange und Scheiben'),
                trailing: const DisclosureChevron(),
                onTap: () => _push(context, const EquipmentSettingsScreen()),
              ),
            ],
          ),
          FormSection(
            footer:
                'In der Pause nach jedem Satz kurz antippen, wie viele Wiederholungen noch gegangen wären (RIR) – '
                'freiwillig, das Abhaken bleibt ein Tipp. Bleiben in allen Sätzen 4 oder mehr übrig, schlägt die App '
                'sofort mehr Gewicht vor.',
            children: [
              SwitchListTile.adaptive(
                title: const Text('Wiederholungen in Reserve abfragen'),
                value: gym.tracksRIR,
                onChanged: (value) => change((gym) => gym.tracksRIR = value),
              ),
            ],
          ),
          FormSection(
            footer:
                'Während einer Einheit sperrt sich das Gerät nicht – kein Entsperren mit verschwitzten Händen. Auf dem '
                'Sperrbildschirm stehen Pause und nächster Satz, mit „Satz erledigt“ zum Antippen (Live-Aktivität bzw. '
                'Mitteilung; in den Systemeinstellungen unter AIronLudi abschaltbar).',
            children: [
              SwitchListTile.adaptive(
                title: const Text('Bildschirm anlassen'),
                value: gym.keepsScreenOn,
                onChanged: (value) => change((gym) => gym.keepsScreenOn = value),
              ),
              SwitchListTile.adaptive(
                title: const Text('Pause auf dem Sperrbildschirm'),
                value: gym.liveActivity,
                onChanged: (value) => change((gym) => gym.liveActivity = value),
              ),
              if (gym.liveActivity)
                ListTile(
                  title: const Text('Ansicht auf dem Sperrbildschirm'),
                  subtitle: Text(gym.liveActivityLayout.label),
                  trailing: const DisclosureChevron(),
                  onTap: () => _push(context, const LockScreenSettingsScreen()),
                ),
            ],
          ),
          FormSection(
            footer:
                'Zeichnest du die Einheit auch mit der Uhr auf, schreibt AIronLudi die Übungen, Wiederholungen und '
                'Gewichte in diese Aufzeichnung – eine Aktivität mit Kalorien und Puls der Uhr, nichts doppelt. Die '
                'ursprünglichen Sätze der Uhr werden vorher gesichert. Ohne Aufzeichnung der Uhr wird die Einheit nach '
                '$hours Stunden als eigenes Krafttraining hochgeladen (abschaltbar). Nur mit Garmin-Konto; nutzt die '
                'Schnittstelle von „Sätze bearbeiten“ in Garmin Connect.',
            children: [
              SwitchListTile.adaptive(
                title: const Text('Mit Garmin Connect abgleichen'),
                value: gym.uploadsToGarmin,
                onChanged: (value) => change((gym) => gym.uploadsToGarmin = value),
              ),
              if (gym.uploadsToGarmin)
                SwitchListTile.adaptive(
                  title: const Text('Ohne Uhr als eigene Aktivität hochladen'),
                  value: gym.garminFallbackUpload,
                  onChanged: (value) => change((gym) => gym.garminFallbackUpload = value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Verlauf aus einem GymBook-Backup übernehmen (Port von `GymBookImportSection`).
class GymBookImportSection extends ConsumerStatefulWidget {
  const GymBookImportSection({super.key, this.pickFile});

  /// Für Tests; sonst die Dateiauswahl des Systems.
  final Future<String?> Function()? pickFile;

  @override
  ConsumerState<GymBookImportSection> createState() => _GymBookImportSectionState();
}

class _GymBookImportSectionState extends ConsumerState<GymBookImportSection> {
  String? _result;

  static Future<String?> _systemPicker() async => (await FilePicker.pickFiles()).firstOrNull?.path;

  Future<void> _import() async {
    try {
      final path = await (widget.pickFile ?? _systemPicker)();
      if (path == null) return;
      final result = await GymBookReader.importBackup(
        path,
        gym: ref.read(gymRepositoryProvider),
        settings: ref.read(coachSettingsProvider),
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _result = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => FormSection(
    header: 'Daten übernehmen',
    footer: 'Backup-Datei von GymBook (….database) auswählen. Mehrfaches Importieren legt nichts doppelt an.',
    children: [
      ListTile(
        leading: const Icon(Icons.history),
        title: const Text('Verlauf aus Backup importieren'),
        textColor: Theme.of(context).colorScheme.primary,
        onTap: _import,
      ),
      if (_result case final result?)
        ListTile(
          dense: true,
          title: Text(result, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
    ],
  );
}

/// Übungen aus den eigenen Routinen und alle mit eigener Pause oder Notiz – per Suche jede andere (Port von
/// `ExerciseSettingsList`).
class ExerciseSettingsScreen extends ConsumerStatefulWidget {
  const ExerciseSettingsScreen({super.key});

  @override
  ConsumerState<ExerciseSettingsScreen> createState() => _ExerciseSettingsScreenState();
}

class _ExerciseSettingsScreenState extends ConsumerState<ExerciseSettingsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(coachSettingsProvider).gym;
    final mine = {
      for (final routine in gym.routines)
        for (final item in routine.items) item.exerciseID,
      ...gym.restOverrides.keys,
      ...gym.notes.keys,
      ...gym.bars.keys,
    };
    final found = _search.isEmpty
        ? const <ExerciseInfo>[]
        : ExerciseLibrary.search(_search, custom: gym.customExercises);
    final own = [for (final id in mine) ?gym.exercise(id)]..sort((a, b) => a.name.compareTo(b.name));
    final others = [
      for (final exercise in found)
        if (!mine.contains(exercise.id)) exercise,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Je Übung')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Übung suchen'),
              onChanged: (text) => setState(() => _search = text),
            ),
          ),
          if (own.isNotEmpty)
            FormSection(header: 'Meine Übungen', children: [for (final exercise in own) _row(gym, exercise)]),
          if (others.isNotEmpty)
            FormSection(header: 'Suche', children: [for (final exercise in others) _row(gym, exercise)]),
        ],
      ),
    );
  }

  Widget _row(GymSettings gym, ExerciseInfo exercise) {
    final rest = gym.rest(exercise.id, compound: exercise.compound);
    final custom = gym.restOverrides[exercise.id] != null;
    final note = gym.notes[exercise.id];
    return ListTile(
      title: Text(exercise.name),
      subtitle: Text(
        'Pause ${RestText.format(rest)}${custom ? '' : ' (Standard)'}${note == null ? '' : ' · $note'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const DisclosureChevron(),
      onTap: () => _push(context, ExerciseSettingsDetailScreen(exercise: exercise)),
    );
  }
}

/// Pause, Notiz und Stange einer Übung (Port von `ExerciseSettingsDetail`).
class ExerciseSettingsDetailScreen extends ConsumerStatefulWidget {
  const ExerciseSettingsDetailScreen({super.key, required this.exercise});

  final ExerciseInfo exercise;

  @override
  ConsumerState<ExerciseSettingsDetailScreen> createState() => _ExerciseSettingsDetailScreenState();
}

class _ExerciseSettingsDetailScreenState extends ConsumerState<ExerciseSettingsDetailScreen> {
  late final _note = TextEditingController(text: ref.read(coachSettingsProvider).gym.notes[widget.exercise.id] ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final gym = settings.gym;
    final exercise = widget.exercise;
    void change(void Function(GymSettings gym) edit) {
      edit(gym);
      settings.gym = gym;
    }

    final current = gym.restOverrides[exercise.id] ?? 0;
    final bar = gym.bars[exercise.id] ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            footer: 'Gilt ab der nächsten Einheit, auch wenn der Trainingsplan eine andere Pause hat.',
            children: [
              _Choice<int>(
                label: 'Pause',
                value: current,
                items: {
                  0: 'Standard (${RestText.format(gym.rest('', compound: exercise.compound))})',
                  ..._restItems(current == 0 ? RestText.options.first : current),
                },
                onChanged: (seconds) => change(
                  (gym) =>
                      seconds == 0 ? gym.restOverrides.remove(exercise.id) : gym.restOverrides[exercise.id] = seconds,
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Notiz',
            footer: 'Steht bei jeder Einheit unter der Übung – für Sitzhöhe, Griff, Bankeinstellung oder Gerätenummer.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'z. B. Sitz 4, Griff weit, Bank auf Stufe 3'),
                  onChanged: (text) => change(
                    (gym) => text.trim().isEmpty ? gym.notes.remove(exercise.id) : gym.notes[exercise.id] = text,
                  ),
                ),
              ),
            ],
          ),
          if (exercise.equipment.firstOrNull == Equipment.barbell)
            FormSection(
              header: 'Stange',
              children: [
                _Choice<double>(
                  label: 'Stange',
                  value: bar,
                  items: {
                    0: 'Standard (${GermanFormat.number(gym.barKg)} kg)',
                    for (final kg in const [20.0, 15.0, 10.0, 25.0, 7.5]) kg: '${GermanFormat.number(kg)} kg',
                  },
                  onChanged: (kg) =>
                      change((gym) => kg == 0 ? gym.bars.remove(exercise.id) : gym.bars[exercise.id] = kg),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Laufen, Rad, Schwimmen: Herzfrequenz für alle; Testwerte (FTP, CSS, Paces) nur im Saisonplan (Port von
/// `EnduranceSettingsView`).
class EnduranceSettingsScreen extends ConsumerWidget {
  const EnduranceSettingsScreen({super.key, required this.sport});

  final TrainingSport sport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final season = settings.profile.mode == ProfileMode.season;
    final config = settings.season;
    void changeSeason(void Function(SeasonConfig config) edit) {
      final copy = config.copy();
      edit(copy);
      settings.season = copy;
    }

    Widget pace(String title, int value, void Function(SeasonConfig config, int value) set) => StepperRow(
      title: '$title ${GermanFormat.minutesSeconds(value)} /km',
      value: value,
      min: 150,
      max: 480,
      onChanged: (value) => changeSeason((config) => set(config, value)),
    );

    final heartRate = settings.heartRate;
    void changeHeartRate({Object? max = _keep, Object? run = _keep, Object? bike = _keep}) =>
        settings.heartRate = HeartRateOverrides(
          maxHeartRate: identical(max, _keep) ? heartRate.maxHeartRate : max as int?,
          thresholdRun: identical(run, _keep) ? heartRate.thresholdRun : run as int?,
          thresholdBike: identical(bike, _keep) ? heartRate.thresholdBike : bike as int?,
        );

    return Scaffold(
      appBar: AppBar(title: Text(sport.shortLabel)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (season)
            FormSection(
              header: 'Testwerte',
              footer:
                  'Nach jedem Test aktualisieren – Watt- und Pace-Angaben im Plan und in der KI-Notiz rechnen sich '
                  'daraus.',
              children: [
                if (sport == TrainingSport.run) ...[
                  pace('Schwellenpace', config.thresholdPaceSecondsPerKm, (c, v) => c.thresholdPaceSecondsPerKm = v),
                  pace('Marathonpace', config.marathonPaceSecondsPerKm, (c, v) => c.marathonPaceSecondsPerKm = v),
                  pace('Renn-Laufpace', config.racePaceSecondsPerKm, (c, v) => c.racePaceSecondsPerKm = v),
                ],
                if (sport == TrainingSport.bike)
                  StepperRow(
                    title: 'FTP ${config.ftpWatts} W',
                    value: config.ftpWatts,
                    min: 80,
                    max: 500,
                    onChanged: (value) => changeSeason((config) => config.ftpWatts = value),
                  ),
                if (sport == TrainingSport.swim)
                  StepperRow(
                    title: 'CSS ${GermanFormat.minutesSeconds(config.cssSecondsPer100m)} /100 m',
                    value: config.cssSecondsPer100m,
                    min: 60,
                    max: 240,
                    onChanged: (value) => changeSeason((config) => config.cssSecondsPer100m = value),
                  ),
              ],
            ),
          if (sport == TrainingSport.run || sport == TrainingSport.bike)
            FormSection(
              header: 'Herzfrequenz',
              footer:
                  'Ohne eigene Werte nutzt die App die Laktatschwelle deiner Uhr und den höchsten bestätigten Puls aus '
                  'deinen Einheiten. Schwelle: 30 Minuten am Anschlag, Ø-HF der letzten 20 Minuten. HFmax gilt für '
                  'Laufen und Rad.',
              children: [
                HeartRateRow(
                  title: 'HFmax',
                  value: heartRate.maxHeartRate,
                  min: 140,
                  max: 230,
                  onChanged: (value) => changeHeartRate(max: value),
                ),
                if (sport == TrainingSport.run)
                  HeartRateRow(
                    title: 'Schwelle Laufen',
                    value: heartRate.thresholdRun,
                    min: 120,
                    max: 210,
                    onChanged: (value) => changeHeartRate(run: value),
                  )
                else
                  HeartRateRow(
                    title: 'Schwelle Rad',
                    value: heartRate.thresholdBike,
                    min: 120,
                    max: 210,
                    onChanged: (value) => changeHeartRate(bike: value),
                  ),
              ],
            ),
          if (sport == TrainingSport.swim)
            FormSection(
              header: 'Erinnerung',
              footer: season ? 'Am Abend vor dem Schwimmen: Badesachen, Brille, Schloss.' : 'Herzfrequenz am Handgelenk ist im Wasser ungenau – Schwimmen bewertet die App nach Dauer und Plan.',
              children: [
                if (season)
                  SwitchListTile.adaptive(
                    title: const Text('Ausrüstung am Vorabend (18 Uhr)'),
                    value: settings.reminders.equipment,
                    onChanged: (value) => settings.reminders = settings.reminders.copy()..equipment = value,
                  ),
              ],
            ),
          if (sport == TrainingSport.run) const RunRouteSettingsSection(),
        ],
      ),
    );
  }
}

const _keep = Object();

/// Zahl mit Minus/Plus in festen Grenzen (wie `Stepper`).
class StepperRow extends StatelessWidget {
  const StepperRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Weniger',
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        IconButton(
          tooltip: 'Mehr',
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    ),
  );
}

/// Eigener Pulswert; „automatisch“, solange keiner gesetzt ist (Port von `HeartRateStepper`).
class HeartRateRow extends StatelessWidget {
  const HeartRateRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final int? value;
  final int min;
  final int max;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value;
    if (current == null) {
      return ListTile(
        title: Text(title),
        subtitle: const Text('automatisch'),
        trailing: TextButton(
          style: TextButton.styleFrom(textStyle: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => onChanged((min + max) ~/ 2 + 10),
          child: const Text('eigenen Wert setzen'),
        ),
      );
    }
    return ListTile(
      title: Text('$title $current bpm'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Weniger',
            icon: const Icon(Icons.remove),
            onPressed: current > min ? () => onChanged(current - 1) : null,
          ),
          IconButton(
            tooltip: 'Mehr',
            icon: const Icon(Icons.add),
            onPressed: current < max ? () => onChanged(current + 1) : null,
          ),
          TextButton(onPressed: () => onChanged(null), child: const Text('Auto')),
        ],
      ),
    );
  }
}

/// Laufen › Routenvorschläge: an/aus, bevorzugtes Gelände, Start der Runden.
class RunRouteSettingsSection extends ConsumerWidget {
  const RunRouteSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(routeStoreProvider);
    final runs = store.runSuggestions;
    final favorites = store.favorites;
    Future<void> change(void Function(RunRouteSuggestions runs) edit) => store.updateRunSuggestions(edit);
    final chosen = favorites.where((place) => place.id == runs.startFavoriteID).firstOrNull;
    return FormSection(
      header: 'Routenvorschläge',
      footer:
          'Zu jeder geplanten Laufeinheit schlägt die App eine Runde vor, die zum Training passt (Tempo und Intervalle '
          'flach, Regeneration weich, lange Läufe als große Runde) – jedes Mal in eine andere Richtung als die Strecken '
          'der letzten vier Wochen. Annehmen ordnet sie der Einheit zu, Ablehnen zeigt eine andere.',
      children: [
        SwitchListTile.adaptive(
          title: const Text('Routen zu geplanten Läufen vorschlagen'),
          value: runs.enabled,
          onChanged: (value) => unawaited(change((runs) => runs.enabled = value)),
        ),
        if (runs.enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Am liebsten laufe ich …', style: AppText.footnote(context)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: PreferenceChips(
              discipline: RouteDiscipline.run,
              selected: runs.preferences,
              onChanged: (selection) => unawaited(change((runs) => runs.preferences = {...selection})),
            ),
          ),
          _Choice<String>(
            label: 'Start der Runden',
            value: chosen?.id ?? '',
            items: {
              '': 'Automatisch (Favorit „Zuhause“, sonst Standort)',
              for (final place in favorites) place.id: place.name,
            },
            onChanged: (id) => unawaited(change((runs) => runs.startFavoriteID = id.isEmpty ? null : id)),
          ),
        ],
      ],
    );
  }
}
