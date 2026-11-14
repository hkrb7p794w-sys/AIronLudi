import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/sport_style.dart';
import '../../ui/symbols.dart';

/// Auslassen, Verschieben und Rückgängig für die Einheiten eines Tages – nur für diese Woche
/// (Port von `PlanDayActions`).
class PlanDayActions extends ConsumerWidget {
  const PlanDayActions({super.key, required this.day, this.suggested});

  final CalendarDay day;

  /// Vom Tagesampel vorgeschlagener Zieltag (zuerst angeboten).
  final Weekday? suggested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final reminders = ref.read(reminderServiceProvider);
    final weekday = Weekday.of(day);
    final schedule = settings.schedule(day);
    final note = settings.planAdjustments.note(weekday, inWeekOf: day);
    var options = PlanMoveAdvisor.options(weekday, schedule: schedule, profile: settings.profile, today: day);
    if (suggested case final target? when options.contains(target)) {
      options = [target, ...options.where((other) => other != target)];
    }
    // Nebeneinander, wenn genug Platz ist; sonst untereinander (kleines Telefon, große Schrift).
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (schedule.slots(weekday).isNotEmpty) ...[
          if (options.isNotEmpty)
            PopupMenuButton<Weekday>(
              onSelected: (target) => reminders.move(day, to: target),
              itemBuilder: (_) => [
                for (final target in options)
                  PopupMenuItem(
                    value: target,
                    child: Text(target == suggested ? '${target.long} (empfohlen)' : target.long),
                  ),
              ],
              child: const _ActionChip(icon: Icons.subdirectory_arrow_right, label: 'Verschieben'),
            ),
          ActionChip(
            avatar: const Icon(Icons.skip_next, size: 18),
            label: const Text('Diese Woche auslassen'),
            onPressed: () => reminders.skip(day),
          ),
        ],
        if (note != null)
          ActionChip(
            avatar: const Icon(Icons.undo, size: 18),
            label: const Text('Rückgängig'),
            onPressed: () => settings.planAdjustments = settings.planAdjustments..undo(weekday, inWeekOf: day),
          ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 18), label: Text(label));
}

/// Aus einer Mitteilung geöffnet: Einheit des Tages verschieben oder auslassen (Port von `AdjustDaySheet`).
class AdjustDaySheet extends ConsumerWidget {
  const AdjustDaySheet({super.key, required this.day});

  final CalendarDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final reminders = ref.read(reminderServiceProvider);
    final weekday = Weekday.of(day);
    final schedule = settings.schedule(day);
    final slots = schedule.slots(weekday);
    final options = PlanMoveAdvisor.options(
      weekday,
      schedule: schedule,
      profile: settings.profile,
      today: CalendarDay.today(),
      limit: 6,
    );
    String describe(List<SessionSlot> slots) => slots.isEmpty ? 'frei' : slots.map((slot) => slot.chipLabel).join(', ');
    final note = settings.planAdjustments.note(weekday, inWeekOf: day);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einheit anpassen'),
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen'))],
      ),
      body: ListView(
        children: [
          if (slots.isEmpty)
            FormSection(
              children: [
                ListTile(
                  title: Text(note == null ? 'Für ${weekday.long} ist nichts geplant.' : '${weekday.long}: $note.'),
                ),
              ],
            )
          else ...[
            FormSection(
              header: weekday.long,
              children: [
                for (final slot in slots)
                  ListTile(leading: Icon(AppSymbols.of(slot.sport.symbol)), title: Text(slot.title)),
              ],
            ),
            FormSection(
              header: 'Verschieben auf',
              footer: options.isEmpty
                  ? 'Diese Woche ist kein späterer Tag mehr frei.'
                  : 'Die besten Tage stehen oben: möglichst kein harter Tag direkt neben einem anderen.',
              children: [
                for (final target in options)
                  ListTile(
                    title: Text(target.long),
                    trailing: Text(describe(schedule.slots(target))),
                    onTap: () {
                      reminders.move(day, to: target);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            FormSection(
              footer: 'Der Wochenplan selbst bleibt unverändert; nächste Woche gilt er wieder.',
              children: [
                ListTile(
                  title: const Text('Diese Woche auslassen', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    reminders.skip(day);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
