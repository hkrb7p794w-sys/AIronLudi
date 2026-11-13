// Port von InsightsTests.swift und AIPolicyTests.swift.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true);

Insight insight({
  InsightTopic topic = InsightTopic.recovery,
  String subject = 'schlaf',
  String title = 'Schlaf nachholen',
  String text = 'Mehr schlafen.',
  InsightDirection direction = InsightDirection.more,
  InsightOrigin origin = InsightOrigin.rules,
  double days = 3,
}) => Insight(
  topic: topic,
  subject: subject,
  title: title,
  text: text,
  direction: direction,
  origin: origin,
  created: now,
  validUntil: now.add(Duration(microseconds: (days * 86400 * 1e6).round())),
  basis: const ['Fakt'],
);

void main() {
  group('Insights', () {
    test('Stand bleibt, solange der Inhalt gleich ist', () {
      var inbox = InsightInbox.merge([], [insight()], now: now);
      inbox = InsightInbox.setStatus(InsightStatus.read, id: inbox[0].id, insights: inbox, now: now);
      // Gleicher Inhalt: bleibt gelesen.
      inbox = InsightInbox.merge(inbox, [insight()], now: now.add(const Duration(seconds: 60)));
      expect(inbox.length, 1);
      expect(inbox[0].status, InsightStatus.read);
      // Neuer Inhalt: wieder neu.
      inbox = InsightInbox.merge(inbox, [insight(text: 'Heute früher ins Bett.')], now: now);
      expect(inbox[0].status, InsightStatus.newInsight);
      // Verworfen bleibt verworfen, solange die Richtung gleich ist.
      inbox = InsightInbox.setStatus(InsightStatus.dismissed, id: inbox[0].id, insights: inbox, now: now);
      inbox = InsightInbox.merge(inbox, [insight(text: 'Noch ein Text.')], now: now);
      expect(inbox[0].status, InsightStatus.dismissed);
    });

    test('Regeln schlagen widersprechende KI', () {
      final rule = insight(subject: 'intensitaet', title: 'Heute locker', direction: InsightDirection.less);
      final ai = insight(
        topic: InsightTopic.training,
        subject: 'intensitaet',
        title: 'Heute Intervalle',
        direction: InsightDirection.more,
        origin: InsightOrigin.ai,
      );
      var inbox = InsightInbox.merge([], [rule], now: now);
      inbox = InsightInbox.merge(inbox, [ai], now: now);
      expect(inbox.map((item) => item.title), ['Heute locker']);
      // Umgekehrt ersetzt die Regel die KI.
      inbox = InsightInbox.merge([], [ai], now: now);
      inbox = InsightInbox.merge(inbox, [rule], now: now);
      expect(inbox.map((item) => item.title), ['Heute locker']);
      // KI unter gleicher ID wie eine gültige Regel: Regel bleibt.
      final sameID = insight(text: 'KI-Text', origin: InsightOrigin.ai);
      inbox = InsightInbox.merge([insight()], [sameID], now: now);
      expect(inbox[0].origin, InsightOrigin.rules);
    });

    test('doppelte Titel und Abgelaufenes fallen weg', () {
      final first = insight(subject: 'protein', title: 'Mehr Protein');
      final duplicate = insight(
        topic: InsightTopic.nutrition,
        subject: 'eiweiss',
        title: 'Mehr Protein',
        origin: InsightOrigin.ai,
      );
      final expired = insight(subject: 'alt', title: 'Alt', days: -1);
      expect(InsightInbox.merge([], [first, duplicate, expired], now: now).length, 1);
    });

    test('Gruppen und zurückgezogene Regeln', () {
      var inbox = InsightInbox.merge([], [
        insight(),
        insight(subject: 'protein', title: 'Mehr Protein', days: 5),
      ], now: now);
      inbox = InsightInbox.setStatus(InsightStatus.done, id: 'erholung.protein', insights: inbox, now: now);
      expect(InsightInbox.unreadCount(inbox, now: now), 1);
      var groups = InsightInbox.groups(inbox, now: now);
      expect(groups.newItems.length, 1);
      expect(groups.closed.length, 1);
      // Regel trifft nicht mehr zu → nicht mehr aktuell.
      inbox = InsightInbox.retireRules(inbox, keeping: {}, now: now);
      groups = InsightInbox.groups(inbox, now: now.add(const Duration(seconds: 1)));
      expect(groups.expired.length, 1);
      // Nach 30 Tagen fallen erledigte, nach 14 Tagen abgelaufene weg.
      expect(InsightInbox.merge(inbox, [], now: now.add(const Duration(days: 31))), isEmpty);
    });

    test('Regeln erzeugen Empfehlungen aus den bestehenden Prüfungen', () {
      const recommendation = Recommendation(
        level: RecoveryLevel.locker,
        reasons: ['Ruhepuls deutlich über dem Schnitt'],
      );
      final insights = InsightRules.build(
        InsightRulesInput(
          now: now,
          recommendation: recommendation,
          gymObservations: const [
            'Bankdrücken: seit drei Einheiten 80 kg ohne mehr Wiederholungen – Stillstand. Variante ändern.',
            'Beine: 4 Sätze in 7 Tagen – unter 10. Für mehr Zuwachs Sätze ergänzen.',
          ],
          nutritionGaps: const ['Protein: im Schnitt 90 von 140 g (64 %)'],
        ),
      );
      expect(insights.map((item) => item.topic), [
        InsightTopic.recovery,
        InsightTopic.stagnation,
        InsightTopic.training,
        InsightTopic.nutrition,
      ]);
      expect(insights[1].subject, 'bankdruecken');
      expect(insights[1].direction, InsightDirection.change);
      expect(insights[2].direction, InsightDirection.more);
      expect(insights[3].text.startsWith('Du kommst im Schnitt 90 von 140 g'), isTrue);
      // Normale Erholung erzeugt nichts.
      final normal = InsightRules.build(
        InsightRulesInput(
          now: now,
          recommendation: const Recommendation(level: RecoveryLevel.normal, reasons: []),
        ),
      );
      expect(normal, isEmpty);
    });

    test('KI-Antwort nur mit Belegen', () {
      final facts = InsightAnalysis.facts(['Ruhepuls heute 64, Schnitt 58', '']);
      expect(facts.map((fact) => fact.id), ['f1']);
      const output = JsonValue({
        'empfehlungen': [
          {
            'thema': 'erholung',
            'betreff': 'Ruhepuls',
            'titel': 'Erholung reduziert',
            'text': 'Dein Ruhepuls liegt über deinem Normalbereich.',
            'richtung': 'weniger',
            'prioritaet': 1,
            'gueltig_tage': 30,
            'sicherheit': 'niedrig',
            'belege': ['f1'],
          },
          {'thema': 'erholung', 'titel': 'Ohne Beleg', 'text': 'x'},
          {
            'thema': 'unsinn',
            'titel': 'x',
            'text': 'x',
            'belege': ['f1'],
          },
        ],
      });
      final insights = InsightAnalysis.insights(output, facts: facts, model: 'gemma', now: now);
      expect(insights.length, 1);
      expect(insights[0].basis, ['Ruhepuls heute 64, Schnitt 58']);
      expect(insights[0].uncertain, isTrue);
      expect(insights[0].validUntil, now.add(const Duration(days: 14)));
      expect(insights[0].subject, 'ruhepuls');
      final input = InsightAnalysis.input(
        topic: InsightTopic.recovery,
        facts: facts,
        missing: ['Keine Schlafdaten'],
        ruleInsights: [],
      );
      expect(input['thema'], 'erholung');
      expect(input['fehlend'], ['Keine Schlafdaten']);
    });

    test('gespeicherte Empfehlungen lassen sich lesen', () {
      final text = jsonEncode([insight().toJson()]);
      final decoded = listStrict(jsonDecode(text), Insight.fromJson);
      expect(decoded, [insight()]);
      final changed = InsightInbox.setStatus(InsightStatus.done, id: insight().id, insights: [insight()], now: now);
      expect(Insight.fromJson(jsonDecode(jsonEncode(changed[0].toJson()))), changed[0]);
    });
  });

  group('KI-Einstellungen', () {
    test('Stufen erlauben Aufgaben', () {
      // Voll: alles.
      expect(AIPolicy.allows(AIMode.full, task: 'daily_note', trigger: AITrigger.automatic), isTrue);
      // Auf Anfrage: nichts Automatisches.
      expect(AIPolicy.allows(AIMode.onRequest, task: 'daily_note', trigger: AITrigger.automatic), isFalse);
      expect(AIPolicy.allows(AIMode.onRequest, task: 'daily_note', trigger: AITrigger.user), isTrue);
      expect(AIPolicy.allows(AIMode.onRequest, task: 'meal_analyze', trigger: AITrigger.user), isTrue);
      // Keine Empfehlungen: nur Erfassung auf Anfrage.
      expect(AIPolicy.allows(AIMode.captureOnly, task: 'meal_analyze', trigger: AITrigger.user), isTrue);
      expect(AIPolicy.allows(AIMode.captureOnly, task: 'nutrition_label', trigger: AITrigger.user), isTrue);
      expect(AIPolicy.allows(AIMode.captureOnly, task: 'coach_chat', trigger: AITrigger.user), isFalse);
      expect(AIPolicy.allows(AIMode.captureOnly, task: 'gym_plan', trigger: AITrigger.user), isFalse);
      expect(AIPolicy.allows(AIMode.captureOnly, task: 'meal_analyze', trigger: AITrigger.automatic), isFalse);
      // Aus: nichts mit Daten; Verbindungstest nur von Hand.
      expect(AIPolicy.allows(AIMode.off, task: 'meal_analyze', trigger: AITrigger.user), isFalse);
      expect(AIPolicy.allows(AIMode.off, task: 'ping', trigger: AITrigger.user), isTrue);
      expect(AIPolicy.allows(AIMode.full, task: 'ping', trigger: AITrigger.automatic), isFalse);
      // Unbekannte Aufgaben zählen als Empfehlung.
      expect(AIPolicy.kind('neu'), AITaskKind.recommendation);
    });

    test('Einstellungen werden tolerant gelesen', () {
      expect(AISettings.fromJson(jsonDecode('{"mode": "unbekannt"}')), const AISettings());
      const stored = AISettings(mode: AIMode.captureOnly, provider: AIProviderChoice.privat);
      expect(AISettings.fromJson(jsonDecode(jsonEncode(stored.toJson()))), stored);
    });

    test('Nutzungsprotokoll kürzt und summiert', () {
      final old = AIUsageEntry(
        date: now.subtract(const Duration(days: 200)),
        task: 'x',
        trigger: AITrigger.user,
        provider: 'gemini',
        model: 'm',
        ok: true,
        milliseconds: 1,
      );
      var log = AIUsageLog.appending(old, []);
      final entries = [
        AIUsageEntry(
          date: now,
          task: 'daily_note',
          trigger: AITrigger.automatic,
          provider: 'gemini',
          model: 'flash',
          ok: true,
          inputTokens: 1000,
          outputTokens: 200,
          listPriceUsd: 0.0008,
          milliseconds: 2000,
        ),
        AIUsageEntry(
          date: now,
          task: 'coach_chat',
          trigger: AITrigger.user,
          provider: 'workers_ai',
          model: 'gemma',
          ok: true,
          inputTokens: 500,
          outputTokens: 100,
          listPriceUsd: 0.00008,
          milliseconds: 1000,
        ),
        AIUsageEntry(
          date: now,
          task: 'coach_chat',
          trigger: AITrigger.user,
          provider: null,
          model: null,
          ok: false,
          milliseconds: 500,
          error: 'x' * 500,
        ),
      ];
      for (final entry in entries) {
        log = AIUsageLog.appending(entry, log);
      }
      expect(log.length, 3);
      expect(log.first.error?.length, 160);
      final summary = AIUsageLog.summary(log, since: now.subtract(const Duration(days: 30)));
      expect(summary.requests, 3);
      expect(summary.failures, 1);
      expect(summary.automatic, 1);
      expect(summary.byTask.first.task, 'coach_chat');
      expect((summary.listPriceUsd - 0.00088).abs(), lessThan(1e-9));
      expect(summary.lines.length, 3);
      expect(AIUsageLog.providerLabel('workers_ai'), 'Cloudflare Workers AI');
      expect(AIUsageEntry.fromJson(jsonDecode(jsonEncode(log.first.toJson()))), log.first);
    });
  });
}
