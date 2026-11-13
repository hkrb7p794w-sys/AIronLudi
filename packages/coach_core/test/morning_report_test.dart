// Port von HealthDashboardTests.swift (mit WakePlanTests) und MorningReportTests.swift. Die Weckzeit-Fälle laufen in
// der Zeitzone des Rechners; geprüft wird die Uhrzeit, die Dauer über die Zeitumstellung nur, wenn sie dort gilt.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 11, 2);

/// 14 unauffällige Vortage mit leichter Streuung.
List<DailyMetrics> history() => [
  for (var offset = 1; offset <= 14; offset++)
    () {
      final wobble = offset % 3 - 1.0;
      return DailyMetrics(today.adding(-offset))
        ..sleepSeconds = (7.8 + wobble * 0.2) * 3600
        ..restingHeartRate = 48 + wobble
        ..hrvLastNightAverage = 60 + wobble * 3
        ..stressAverage = 25 + wobble * 3
        ..bodyBatteryAtWake = 80 + wobble * 4
        ..deepSleepSeconds = 5400 + wobble * 300;
    }(),
];

void main() {
  group('Gesundheitsbereich', () {
    test('Standard ohne Doppelte, alles sichtbar', () {
      final dashboard = HealthDashboard();
      expect(dashboard.entries.map((entry) => entry.kind), HealthDashboard.standard);
      expect(dashboard.entries.every((entry) => !entry.hidden && entry.style == HealthWidgetStyle.week), isTrue);
    });

    test('hinzufügen, entfernen, ausblenden, Darstellung', () {
      final dashboard = HealthDashboard(
        entries: [
          HealthDashboardEntry(kind: HealthWidget.sleep),
          HealthDashboardEntry(kind: HealthWidget.hrv),
        ],
      );
      dashboard.add(HealthWidget.weight, style: HealthWidgetStyle.month);
      expect(dashboard.entries.map((entry) => entry.kind), [HealthWidget.sleep, HealthWidget.hrv, HealthWidget.weight]);
      dashboard.add(HealthWidget.weight);
      expect(dashboard.entries.length, 3);
      dashboard.setHidden(HealthWidget.hrv, true);
      const all = {HealthWidget.sleep, HealthWidget.hrv, HealthWidget.weight};
      expect(dashboard.visible(all).map((entry) => entry.kind), [HealthWidget.sleep, HealthWidget.weight]);
      // Wieder hinzufügen blendet ein, statt doppelt anzulegen.
      dashboard.add(HealthWidget.hrv);
      expect(dashboard.visible(all).map((entry) => entry.kind), [
        HealthWidget.sleep,
        HealthWidget.hrv,
        HealthWidget.weight,
      ]);
      dashboard.setStyle(HealthWidget.sleep, HealthWidgetStyle.value);
      expect(dashboard.entries[0].style, HealthWidgetStyle.value);
      dashboard.remove(HealthWidget.sleep);
      expect(dashboard.contains(HealthWidget.sleep), isFalse);
      expect(dashboard.addable({HealthWidget.sleep, HealthWidget.hrv, HealthWidget.steps}), [
        HealthWidget.sleep,
        HealthWidget.steps,
      ]);
    });

    test('verschieben wie in SwiftUI-Listen', () {
      final dashboard = HealthDashboard(
        entries: [
          HealthDashboardEntry(kind: HealthWidget.sleep),
          HealthDashboardEntry(kind: HealthWidget.hrv),
          HealthDashboardEntry(kind: HealthWidget.stress),
        ],
      );
      List<HealthWidget> kinds() => dashboard.entries.map((entry) => entry.kind).toList();
      dashboard.move(fromOffsets: {0}, toOffset: 3);
      expect(kinds(), [HealthWidget.hrv, HealthWidget.stress, HealthWidget.sleep]);
      dashboard.move(fromOffsets: {2}, toOffset: 0);
      expect(kinds(), [HealthWidget.sleep, HealthWidget.hrv, HealthWidget.stress]);
      dashboard.move(fromOffsets: {0, 2}, toOffset: 2);
      expect(kinds(), [HealthWidget.hrv, HealthWidget.sleep, HealthWidget.stress]);
    });

    test('Ausblenden und Darstellung überstehen das Speichern', () {
      final dashboard = HealthDashboard()
        ..setHidden(HealthWidget.stress, true)
        ..setStyle(HealthWidget.hrv, HealthWidgetStyle.month);
      final decoded = HealthDashboard.fromJson(jsonDecode(jsonEncode(dashboard.toJson())))!;
      expect(decoded.entries, dashboard.entries);
    });

    test('Lesen verwirft unbekannte und doppelte Widgets', () {
      final dashboard = HealthDashboard.fromJson(
        jsonDecode(
          '{"entries": [{"kind": "hrv"}, {"kind": "zukunft"}, {"kind": "hrv", "style": "month"}, '
          '{"kind": "sleep", "style": "value", "hidden": true}]}',
        ),
      )!;
      expect(dashboard.entries.map((entry) => entry.kind), [HealthWidget.hrv, HealthWidget.sleep]);
      expect(dashboard.entries[0].style, HealthWidgetStyle.week);
      expect(dashboard.entries[1].hidden, isTrue);
    });

    test('nur Widgets mit Daten', () {
      final day = DailyMetrics(today)
        ..restingHeartRate = 50
        ..sleepSeconds = 7 * 3600;
      final old = DailyMetrics(today.adding(-40))..stressAverage = 30;
      final weight = [DayValue(day: today.adding(-3), value: 80.4)];
      final available = HealthDashboard.available(days: [day, old], extra: {HealthWidget.weight: weight}, today: today);
      expect(available, {HealthWidget.restingHeartRate, HealthWidget.sleep, HealthWidget.weight});
      expect(HealthDashboard().visible(available).map((entry) => entry.kind), [
        HealthWidget.sleep,
        HealthWidget.restingHeartRate,
      ]);
    });

    test('Tageswerte vor Ersatzquellen', () {
      final day = DailyMetrics(today)..acuteLoad = 500;
      final fallback = [DayValue(day: today, value: 120), DayValue(day: today.adding(-1), value: 110)];
      final series = HealthDashboard.series(
        HealthWidget.trainingLoad,
        days: [day],
        extra: {HealthWidget.trainingLoad: fallback},
        today: today,
        window: 7,
      );
      expect(series.map((value) => value.value), [110, 500]);
    });

    test('jedes Widget hat Bereich und Titel', () {
      for (final widget in HealthWidget.values) {
        expect(widget.title, isNotEmpty);
        expect(HealthCategory.values, contains(widget.category));
      }
    });
  });

  group('Weckplan', () {
    test('jetzt ins Bett: Einschlafzeit dazu und runden', () {
      expect(WakePlan.wakeIfSleepingNow(nowMinutes: 23 * 60 + 40, sleepMinutes: 480), WakeTime(hour: 7, minute: 55));
      expect(WakePlan.wakeIfSleepingNow(nowMinutes: 22 * 60 + 31, sleepMinutes: 480), WakeTime(hour: 6, minute: 50));
    });

    test('Schlafdauer über Mitternacht', () {
      expect(WakePlan.sleepMinutes(bedtimeMinutes: 22 * 60 + 30, wake: WakeTime(hour: 6, minute: 45)), 480);
    });

    test('nächster Zeitpunkt morgen oder heute', () {
      final evening = DateTime(2026, 11, 2, 22);
      final morning = DateTime(2026, 11, 3, 5);
      final time = WakeTime(hour: 6, minute: 30);
      final next = WakePlan.nextDate(time, now: evening);
      expect((next.day, next.hour, next.minute), (3, 6, 30));
      expect(WakePlan.dayLabel(next, now: evening), 'morgen');
      expect(WakePlan.dayLabel(WakePlan.nextDate(time, now: morning), now: morning), 'heute');
    });

    test('Uhrzeit bleibt über die Zeitumstellung', () {
      // Nacht der Zeitumstellung in Mitteleuropa (25.10.2026, 3 Uhr → 2 Uhr).
      final evening = DateTime(2026, 10, 24, 23);
      final next = WakePlan.nextDate(WakeTime(hour: 6, minute: 30), now: evening);
      expect((next.day, next.hour, next.minute), (25, 6, 30));
      final shift = next.timeZoneOffset - evening.timeZoneOffset;
      expect(next.difference(evening), const Duration(hours: 7, minutes: 30) - shift);
    });

    test('Wochentage und Grenzen', () {
      expect(WakeRepeat.once.calendarWeekdays, isEmpty);
      expect(WakeRepeat.weekdays.calendarWeekdays, [2, 3, 4, 5, 6]);
      expect(WakeRepeat.daily.calendarWeekdays.length, 7);
      expect(WakeTime.fromMinutes(1500), WakeTime(hour: 1, minute: 0));
      expect(WakeTime.fromMinutes(-30), WakeTime(hour: 23, minute: 30));
      expect(WakeTime(hour: 6, minute: 5).text, '6:05');
    });
  });

  group('Morgenbericht', () {
    test('schlechte Nacht mit persönlichen Bereichen erklärt', () {
      final night = DailyMetrics(today)
        ..sleepSeconds = 6.2 * 3600
        ..sleepScore = 55
        ..restingHeartRate = 54
        ..hrvLastNightAverage = 48
        ..bodyBatteryAtWake = 52;
      const sessions = [MorningSession(id: '1', title: 'Intervalle', target: 'Soll 60 min', demanding: true)];
      final report = MorningReport.make(
        days: [...history(), night],
        today: today,
        sleep: SleepSettings(),
        sessions: sessions,
      );
      expect(report.level, RecoveryLevel.locker);
      expect(report.headline, 'Heute eher locker');
      expect(
        report.findings.any((line) => line.startsWith('Schlaf war') && line.contains('kürzer als dein Bedarf')),
        isTrue,
      );
      expect(report.findings, contains('HRV liegt unter deinem Normalbereich.'));
      expect(report.findings, contains('Body Battery ist vergleichsweise niedrig.'));
      expect(report.findings.any((line) => line.startsWith('Ruhepuls')), isTrue);
      expect(report.recommendation, contains('lockere Trainingseinheit'));
      expect(report.recommendation, contains('„Intervalle“'));
      expect(report.sleepAdvice, contains('ins Bett'));
      expect(report.isFromYesterday, isFalse);
    });

    test('gute Nacht: Plan bleibt', () {
      final night = DailyMetrics(today)
        ..sleepSeconds = 8.1 * 3600
        ..sleepScore = 86
        ..restingHeartRate = 48
        ..hrvLastNightAverage = 61
        ..hrvStatus = 'BALANCED'
        ..bodyBatteryAtWake = 82;
      const sessions = [MorningSession(id: '1', title: 'Lauf', target: '45 min', demanding: false)];
      final report = MorningReport.make(
        days: [...history(), night],
        today: today,
        sleep: SleepSettings(),
        sessions: sessions,
      );
      expect(report.level, RecoveryLevel.normal);
      expect(report.findings, isEmpty);
      expect(report.recommendation, 'Empfehlung: Training wie geplant.');
      expect(report.items.firstWhere((item) => item.metric == MorningMetric.sleepDuration).status, MorningStatus.good);
      expect(report.items.firstWhere((item) => item.metric == MorningMetric.hrv).status, MorningStatus.good);
    });

    test('eine Abweichung stuft nicht herab', () {
      final night = DailyMetrics(today)
        ..sleepSeconds = 8 * 3600
        ..restingHeartRate = 48
        ..bodyBatteryAtWake = 60;
      final report = MorningReport.make(days: [...history(), night], today: today, sleep: SleepSettings());
      expect(report.findings, ['Body Battery ist vergleichsweise niedrig.']);
      expect(report.level, RecoveryLevel.normal);
    });

    test('ohne Daten sagt der Bericht es', () {
      final report = MorningReport.make(days: [], today: today, sleep: SleepSettings());
      expect(report.level, isNull);
      expect(report.headline, 'Zu wenig Daten für eine Einschätzung');
      expect(report.recommendation, contains('Gefühl'));
      expect(report.missing, containsAll(['Schlafdauer', 'Body Battery']));
      expect(report.items.every((item) => item.status == MorningStatus.missing), isTrue);
      expect(report.sleepAdvice, isNull);
    });

    test('Teilwerte ohne persönliche Bereiche', () {
      final night = DailyMetrics(today)
        ..sleepSeconds = 7.5 * 3600
        ..restingHeartRate = 52;
      final report = MorningReport.make(days: [night], today: today, sleep: SleepSettings());
      expect(report.level, RecoveryLevel.normal);
      expect(
        report.items.firstWhere((item) => item.metric == MorningMetric.restingHeartRate).note,
        contains('ab 7 Tagen'),
      );
      expect(report.missing, contains('HRV'));
      expect(report.missing, isNot(contains('Ruhepuls')));
    });

    test('vor dem Abruf die Werte von gestern', () {
      final yesterday = DailyMetrics(today.adding(-1))
        ..sleepSeconds = 7 * 3600
        ..restingHeartRate = 50;
      final report = MorningReport.make(days: [yesterday], today: today, sleep: SleepSettings());
      expect(report.isFromYesterday, isTrue);
      expect(report.dataDay, today.adding(-1));
      expect(MorningReportReminder.morningSummary(report), isNull);
    });

    test('Belastung aus dem Verhältnis der Uhr', () {
      final metrics = DailyMetrics(today)
        ..acuteLoad = 900
        ..chronicLoad = 500;
      expect(MorningReport.load(metrics, form: null).status, MorningStatus.attention);
      metrics.acuteLoad = 520;
      expect(MorningReport.load(metrics, form: null).status, MorningStatus.normal);
      expect(MorningReport.load(null, form: null).status, MorningStatus.missing);
    });

    test('HRV-Status vor dem Nachtwert', () {
      final metrics = DailyMetrics(today)
        ..hrvStatus = 'LOW'
        ..hrvLastNightAverage = 70;
      expect(MorningReport.hrv(metrics, norm: null).status, MorningStatus.attention);
      metrics.hrvStatus = null;
      expect(
        MorningReport.hrv(metrics, norm: const PersonalNorm(mean: 60, low: 55, high: 65, count: 10)).status,
        MorningStatus.good,
      );
    });

    test('Mitteilung um 8 Uhr', () {
      final notes = MorningReportReminder.morningReport(today: today, minutesNow: 7 * 60, summary: ' Heute locker ');
      expect(notes.length, 5);
      expect(notes.first.body, 'Heute locker');
      expect(notes[1].body, MorningReportReminder.morningReportFallback);
      expect(MorningReportReminder.morningReport(today: today, minutesNow: 9 * 60).first.day, today.adding(1));
    });
  });
}
