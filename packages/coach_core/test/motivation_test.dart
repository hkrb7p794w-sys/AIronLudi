// Port von AccountRulesTests.swift und MotivationTests.swift (Adherence, Companion, League, DaisyGeometry).
import 'dart:convert';
import 'dart:math' as math;

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

/// Montag, 26.10.2026.
const monday = CalendarDay(2026, 10, 26);

/// Di, Do, Sa geplant.
WeekSchedule threeDays() => WeekSchedule()
    .withSlots(const [SessionSlot(TrainingSport.run)], Weekday.tuesday)
    .withSlots(const [SessionSlot(TrainingSport.strength, SessionIntensity.hard)], Weekday.thursday)
    .withSlots(const [SessionSlot(TrainingSport.run, SessionIntensity.long)], Weekday.saturday);

WeekAdherence week(List<int> done, {required int today, WeekSchedule? schedule}) => WeekAdherence.compute(
  schedule: schedule ?? threeDays(),
  trainingDays: {for (final offset in done) monday.adding(offset)},
  weekOf: monday,
  today: monday.adding(today),
);

void main() {
  group('Konto-Regeln', () {
    test('Benutzernamen wie im Worker', () {
      expect(AccountRules.usernameProblem('lena'), isNull);
      expect(AccountRules.usernameProblem(' Max_Mustermann.1 '), isNull);
      expect(AccountRules.usernameProblem('ab'), isNotNull);
      expect(AccountRules.usernameProblem('.lena'), isNotNull);
      expect(AccountRules.usernameProblem('lena müller'), isNotNull);
      expect(AccountRules.usernameProblem('jörg'), isNotNull);
      expect(AccountRules.usernameProblem('admin'), 'Dieser Benutzername ist reserviert.');
    });

    test('Passwörter wie im Worker', () {
      expect(AccountRules.passwordProblem('Sommer-Lauf-2026', username: 'lena'), isNull);
      expect(AccountRules.passwordProblem('kurz', username: 'lena'), contains('mindestens 10'));
      expect(AccountRules.passwordProblem('LENA-passwort-1', username: 'lena'), contains('Benutzernamen'));
      expect(AccountRules.passwordProblem('aaaaaaaaaaaa', username: 'lena'), 'Das Passwort ist zu einfach.');
    });

    test('Anzeigenamen und Codes', () {
      expect(AccountRules.displayName('  Lena   Sommer '), 'Lena Sommer');
      expect(AccountRules.displayName('   '), '');
      expect(AccountRules.displayName('x' * 41), isNull);
      expect(AccountRules.normalizeCode('abcd-efgh jk'), 'ABCDEFGHJK');
    });

    test('Einladungslink hin und zurück', () {
      final invite = AccountInvite(workerURL: 'https://coach-ai.example.workers.dev', code: 'abcde-fghjk');
      expect(invite.code, 'ABCDEFGHJK');
      expect(AccountInvite.fromUri(invite.url!), invite);
      expect(invite.shareURL.toString(), 'https://coach-ai.example.workers.dev/i/ABCDEFGHJK');
      expect(AccountInvite.fromUri(Uri.parse('coach://account?worker=http://x.dev&invite=ABCDEFGHJK')), isNull);
      expect(AccountInvite.fromUri(Uri.parse('coach://account?worker=https://x.dev&invite=ABC')), isNull);
      expect(AccountInvite.fromUri(Uri.parse('coach://join?worker=https://x.dev&invite=ABCDEFGHJK')), isNull);
    });
  });

  group('Planerfüllung', () {
    test('Zustand je Tag', () {
      // Di erledigt, Mi extra, Do verpasst, heute Fr, Sa offen.
      final result = week([1, 2], today: 4);
      expect(result.days, [
        AdherenceDay.rest,
        AdherenceDay.done,
        AdherenceDay.extra,
        AdherenceDay.missed,
        AdherenceDay.rest,
        AdherenceDay.open,
        AdherenceDay.rest,
      ]);
      expect(result.planned, 3);
      expect(result.done, 1);
      expect(result.missed, 1);
      expect(result.shareSoFar, 0.5);
      expect(result.isComplete, isFalse);
    });

    test('zusätzliches Training bringt nichts extra', () {
      final planOnly = ScoreRules.points(week([1, 3, 5], today: 6));
      final withExtra = ScoreRules.points(week([0, 1, 2, 3, 4, 5, 6], today: 6));
      expect(planOnly, 3 * ScoreRules.pointsPerSession + ScoreRules.completeWeekBonus);
      expect(withExtra, planOnly);
    });

    test('kleine Pläne können auch gewinnen', () {
      final two = WeekSchedule().withSlots(const [SessionSlot(TrainingSport.run)], Weekday.monday).withSlots(const [
        SessionSlot(TrainingSport.run),
      ], Weekday.friday);
      final small = week([0, 4], today: 6, schedule: two);
      final bigButPartial = week([1], today: 6);
      expect(ScoreRules.points(small), greaterThan(ScoreRules.points(bigButPartial)));
    });

    test('ausgelassene Tage zählen nicht als geplant', () {
      final adjustments = PlanAdjustments()..skip(Weekday.thursday, inWeekOf: monday);
      final adjusted = week([1, 5], today: 6, schedule: adjustments.schedule(threeDays(), inWeekOf: monday));
      expect(adjusted.planned, 2);
      expect(adjusted.isComplete, isTrue);
    });

    test('Serie überspringt leere Wochen und endet bei einer verfehlten', () {
      final good = week([1, 3], today: 6); // 2 von 3 = 67 %
      final full = week([1, 3, 5], today: 6);
      final empty = week([], today: 6, schedule: WeekSchedule());
      expect(ScoreRules.countsForStreak(good), isFalse);
      expect(ScoreRules.streak([full, empty, full, good, full]), 2);
      expect(ScoreRules.level(0), 1);
      expect(ScoreRules.level(250), 3);
    });
  });

  group('Begleiter', () {
    final daisy = CompanionSettings(enabled: true, name: 'Daisy');
    CompanionContext context({
      List<String> planned = const ['Lockerer Lauf'],
      bool trained = false,
      RecoveryLevel? recovery = RecoveryLevel.normal,
      WeekAdherence? adherence,
      bool missed = false,
    }) => CompanionContext(
      plannedToday: planned,
      trainedToday: trained,
      recovery: recovery,
      week: adherence ?? week([], today: 1),
      missedYesterday: missed,
    );

    test('Stimmung folgt den Regeln', () {
      expect(CompanionVoice.mood(context()), CompanionMood.excited);
      expect(CompanionVoice.mood(context(trained: true)), CompanionMood.happy);
      expect(CompanionVoice.mood(context(trained: true, adherence: week([1, 3, 5], today: 5))), CompanionMood.proud);
      expect(CompanionVoice.mood(context(recovery: RecoveryLevel.pause)), CompanionMood.cozy);
      expect(CompanionVoice.mood(context(planned: [])), CompanionMood.resting);
      expect(CompanionVoice.mood(context(missed: true)), CompanionMood.hopeful);
    });

    test('Sätze mit Name und Einheit', () {
      final message = CompanionVoice.message(context(), companion: daisy, day: monday);
      expect(message.text, contains('Daisy'));
      expect(message.text, contains('Lockerer Lauf'));
      final cozy = CompanionVoice.message(
        context(recovery: RecoveryLevel.pause),
        companion: daisy,
        day: monday,
      );
      expect(cozy.mood, CompanionMood.cozy);
      expect(cozy.text, contains('Daisy'));
    });

    test('jede Art und Stimmung hat einen Text', () {
      final moods = [
        context(),
        context(trained: true),
        context(trained: true, adherence: week([1, 3, 5], today: 5)),
        context(recovery: RecoveryLevel.pause),
        context(planned: []),
        context(missed: true),
      ];
      for (final kind in CompanionKind.values) {
        for (final item in moods) {
          for (var offset = 0; offset < 3; offset++) {
            final text = CompanionVoice.message(
              item,
              companion: CompanionSettings(enabled: true, kind: kind),
              day: monday.adding(offset),
            ).text;
            expect(text, isNotEmpty);
          }
        }
      }
    });

    test('Daisy spricht wie ein Hund', () {
      final animated = CompanionSettings(enabled: true, kind: CompanionKind.daisy);
      expect(
        CompanionVoice.message(context(), companion: animated, day: monday).text,
        CompanionVoice.message(context(), companion: daisy, day: monday).text,
      );
      expect(animated.displayName, 'Daisy');
      expect(CompanionVoice.reminderLead(animated), 'Daisy wartet schon an der Tür.');
    });

    test('Standards und Lesen', () {
      expect(CompanionSettings().displayName, 'Daisy');
      expect(CompanionSettings(name: '  Bello ').displayName, 'Bello');
      expect(CompanionSettings.fromJson(jsonDecode('{"kind":"pferd"}')), CompanionSettings());
      expect(CompanionVoice.reminderLead(daisy), 'Daisy wartet schon an der Tür.');
      expect(CompanionVoice.reminderLead(CompanionSettings()), isNull);
      expect(CompanionSettings.fromJson(jsonDecode(jsonEncode(daisy.toJson()))), daisy);
    });
  });

  group('Rangliste', () {
    test('Zusammenfassung zählt Wochen und Serie', () {
      // Drei Wochen zurück alles erledigt, diese Woche Di erledigt (heute Mi).
      final trained = {monday.adding(1)};
      for (var back = 1; back <= 3; back++) {
        for (final offset in [1, 3, 5]) {
          trained.add(monday.adding(offset - 7 * back));
        }
      }
      final summary = MotivationSummary.compute(
        schedule: (_) => threeDays(),
        trainingDays: trained,
        today: monday.adding(2),
        weeks: 6,
      );
      expect(summary.weekPoints, 10);
      expect(summary.streak, 3);
      expect(summary.totalPoints, 10 + 3 * 50);
      expect(summary.level, 2);
      expect(summary.missedYesterday(monday.adding(2)), isFalse);
      final thursdayMissed = MotivationSummary.compute(
        schedule: (_) => threeDays(),
        trainingDays: trained,
        today: monday.adding(4),
        weeks: 1,
      );
      expect(thursdayMissed.missedYesterday(monday.adding(4)), isTrue);
    });

    test('Eintrag im Format des Workers', () {
      final summary = MotivationSummary.compute(
        schedule: (_) => threeDays(),
        trainingDays: {monday.adding(1)},
        today: monday.adding(2),
        weeks: 1,
      );
      final entry = LeagueEntry.fromSummary(id: 'alex-0001', name: 'Alex', avatar: 'dog.fill', summary: summary);
      expect(entry.week, '2026-10-26');
      expect(entry.done, 1);
      expect(entry.planned, 3);
      const json =
          '{"id":"a","name":"Lea","avatar":"person","week":"2026-10-26","weekPoints":5,'
          '"totalPoints":9,"streak":1,"done":1,"planned":2,"updatedAt":"2026-10-28T12:00:00.000Z"}';
      final decoded = LeagueEntry.fromJson(jsonDecode(json))!;
      expect(decoded.name, 'Lea');
      expect(decoded.weekPoints, 5);
      expect(LeagueEntry.fromJson(jsonDecode(jsonEncode(decoded.toJson()))), decoded);
    });

    test('Einladung hin und zurück', () {
      const invite = LeagueInvite(
        workerURL: 'https://coach-ai.example.workers.dev',
        token: 'geheim+/=&',
        code: 'team-abc234xyz9',
      );
      final url = invite.url!;
      expect(url.toString().startsWith('coach://join?'), isTrue);
      expect(LeagueInvite.fromUri(url), invite);
      expect(LeagueInvite.fromUri(Uri.parse('coach://join?worker=http://x&league=team-abc234')), isNull);
      expect(LeagueInvite.fromUri(Uri.parse('https://join?worker=https://x&league=team-abc234')), isNull);
    });

    test('Codes sind gültig', () {
      for (var index = 0; index < 20; index++) {
        expect(LeagueCode.isValid(LeagueCode.generate()), isTrue);
      }
      expect(LeagueCode.generate(math.Random(1)), LeagueCode.generate(math.Random(1)));
      expect(LeagueCode.isValid('AB'), isFalse);
      expect(LeagueCode.isValid('team abc'), isFalse);
      expect(LeagueCode.isValid('paar-123'), isTrue);
    });
  });

  group('Daisy', () {
    test('ein Bogen je Zottel, geschlossen', () {
      final fur = DaisyGeometry.fur(
        center: const DaisyPoint(100, 100),
        radiusX: 40,
        radiusY: 20,
        tufts: 12,
        depth: 0.2,
      );
      expect(fur.curves.length, 12);
      expect(fur.start, const DaisyPoint(140, 100));
      final last = fur.curves.last.end;
      expect((last.x - 140).abs(), lessThan(1e-9));
      expect((last.y - 100).abs(), lessThan(1e-9));
      // Fellspitzen stehen über den Rand hinaus, Ansatzpunkte liegen genau auf der Ellipse.
      for (final curve in fur.curves) {
        final control = math.pow((curve.control.x - 100) / 40, 2) + math.pow((curve.control.y - 100) / 20, 2);
        final end = math.pow((curve.end.x - 100) / 40, 2) + math.pow((curve.end.y - 100) / 20, 2);
        expect(control, greaterThan(1.1));
        expect((end - 1).abs(), lessThan(1e-9));
      }
    });

    test('Haltungen passen zur Stimmung', () {
      for (var time = 0.0; time < 8; time += 0.37) {
        expect(DaisyGeometry.pose(CompanionMood.resting, time: time).eyesOpen, 0);
        expect(DaisyGeometry.pose(CompanionMood.happy, time: time).tongue, isTrue);
        expect(DaisyGeometry.pose(CompanionMood.excited, time: time).tongue, isFalse);
        expect(DaisyGeometry.pose(CompanionMood.excited, time: time).bounce, lessThanOrEqualTo(0));
        final phase = DaisyGeometry.pose(CompanionMood.proud, time: time).floatPhase;
        expect(phase >= 0 && phase <= 1, isTrue);
      }
      // Blinzeln: kurz vor jeder vollen 4-Sekunden-Marke sind die Augen fast zu.
      expect(DaisyGeometry.pose(CompanionMood.excited, time: 3.9).eyesOpen, lessThan(0.2));
      expect(DaisyGeometry.pose(CompanionMood.excited, time: 2).eyesOpen, 1);
      // Bewegung reduzieren: unabhängig von der Zeit.
      expect(
        DaisyGeometry.pose(CompanionMood.hopeful, time: 1.3, reduceMotion: true),
        DaisyGeometry.pose(CompanionMood.hopeful, time: 7.7, reduceMotion: true),
      );
    });

    test('Gast-Tokens werden erkannt', () {
      expect(GuestToken.isGuest('g1.abcdefghijk2.0123abcd'), isTrue);
      expect(GuestToken.isGuest('mein-haupt-token'), isFalse);
      expect(GuestToken.isGuest(''), isFalse);
    });

    test('Android-Link trägt das Gast-Token im Anker', () {
      final url = AndroidLink.url(
        base: Uri.parse('https://w.example.dev/android/abc/'),
        guestToken: 'g1.abcdefghijk2.0f',
      )!;
      expect(url.toString(), 'https://w.example.dev/android/abc/#zugang=g1.abcdefghijk2.0f');
      expect(url.fragment, 'zugang=g1.abcdefghijk2.0f');
    });

    test('eine Einladung gibt nie das Haupt-Token preis', () {
      const invite = LeagueInvite(workerURL: 'https://fremd.example', token: 'g1.gast.sig', code: 'team-abc234');
      const home = 'https://mein.example';
      expect(invite.host, 'fremd.example');
      expect(invite.decision(currentURL: home, currentToken: 'haupt'), InviteDecision.rejectOtherServer);
      expect(
        invite.decision(currentURL: 'https://FREMD.example', currentToken: 'haupt'),
        InviteDecision.keepCurrentToken,
      );
      expect(invite.decision(currentURL: home, currentToken: 'g1.alt.sig'), InviteDecision.useInviteToken);
      expect(invite.decision(currentURL: '', currentToken: null), InviteDecision.useInviteToken);
    });
  });
}
