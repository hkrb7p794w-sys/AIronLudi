import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/settings/coach_settings.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import '../social/social_views.dart';
import 'exercise_picker.dart';
import 'gym_controller.dart';
import 'gym_library.dart';
import 'gym_share_views.dart';
import 'muscle_views.dart';

part 'workout_result_parts.dart';
part 'workout_set_pad.dart';

/// Welcher Wert gerade über den Ziffernblock eingegeben wird.
enum SetField { weight, reps }

/// „1:05“ bzw. „1:02:05“ seit [start].
String elapsedText(DateTime start, DateTime now) {
  final seconds = now.difference(start).inSeconds.clamp(0, 359999);
  final (hours, minutes, rest) = (seconds ~/ 3600, seconds % 3600 ~/ 60, seconds % 60);
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${two(minutes)}:${two(rest)}' : '$minutes:${two(rest)}';
}

/// Gewicht × Wiederholungen eines Satzes, kurz.
String setValues(LoggedSet set) =>
    set.weightKg != 0 ? '${GermanFormat.number(set.weightKg)} kg × ${set.reps}' : '${set.reps} Wdh.';

/// Gym-Einstellungen ändern und speichern.
void changeGym(CoachSettings settings, void Function(GymSettings gym) change) {
  final gym = settings.gym;
  change(gym);
  settings.gym = gym;
}

/// Notiz, letztes Mal, Progression, Aufwärmen und Scheiben – klein unter dem Satz.
class ExerciseNotes extends ConsumerWidget {
  const ExerciseNotes({
    super.key,
    required this.exercise,
    required this.gym,
    this.set,
    this.offersWarmUp = false,
    this.centered = true,
  });

  final LoggedExercise exercise;
  final GymController gym;

  /// Satz der Fokus-Karte (Scheiben für genau dieses Gewicht); `null` = schwerster Satz.
  final int? set;
  final bool offersWarmUp;
  final bool centered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final gymSettings = settings.gym;
    final info = gymSettings.exercise(exercise.exerciseID);
    final theme = Theme.of(context);
    final style = AppText.footnote(context).copyWith(color: theme.colorScheme.onSurfaceVariant);
    final strong = style.copyWith(color: theme.colorScheme.onSurface);
    final align = centered ? TextAlign.center : TextAlign.start;
    final note = gymSettings.notes[exercise.exerciseID];
    final last = centered ? null : gym.lastTime(exercise.exerciseID);
    final progress = gym.progress.where((item) => item.exerciseID == exercise.exerciseID).firstOrNull;
    final working = exercise.sets
        .where((set) => set.kind != SetKind.warmup)
        .fold<double>(0, (top, set) => set.weightKg > top ? set.weightKg : top);
    final shown = set != null && set! < exercise.sets.length ? exercise.sets[set!].weightKg : working;
    final level = settings.profile.level(TrainingSport.strength);
    final warmUp = info == null ? const <WarmUpStep>[] : gym.warmUpSteps(exercise, level: level);
    final bar = info == null ? PlateCalculator.standardBar : gymSettings.bar(info.id);
    final plates = info != null && info.equipment.firstOrNull == Equipment.barbell
        ? PlateCalculator.plates(shown, bar: bar, available: gymSettings.plates)
        : null;
    return Column(
      crossAxisAlignment: centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      spacing: 6,
      children: [
        if (note != null && note.isNotEmpty) _IconText(Icons.sticky_note_2_outlined, note, strong, align),
        if (last != null) Text(last, style: style, textAlign: align),
        // Was die Progression für heute vorschlägt – sichtbar statt nur vorbefüllt.
        if (progress != null)
          Text(
            GymTarget.text(progress, recovered: gym.recovered),
            style: AppText.callout(context).copyWith(color: strong.color, fontWeight: FontWeight.w500),
            textAlign: align,
          ),
        if (warmUp.isNotEmpty) ...[
          _IconText(Icons.local_fire_department_outlined, WarmUp.text(warmUp), strong, align),
          if (offersWarmUp)
            OutlinedButton.icon(
              onPressed: () => gym.insertWarmUp(exercise.id, level: level),
              icon: const Icon(Icons.add),
              label: const Text('Aufwärmsätze einfügen'),
            ),
        ],
        if (plates != null)
          Text(
            '${GermanFormat.number(shown)} kg · Stange ${GermanFormat.number(bar)} kg · ${PlateCalculator.text(plates)}',
            style: style,
            textAlign: align,
          ),
      ],
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText(this.icon, this.text, this.style, this.align);

  final IconData icon;
  final String text;
  final TextStyle style;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icon, size: 15)),
        ),
        TextSpan(text: text),
      ],
    ),
    style: style,
    textAlign: align,
  );
}

