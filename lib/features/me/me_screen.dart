import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../ai/ai_screen.dart';
import '../settings/settings_screen.dart';
import '../social/social_views.dart';

/// Reiter „Ich“ (Roast Stufe 4, docs/roast/design-konzept.md Abschnitt 2): Benutzer und Konto, Freunde & Liga, KI und
/// alle Einstellungen an einem sichtbaren Ort – vorher nur über das Zahnrad auf „Heute“ bzw. ein Symbol in
/// „Aktivitäten“ erreichbar.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsScreen(isTab: true);
}

/// Oberer Block von „Ich“: soziale Funktionen und KI.
class MeShortcutsSection extends ConsumerWidget {
  const MeShortcutsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming = ref.watch(socialServiceProvider).incomingCount;
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return FormSection(
      children: [
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: const Text('Freunde & Liga'),
          subtitle: Text(incoming > 0 ? '$incoming neue Anfragen' : 'Feed, Freunde, Rangliste, Challenges'),
          trailing: const DisclosureChevron(),
          onTap: () => open(const FriendsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('KI'),
          subtitle: const Text('Empfehlungen, Analyse, Chat, Export und Import'),
          trailing: const DisclosureChevron(),
          onTap: () => open(const AIScreen()),
        ),
      ],
    );
  }
}
