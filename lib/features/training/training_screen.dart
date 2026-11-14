import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/placeholder_view.dart';
import '../gym/gym_providers.dart';
import '../gym/gym_screen.dart';

/// Reiter „Training“. Bisher nur der Einstieg ins Gym; die übrigen Inhalte folgen in Phase 3
/// (Checkliste: docs/migrationsplan.md).
class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final running = ref.watch(gymControllerProvider).active?.title;
    final theme = Theme.of(context);
    final secondary = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Training')),
      body: ListView(
        children: [
          // Früher eigener Reiter; „Training starten“ (App-Icon, Kurzbefehl, Widget) öffnet diesen Bereich direkt.
          if (settings.profile.trains(TrainingSport.strength))
            FormSection(
              children: [
                ListTile(
                  leading: const SportIcon(symbol: 'dumbbell.fill', color: Colors.green),
                  title: const Text('Gym', style: TextStyle(fontWeight: FontWeight.w500)),
                  // Auf schmalen Bildschirmen passt der Status nicht rechts neben den Titel: als Untertitel.
                  subtitle: running != null
                      ? Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'läuft',
                                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
                              ),
                              TextSpan(text: ' · $running', style: secondary),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Einheit starten',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              TextSpan(text: ' · Pläne, Übungen, Auswertung', style: secondary),
                            ],
                          ),
                        ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GymScreen())),
                ),
              ],
            ),
          const SizedBox(height: 400, child: PlaceholderView()),
        ],
      ),
    );
  }
}
