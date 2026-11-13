// Bisher offene Fälle: `prioritiesOrderDashboardAndInsights` (PersonalizationTests.swift), `seasonRemindersUseFixedDays`
// (PlanAdjustmentsTests.swift) sowie die Saisonplan-Fälle aus ReminderExtrasTests.swift (Schwimmausrüstung,
// `ReminderDoneTests`).
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

SeasonSchedule loadSchedule() => SeasonSchedule.load(File('assets/season-plan.json').readAsStringSync())!;

/// Montag, 26.10.2026: In dieser Woche braucht die Schwimmeinheit einen Pull-Buoy.
const monday = CalendarDay(2026, 10, 26);

void main() {
  final schedule = loadSchedule();

  test('Prioritäten ordnen Dashboard und Empfehlungen', () {
    const today = CalendarDay(2026, 11, 9);
    final sleep = PersonalGoals(
      primary: TrainingGoal.recovery,
      priorities: const [FocusArea.sleep, FocusArea.recovery],
      since: today,
    );
    expect(Personalization.healthWidgets(sleep).take(3), [
      HealthWidget.sleep,
      HealthWidget.hrv,
      HealthWidget.bodyBattery,
    ]);
    expect(Personalization.insightTopics(sleep).first, InsightTopic.recovery);
    final muscle = PersonalGoals(primary: TrainingGoal.muscleGain, priorities: const [FocusArea.muscle], since: today);
    expect(Personalization.insightTopics(muscle).take(2), [InsightTopic.training, InsightTopic.progress]);
    // Jedes Standard-Widget bleibt erreichbar.
    expect(Personalization.healthWidgets(muscle).toSet().containsAll(HealthDashboard.standard), isTrue);

    final now = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true);
    Insight insight(InsightTopic topic, String subject) => Insight(
      topic: topic,
      subject: subject,
      title: subject,
      text: '',
      direction: InsightDirection.check,
      origin: InsightOrigin.rules,
      created: now,
      validUntil: now.add(const Duration(days: 1)),
    );
    final groups = InsightInbox.groups(
      [insight(InsightTopic.nutrition, 'protein'), insight(InsightTopic.recovery, 'schlaf')],
      focus: Personalization.insightTopics(sleep),
      now: now,
    );
    expect(groups.newItems.map((item) => item.subject), ['schlaf', 'protein']);
  });

  test('Saisonplan-Erinnerungen an festen Tagen', () {
    final reminders = ReminderPlanner.season(
      schedule: schedule,
      config: SeasonConfig.standard,
      decisions: const {},
      today: monday,
      includeToday: true,
      days: 7,
    );
    expect(reminders, isNotEmpty);
    expect(reminders.every((reminder) => !reminder.canAdjust && reminder.titles.isNotEmpty), isTrue);
    expect(reminders.any((reminder) => reminder.titles.contains('Ruhetag')), isFalse);
  });

  test('Schwimmausrüstung am Vorabend', () {
    List<ScheduledNote> notes({
      required CalendarDay today,
      required int minutesNow,
      TrainingLog log = const TrainingLog(),
    }) => ReminderPlanner.swimEquipment(
      schedule: schedule,
      config: SeasonConfig.standard,
      decisions: const {},
      today: today,
      minutesNow: minutesNow,
      days: 7,
      log: log,
    );
    final early = notes(today: monday, minutesNow: 600);
    expect(early.map((note) => note.day), [monday, monday.adding(2)]);
    expect(
      early.every((note) => note.hour == 18 && note.minute == 0 && note.kind == ScheduledNoteKind.equipment),
      isTrue,
    );
    expect(early.first.title, 'Morgen Schwimmen: Pull-Buoy einpacken');
    expect(early.first.id, 'coach.reminder.equipment.2026-10-26');
    // Nach 18 Uhr kommt die Erinnerung für heute Abend nicht mehr.
    expect(notes(today: monday, minutesNow: 19 * 60).map((note) => note.day), [monday.adding(2)]);

    // Schon am Dienstag geschwommen: Am Donnerstag stehen die Beine an, keine Erinnerung.
    final tuesday = monday.adding(1);
    expect(notes(today: tuesday, minutesNow: 600).map((note) => note.day), [tuesday.adding(1)]);
    final swim = GarminActivity(tuesday.day)
      ..typeKey = 'lap_swimming'
      ..startLocal = '${tuesday.iso} 07:00:00'
      ..durationSeconds = 40 * 60
      ..distanceMeters = 2000;
    expect(
      notes(
        today: tuesday,
        minutesNow: 600,
        log: TrainingLog(activities: [swim]),
      ),
      isEmpty,
    );
  });

  test('Saisonplan-Erinnerung lässt Erledigtes weg', () {
    List<TrainingReminder> reminders([TrainingLog log = const TrainingLog()]) => ReminderPlanner.season(
      schedule: schedule,
      config: SeasonConfig.standard,
      decisions: const {},
      today: monday,
      includeToday: true,
      days: 1,
      log: log,
    );
    final before = reminders();
    final after = reminders(TrainingLog(gymDays: {monday}));
    // Montag ist Push; mit erledigter Krafteinheit bleibt davon nichts in der Erinnerung.
    expect(before.first.titles, isNotEmpty);
    expect(after.isEmpty ? 0 : after.first.titles.length, lessThan(before.first.titles.length));
  });
}
