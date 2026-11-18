import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../ui/components.dart';

/// „Heute anpassen“: Bereiche der Startseite ein- und ausblenden (auch die AI-Empfehlungen ganz).
class TodayDashboardEditor extends ConsumerWidget {
  const TodayDashboardEditor({super.key});

  static String? _detail(TodayModule module) => switch (module) {
    TodayModule.kpis => 'Drei Ringe mit Ampelfarben; Strain auf einer Skala von 0 bis 21.',
    TodayModule.training => 'Jetzt dran, Geplantes und heute Erledigtes mit Dauer, Puls und Strain.',
    TodayModule.ai => 'Empfehlungen aus Regeln und KI. Export und Import für externe KI bleiben in den Einstellungen.',
    TodayModule.suggestions => 'Plan an Tagesform und Wochenbelastung anpassen.',
    TodayModule.strainDetails => 'Balken mit Erledigtem, Geplantem und dem üblichen Tag.',
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(coachSettingsProvider);
    final dashboard = settings.todayDashboard;
    return Scaffold(
      appBar: AppBar(title: const Text('Heute anpassen')),
      body: ListView(
        children: [
          FormSection(
            header: 'Bereiche',
            footer: 'Reihenfolge fest: oben Schlaf, Erholung und Strain, darunter das Training des Tages.',
            children: [
              for (final module in TodayModule.values)
                SwitchListTile.adaptive(
                  title: Text(module.label),
                  subtitle: switch (_detail(module)) {
                    final detail? => Text(detail),
                    null => null,
                  },
                  value: dashboard.shows(module),
                  onChanged: (visible) =>
                      settings.todayDashboard = TodayDashboard(hidden: {...dashboard.hidden})
                        ..set(module, visible: visible),
                ),
            ],
          ),
          FormSection(
            children: [
              ListTile(
                title: const Text('Standard wiederherstellen'),
                onTap: () => settings.todayDashboard = TodayDashboard(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
