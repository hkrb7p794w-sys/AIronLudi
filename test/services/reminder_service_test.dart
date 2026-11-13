// Port von `ReminderAppTests` plus Planen der Mitteilungen gegen eine nachgebildete Mitteilungszentrale.
import 'package:aironludi/data/db/database.dart';
import 'package:aironludi/data/settings/coach_settings.dart';
import 'package:aironludi/data/settings/settings_store.dart';
import 'package:aironludi/platform/notifications.dart';
import 'package:aironludi/services/reminders/reminder_service.dart';
import 'package:coach_core/coach_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CoachDatabase db;
  late SettingsStore store;

  setUp(() async {
    db = CoachDatabase(NativeDatabase.memory());
    store = await SettingsStore.open(db);
  });

  tearDown(() async {
    await store.close();
    await db.close();
  });

  CoachSettings settings() {
    final settings = CoachSettings(store);
    final profile = UserProfile(
      mode: ProfileMode.personal,
      onboardingDone: true,
      sports: const [TrainingSport.run, TrainingSport.strength],
      goal: FitnessGoal.loseWeight,
    );
    // Jeden Tag eine Einheit, damit der Test unabhängig vom heutigen Wochentag ist.
    for (final weekday in Weekday.values) {
      profile.schedule = profile.schedule.withSlots(const [SessionSlot(TrainingSport.run)], weekday);
    }
    settings.profile = profile;
    return settings;
  }

  DateTime at(int hour) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour);
  }

  test('heute nur vor der Erinnerungszeit', () {
    final coach = settings();
    final service = ReminderService(settings: coach);
    final today = CalendarDay.today();
    expect(service.reminders(seasonSchedule: null, now: at(6)).first.day, today);
    expect(service.reminders(seasonSchedule: null, now: at(9)).first.day, today.adding(1));
    coach.reminders = coach.reminders..hour = 10;
    expect(service.reminders(seasonSchedule: null, now: at(9)).first.day, today);
  });

  test('Auslassen gilt nur diese Woche und bleibt nach dem Neustart', () async {
    final coach = settings();
    final service = ReminderService(settings: coach);
    final today = CalendarDay.today();
    service.skip(today);
    expect(coach.schedule(today).slots(Weekday.of(today)), isEmpty);
    expect(service.reminders(seasonSchedule: null, now: at(6)).any((reminder) => reminder.day == today), isFalse);
    expect(coach.schedule(today.adding(7)), coach.profile.schedule);
    await Future<void>.delayed(Duration.zero);
    expect(CoachSettings(await SettingsStore.open(db)).planAdjustments, coach.planAdjustments);
    coach.planAdjustments = coach.planAdjustments..undo(Weekday.of(today), inWeekOf: today);
    expect(coach.schedule(today), coach.profile.schedule);
  });

  test('plant Mitteilungen; während einer Krafteinheit keine für heute', () async {
    final coach = settings();
    final center = FakeNotificationCenter();
    var training = false;
    final service = ReminderService(settings: coach, center: center, suppressesToday: () => training);
    final today = CalendarDay.today();
    await service.refresh(seasonSchedule: null, now: at(6));
    expect(service.permission, NotificationPermission.allowed);
    final todayID = 'coach.reminder.${today.iso}';
    expect(center.pending[todayID]?.category, NotificationCategories.adjustable);
    expect(center.pending[todayID]?.hour, 7);
    training = true;
    await service.refresh(seasonSchedule: null, now: at(6));
    expect(center.pending.containsKey(todayID), isFalse);
    expect(center.pending.containsKey('coach.reminder.${today.adding(1).iso}'), isTrue);
  });

  test('ohne Erlaubnis nichts geplant; Antworten aus Mitteilungen', () async {
    final coach = settings();
    final center = FakeNotificationCenter(granted: false);
    final service = ReminderService(settings: coach, center: center);
    await service.refresh(seasonSchedule: null, now: at(6));
    expect(service.permission, NotificationPermission.denied);
    expect(center.pending, isEmpty);

    final today = CalendarDay.today();
    service.handle(NotificationAnswer(action: '', info: {'day': today.iso}));
    expect(service.pendingDay, today);
    service.handle(NotificationAnswer(action: NotificationCategories.skipAction, info: {'day': today.iso}));
    expect(coach.schedule(today).slots(Weekday.of(today)), isEmpty);
    expect(center.removedDelivered, ['coach.reminder.${today.iso}']);
    service.handle(
      NotificationAnswer(action: '', info: {'day': today.iso, 'kind': ScheduledNoteKind.weekPlanning.rawValue}),
    );
    expect(service.showsWeekPlanning, isTrue);
  });
}
