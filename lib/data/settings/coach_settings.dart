import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import 'settings_store.dart';

/// Einstellungen der App (Port von `CoachSettings`): Saison, Profil, KI, Ernährung, Plan und mehr – jeder Wert unter
/// seinem Schlüssel der Swift-App (`coach.*`) als JSON. Gespeichert wird beim Zuweisen (wie `didSet`); wer ein Objekt
/// ändert, weist es danach erneut zu (`settings.league = settings.league..code = 'x'`).
final class CoachSettings extends ChangeNotifier {
  CoachSettings(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final today = CalendarDay.fromDate(_clock());
    _season = _store.read(SettingsKeys.season, SeasonConfig.fromJson, SeasonConfig.standard);
    _ai = _store.read(SettingsKeys.ai, AISettings.fromJson, const AISettings());
    _aiUsage = _store.read(SettingsKeys.aiUsage, (json) => listStrict(json, AIUsageEntry.fromJson), <AIUsageEntry>[]);
    _insights = _store.read(SettingsKeys.insights, (json) => listStrict(json, Insight.fromJson), <Insight>[]);
    _nutritionDashboard = _store.read(
      SettingsKeys.nutritionDashboard,
      NutritionDashboard.fromJson,
      NutritionDashboard(),
    );
    _favoriteMeals = _store.read(
      SettingsKeys.favoriteMeals,
      (json) => listStrict(json, FavoriteMeal.fromJson),
      <FavoriteMeal>[],
    );
    _customPrompts = _store.read(
      SettingsKeys.customPrompts,
      (json) => listStrict(json, PromptTemplate.fromJson),
      <PromptTemplate>[],
    );
    _nutrition = _store.read(SettingsKeys.nutrition, NutritionSettings.fromJson, NutritionSettings());
    _competitionDecisions = _store.read(SettingsKeys.competition, _decisions, const <String, PlannedUnitDecision>{});
    _tests = _store.read(SettingsKeys.tests, (json) => listStrict(json, TestRecord.fromJson), <TestRecord>[]);
    _reminders = _store.read(SettingsKeys.reminders, ReminderSettings.fromJson, ReminderSettings());
    _companion = _store.read(SettingsKeys.companion, CompanionSettings.fromJson, CompanionSettings());
    _gym = _store.read(SettingsKeys.gym, GymSettings.fromJson, GymSettings());
    _recipes = _store.read(SettingsKeys.recipes, RecipePreferences.fromJson, RecipePreferences());
    _weights = _store.read(SettingsKeys.weights, (json) => listStrict(json, WeightEntry.fromJson), <WeightEntry>[]);
    _sleep = _store.read(SettingsKeys.sleep, SleepSettings.fromJson, SleepSettings());
    _healthDashboard = _store.read(SettingsKeys.healthDashboard, HealthDashboard.fromJson, HealthDashboard());
    _sentWorkouts = _store.read(SettingsKeys.sentWorkouts, SentWorkouts.fromJson, SentWorkouts());
    _mobility = _store.read(SettingsKeys.mobility, MobilitySettings.fromJson, MobilitySettings());
    _sources = _store.read(SettingsKeys.sources, SourcePreferences.fromJson, SourcePreferences());
    _userSources = _store.read(
      SettingsKeys.userSources,
      (json) => listStrict(json, UserSource.fromJson),
      <UserSource>[],
    );
    _ownRecipes = _store.read(SettingsKeys.ownRecipes, (json) => listStrict(json, OwnRecipe.fromJson), <OwnRecipe>[]);
    _pantry = _store.read(SettingsKeys.pantry, _strings, <String>[]);
    _cookPartners = _store.read(
      SettingsKeys.cookPartners,
      (json) => listStrict(json, CookPartner.fromJson),
      <CookPartner>[],
    );
    _handledMissed = _store.read(SettingsKeys.handledMissed, _strings, <String>[]);
    _efforts = _store.read(SettingsKeys.efforts, _ints, const <String, int>{});
    _closedReviews = _store.read(SettingsKeys.closedReviews, _strings, <String>[]);
    _dismissedSuggestions = _store.read(SettingsKeys.dismissedSuggestions, _strings, <String>[]);
    _heartRate = _store.read(SettingsKeys.heartRate, HeartRateOverrides.fromJson, HeartRateOverrides());
    _cookRelease = _store.read<CookRelease?>(SettingsKeys.cookRelease, CookRelease.fromJson, null);
    _illnessDay = _store.read<CalendarDay?>(SettingsKeys.illness, _day, null);
    _trainingBreak = _store.read<TrainingBreak?>(SettingsKeys.trainingBreak, TrainingBreak.fromJson, null);
    _importedNotes = _store.read<ImportedNotes?>(SettingsKeys.importedNotes, ImportedNotes.fromJson, null);
    _privacy = enumFromRaw(PrivacyMode.values, _store.string(SettingsKeys.privacy)) ?? PrivacyMode.reduced;
    _showsEvidence = _store.boolValue(SettingsKeys.showsEvidence);
    // Ausnahmen der vergangenen Wochen fallen beim Start weg (gespeichert erst bei der nächsten Änderung, wie in Swift).
    _planAdjustments = _store.read(SettingsKeys.adjustments, PlanAdjustments.fromJson, PlanAdjustments())
      ..prune(before: today);
    final storedLeague = _store.read<LeagueSettings?>(SettingsKeys.league, LeagueSettings.fromJson, null);
    _league = storedLeague ?? LeagueSettings();
    final storedProfile = _store.read<UserProfile?>(SettingsKeys.profile, UserProfile.fromJson, null);
    if (storedProfile != null) {
      _profile = storedProfile;
    } else {
      final existing = _store.contains(SettingsKeys.garminLastSync) || _store.data(SettingsKeys.season) != null;
      _profile = ProfileMigration.initialProfile(hasExistingData: existing);
      if (existing) _persist(SettingsKeys.profile, _profile.toJson());
    }
    // Die Mitglieds-ID muss stabil bleiben, sonst entstehen doppelte Einträge in der Rangliste.
    if (storedLeague == null) _persist(SettingsKeys.league, _league.toJson());
  }

