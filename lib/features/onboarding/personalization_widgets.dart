import 'package:coach_core/coach_core.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../app/app_model.dart';
import '../../ui/components.dart';

/// Hauptziel (eins) und Nebenziele (bis zu zwei, optional).
class GoalsPicker extends StatelessWidget {
  const GoalsPicker({super.key, required this.goals, required this.onChanged});

  final PersonalGoals goals;
  final ValueChanged<PersonalGoals> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hauptziel', style: text.titleMedium),
        const SizedBox(height: 8),
        for (final goal in TrainingGoal.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectionCard(
              title: goal.label,
              detail: goal == goals.primary ? goal.effect : null,
              symbol: goal.symbol,
              color: accent,
              isSelected: goals.primary == goal,
              onTap: () => onChanged(
                goals.copyWith(primary: goal, secondary: goals.secondary.where((other) => other != goal).toList()),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text('Nebenziele (optional, bis zu ${PersonalGoals.maxSecondary})', style: text.titleMedium),
        ),
        FlowChips<TrainingGoal>(
          items: TrainingGoal.values.where((goal) => goal != goals.primary).toList(),
          label: (goal) => goal.label,
          isSelected: goals.secondary.contains,
          onToggle: (goal) {
            final secondary = [...goals.secondary];
            if (secondary.contains(goal)) {
              secondary.remove(goal);
            } else if (secondary.length < PersonalGoals.maxSecondary) {
              secondary.add(goal);
            }
            onChanged(goals.copyWith(secondary: secondary));
          },
        ),
      ],
    );
  }
}

/// Was besonders wichtig ist (bis zu drei, Reihenfolge = Wichtigkeit). Ohne Auswahl gelten die Standards zum Ziel.
class PrioritiesPicker extends StatelessWidget {
  const PrioritiesPicker({super.key, required this.goals, required this.onChanged});

  final PersonalGoals goals;
  final ValueChanged<PersonalGoals> onChanged;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowChips<FocusArea>(
          items: FocusArea.values,
          label: (area) {
            final index = goals.priorities.indexOf(area);
            return index >= 0 ? '${index + 1}. ${area.label}' : area.label;
          },
          isSelected: goals.priorities.contains,
          onToggle: (area) {
            final priorities = [...goals.priorities];
            if (priorities.contains(area)) {
              priorities.remove(area);
            } else if (priorities.length < PersonalGoals.maxPriorities) {
              priorities.add(area);
            }
            onChanged(goals.copyWith(priorities: priorities));
          },
        ),
        if (goals.priorities.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Ohne Auswahl: ${goals.effectivePriorities.map((area) => area.label).join(', ')} – passend zu den Zielen.',
              style: muted,
            ),
          ),
        const SizedBox(height: 12),
        Text('Das ändert sich dadurch:', style: muted?.copyWith(fontWeight: FontWeight.w600)),
        Text(
          'Reihenfolge der AI-Empfehlungen unter „Heute“, Startauswahl der Gesundheits-Widgets, worauf die KI in '
          'Analysen achtet, und wie vorsichtig die Wochenbelastung steigen darf (Recovery/Gesundheit: 20 % statt '
          '30 %).',
          style: muted,
        ),
      ],
    );
  }
}

/// Fitness-Tracker: ja/nein und welche Anbieter. Ehrlich, was davon in der App wirklich geht.
class TrackerPicker extends StatelessWidget {
  const TrackerPicker({super.key, required this.setup, required this.onChanged});

  final TrackerSetup setup;
  final ValueChanged<TrackerSetup> onChanged;

  static const offered = [
    DataProvider.garmin,
    DataProvider.appleHealth,
    DataProvider.whoop,
    DataProvider.polar,
    DataProvider.fitbit,
  ];