/// Menü einer Übung: später, überspringen, ersetzen, Reihenfolge, Supersatz, Satz, Pause, Notiz, Stange, entfernen.
class ExerciseMenu extends ConsumerWidget {
  const ExerciseMenu({super.key, required this.exercise, required this.gym, this.showsFocus = false});

  final LoggedExercise exercise;
  final GymController gym;
  final bool showsFocus;

  static const bars = [
    (20.0, 'Langhantel 20 kg'),
    (15.0, 'Langhantel 15 kg'),
    (10.0, 'SZ-Stange 10 kg'),
    (25.0, 'Trap Bar 25 kg'),
    (7.5, 'Kurze Stange 7,5 kg'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = gym.active;
    if (session == null) return const SizedBox.shrink();
    final settings = ref.read(coachSettingsProvider);
    final info = settings.gym.exercise(exercise.exerciseID);
    final index = session.exercises.indexWhere((other) => other.id == exercise.id);
    final isLast = index >= session.exercises.length - 1;
    final note = settings.gym.notes[exercise.exerciseID];
    PopupMenuItem<VoidCallback> item(String title, IconData icon, VoidCallback action, {bool destructive = false}) =>
        PopupMenuItem(
          value: action,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: destructive ? AppColors.of(context).alert : null),
            title: Text(title, style: destructive ? TextStyle(color: AppColors.of(context).alert) : null),
          ),
        );
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Optionen für ${exercise.name}',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        if (showsFocus) item('Auf der Fokus-Karte zeigen', Icons.center_focus_strong, () => gym.focus(exercise.id)),
        if (!isLast) item('Später (Gerät belegt)', Icons.low_priority, () => gym.moveToEnd(exercise.id)),
        if (exercise.skipped)
          item('Wieder aufnehmen', Icons.undo, () => gym.resume(exercise.id))
        else if (exercise.sets.any((set) => !set.done))
          item('Überspringen', Icons.skip_next, () => gym.skip(exercise.id)),
        item('Ersetzen …', Icons.swap_horiz, () => _push(context, ReplaceExerciseScreen(exercise: exercise, gym: gym))),
        item('Reihenfolge ändern …', Icons.swap_vert, () => _push(context, ReorderExercisesScreen(gym: gym))),
        if (exercise.supersetID != null)
          item('Supersatz auflösen', Icons.link_off, () => gym.toggleSuperset(exercise.id))
        else if (!isLast)
          item('Supersatz mit ${session.exercises[index + 1].name}', Icons.link, () => gym.toggleSuperset(exercise.id)),
        const PopupMenuDivider(),
        item('Satz hinzufügen', Icons.add_circle_outline, () => gym.addSet(exercise.id)),
        item('Pause ${RestText.format(exercise.restSeconds)}', Icons.timer_outlined, () => _pickRest(context, ref)),
        item(note == null ? 'Notiz …' : 'Notiz ändern …', Icons.sticky_note_2_outlined, () => _editNote(context, ref)),
        if (info?.equipment.firstOrNull == Equipment.barbell)
          item(
            'Stange: ${GermanFormat.number(settings.gym.bar(exercise.exerciseID))} kg',
            Icons.horizontal_rule,
            () => _pickBar(context, ref),
          ),
        item(
          'Anleitung und Verlauf',
          Icons.info_outline,
          () => _push(context, ExerciseDetailScreen(exerciseID: exercise.exerciseID, gym: gym, showsDone: true)),
        ),
        const PopupMenuDivider(),
        item('Übung entfernen', Icons.delete_outline, () => gym.removeExercise(exercise.id), destructive: true),
      ],
    );
  }

  void _push(BuildContext context, Widget page) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => page)));

  /// Pause der Übung; gilt sofort und – gemerkt – auch beim nächsten Mal.
  Future<void> _pickRest(BuildContext context, WidgetRef ref) async {
    final current = RestText.options.reduce(
      (a, b) => (a - exercise.restSeconds).abs() <= (b - exercise.restSeconds).abs() ? a : b,
    );
    final seconds = await showDialog<int>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Pause'),
        children: [
          for (final option in RestText.options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialog).pop(option),
              child: Text(
                RestText.format(option),
                style: TextStyle(fontWeight: option == current ? FontWeight.bold : null),
              ),
            ),
        ],
      ),
    );
    if (seconds == null) return;
    if (gym.setRest(seconds, of: exercise.id) case final remembered?) {
      changeGym(
        ref.read(coachSettingsProvider),
        (gym) => gym.restOverrides[remembered.exerciseID] = remembered.seconds,
      );
    }
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(coachSettingsProvider);
    final controller = TextEditingController(text: settings.gym.notes[exercise.exerciseID] ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Notiz zu ${exercise.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Steht ab jetzt bei jeder Einheit unter der Übung.'),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'z. B. Sitz 4, Griff weit'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.of(dialog).pop(controller.text), child: const Text('Sichern')),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;
    final trimmed = text.trim();
    changeGym(settings, (gym) {
      if (trimmed.isEmpty) {
        gym.notes.remove(exercise.exerciseID);
      } else {
        gym.notes[exercise.exerciseID] = trimmed;
      }
    });
  }

  Future<void> _pickBar(BuildContext context, WidgetRef ref) async {
    final weight = await showDialog<double>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Stange'),
        children: [
          for (final (weight, label) in bars)
            SimpleDialogOption(onPressed: () => Navigator.of(dialog).pop(weight), child: Text(label)),
        ],
      ),
    );
    if (weight == null) return;
    changeGym(ref.read(coachSettingsProvider), (gym) => gym.bars[exercise.exerciseID] = weight);
  }
}

