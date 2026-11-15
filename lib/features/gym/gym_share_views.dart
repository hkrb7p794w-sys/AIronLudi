import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import 'workout_parts.dart';

/// Einheit oder Trainingsplan über das Teilen-Menü des Systems (Nachrichten, Mail, …) als Text mit Link
/// `coach://routine/…` (`GymShareText`).
Future<void> shareGymText(BuildContext context, String text, {required String subject}) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: subject,
      // iPad braucht einen Ausgangspunkt für das Menü.
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Abgeschlossene Einheit teilen.
Future<void> shareSession(BuildContext context, WidgetRef ref, GymSession session) => shareGymText(
  context,
  GymShareText.session(session, custom: ref.read(coachSettingsProvider).gym.customExercises),
  subject: session.title.isEmpty ? 'Krafttraining' : session.title,
);

/// Geplante Einheit (Trainingsplan) teilen.
Future<void> shareRoutine(BuildContext context, WidgetRef ref, Routine routine) => shareGymText(
  context,
  GymShareText.routine(routine, custom: ref.read(coachSettingsProvider).gym.customExercises),
  subject: routine.name,
);

/// Geteilter Trainingsplan aus `coach://routine/…`: ansehen und als eigenen Plan übernehmen.
class ImportRoutineScreen extends ConsumerWidget {
  const ImportRoutineScreen({super.key, required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final custom = settings.gym.customExercises;
    final unknown = [
      for (final item in routine.items)
        if (ExerciseLibrary.info(item.exerciseID, custom: custom) == null) item.name,
    ];
    final secondary = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geteilter Trainingsplan'),
        leading: IconButton(
          tooltip: 'Abbrechen',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FormSection(
            header: routine.name,
            footer: unknown.isEmpty
                ? 'Nach dem Übernehmen lässt sich der Plan frei ändern. Gewichte sind Vorschläge der anderen Person – '
                      'die Progression rechnet ab deinem ersten Satz mit deinen Werten.'
                : 'Nicht in deiner Übungsbibliothek: ${unknown.join(', ')}. Sie erscheinen mit ihrem Namen, ohne '
                      'Muskelzuordnung.',
            children: [
              for (final item in routine.items)
                ListTile(
                  title: Text(item.name),
                  subtitle: Text(_detail(item), style: secondary),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.download),
              label: const Text('Als eigenen Trainingsplan übernehmen'),
              onPressed: () {
                changeGym(settings, (gym) => gym.routines.add(routine));
                final messenger = ScaffoldMessenger.maybeOf(context);
                Navigator.of(context).pop();
                messenger?.showSnackBar(SnackBar(content: Text('„${routine.name}“ steht jetzt unter Trainingspläne.')));
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// „3 × 8–10 · 60 kg · Pause 90 s“.
String _detail(RoutineItem item) {
  final reps = item.lowerReps == item.upperReps ? '${item.lowerReps}' : '${item.lowerReps}–${item.upperReps}';
  final kg = item.weightKg;
  final weight = kg == null || kg == 0 ? '' : ' · ${GermanFormat.number(kg)} kg';
  return '${item.sets} × $reps$weight · Pause ${item.restSeconds} s';
}

/// Knopf „Teilen …“ für Listen und Kopfzeilen.
class GymShareButton extends StatelessWidget {
  const GymShareButton({super.key, required this.onShare});

  final Future<void> Function(BuildContext context) onShare;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) =>
        IconButton(tooltip: 'Teilen', icon: const Icon(Icons.ios_share), onPressed: () => unawaited(onShare(context))),
  );
}
