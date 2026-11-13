// Port von ChatRouterTests.swift, ChatContextTests.swift und dem PersonalNote-Test aus ActivityFeedTests.swift.
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const today = CalendarDay(2026, 11, 9);

DateTime date(int offset) {
  final day = today.adding(offset);
  return DateTime(day.year, day.month, day.day, 18);
}

GymSession bench(int offset, {required double weight, required int reps}) {
  LoggedSet set() => LoggedSet(reps: reps, weightKg: weight);
  final exercise = LoggedExercise(
    exerciseID: 'bankdruecken',
    name: 'Bankdrücken',
    group: MuscleGroup.chest,
    sets: [set(), set()],
  );
  return GymSession(workoutKey: null, title: 'Oberkörper', start: date(offset), exercises: [exercise]);
}

ChatFacts routerFacts([PrivacyMode privacy = PrivacyMode.reduced]) =>
    ChatFacts(
        profile: UserProfile(
          mode: ProfileMode.personal,
          sports: const [TrainingSport.strength],
          goal: FitnessGoal.buildMuscle,
        ),
        privacy: privacy,
      )
      ..gymSessions = [bench(-20, weight: 75, reps: 8), bench(-3, weight: 80, reps: 8)]
      ..eaten = NutrientValues({Nutrient.kcal: 1200, Nutrient.protein: 70, Nutrient.carbs: 120, Nutrient.fat: 40})
      ..todayMeals = [
        ChatMealLine(title: 'Haferbrei', nutrients: NutrientValues({Nutrient.kcal: 400, Nutrient.protein: 20})),
      ]
      ..recommendation = 'Locker trainieren'
      ..reasons = ['Ruhepuls 8 über Normal']
      ..todaySessions = ['Oberkörper']
      ..tomorrowSessions = ['Beine']
      ..todayMetrics = (DailyMetrics(today)..restingHeartRate = 58);

String text(ChatFacts facts, String question, [List<ChatMessage> history = const []]) {
  final topics = ChatRouter.topics(question: question, history: history);
  return ChatContext.focusedLines(facts, topics: topics, question: question, today: today).join('\n');
}

Insight insight(
  InsightTopic topic,
  String subject,
  String title, [
  InsightDirection direction = InsightDirection.check,
]) => Insight(
  topic: topic,
  subject: subject,
  title: title,
  text: '',
  direction: direction,
  origin: InsightOrigin.ai,
  created: date(-1),
  validUntil: date(5),
);

ChatFacts contextFacts(PrivacyMode privacy) =>
    ChatFacts(
        profile: UserProfile(goal: FitnessGoal.loseWeight),
        privacy: privacy,
      )
      ..recommendation = 'Locker'
      ..reasons = ['HRV 48 ms unter dem Normalbereich']
      ..todaySessions = ['Lockerer Lauf, 40 min']
      ..sleep = const SleepReport(
        nights: 7,
        averageHours: 6.4,
        shortNights: 5,
        debtHours: 9,
        tonightMinutes: 540,
        bedtimeMinutes: 1275,
        bedtimeSpreadMinutes: 75,
        tips: [],
      )
      ..weightTrend = const WeightTrendResult(trendKilograms: 71.8, weeklyPercent: -0.52, entries: 20, spanDays: 27);