/// Alternativen für dieselbe Muskelgruppe mit der eigenen Ausstattung.
class ReplaceExerciseScreen extends ConsumerWidget {
  const ReplaceExerciseScreen({super.key, required this.exercise, required this.gym});

  final LoggedExercise exercise;
  final GymController gym;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider).gym;
    final options = WorkoutEdits.alternatives(
      exercise.exerciseID,
      custom: settings.customExercises,
      equipment: settings.equipment,
    );
    void choose(ExerciseInfo option) {
      gym.replace(exercise.id, option);
      Navigator.of(context).pop();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${exercise.name} ersetzen'),
        leading: BarTextButton('Abbrechen', onPressed: () => Navigator.of(context).pop()),
        leadingWidth: 100,
      ),
      body: ListView(
        children: [
          for (final option in options) ExerciseLabel(exercise: option, onTap: () => choose(option)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              exercise.sets.any((set) => set.done)
                  ? 'Erledigte Sätze bleiben bei ${exercise.name}; die offenen übernimmt die neue Übung.'
                  : 'Satzzahl und Wiederholungen bleiben, das Gewicht kommt aus deinem Verlauf.',
              style: AppText.footnote(context).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            title: const Text('Andere Übung wählen …'),
            onTap: () async {
              final option = await Navigator.of(context).push<ExerciseInfo>(
                MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ExercisePickerScreen()),
              );
              if (option != null) choose(option);
            },
          ),
        ],
      ),
    );
  }
}

class ReorderExercisesScreen extends StatelessWidget {
  const ReorderExercisesScreen({super.key, required this.gym});

  final GymController gym;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: gym,
    builder: (context, _) {
      final exercises = gym.active?.exercises ?? const <LoggedExercise>[];
      return Scaffold(
        appBar: AppBar(
          title: const Text('Reihenfolge'),
          automaticallyImplyLeading: false,
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fertig'))],
        ),
        body: ReorderableListView(
          onReorderItem: (from, to) => gym.moveExercises(fromOffsets: {from}, toOffset: to > from ? to + 1 : to),
          children: [
            for (final exercise in exercises)
              ListTile(
                key: ValueKey(exercise.id),
                leading: const Icon(Icons.drag_handle),
                title: Text(exercise.name),
                trailing: Text(() {
                  final progress = WorkoutFlow.progress(exercise);
                  return '${progress.done}/${progress.total}';
                }()),
              ),
          ],
        ),
      );
    },
  );
}
