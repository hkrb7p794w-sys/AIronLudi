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
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';

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
                // Vorschau der gewählten Ansicht mit Beispielwerten.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: LiquidSwitcher(
                    child: LiveActivityPreview(key: ValueKey(gym.liveActivityLayout), layout: gym.liveActivityLayout),
                  ),
                ),
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

/// Vorschau der Live-Aktivität einer Gym-Einheit auf dem Sperrbildschirm (Beispielwerte). Das echte Widget bleibt
/// nativ (ActivityKit bzw. Android-Mitteilung); die Vorschau zeigt nur, welche Teile die gewählte Ansicht enthält.
class LiveActivityPreview extends StatelessWidget {
  const LiveActivityPreview({super.key, required this.layout});

  final WorkoutActivityLayout layout;

  @override
  Widget build(BuildContext context) {
    // Sperrbildschirm-Karten sind immer dunkel – unabhängig vom Erscheinungsbild der App.
    const label = TextStyle(fontSize: 13, color: Color(0x99FFFFFF), fontWeight: FontWeight.w500);
    const accent = Color(0xFF30D158);
    Widget control(String value, String unit) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: LiquidRadii.innerAll,
          border: Border.all(color: const Color(0x1FFFFFFF), width: 0.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.remove, size: 16, color: Colors.white70),
            Expanded(
              child: Text(
                '$value $unit',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppPalette.onColor, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
            const Icon(Icons.add, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
    return Semantics(
      label: 'Vorschau: ${layout.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: LiquidRadii.cardAll,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xE61C2233), Color(0xF20B0E16)],
          ),
          border: Border.all(color: const Color(0x33FFFFFF), width: 1),
          boxShadow: LiquidTheme.of(context).ambientShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    layout.showsExercise ? 'Bankdrücken · Satz 2 von 4' : 'Satzpause',
                    style: const TextStyle(color: AppPalette.onColor, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                const Text('Beispiel', style: label),
              ],
            ),
            if (layout.showsTimer)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '1:30',
                    style: LiquidText.kpi(
                      context,
                      size: layout.showsExercise ? 34 : 48,
                    ).copyWith(color: AppPalette.onColor),
                  ),
                  const SizedBox(width: 10),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('Pause', style: label),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 90,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: const LinearProgressIndicator(
                        value: 0.6,
                        minHeight: 6,
                        color: accent,
                        backgroundColor: Color(0x26FFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
            if (layout.showsExercise) Row(spacing: 8, children: [control('80', 'kg'), control('8', 'Wdh')]),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: LiquidGradients.linear(accent),
                borderRadius: BorderRadius.circular(LiquidRadii.pill),
              ),
              child: const Text(
                'Satz erledigt',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppPalette.onColor, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
