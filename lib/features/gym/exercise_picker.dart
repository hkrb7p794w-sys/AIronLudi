import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';

/// Filter nach Muskelgruppe als Chips („Alle“ hebt ihn auf).
class MuscleGroupChips extends StatelessWidget {
  const MuscleGroupChips({super.key, required this.selection, required this.onChanged});

  final MuscleGroup? selection;
  final ValueChanged<MuscleGroup?> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      spacing: 8,
      children: [
        ChoiceChip(label: const Text('Alle'), selected: selection == null, onSelected: (_) => onChanged(null)),
        for (final group in MuscleGroup.values.where((group) => group != MuscleGroup.other))
          ChoiceChip(
            label: Text(group.rawValue),
            selected: selection == group,
            onSelected: (_) => onChanged(selection == group ? null : group),
          ),
      ],
    ),
  );
}

/// Name, Geräte und „eigene Übung“.
class ExerciseLabel extends StatelessWidget {
  const ExerciseLabel({super.key, required this.exercise, this.onTap, this.trailing});

  final ExerciseInfo exercise;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final detail = [
      exercise.equipment.map((item) => item.label).join(' / '),
      if (exercise.isCustom) 'eigene Übung',
    ].where((text) => text.isNotEmpty).join(' · ');
    return ListTile(
      title: Text(exercise.name),
      subtitle: detail.isEmpty ? null : Text(detail),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Übung auswählen (für Training und Routinen); gibt die gewählte Übung zurück (Port von `ExercisePickerView`).
class ExercisePickerScreen extends ConsumerStatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  ConsumerState<ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends ConsumerState<ExercisePickerScreen> {
  final _search = TextEditingController();
  MuscleGroup? _filter;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gym = ref.watch(coachSettingsProvider).gym;
    final items = ExerciseLibrary.search(_search.text, custom: gym.customExercises, available: gym.equipment);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Übung wählen'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Übung suchen',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        children: [
          MuscleGroupChips(selection: _filter, onChanged: (group) => setState(() => _filter = group)),
          for (final group in MuscleGroup.values.where((group) => _filter == null || group == _filter))
            if (items.where((item) => item.group == group).toList() case final inGroup when inGroup.isNotEmpty)
              FormSection(
                header: group.rawValue,
                children: [
                  for (final exercise in inGroup)
                    ExerciseLabel(exercise: exercise, onTap: () => Navigator.of(context).pop(exercise)),
                ],
              ),
          FormSection(
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Eigene Übung anlegen'),
                onTap: () async {
                  final exercise = await Navigator.of(context).push<ExerciseInfo>(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => CustomExerciseEditor(initialName: _search.text),
                    ),
                  );
                  if (exercise != null && context.mounted) Navigator.of(context).pop(exercise);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eigene Übung: Name, Muskel, Gerät, Erfassung; wird in den Gym-Einstellungen gespeichert.
class CustomExerciseEditor extends ConsumerStatefulWidget {
  const CustomExerciseEditor({super.key, this.initialName = ''});

  final String initialName;

  @override
  ConsumerState<CustomExerciseEditor> createState() => _CustomExerciseEditorState();
}

class _CustomExerciseEditorState extends ConsumerState<CustomExerciseEditor> {
  late final _name = TextEditingController(text: widget.initialName);
  MuscleGroup _group = MuscleGroup.chest;
  Equipment _equipment = Equipment.dumbbell;
  ExerciseTracking _tracking = ExerciseTracking.weightReps;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _picker<T>(String label, T value, List<(T, String)> options, ValueChanged<T> onChanged) => ListTile(
    title: Text(label),
    trailing: DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      items: [for (final (option, text) in options) DropdownMenuItem(value: option, child: Text(text))],
      onChanged: (option) {
        if (option != null) setState(() => onChanged(option));
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Eigene Übung'),
      leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
      leadingWidth: 100,
      actions: [
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => TextButton(
            onPressed: _name.text.trim().isEmpty
                ? null
                : () {
                    final exercise = ExerciseInfo.custom(
                      name: _name.text,
                      group: _group,
                      equipment: _equipment,
                      tracking: _tracking,
                    );
                    final settings = ref.read(coachSettingsProvider);
                    settings.gym = settings.gym..addCustom(exercise);
                    Navigator.of(context).pop(exercise);
                  },
            child: const Text('Sichern'),
          ),
        ),
      ],
    ),
    body: ListView(
      children: [
        FormSection(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            ),
            _picker('Muskel', _group, [for (final group in MuscleGroup.values) (group, group.rawValue)], (value) {
              _group = value;
            }),
            _picker('Gerät', _equipment, [for (final item in Equipment.values) (item, item.label)], (value) {
              _equipment = value;
            }),
            _picker('Erfassung', _tracking, const [
              (ExerciseTracking.weightReps, 'Gewicht × Wiederholungen'),
              (ExerciseTracking.reps, 'Nur Wiederholungen'),
              (ExerciseTracking.time, 'Haltezeit (Sekunden)'),
            ], (value) => _tracking = value),
          ],
        ),
      ],
    ),
  );
}
