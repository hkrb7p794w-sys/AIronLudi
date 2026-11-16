import 'dart:async';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/settings_store.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../services/widgets/widget_providers.dart';
import '../../ui/components.dart';

/// Live-Aktivitäten auf dem Sperrbildschirm an einem Ort: welche Bereiche (Gym, Ernährung) erscheinen dürfen, was die
/// Karte der Einheit zeigt und ob die Erinnerung an Mahlzeiten dort statt als Mitteilung steht. Während einer Einheit
/// hat die Einheit Vorrang (`LockScreenActivities`).
class LockScreenSettingsScreen extends ConsumerStatefulWidget {
  const LockScreenSettingsScreen({super.key});

  @override
  ConsumerState<LockScreenSettingsScreen> createState() => _LockScreenSettingsScreenState();
}

class _LockScreenSettingsScreenState extends ConsumerState<LockScreenSettingsScreen> {
  late final SettingsStore _store = ref.read(settingsStoreProvider);
  late bool _meals = _store.boolValue(SettingsKeys.mealsLiveActivity);
  late bool _mealReminders = _store.boolValue(SettingsKeys.mealsLiveReminders);

  /// Neuen Stand sofort zeigen bzw. beenden und die Mitteilungen neu planen.
  Future<void> _apply() async {
    await ref.read(widgetPublisherProvider).publish();
    await ref.read(appModelProvider).refreshReminders();
  }

  Future<void> _setMeals(bool on) async {
    setState(() => _meals = on);
    await _store.setBool(SettingsKeys.mealsLiveActivity, on);
    await _apply();
  }

  Future<void> _setMealReminders(bool on) async {
    setState(() => _mealReminders = on);
    await _store.setBool(SettingsKeys.mealsLiveReminders, on);
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(coachSettingsProvider);
    final gym = settings.gym;
    final trainsStrength = settings.profile.trains(TrainingSport.strength);
    void change(void Function(GymSettings gym) edit) {
      edit(gym);
      settings.gym = gym;
    }

    final android = !Platform.isIOS;
    return Scaffold(
      appBar: AppBar(title: const Text('Sperrbildschirm')),
      body: ListView(
        children: [
          FormSection(
            header: 'Erlaubte Bereiche',
            footer:
                'Läuft eine Gym-Einheit, hat sie Vorrang: „Mahlzeiten heute“ tritt so lange zurück und erscheint nach '
                'der Einheit wieder. ${android ? 'Unter Android als dauerhafte, lautlose Mitteilung.' : 'Abschalten '
                          'lässt sich alles auch in den iOS-Einstellungen unter AIronLudi › Live-Aktivitäten.'}',
            children: [
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.fitness_center),
                title: const Text('Gym-Einheit'),
                subtitle: Text(trainsStrength ? 'Pause und nächster Satz' : 'Krafttraining ist nicht im Profil'),
                value: gym.liveActivity,
                onChanged: (value) => change((gym) => gym.liveActivity = value),
              ),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.restaurant),
                title: const Text('Ernährung'),
                subtitle: const Text('Mahlzeiten heute, Serie und übrige Kalorien'),
                value: _meals,
                onChanged: (on) => unawaited(_setMeals(on)),
              ),
            ],
          ),
          if (gym.liveActivity)
            FormSection(
              header: 'Ansicht der Gym-Einheit',
              children: [
                RadioGroup<WorkoutActivityLayout>(
                  groupValue: gym.liveActivityLayout,
                  onChanged: (layout) {
                    if (layout != null) change((gym) => gym.liveActivityLayout = layout);
                  },
                  child: Column(
                    children: [
                      for (final layout in WorkoutActivityLayout.values)
                        RadioListTile<WorkoutActivityLayout>(
                          value: layout,
                          title: Text(layout.label),
                          subtitle: Text(layout.detail),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          FormSection(
            header: 'Erinnerung an Mahlzeiten',
            footer:
                'Statt einer Mitteilung zeigt „Mahlzeiten heute“ die nächste Mahlzeit – zur gewohnten Zeit (Einstellungen '
                '› Ernährung) als „Zeit fürs Mittagessen“, ohne Ton und ohne Banner. Mitteilungen für Mahlzeiten '
                'entfallen dann. Ohne eingeschaltete Essenszeiten gelten 8:00, 12:30 und 19:00 Uhr. Öffnest du die App '
                'länger nicht, blendet das System die Karte nach einigen Stunden aus – dann erscheint auch keine '
                'Erinnerung.',
            children: [
              SwitchListTile.adaptive(
                title: const Text('Auf dem Sperrbildschirm statt als Mitteilung'),
                value: _meals && _mealReminders,
                onChanged: _meals ? (on) => unawaited(_setMealReminders(on)) : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