  static String note(DataProvider provider) => switch (provider) {
    DataProvider.garmin => 'Direkt verbinden: Anmeldung mit dem Garmin-Konto.',
    DataProvider.appleHealth => 'Direkt verbinden: Import aus Apple Health einschalten.',
    DataProvider.whoop => 'Noch keine direkte Verbindung – Schlaf, Ruhepuls und Workouts kommen über Apple Health.',
    DataProvider.polar => 'Noch keine direkte Verbindung – Trainings kommen über Apple Health (Polar Flow).',
    DataProvider.fitbit =>
      'Derzeit nicht möglich: Fitbit schreibt nicht in Apple Health, die Web-API ist abgeschaltet.',
  };

  static String symbol(DataProvider provider) => switch (provider) {
    DataProvider.garmin => 'applewatch.side.right',
    DataProvider.appleHealth => 'heart.text.square.fill',
    DataProvider.whoop => 'bolt.heart',
    DataProvider.polar => 'heart.circle',
    DataProvider.fitbit => 'figure.walk.circle',
  };

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Ja')),
            ButtonSegment(value: false, label: Text('Nein')),
          ],
          selected: {?setup.usesTracker},
          emptySelectionAllowed: true,
          onSelectionChanged: (selection) =>
              onChanged(TrackerSetup(usesTracker: selection.firstOrNull, providers: setup.providers)),
        ),
        const SizedBox(height: 12),
        if (setup.usesTracker == true)
          for (final provider in offered)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectionCard(
                title: provider == DataProvider.appleHealth ? 'Apple Watch / Apple Health' : provider.label,
                detail: note(provider),
                symbol: symbol(provider),
                color: accent,
                isSelected: setup.providers.contains(provider),
                onTap: () {
                  final providers = [...setup.providers];
                  if (!providers.remove(provider)) providers.add(provider);
                  onChanged(TrackerSetup(usesTracker: setup.usesTracker, providers: providers));
                },
              ),
            )
        else if (setup.usesTracker == false)
          Text(
            'Kein Problem: Trainings trägst du in der App ein (Gym-Einheiten, „Nachtragen“). Schritte zählt das '
            'Handy über Apple Health bzw. Health Connect, wenn du es später einschaltest.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// Übernimmt Ziele und Tracker zentral: Profil (mit Verlauf), Ernährungsrichtung, Standard-Widgets, primäres Gerät.
abstract final class PersonalizationApply {
  static void apply({
    required PersonalGoals goals,
    required TrackerSetup tracker,
    required AppModel model,
    required CalendarDay today,
  }) {
    final settings = model.settings;
    final profile = settings.profile.copy();
    final before = profile.effectiveGoals(today);
    profile
      ..updateGoals(goals, on: today)
      ..tracker = tracker;
    if (profile == settings.profile) return;
    settings.profile = profile;
    if (profile.mode == ProfileMode.personal) settings.applyProfileToNutrition(model.sync.profile);
    applyDefaults(goals: goals, before: before, tracker: tracker, model: model);
  }

  /// Standard-Widgets nach den Prioritäten (nur wenn noch nicht angepasst) und primäres Gerät.
  static void applyDefaults({
    required PersonalGoals goals,
    required PersonalGoals before,
    required TrackerSetup tracker,
    required AppModel model,
  }) {
    final settings = model.settings;
    const equality = ListEquality<Object?>();
    final current = settings.healthDashboard.entries;
    final untouched =
        equality.equals(current, HealthDashboard().entries) ||
        equality.equals(
          current.map((entry) => entry.kind).toList(),
          Personalization.healthWidgets(before).take(8).toList(),
        );
    if (untouched) {
      settings.healthDashboard = HealthDashboard(
        entries: [for (final kind in Personalization.healthWidgets(goals).take(8)) HealthDashboardEntry(kind: kind)],
      );
    }
    // Primäres Gerät: erster gewählter Tracker mit eingebauter Anbindung (nur wenn noch keins gesetzt).
    if (settings.sources.primary == null) {
      final first = tracker.providers.where((provider) => provider.availability == ProviderAvailability.available);
      if (first.isNotEmpty) settings.sources = settings.sources..primary = first.first;
    }
  }
}
