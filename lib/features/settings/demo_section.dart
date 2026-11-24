import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/user_providers.dart';
import '../../data/settings/settings_store.dart';
import '../../data/storage.dart';
import '../../services/demo/demo_seed.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';

/// Demo-Modus (Roast F-1, Stufe 3 / PR 17): ein eigener Benutzer „Demo“ mit erfundenen Daten (35 Tage Tageswerte,
/// Training, Mahlzeiten, Gewicht), um die App zu zeigen oder auszuprobieren. Getrennt wie jeder Benutzer (eigene
/// Datenbank, Schlüssel, Ordner); der Schlüssel `coach.demo` macht ihn zum Demo-Benutzer: nichts wird abgerufen,
/// gesichert, geteilt oder an Widgets gegeben. Zurück über „Benutzer“; dort lässt er sich auch löschen.
class DemoSection extends ConsumerWidget {
  const DemoSection({super.key});

  static const username = 'demo';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final isDemo = ref.watch(appModelProvider).isDemo;
    return FormSection(
      header: 'Demo',
      footer: isDemo
          ? 'Du siehst die Demo. Zurück zu deinen Daten über „Benutzer“ oben unter „Ich“.'
          : 'Legt einen eigenen Benutzer „Demo“ mit erfundenen Daten an. Deine Daten bleiben unberührt; zurück geht es '
                'über „Benutzer“.',
      children: [
        if (!isDemo)
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Demo ansehen'),
            trailing: const DisclosureChevron(),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Demo ansehen?'),
                  content: const Text(
                    'Die App wechselt zum Benutzer „Demo“ mit erfundenen Daten. Deine Daten bleiben unverändert.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
                    TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Demo öffnen')),
                  ],
                ),
              );
              if (ok != true) return;
              final existing = session.users.where((user) => user.username == username).firstOrNull;
              if (existing != null) {
                await session.switchTo(existing.id);
                return;
              }
              await session.add(username: username, displayName: 'Demo');
              // Der neue Container gehört jetzt dem Demo-Benutzer (dieses Widget ist schon abgebaut).
              final container = session.container;
              await container.read(settingsStoreProvider).setBool(SettingsKeys.demo, true);
              await seedDemo(container);
              container.invalidate(appModelProvider);
            },
          ),
      ],
    );
  }
}