void main() {
  group('Chat-Router (Testfälle aus Paket 12)', () {
    test('Test 1: Bankdrücken wird verglichen', () {
      final result = text(
        routerFacts(),
        'Wie hat sich meine Leistung beim Bankdrücken in den letzten vier Wochen entwickelt?',
      );
      expect(result, contains('75 kg für 8 Wiederholungen'));
      expect(result, contains('80 kg für 8 Wiederholungen'));
      expect(result, contains('Differenz 5 kg'));
    });

    test('fehlende Übung wird genannt', () {
      expect(text(routerFacts(), 'Wie läuft meine Kniebeuge?'), contains('keine erfassten Sätze'));
    });

    test('Test 2: offenes Protein ist gerechnet', () {
      final value = routerFacts()
        ..targets = NutritionPlanner.compute(
          activities: [],
          planItems: [],
          settings: NutritionSettings(),
          garminProfile: null,
          day: today,
          hasGarminData: false,
        );
      final goal = (value.targets!.values[Nutrient.protein] ?? 0).round();
      final result = text(value, 'Wie viel Protein fehlt mir heute noch?');
      expect(result, contains('70 g Protein'));
      expect(result, contains('Noch offen heute'));
      expect(result, contains('${goal - 70} g Protein'));
    });

    test('Test 3: Erholungsfrage bekommt Ampel und Plan', () {
      final result = text(routerFacts(), 'Sollte ich heute schwer trainieren?');
      expect(result, contains('Locker trainieren'));
      expect(result, contains('Heute geplant'));
    });

    test('Test 4: Folgefrage übernimmt das Thema', () {
      const history = [(role: 'user', text: 'Wie viel Protein fehlt mir heute?'), (role: 'coach', text: 'Noch 60 g.')];
      const question = 'Und was bedeutet das für mein Training morgen?';
      final topics = ChatRouter.topics(question: question, history: history);
      expect(topics, contains(ChatTopic.nutrition));
      expect(topics, contains(ChatTopic.recovery));
      expect(text(routerFacts(), question, history), contains('Morgen geplant: Beine'));
    });

    test('allgemeine Frage lädt keine persönlichen Daten', () {
      final result = text(routerFacts(), 'Was ist der Unterschied zwischen Kreatin und Molke im Allgemeinen?');
      expect(result, isNot(contains('Oberkörper')));
      expect(result, isNot(contains('kcal')));
    });

    test('nur passende Daten', () {
      final result = text(routerFacts(), 'Wie viel Protein brauche ich noch?');
      expect(result, isNot(contains('Bankdrücken')));
      expect(result, isNot(contains('Ampel')));
    });

    test('reduziert ohne Roh-Gesundheitswerte', () {
      const question = 'Wie war mein Schlaf und soll ich heute trainieren?';
      final reduced = text(routerFacts(), question);
      expect(reduced, isNot(contains('Ruhepuls heute')));
      expect(reduced, isNot(contains('Ruhepuls 8')));
      expect(text(routerFacts(PrivacyMode.full), question), contains('Ruhepuls heute: 58'));
    });

    test('Bereiche folgen erst dem Thema, dann dem Inhalt', () {
      expect(insight(InsightTopic.training, 'bankdruecken', 'Mehr Volumen').category, InsightCategory.strength);
      expect(insight(InsightTopic.performance, 'laufen', 'Tempo').category, InsightCategory.endurance);
      expect(
        insight(InsightTopic.recovery, 'schlaf', 'Früher ins Bett, für mehr Kraft').category,
        InsightCategory.recovery,
      );
      expect(insight(InsightTopic.recovery, 'ruhepuls', 'Ruhepuls erhöht').category, InsightCategory.health);
      expect(insight(InsightTopic.nutrition, 'gewicht', 'Gewicht halten').category, InsightCategory.bodyComposition);
      expect(insight(InsightTopic.action, 'motivation', 'Dranbleiben').category, InsightCategory.general);
    });

    test('verwandte gegensätzliche Empfehlungen widersprechen sich', () {
      final more = insight(InsightTopic.training, 'kniebeuge volumen', 'A', InsightDirection.more);
      final less = insight(InsightTopic.training, 'kniebeuge', 'B', InsightDirection.less);
      final other = insight(InsightTopic.training, 'bankdruecken', 'C', InsightDirection.less);
      expect(more.contradicts(less), isTrue);
      expect(more.contradicts(other), isFalse);
      expect(InsightInbox.merge([more], [less], now: date(0)).map((item) => item.title), ['B']);
    });

    test('Erledigtes erreicht Analyse und Chat', () {
      final done = insight(
        InsightTopic.training,
        'bankdruecken',
        'Bankdrücken steigern',
      ).copyWith(status: InsightStatus.done);
      final open = insight(InsightTopic.nutrition, 'protein', 'Mehr Protein').copyWith(status: InsightStatus.read);
      final input = InsightAnalysis.input(topic: null, facts: [], missing: [], ruleInsights: [], closed: [done, open]);
      expect((input['bearbeitet']! as List).length, 1);
      final value = routerFacts()..insights = [done, open];
      final result = text(value, 'Wie läuft mein Bankdrücken?');
      expect(result, contains('Frühere Empfehlung (umgesetzt): Bankdrücken steigern.'));
      expect(result, isNot(contains('Mehr Protein')));
    });

    test('Zahlen in Mahlzeit-Titeln gehen nicht hinaus', () {
      final value = routerFacts()
        ..todayMeals = [
          ChatMealLine(title: 'Ab heute nur 800 kcal', nutrients: NutrientValues({Nutrient.kcal: 400})),
        ];
      final result = text(value, 'Wie viel Protein fehlt mir?');
      expect(result, isNot(contains('800')));
      expect(result, contains('Ab heute nur'));
    });

    test('Schutzgrenze verbirgt Mengen', () {
      final value = routerFacts()..withholdsWeightTargets = true;
      final result = text(value, 'Wie viel habe ich heute gegessen?');
      expect(result, contains('Haferbrei'));
      expect(result, isNot(contains('kcal')));
      expect(result, isNot(contains('70 g Protein')));
    });

    test('Empfehlungstitel mit Gesundheitswerten bleiben im reduzierten Modus lokal', () {
      final value = routerFacts()..insights = [insight(InsightTopic.recovery, 'ruhepuls', 'Ruhepuls 8 über Normal')];
      expect(text(value, 'Wie ist meine Erholung?'), isNot(contains('Ruhepuls 8')));
      value.privacy = PrivacyMode.full;
      expect(text(value, 'Wie ist meine Erholung?'), contains('Frühere Empfehlung (offen): Ruhepuls 8'));
    });

    test('Eingabe behält die letzten Nachrichten und kürzt ältere', () {
      final history = [for (var index = 0; index < 14; index++) (role: 'user', text: 'Frage $index')];
      final input = ChatContext.focusedInput(
        routerFacts(),
        question: 'Wie geht es weiter?',
        history: history,
        today: today,
      );
      expect((input['history']! as List).length, 10);
      expect((input['olderQuestions']! as List), isNotEmpty);
    });
  });

  group('Chat-Kontext', () {
    test('reduziert: keine Roh-Gesundheitswerte', () {
      final result = ChatContext.lines(contextFacts(PrivacyMode.reduced)).join('\n');
      expect(result, contains('Tagesampel heute: Locker.'));
      expect(result, isNot(contains('48 ms')));
      expect(result, contains('im Schnitt unter 7 Stunden'));
      expect(result, isNot(contains('6,4')));
      expect(result, contains('Gewichtstrend: leicht fallend.'));
      expect(result, isNot(contains('71,8')));
      expect(result, contains('Schlafenszeit heute 21:15'));
      expect(result, contains('Die Einschlafzeit schwankt stark.'));
    });

    test('voll: mit Werten', () {
      final result = ChatContext.lines(contextFacts(PrivacyMode.full)).join('\n');
      expect(result, contains('48 ms'));
      expect(result, contains('6,4 Stunden'));
      expect(result, contains('71,8 kg'));
    });

    test('Eingabe und Antwort', () {
      final history = [
        for (var index = 0; index < 10; index++) (role: index.isEven ? 'user' : 'coach', text: 'Nachricht $index'),
      ];
      final input = ChatContext.input(
        contextFacts(PrivacyMode.reduced),
        question: 'Wie geht es mir?',
        history: history,
      );
      expect((input['history']! as List).length, 6);
      expect(input['question'], 'Wie geht es mir?');
      final answer = ChatContext.answer(
        const JsonValue({
          'antwort': ' Gut. ',
          'quellen': ['recovery.hrv'],
        }),
      );
      expect(answer?.text, 'Gut.');
      expect(answer?.sources, ['recovery.hrv']);
      expect(ChatContext.answer(const JsonValue(<String, Object?>{})), isNull);
    });
  });

  test('persönliche Notiz ohne Saisonwerte', () {
    const day = CalendarDay(2026, 10, 28);
    final profile = UserProfile(
      sports: const [TrainingSport.run, TrainingSport.strength],
      goal: FitnessGoal.improveFitness,
    );
    const advice = ScheduleAdvice(
      mode: ScheduleAdviceMode.asPlanned,
      headline: 'Lockerer Lauf',
      detail: 'Wie geplant.',
      move: null,
      plannedTitles: [],
      evidenceIDs: [],
    );
    final planned = [PlannedSession(day: day, slot: const SessionSlot(TrainingSport.run, SessionIntensity.easy))];
    final week = SessionMatcher.match(planned: planned, activities: [], today: day);
    final input = PersonalNote.input(
      profile: profile,
      advice: advice,
      recommendation: null,
      metrics: null,
      week: week,
      today: day,
      privacy: PrivacyMode.reduced,
    );
    expect(input.containsKey('raceName'), isFalse);
    expect(input.containsKey('testValues'), isFalse);
    expect(input['todayItems'], ['Lockerer Lauf (heute)']);
    expect(input['weekPlanned'], 1);
    expect(PersonalNote.fallback(advice: advice, recommendation: null, week: week), [
      'Lockerer Lauf: Wie geplant.',
      'Diese Woche: 0 von 1 Einheiten geschafft.',
    ]);
  });
}
