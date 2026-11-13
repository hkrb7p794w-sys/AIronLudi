// Port von SocialTests.swift, SocialTimelineTests.swift, WidgetSnapshotTests.swift und MealHeadlineTests.swift.
// Zeiten in Ortszeit gebaut, damit die Tests in jeder Zeitzone gelten (Swift übergibt dort eine feste `TimeZone`).
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

String iso(DateTime local) => '${local.toUtc().toIso8601String().substring(0, 19)}.000Z';

void main() {
  group('Social', () {
    test('Feed des Workers wird gelesen', () {
      const json = '''
        {"posts": [{"id": "p1", "kind": "workout", "createdAt": "2026-11-09T12:00:00.000Z",
          "author": {"username": "lena", "displayName": "Lena"}, "mine": false,
          "payload": {"sport": "run", "title": "Lockerer Lauf", "durationMin": 45, "distanceKm": 8.2},
          "reactions": 2, "myReaction": "🔥", "topReactions": "🔥💪", "comments": 1},
          {"id": "p2", "kind": "zukunft", "createdAt": "2026-11-09T11:00:00.000Z",
          "author": {"username": "tom", "displayName": "Tom"}, "mine": true, "payload": {},
          "reactions": 0, "myReaction": null, "topReactions": "", "comments": 0}]}''';
      final posts = listStrict((jsonDecode(json) as Map)['posts'], SocialPost.fromJson)!;
      expect(posts[0].headline, 'Lockerer Lauf');
      expect(posts[0].facts, '45 min · 8,2 km');
      expect(posts[0].symbol, 'figure.run');
      expect(posts[0].date, isNotNull);
      expect(posts[1].kind, SocialPostKind.unknown);
    });

    test('Krafteinheit teilt keine Körperwerte', () {
      final start = DateTime.fromMillisecondsSinceEpoch(1793500000 * 1000, isUtc: true);
      final squat = LoggedExercise(
        exerciseID: 'kniebeuge',
        name: 'Kniebeuge',
        group: MuscleGroup.legs,
        sets: [for (var index = 0; index < 3; index++) LoggedSet(reps: 5, weightKg: 100)],
      );
      final session = GymSession(
        workoutKey: null,
        title: 'Beine',
        start: start,
        end: start.add(const Duration(seconds: 3000)),
        exercises: [squat],
      );
      final share = WorkoutShare.gym(session, records: ['Kniebeuge: 100 kg × 5']);
      expect(share.sport, 'strength');
      expect(share.durationMin, 50);
      expect(share.sets, 3);
      expect(share.volumeKg, 1500);
      expect(share.exercises, ['Kniebeuge']);
      final text = jsonEncode(share.toJson());
      expect(text, isNot(contains('weight"')));
      expect(text, isNot(contains('heart')));
    });

    test('Ausdauer teilt weder Puls noch Kalorien', () {
      final run = GarminActivity(1)
        ..typeKey = 'running'
        ..name = 'Morgenlauf'
        ..durationSeconds = 2710
        ..distanceMeters = 8249
        ..averageHeartRate = 150
        ..calories = 600
        ..elevationGain = 42;
      final share = WorkoutShare.activity(run);
      expect(share.toJson(), {
        'kind': 'workout',
        'sport': 'run',
        'title': 'Morgenlauf',
        'durationMin': 45,
        'distanceKm': 8.2,
        'elevationM': 42,
      });
      final text = jsonEncode(share.toJson());
      expect(text, isNot(contains('150')));
      expect(text, isNot(contains('600')));
      expect(WorkoutShare.activity(GarminActivity(2)..typeKey = 'walking').title, 'Spaziergang');
    });

    test('relative Zeiten', () {
      final now = DateTime(2026, 11, 9, 15);
      expect(SocialFormat.relative(now.subtract(const Duration(seconds: 30)), now: now), 'gerade eben');
      expect(SocialFormat.relative(now.subtract(const Duration(minutes: 5)), now: now), 'vor 5 Min.');
      expect(SocialFormat.relative(now.subtract(const Duration(hours: 3)), now: now), 'vor 3 Std.');
      expect(SocialFormat.relative(now.subtract(const Duration(hours: 20)), now: now), 'gestern');
      expect(SocialFormat.relative(DateTime(2026, 3, 5, 12), now: now), '5. März');
    });
  });

  group('Aktivitäten und Feed', () {
    /// 10.11.2026, 12:00 Ortszeit.
    final now = DateTime(2026, 11, 10, 12);
    GarminActivity run(int id, String start) => GarminActivity(id)
      ..typeKey = 'running'
      ..name = 'Lauf $id'
      ..startLocal = start;
    List<SocialPost> posts(List<({String id, DateTime at, bool mine})> rows) => [
      for (final row in rows)
        SocialPost.fromJson({
          'id': row.id,
          'kind': 'workout',
          'createdAt': iso(row.at),
          'author': {'username': 'u', 'displayName': 'U'},
          'mine': row.mine,
          'payload': {'sport': 'run', 'title': 'Lauf'},
          'reactions': 1,
          'myReaction': null,
          'topReactions': '🔥',
          'comments': 0,
        })!,
    ];

    test('eigene und fremde, neueste zuerst, ohne Doppelte', () {
      final gym = GymItem(
        id: newUuid(),
        title: 'Push',
        start: now.subtract(const Duration(hours: 1)),
        minutes: 50,
        sets: 12,
        volumeKg: 4000,
      );
      final entries = ActivityFeed.entries(
        activities: [run(1, '2026-11-09 18:00:00'), run(2, '2026-11-08 07:00:00')],
        gym: [gym],
      );
      final feed = posts([
        (id: 'friend', at: DateTime(2026, 11, 9, 20), mine: false),
        (id: 'mine', at: DateTime(2026, 11, 9, 18, 30), mine: true),
      ]);
      final items = SocialTimeline.merge(entries: entries, posts: feed, shared: {'a1': 'mine'});
      expect(items.map((item) => item.id), ['g${gym.id}', 'pfriend', 'a1', 'a2']);
      // Der eigene geteilte Lauf steht einmal da und trägt die Reaktionen seines Beitrags.
      expect(items[2].post?.id, 'mine');
      expect(items[3].post, isNull);
      expect(items[1].entry, isNull);
    });

    test('eigene Einträge enden am ältesten geladenen Beitrag', () {
      final entries = ActivityFeed.entries(
        activities: [run(1, '2026-11-09 18:00:00'), run(2, '2026-10-01 07:00:00')],
        gym: [],
      );
      final feed = posts([(id: 'friend', at: DateTime(2026, 11, 5, 20), mine: false)]);
      final items = SocialTimeline.merge(entries: entries, posts: feed, shared: {}, oldest: feed[0].date);
      expect(items.map((item) => item.id), ['a1', 'pfriend']);
      expect(SocialTimeline.merge(entries: entries, posts: feed, shared: {}).length, 3);
    });

    test('automatisch teilen nur neue, ungeteilte Trainings', () {
      final gym = GymItem(
        id: newUuid(),
        title: 'Pull',
        start: now.subtract(const Duration(hours: 2)),
        minutes: 45,
        sets: 10,
        volumeKg: 3000,
      );
      final entries = ActivityFeed.entries(
        activities: [
          run(1, '2026-11-10 08:00:00'),
          run(2, '2026-11-09 08:00:00'),
          run(3, '2026-11-08 08:00:00'),
          run(4, '2026-11-01 08:00:00'),
        ],
        gym: [gym],
      );
      // Eingeschaltet am 08.11. um 12 Uhr: der Lauf vom Morgen davor und der alte bleiben privat.
      final since = now.subtract(const Duration(days: 2));
      final candidates = SocialTimeline.autoShareCandidates(
        entries: entries,
        shared: {'a2': 'p'},
        since: since,
        now: now,
      );
      expect(candidates.map((entry) => entry.id), ['a1', 'g${gym.id}']);
      // Die Gym-Einheit gilt auch dann als geteilt, wenn sie später mit der Uhr-Aufzeichnung verschmilzt.
      final shared = {'g${gym.id}': 'p2', 'a1': 'p3', 'a2': 'p'};
      expect(SocialTimeline.autoShareCandidates(entries: entries, shared: shared, since: since, now: now), isEmpty);
      final many = [for (var id = 10; id < 20; id++) run(id, '2026-11-10 09:$id:00')];
      final limited = SocialTimeline.autoShareCandidates(
        entries: ActivityFeed.entries(activities: many, gym: []),
        shared: {},
        since: since,
        now: now,
      );
      expect(limited.map((entry) => entry.id), ['a10', 'a11', 'a12']);
    });
  });

  group('Widgets', () {
    const day = CalendarDay(2026, 11, 4);
    DateTime noon(CalendarDay day) => DateTime(day.year, day.month, day.day, 12);
    WidgetSnapshot snapshot() => WidgetSnapshot(
      createdAt: DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true),
      day: day,
      today: const WidgetToday(
        level: RecoveryLevel.normal,
        headline: 'Normal trainieren',
        sessions: [
          WidgetSession(title: 'Lauf', target: '45 min', done: true, symbol: 'figure.run'),
          WidgetSession(title: 'Push', target: '6 Übungen', done: false, symbol: 'dumbbell'),
        ],
        week: '2/5 Einheiten · 90 min',
        weekFraction: 0.4,
      ),
      nutrition: WidgetNutrition(
        kcal: 1500,
        kcalTarget: 2400,
        protein: 90,
        proteinTarget: 150,
        waterMilliliters: 1000,
        waterTarget: 2500,
        lastMeal: WidgetLastMeal(
          title: 'Mittagessen',
          at: DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true),
          kcal: 700,
        ),
      ),
      gym: WidgetGym(
        next: 'Push',
        nextDetail: '6 Übungen',
        running: true,
        runningTitle: 'Push',
        last: null,
        weekDone: 2,
        weekPlanned: 3,
      ),
      health: const [
        WidgetHealth(
          metric: HealthMetric.bodyBattery,
          value: '78',
          gauge: 78,
          status: MorningStatus.good,
          note: 'über üblich',
        ),
      ],
    );

    test('hin und zurück als JSON, Zeitpunkte wie der Standard-JSONEncoder', () {
      final original = snapshot();
      final json = original.toJson();
      expect(json['createdAt'], 1800000000 - 978307200);
      expect(WidgetSnapshot.fromJson(jsonDecode(jsonEncode(json))), original);
    });

    test('gleicher Tag: Werte plus wartendes Wasser', () {
      final queue = WidgetActionQueue()..addWater(250, at: noon(day));
      final display = snapshot().display(day, queue: queue);
      expect(display.isCurrent, isTrue);
      expect(display.snapshot.nutrition?.waterMilliliters, 1250);
      expect(display.snapshot.nutrition?.kcalRemaining, 900);
      expect(display.snapshot.today.nextSession?.title, 'Push');
      expect(display.healthIsOld, isFalse);
    });

    test('neuer Tag übernimmt weder Mahlzeiten noch Plan', () {
      final display = snapshot().display(day.adding(1));
      expect(display.isCurrent, isFalse);
      expect(display.snapshot.nutrition?.kcal, 0);
      expect(display.snapshot.nutrition?.kcalTarget, isNull);
      expect(display.snapshot.nutrition?.lastMeal, isNull);
      expect(display.snapshot.today.sessions, isEmpty);
      expect(display.snapshot.today.level, isNull);
      expect(display.snapshot.gym?.running, isFalse);
      // Gleiche Woche (Mi → Do): Zählung bleibt.
      expect(display.snapshot.gym?.weekDone, 2);
      // Der Stand von gestern enthält nicht die letzte Nacht (R3C-02).
      expect(display.healthIsOld, isTrue);
      expect(snapshot().display(day.adding(2)).healthIsOld, isTrue);
    });

    test('neue Woche setzt die Kraft-Zählung zurück', () {
      // 04.11.2026 ist ein Mittwoch; Montag darauf ist der 09.11.
      final display = snapshot().display(const CalendarDay(2026, 11, 9));
      expect(display.snapshot.gym?.weekDone, 0);
      expect(display.snapshot.gym?.weekText, '0/3 diese Woche');
      // Der gespeicherte Stand selbst bleibt unverändert.
      expect(snapshot().gym?.weekDone, 2);
    });

    test('Anteile sind begrenzt und brauchen Ziele', () {
      final over = WidgetNutrition(
        kcal: 3000,
        kcalTarget: 2000,
        protein: 10,
        proteinTarget: null,
        waterMilliliters: 0,
        waterTarget: 0,
        lastMeal: null,
      );
      expect(over.kcalFraction, 1);
      expect(over.kcalRemaining, -1000);
      expect(over.proteinFraction, isNull);
      expect(over.waterFraction, isNull);
    });

    test('Warteschlange behält nur neue Einträge und entfernt Übernommenes', () {
      final queue = WidgetActionQueue()
        ..addWater(250, at: noon(day))
        ..addWater(0, at: noon(day));
      queue.entries.add(WidgetActionEntry(day: day.adding(-10), at: DateTime.utc(1), waterMilliliters: 250));
      expect(queue.entries.length, 2);
      final pending = queue.pending(day);
      expect(pending.length, 1);
      queue
        ..addWater(500, at: noon(day))
        ..remove({for (final entry in pending) entry.id});
      expect(queue.water(day), 500);
      final decoded = WidgetActionQueue.fromJson(jsonDecode(jsonEncode(queue.toJson())))!;
      expect(decoded.water(day), 500);
    });

    test('Gesundheitswerte aus dem Morning Report', () {
      const report = MorningReport(
        day: day,
        dataDay: day,
        items: [
          MorningItem(metric: MorningMetric.bodyBattery, value: '78', status: MorningStatus.good, note: 'gut'),
          MorningItem(
            metric: MorningMetric.sleepDuration,
            value: '7,5 h',
            status: MorningStatus.normal,
            note: 'üblich',
          ),
          MorningItem(metric: MorningMetric.hrv, value: null, status: MorningStatus.missing, note: 'keine Daten'),
        ],
        level: RecoveryLevel.normal,
        headline: 'Gut erholt',
        findings: [],
        recommendation: '',
        sleepAdvice: null,
        sessions: [],
        missing: [],
      );
      final health = WidgetSnapshot.healthFrom(report, bodyBattery: 78);
      expect(health.map((item) => item.metric), [HealthMetric.bodyBattery, HealthMetric.sleep, HealthMetric.hrv]);
      expect(health.first.gauge, 78);
      expect(health.last.gauge, isNull);
      expect(health.last.status, MorningStatus.missing);
    });

    test('App Group aus dem Profil mit Team-Kennung', () {
      const plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Entitlements</key><dict>
<key>com.apple.security.application-groups</key>
<array><string>group.io.github.hkrb7p794w.coach.ABCDE12345</string><string>group.other</string></array>
</dict></dict></plist>''';
      final data = [0x30, 0x82, 0x01, ...utf8.encode(plist), 0x00, 0xA0];
      final groups = AppGroupProfile.groups(data);
      expect(groups, ['group.io.github.hkrb7p794w.coach.ABCDE12345', 'group.other']);
      expect(AppGroupProfile.candidates(groups), [
        'group.io.github.hkrb7p794w.coach.ABCDE12345',
        'group.io.github.hkrb7p794w.coach',
      ]);
      expect(AppGroupProfile.groups(utf8.encode('kein Profil')), isEmpty);
      expect(AppGroupProfile.candidates([]), ['group.io.github.hkrb7p794w.coach']);
      expect(AppGroupProfile.candidates(['group.io.github.hkrb7p794w.coachX']).length, 1);
    });

    test('Serie: Kopfzeile und Tageswechsel', () {
      expect(const WidgetStreak(days: 34, activeToday: true).headline, 'Serie läuft – weiter so!');
      expect(const WidgetStreak(days: 1, activeToday: true).headline, 'Guter Start – dranbleiben!');
      expect(const WidgetStreak(days: 5, activeToday: false).headline, 'Heute noch etwas erfassen');
      expect(const WidgetStreak(days: 0, activeToday: false).headline, 'Heute starten – erster Tag!');
      final value = snapshot()..streak = const WidgetStreak(days: 12, activeToday: true);
      expect(value.display(day).snapshot.streak, const WidgetStreak(days: 12, activeToday: true));
      expect(value.display(day.adding(1)).snapshot.streak, const WidgetStreak(days: 12, activeToday: false));
      expect(value.display(day.adding(3)).snapshot.streak, isNull);
      // Ältere Stände ohne Serie bleiben lesbar.
      final old = value.toJson()..remove('streak');
      expect(WidgetSnapshot.fromJson(jsonDecode(jsonEncode(old)))?.streak, isNull);
    });
  });

  group('Mahlzeiten-Kopfzeile', () {
    List<WidgetMealPart> meals(List<double> kcal) => [
      for (var index = 0; index < kcal.length; index++)
        WidgetMealPart(category: MealSplit.order[index], kcal: kcal[index], target: 500),
    ];
    String text(
      List<double> kcal, {
      double? remaining = 1000,
      WidgetStreak? streak = const WidgetStreak(days: 1, activeToday: true),
      int hour = 13,
    }) => MealHeadline.text(meals: meals(kcal), kcalRemaining: remaining, kcalTarget: 2000, streak: streak, hour: hour);

    test('vor dem ersten Eintrag nach Tageszeit', () {
      const none = WidgetStreak(days: 0, activeToday: false);
      expect(text([0, 0, 0, 0], streak: none, hour: 7), 'Guten Morgen – Frühstück eintragen?');
      expect(text([0, 0, 0, 0], streak: none, hour: 12), 'Mittagessen eintragen?');
      expect(text([0, 0, 0, 0], streak: none, hour: 18), 'Heute noch nichts eingetragen');
      expect(text([0, 0, 0, 0], streak: none, hour: 22), 'Noch kurz den Tag eintragen?');
      // Mit Serie von gestern: der nächste Tag, ohne Drohung.
      expect(
        text([0, 0, 0, 0], streak: const WidgetStreak(days: 4, activeToday: false), hour: 7),
        'Tag 5 der Serie – los geht’s',
      );
    });

    test('ändert sich mit jeder Mahlzeit', () {
      expect(text([400, 0, 0, 0]), 'Guter Start – Mittagessen steht an');
      expect(
        text([400, 0, 0, 0], streak: const WidgetStreak(days: 6, activeToday: true)),
        'Tag 6 der Serie – Mittagessen steht an',
      );
      expect(text([400, 500, 0, 0], remaining: 640.4), 'Noch 640 kcal – Abendessen fehlt');
      expect(text([400, 500, 0, 0], remaining: -50), 'Fast komplett – Abendessen fehlt noch');
      // Frühstück ausgelassen: als Nächstes das Abendessen, nicht rückwirkend das Frühstück.
      expect(text([0, 500, 0, 0]), 'Guter Start – Abendessen steht an');
      expect(text([0, 0, 0, 150]), 'Snack notiert – Frühstück eintragen?');
    });

    test('Tagesbilanz, wenn alle Hauptmahlzeiten eingetragen sind', () {
      expect(text([400, 500, 600, 0], remaining: 60), 'Tagesziel getroffen – stark!');
      expect(text([400, 500, 600, 0], remaining: 420), 'Alles eingetragen · noch 420 kcal frei');
      expect(text([400, 500, 900, 100], remaining: -310), 'Alles eingetragen · 310 kcal über Ziel');
      // Ohne Kalorienziel (z. B. gesperrte Gewichtsziele) keine Kalorien im Satz.
      expect(text([400, 500, 600, 0], remaining: null), 'Alles eingetragen – stark!');
      expect(
        text([400, 500, 600, 0], remaining: null, streak: const WidgetStreak(days: 9, activeToday: true)),
        'Alles eingetragen – Tag 9 der Serie',
      );
    });
  });
}