  final SettingsStore _store;
  final DateTime Function() _clock;

  CalendarDay get _today => CalendarDay.fromDate(_clock());

  /// Speichert im Hintergrund (der Zwischenspeicher der Einstellungen ist sofort aktuell).
  void _persist(String key, Object? json) => unawaited(_store.setJson(key, json));

  void _changed(String key, Object? json) {
    _persist(key, json);
    notifyListeners();
  }

  static List<String>? _strings(Object? json) =>
      json is List && json.every((item) => item is String) ? json.cast<String>() : null;

  static Map<String, int>? _ints(Object? json) => json is Map && json.values.every((value) => value is int)
      ? {for (final MapEntry(:key, :value) in json.entries) '$key': value as int}
      : null;

  static CompetitionDecisions? _decisions(Object? json) {
    if (json is! Map) return null;
    final result = <String, PlannedUnitDecision>{};
    for (final MapEntry(:key, :value) in json.entries) {
      final decision = enumFromRaw(PlannedUnitDecision.values, value);
      if (decision == null) return null;
      result['$key'] = decision;
    }
    return result;
  }

  static CalendarDay? _day(Object? json) {
    if (json is! Map) return null;
    try {
      return CalendarDay.fromJson(json.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  PrivacyMode _privacy = PrivacyMode.reduced;

  /// KI-Datenschutz; Standard „reduziert“.
  PrivacyMode get privacy => _privacy;
  set privacy(PrivacyMode value) {
    _privacy = value;
    unawaited(_store.setString(SettingsKeys.privacy, value.rawValue));
    notifyListeners();
  }

  bool _showsEvidence = false;

  /// Quellen unter Empfehlungen einblenden (Standard: aus; sie bleiben unter „Quellen und Regeln“ erreichbar).
  bool get showsEvidence => _showsEvidence;
  set showsEvidence(bool value) {
    _showsEvidence = value;
    unawaited(_store.setBool(SettingsKeys.showsEvidence, value));
    notifyListeners();
  }

  late UserProfile _profile;

  /// Wer die App ist und was sie erreichen will: Sportarten, Ziel, Wochenplan. Bestehende Nutzer behalten den
  /// Saisonplan, neue starten mit dem Einrichtungsassistenten.
  UserProfile get profile => _profile;
  set profile(UserProfile value) {
    _profile = value;
    _changed(SettingsKeys.profile, value.toJson());
  }

  late PlanAdjustments _planAdjustments;

  /// Ausnahmen vom Wochenplan (auslassen, verschieben) für einzelne Wochen.
  PlanAdjustments get planAdjustments => _planAdjustments;
  set planAdjustments(PlanAdjustments value) {
    _planAdjustments = value;
    _changed(SettingsKeys.adjustments, value.toJson());
  }

  late LeagueSettings _league;

  /// Teilnahme an einer Rangliste.
  LeagueSettings get league => _league;
  set league(LeagueSettings value) {
    _league = value;
    _changed(SettingsKeys.league, value.toJson());
  }

  late SeasonConfig _season;

  /// Saison (Renntermine, Testwerte).
  SeasonConfig get season => _season;
  set season(SeasonConfig v) {
    _season = v;
    _changed(SettingsKeys.season, v.toJson());
  }

  late AISettings _ai;

  /// KI-Stufe und bevorzugter Anbieter (Einstellungen › KI).
  AISettings get ai => _ai;
  set ai(AISettings v) {
    _ai = v;
    _changed(SettingsKeys.ai, v.toJson());
  }

  late List<AIUsageEntry> _aiUsage;

  /// Internes Protokoll der KI-Anfragen (ohne Inhalte), neueste zuerst.
  List<AIUsageEntry> get aiUsage => _aiUsage;
  set aiUsage(List<AIUsageEntry> v) {
    _aiUsage = v;
    _changed(SettingsKeys.aiUsage, [for (final e in v) e.toJson()]);
  }

  late List<Insight> _insights;

  /// Empfehlungen im Reiter „AI“ mit Bearbeitungsstand.
  List<Insight> get insights => _insights;
  set insights(List<Insight> v) {
    _insights = v;
    _changed(SettingsKeys.insights, [for (final e in v) e.toJson()]);
  }

  late NutritionDashboard _nutritionDashboard;

  /// Karten im Ernährungsreiter (Reihenfolge, ausgeblendet).
  NutritionDashboard get nutritionDashboard => _nutritionDashboard;
  set nutritionDashboard(NutritionDashboard v) {
    _nutritionDashboard = v;
    _changed(SettingsKeys.nutritionDashboard, v.toJson());
  }

  late List<FavoriteMeal> _favoriteMeals;

  /// Favorisierte Mahlzeiten (Vorlagen, getrennt von Rezepten und Tagebuch).
  List<FavoriteMeal> get favoriteMeals => _favoriteMeals;
  set favoriteMeals(List<FavoriteMeal> v) {
    _favoriteMeals = v;
    _changed(SettingsKeys.favoriteMeals, [for (final e in v) e.toJson()]);
  }

  late List<PromptTemplate> _customPrompts;

  /// Eigene Prompts der Prompt-Bibliothek.
  List<PromptTemplate> get customPrompts => _customPrompts;
  set customPrompts(List<PromptTemplate> v) {
    _customPrompts = v;
    _changed(SettingsKeys.customPrompts, [for (final e in v) e.toJson()]);
  }

  late NutritionSettings _nutrition;

  NutritionSettings get nutrition => _nutrition;
  set nutrition(NutritionSettings v) {
    _nutrition = v;
    _changed(SettingsKeys.nutrition, v.toJson());
  }

  late CompetitionDecisions _competitionDecisions;

  /// Entscheidungen zu Wettkampf-Einheiten 🏁 im Plan (`wk-lauf-<Montag>-q|l`).
  CompetitionDecisions get competitionDecisions => _competitionDecisions;
  set competitionDecisions(CompetitionDecisions v) {
    _competitionDecisions = v;
    _changed(SettingsKeys.competition, {for (final MapEntry(:key, :value) in v.entries) key: value.rawValue});
  }

  late List<TestRecord> _tests;

  /// Eingetragene Testwerte mit Datum (Verläufe und Aktualität der Benchmarks).
  List<TestRecord> get tests => _tests;
  set tests(List<TestRecord> v) {
    _tests = v;
    _changed(SettingsKeys.tests, [for (final e in v) e.toJson()]);
  }

  late ReminderSettings _reminders;

  /// Erinnerung an geplante Einheiten.
  ReminderSettings get reminders => _reminders;
  set reminders(ReminderSettings v) {
    _reminders = v;
    _changed(SettingsKeys.reminders, v.toJson());
  }

  late CompanionSettings _companion;

  /// Optionaler Begleiter (z. B. der eigene Hund).
  CompanionSettings get companion => _companion;
  set companion(CompanionSettings v) {
    _companion = v;
    _changed(SettingsKeys.companion, v.toJson());
  }

  late GymSettings _gym;

  /// Routinen, eigene Übungen und Ausstattung fürs Gym.
  GymSettings get gym => _gym;
  set gym(GymSettings v) {
    _gym = v;
    _changed(SettingsKeys.gym, v.toJson());
  }

  late RecipePreferences _recipes;

  /// Wünsche für die Rezeptideen.
  RecipePreferences get recipes => _recipes;
  set recipes(RecipePreferences v) {
    _recipes = v;
    _changed(SettingsKeys.recipes, v.toJson());
  }

  late List<WeightEntry> _weights;

  /// Eigene Wägungen (Garmin-Wägungen liegen beim Abruf).
  List<WeightEntry> get weights => _weights;
  set weights(List<WeightEntry> v) {
    _weights = v;
    _changed(SettingsKeys.weights, [for (final e in v) e.toJson()]);
  }

  late SleepSettings _sleep;

  /// Schlaf-Coach: Ziel, Weckzeit, Erinnerung.
  SleepSettings get sleep => _sleep;
  set sleep(SleepSettings v) {
    _sleep = v;
    _changed(SettingsKeys.sleep, v.toJson());
  }

  late HealthDashboard _healthDashboard;

  /// Widgets im Gesundheitsbereich (Reihenfolge, Darstellung, ausgeblendet).
  HealthDashboard get healthDashboard => _healthDashboard;
  set healthDashboard(HealthDashboard v) {
    _healthDashboard = v;
    _changed(SettingsKeys.healthDashboard, v.toJson());
  }

  late SentWorkouts _sentWorkouts;

  /// An die Uhr gesendete Workouts (je Einheit und Tag), damit erneutes Senden ersetzt statt verdoppelt.
  SentWorkouts get sentWorkouts => _sentWorkouts;
  set sentWorkouts(SentWorkouts v) {
    _sentWorkouts = v;
    _changed(SettingsKeys.sentWorkouts, v.toJson());
  }

  late MobilitySettings _mobility;

  /// Mobility: gewählte Dauer, Testergebnisse, erledigte Einheiten.
  MobilitySettings get mobility => _mobility;
  set mobility(MobilitySettings v) {
    _mobility = v;
    _changed(SettingsKeys.mobility, v.toJson());
  }

  late SourcePreferences _sources;

  /// Primäres Gerät und bevorzugte Quelle je Datenart.
  SourcePreferences get sources => _sources;
  set sources(SourcePreferences v) {
    _sources = v;
    _changed(SettingsKeys.sources, v.toJson());
  }

  late List<UserSource> _userSources;

  /// Eigene wissenschaftliche Quellen, die die KI zusätzlich berücksichtigt.
  List<UserSource> get userSources => _userSources;
  set userSources(List<UserSource> v) {
    _userSources = v;
    _changed(SettingsKeys.userSources, [for (final e in v) e.toJson()]);
  }

  late List<OwnRecipe> _ownRecipes;

  /// Eigene Rezepte (Meal-Prep mit Portionen und Vorrat).
  List<OwnRecipe> get ownRecipes => _ownRecipes;
  set ownRecipes(List<OwnRecipe> v) {
    _ownRecipes = v;
    _changed(SettingsKeys.ownRecipes, [for (final e in v) e.toJson()]);
  }

  late List<String> _pantry;

  /// „Habe ich da“ aus der Einkaufsliste – fließt in „Was jetzt?“ ein.
  List<String> get pantry => _pantry;
  set pantry(List<String> v) {
    _pantry = v;
    _changed(SettingsKeys.pantry, v);
  }

  late List<CookPartner> _cookPartners;

  /// Personen, die für gemeinsame Rezepte etwas freigegeben haben (nur deren freigegebene Angaben).
  List<CookPartner> get cookPartners => _cookPartners;
  set cookPartners(List<CookPartner> v) {
    _cookPartners = v;
    _changed(SettingsKeys.cookPartners, [for (final e in v) e.toJson()]);
  }

  late List<String> _handledMissed;

  /// Verpasste Einheiten, über die schon entschieden wurde (nachholen, streichen, krank).
  List<String> get handledMissed => _handledMissed;
  set handledMissed(List<String> v) {
    _handledMissed = v;
    _changed(SettingsKeys.handledMissed, v);
  }

  late Map<String, int> _efforts;

  /// Anstrengung 1–10 je Aktivität (Schlüssel: Aktivitäts-ID).
  Map<String, int> get efforts => _efforts;
  set efforts(Map<String, int> v) {
    _efforts = v;
    _changed(SettingsKeys.efforts, v);
  }

  late List<String> _closedReviews;

  /// Aktivitäten, deren „Nach dem Training“-Karte geschlossen wurde.
  List<String> get closedReviews => _closedReviews;
  set closedReviews(List<String> v) {
    _closedReviews = v;
    _changed(SettingsKeys.closedReviews, v);
  }

  late List<String> _dismissedSuggestions;

  /// Verworfene Planvorschläge (`PlanSuggestion.id`).
  List<String> get dismissedSuggestions => _dismissedSuggestions;
  set dismissedSuggestions(List<String> v) {
    _dismissedSuggestions = v;
    _changed(SettingsKeys.dismissedSuggestions, v);
  }

  late HeartRateOverrides _heartRate;

  /// Eigene HFmax und Schwellen-HF (0 = automatisch).
  HeartRateOverrides get heartRate => _heartRate;
  set heartRate(HeartRateOverrides v) {
    _heartRate = v;
    _changed(SettingsKeys.heartRate, v.toJson());
  }

  CookRelease? _cookRelease;

  /// Eigene Freigabe; `null` = nichts freigegeben.
  CookRelease? get cookRelease => _cookRelease;
  set cookRelease(CookRelease? v) {
    _cookRelease = v;
    _changed(SettingsKeys.cookRelease, v?.toJson());
  }

  CalendarDay? _illnessDay;

  /// Zuletzt „war krank“ gemeldet: die nächsten Tage höchstens locker (`MissedSessions`).
  CalendarDay? get illnessDay => _illnessDay;
  set illnessDay(CalendarDay? v) {
    _illnessDay = v;
    _changed(SettingsKeys.illness, v?.toJson());
  }

  TrainingBreak? _trainingBreak;

  /// Urlaub oder Trainingspause (`TrainingBreak`); `null` = keine.
  TrainingBreak? get trainingBreak => _trainingBreak;
  set trainingBreak(TrainingBreak? v) {
    _trainingBreak = v;
    _changed(SettingsKeys.trainingBreak, v?.toJson());
  }

  ImportedNotes? _importedNotes;

  /// Hinweise aus dem letzten Import einer KI-Antwort (manueller KI-Coach).
  ImportedNotes? get importedNotes => _importedNotes;
  set importedNotes(ImportedNotes? v) {
    _importedNotes = v;
    _changed(SettingsKeys.importedNotes, v?.toJson());
  }

  /// Pause, die heute oder später noch gilt.
  TrainingBreak? activeBreak(CalendarDay today) {
    final current = trainingBreak;
    return current == null || current.isOver(today) ? null : current;
  }

  /// Überträgt das Ziel des Profils auf die Ernährung (Tempo, Schutzgrenzen) und liefert die Hinweise dazu. Im
  /// Saisonplan bleibt die Ernährung unverändert.
  GoalAssessment applyProfileToNutrition(GarminProfile? garmin, {CalendarDay? day}) {
    final body = nutrition.profile(garmin, on: day ?? _today);
    final assessment = GoalRules.assess(profile, body);
    if (profile.mode != ProfileMode.personal) return assessment;
    final updated = nutrition.copy();
    GoalRules.apply(assessment, updated);
    nutrition = updated;
    return assessment;
  }

  /// Profil für KI, Export und Anzeige: gesperrte oder erreichte Gewichtsziele tauchen darin nicht mehr auf.
  UserProfile get coachingProfile => GoalRules.coachingProfile(profile, nutrition);

  /// Hält die Schutzgrenzen aktuell: Gesundheitsangaben, neueste Wägung, Grenze oder Zielgewicht erreicht.
  void refreshGoalGuards(List<WeightEntry> entries, {GarminProfile? garmin, CalendarDay? day}) {
    final today = day ?? _today;
    final updated = nutrition.copy();
    final withheld = GoalRules.withholdsTargets(profile);
    updated.weightTargetsWithheld = withheld;
    if (withheld) updated.energyAdjustmentKilocalories = 0;
    GoalRules.updateWeight(updated, entries, today: today);
    if (profile.mode == ProfileMode.personal) {
      final assessment = GoalRules.assess(profile, updated.profile(garmin, on: today));
      if (GoalRules.holdChanged(assessment, updated)) GoalRules.apply(assessment, updated);
    }
    if (updated != nutrition) nutrition = updated;
  }

  /// Wochenplan der Woche, die [day] enthält, mit Ausnahmen.
  WeekSchedule schedule(CalendarDay day) => planAdjustments.schedule(profile.schedule, inWeekOf: day);

  /// Testwert übernehmen: Saisonwerte setzen und im Verlauf festhalten.
  void record(TestKind kind, double value, {CalendarDay? on}) {
    final updated = season.copy();
    switch (kind) {
      case TestKind.css:
        updated.cssSecondsPer100m = value.round();
      case TestKind.ftp:
        updated.ftpWatts = value.round();
      case TestKind.threshold:
        updated.thresholdPaceSecondsPerKm = value.round();
      case TestKind.racePace:
        updated.racePaceSecondsPerKm = value.round();
      case TestKind.bikeSpeed:
        updated.raceBikeSpeedKmh = value;
      case TestKind.halfMarathon:
        break;
    }
    if (kind != TestKind.halfMarathon) season = updated;
    tests = TestHistory.adding(TestRecord(kind: kind, value: value, day: on ?? _today), tests);
  }

  /// Wägung eintragen; ein Eintrag je Tag, der neue ersetzt den alten.
  void logWeight(double kilograms, {CalendarDay? on}) {
    final day = on ?? _today;
    final cutoff = day.adding(-365);
    weights = [
      ...weights.where((entry) => entry.day != day && entry.day >= cutoff),
      WeightEntry(day: day, kilograms: kilograms, source: WeightSource.manual),
    ]..sort((a, b) => a.day.compareTo(b.day));
  }

  int? get halfMarathonSeconds => TestHistory.latest(TestKind.halfMarathon, tests)?.value.toInt();
}
