// Wochenplan-Editor: „Entfernen“ im Menü einer Einheit (Fehler: Menüwert `null` wurde von Flutter als Abbruch
// gewertet, die Einheit blieb stehen).
import 'package:aironludi/features/onboarding/schedule_editor.dart';
import 'package:aironludi/ui/sport_style.dart';
import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Einheit entfernen und Intensität ändern', (tester) async {
    var schedule = WeekSchedule()
        .withSlots(const [SessionSlot(TrainingSport.strength, SessionIntensity.hard)], Weekday.monday)
        .withSlots(const [SessionSlot(TrainingSport.run)], Weekday.tuesday);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: ScheduleEditor(
                schedule: schedule,
                sports: const [TrainingSport.strength, TrainingSport.run],
                onChanged: (updated) => setState(() => schedule = updated),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(const SessionSlot(TrainingSport.strength, SessionIntensity.hard).chipLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    expect(schedule.slots(Weekday.monday), isEmpty);
    expect(schedule.slots(Weekday.tuesday), hasLength(1));

    await tester.tap(find.text(const SessionSlot(TrainingSport.run).chipLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SessionIntensity.long.label));
    await tester.pumpAndSettle();
    expect(schedule.slots(Weekday.tuesday).single.intensity, SessionIntensity.long);
  });
}
