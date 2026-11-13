import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/settings_store.dart';
import '../../data/storage.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import 'settings_sections.dart';

/// Ziel, Ernährungsweise und Körperwerte für die Tagesziele. Leere Körperwerte = Werte aus Garmin.
class NutritionSettingsScreen extends ConsumerWidget {
  const NutritionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final store = ref.watch(settingsStoreProvider);
    final garmin = ref.watch(appModelProvider).sync.profile;
    final nutrition = settings.nutrition;
    final personal = settings.profile.mode == ProfileMode.personal;
    void change(void Function(NutritionSettings value) update) {
      final copy = nutrition.copy();
      update(copy);
      settings.nutrition = copy;
    }

    final reminders = settings.reminders;
    void changeMeal(MealCategory category, MealReminderSlot slot) {
      final copy = reminders.copy();
      copy.meals[category] = slot;
      settings.reminders = copy;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ernährung')),
      body: ListView(
        children: [
          FormSection(
            footer: personal
                ? 'Das Ziel änderst du im Profil (Einstellungen). Defizit und Überschuss gelten voll an Ruhe- und '
                      'leichten Tagen, halb an moderaten, an harten Tagen nicht.'
                : 'Abnehmen: −15 % an Ruhe- und leichten Tagen, halb so viel an moderaten, keins an harten Tagen.',
            children: [
              if (personal) ...[
                // Ziel und Tempo kommen aus dem Profil (mit Schutzgrenzen), nicht von Hand.
                LabeledRow(label: 'Ziel', value: nutrition.goal.label),
                if (nutrition.weeklyWeightChangePercent case final rate?)
                  LabeledRow(label: 'Tempo', value: '${GermanFormat.decimal(rate)} % pro Woche'),
              ] else
                ListTile(
                  title: const Text('Ziel'),
                  trailing: DropdownButton<NutritionGoal>(
                    value: nutrition.goal,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final goal in NutritionGoal.values) DropdownMenuItem(value: goal, child: Text(goal.label)),
                    ],
                    onChanged: (goal) => change((value) => value.goal = goal ?? value.goal),
                  ),
                ),
              ListTile(
                title: const Text('Ernährungsweise'),
                trailing: DropdownButton<Diet>(
                  value: nutrition.diet,
                  underline: const SizedBox.shrink(),
                  items: [for (final diet in Diet.values) DropdownMenuItem(value: diet, child: Text(diet.label))],
                  onChanged: (diet) => change((value) => value.diet = diet ?? value.diet),
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Körperwerte',
            footer: 'Leer lassen, um die Werte aus Garmin zu nutzen. Körperfett ohne Angabe: 15 % (Männer) bzw. 25 %.',
            children: [
              _OptionalNumberField(
                title: 'Gewicht',
                unit: 'kg',
                value: nutrition.weightKilograms,
                placeholder: garmin?.weightKilograms,
                onChanged: (number) => change((value) => value.weightKilograms = number),
              ),
              _OptionalNumberField(
                title: 'Größe',
                unit: 'cm',
                value: nutrition.heightCentimeters,
                placeholder: garmin?.heightCentimeters,
                onChanged: (number) => change((value) => value.heightCentimeters = number),
              ),
              _OptionalNumberField(
                title: 'Körperfett',
                unit: '%',
                value: nutrition.bodyFatPercent,
                onChanged: (number) => change((value) => value.bodyFatPercent = number),
              ),
              ListTile(
                title: Text('Aktivitätsfaktor ohne Sport ${GermanFormat.decimal(nutrition.activityFactor)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Weniger',
                      icon: const Icon(Icons.remove),
                      onPressed: nutrition.activityFactor <= 1.2
                          ? null
                          : () => change(
                              (value) => value.activityFactor = ((value.activityFactor - 0.1) * 10).round() / 10,
                            ),
                    ),
                    IconButton(
                      tooltip: 'Mehr',
                      icon: const Icon(Icons.add),
                      onPressed: nutrition.activityFactor >= 2.0
                          ? null
                          : () => change(
                              (value) => value.activityFactor = ((value.activityFactor + 0.1) * 10).round() / 10,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          FormSection(
            header: 'Erinnerungen an Mahlzeiten',
            footer:
                'Zur gewohnten Zeit kommt eine Mitteilung – aber nur, wenn die Mahlzeit an dem Tag noch nicht erfasst '
                'ist. Die Zeiten gelten in der aktuellen Zeitzone, auch auf Reisen.',
            children: [
              for (final category in MealReminderSettings.categories) ...[
                SwitchListTile(
                  title: Text(category.label),
                  value: reminders.meals[category]?.enabled ?? false,
                  onChanged: (on) => changeMeal(
                    category,
                    (reminders.meals[category] ?? MealReminderSlot(hour: 12, minute: 0)).copyWith(enabled: on),
                  ),
                ),
                if (reminders.meals[category] case final slot? when slot.enabled)
                  ListTile(
                    title: const Text('Uhrzeit'),
                    trailing: Text(timeText(context, slot.hour, slot.minute)),
                    onTap: () async {
                      final time = await pickTime(context, slot.hour, slot.minute);
                      if (time != null) {
                        changeMeal(category, MealReminderSlot(enabled: true, hour: time.hour, minute: time.minute));
                      }
                    },
                  ),
              ],
            ],
          ),
          FormSection(
            header: 'Erinnerung',
            children: [
              SwitchListTile(
                title: const Text('Abends um 20 Uhr „Tag auswerten“'),
                value: reminders.nutritionReview,
                onChanged: (on) => settings.reminders = reminders.copy()..nutritionReview = on,
              ),
            ],
          ),
          FormSection(
            footer:
                'Farbig und in voller Breite: Serie und je Mahlzeit ein Ring mit „+“ zum Eintragen (Live-Aktivität). '
                'Das System blendet sie nach einigen Stunden aus; beim nächsten Öffnen der App ist sie wieder da.',
            children: [
              _StoredSwitch(
                title: 'Mahlzeiten auf dem Sperrbildschirm',
                store: store,
                settingKey: SettingsKeys.mealsLiveActivity,
              ),
            ],
          ),
          const FormSection(
            header: 'Nährwertquellen',
            footer:
                '${BLS.attribution}. Die KI zerlegt Mahlzeiten nur in Lebensmittel; die Nährwerte kommen aus dem BLS. '
                'Ohne passenden Eintrag bleibt die KI-Schätzung (in der Mahlzeit als „geschätzt“ markiert).',
            children: [
              LabeledRow(label: 'Lebensmittel', value: 'BLS 4.0'),
              LabeledRow(label: 'Markenprodukte (Barcode)', value: 'Open Food Facts'),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _OptionalNumberField extends StatefulWidget {
  const _OptionalNumberField({
    required this.title,
    required this.unit,
    required this.value,
    this.placeholder,
    required this.onChanged,
  });

  final String title;
  final String unit;
  final double? value;
  final double? placeholder;
  final ValueChanged<double?> onChanged;

  @override
  State<_OptionalNumberField> createState() => _OptionalNumberFieldState();
}

class _OptionalNumberFieldState extends State<_OptionalNumberField> {
  late final _text = TextEditingController(text: widget.value == null ? '' : GermanFormat.decimal(widget.value!));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(widget.title),
    trailing: SizedBox(
      width: 180,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _text,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: widget.placeholder == null ? '–' : '${GermanFormat.decimal(widget.placeholder!)} (Garmin)',
                border: InputBorder.none,
              ),
              onChanged: (text) => widget.onChanged(text.trim().isEmpty ? null : parseNumber(text)),
            ),
          ),
          const SizedBox(width: 6),
          Text(widget.unit, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    ),
  );
}

/// Schalter für einen einfachen Gerätewert (wie `@AppStorage`).
class _StoredSwitch extends StatefulWidget {
  const _StoredSwitch({required this.title, required this.store, required this.settingKey});

  final String title;
  final SettingsStore store;
  final String settingKey;

  @override
  State<_StoredSwitch> createState() => _StoredSwitchState();
}

class _StoredSwitchState extends State<_StoredSwitch> {
  late bool _on = widget.store.boolValue(widget.settingKey);

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(widget.title),
    value: _on,
    onChanged: (on) {
      setState(() => _on = on);
      widget.store.setBool(widget.settingKey, on);
    },
  );
}
