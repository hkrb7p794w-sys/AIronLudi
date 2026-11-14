import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/alarm/wake_alarm_service.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';

/// Wecker zur Aufstehzeit stellen: Weckzeit aus dem Schlaf-Coach oder „jetzt ins Bett“ plus Schlafbedarf (Port von
/// `WakeAlarmSection`).
class WakeAlarmSection extends ConsumerStatefulWidget {
  const WakeAlarmSection({super.key, required this.wake, required this.tonightMinutes});

  /// Weckzeit laut Schlaf-Coach.
  final WakeTime wake;

  /// Schlafbedarf heute Nacht in Minuten (für „jetzt ins Bett“).
  final int tonightMinutes;

  @override
  ConsumerState<WakeAlarmSection> createState() => _WakeAlarmSectionState();
}

class _WakeAlarmSectionState extends ConsumerState<WakeAlarmSection> {
  WakeRepeat _repeats = WakeRepeat.once;
  bool _busy = false;
  String? _confirmation;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(wakeAlarmServiceProvider).refreshState().then((_) => _syncSleepCoach()));
  }

  WakeTime get _sleepNow {
    final now = DateTime.now();
    return WakePlan.wakeIfSleepingNow(nowMinutes: now.hour * 60 + now.minute, sleepMinutes: widget.tonightMinutes);
  }

  /// Der gestellte Wecker bestimmt die empfohlene Schlafenszeit.
  void _syncSleepCoach() {
    if (!mounted) return;
    final stored = ref.read(wakeAlarmServiceProvider).stored;
    final alarm = stored == null
        ? null
        : SleepAlarm(
            minutes: stored.time.minutes,
            onlyDay: stored.repeats == WakeRepeat.once
                ? CalendarDay.fromDate(WakePlan.nextDate(stored.time, now: DateTime.now()))
                : null,
            weekdaysOnly: stored.repeats == WakeRepeat.weekdays,
          );
    final settings = ref.read(coachSettingsProvider);
    if (settings.sleep.alarm != alarm) settings.sleep = settings.sleep..alarm = alarm;
  }

  Future<void> _set(WakeTime time, {WakeRepeat? repeats}) async {
    setState(() {
      _busy = true;
      _confirmation = null;
    });
    final ok = await ref.read(wakeAlarmServiceProvider).schedule(time, repeats: repeats ?? _repeats);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _confirmation = 'Wecker für ${time.text} Uhr gestellt.';
    });
    _syncSleepCoach();
  }

  @override
  Widget build(BuildContext context) {
    final alarms = ref.watch(wakeAlarmServiceProvider);
    final stored = alarms.stored;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final sleepNow = _sleepNow;
    final now = DateTime.now();
    return FormSection(
      header: 'Wecker',
      footer: alarms.state == WakeAlarmState.denied
          ? 'Wecker sind für AIronLudi nicht erlaubt (Einstellungen des Geräts › AIronLudi).'
          : 'Ein echter Systemwecker (klingelt auch lautlos und im Fokus). Beim ersten Mal fragt das Gerät nach '
                'Erlaubnis; ein neuer Wecker ersetzt den alten.',
      children: [
        if (stored != null) ...[
          LabeledRow(
            label: 'Wecker gestellt',
            value: stored.repeats == WakeRepeat.once
                ? '${WakePlan.dayLabel(WakePlan.nextDate(stored.time, now: now), now: now)} ${stored.time.text} Uhr'
                : '${stored.time.text} Uhr · ${stored.repeats.label}',
          ),
          ListTile(
            leading: const Icon(Icons.alarm_off, color: Colors.red),
            title: const Text('Wecker löschen', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await alarms.cancel();
              setState(() => _confirmation = null);
              _syncSleepCoach();
            },
          ),
        ],
        if (alarms.isSupported) ...[
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<WakeRepeat>(
                segments: [
                  for (final repeat in WakeRepeat.values) ButtonSegment(value: repeat, label: Text(repeat.label)),
                ],
                selected: {_repeats},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => setState(() => _repeats = selection.first),
              ),
            ),
          ),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.alarm),
            title: Text('Wecker für ${widget.wake.text} Uhr stellen'),
            onTap: () => _set(widget.wake),
          ),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.bed),
            title: Text(
              'Jetzt ins Bett: Wecker ${sleepNow.text} Uhr (${GermanFormat.decimal(widget.tonightMinutes / 60)} h)',
            ),
            onTap: () => _set(sleepNow, repeats: WakeRepeat.once),
          ),
        ] else
          ListTile(
            title: Text(
              'Einen Wecker kann die App auf diesem Gerät nicht stellen. Stelle ihn in der Uhr-App auf '
              '${widget.wake.text} Uhr – oder nutze die Schlafenszeit-Erinnerung.',
              style: TextStyle(color: secondary),
            ),
          ),
        if (_confirmation case final confirmation?)
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(confirmation, style: const TextStyle(color: Colors.green)),
          ),
        if (alarms.lastError case final error?)
          ListTile(
            title: Text(error, style: const TextStyle(fontSize: 13, color: Colors.red)),
          ),
      ],
    );
  }
}
