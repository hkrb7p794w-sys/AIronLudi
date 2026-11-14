import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/providers.dart';
import 'gym_controller.dart';
import 'gym_providers.dart';

/// Laufende Einheit – vorläufige Liste mit Abhaken und Beenden. Die Fokus-Karte, Pausen, Ziffernblock und Abschluss
/// aus `ActiveWorkoutView.swift` folgen in Phase 3e-3.
class ActiveWorkoutScreen extends ConsumerWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gym = ref.watch(gymControllerProvider);
    final session = gym.active;
    return Scaffold(
      appBar: AppBar(
        title: Text(session?.title ?? 'Krafttraining'),
        actions: [
          if (session != null)
            TextButton(
              onPressed: gym.isSaving ? null : () => _finish(context, ref, gym),
              child: const Text('Beenden', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: session == null
          ? const Center(child: Text('Keine laufende Einheit.'))
          : ListView(
              children: [
                for (final exercise in session.exercises)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: Text(exercise.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        for (final (index, set) in exercise.sets.indexed)
                          CheckboxListTile(
                            value: set.done,
                            onChanged: (_) => gym.toggleDone(set: index, of: exercise.id),
                            title: Text(
                              'Satz ${index + 1}: '
                              '${set.weightKg != 0 ? '${GermanFormat.number(set.weightKg)} kg × ' : ''}${set.reps}',
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: () {
                      gym.cancelActive();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Einheit verwerfen', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _finish(BuildContext context, WidgetRef ref, GymController gym) async {
    final saved = await gym.finish(
      repository: ref.read(gymRepositoryProvider),
      writer: ref.read(workoutWriterProvider),
      strength: ref.read(garminStrengthServiceProvider),
      garmin: ref.read(garminConnectProvider),
    );
    if (saved != null && context.mounted) Navigator.of(context).pop();
  }
}
