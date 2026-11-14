import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/settings/coach_settings.dart';
import '../../services/ai/ai_client.dart';
import '../../services/nutrition/cook_share_service.dart';

/// Gemeinsam kochen und vorkochen: Vorschläge für eine oder zwei Personen, gespeichert als `cook-plans.json` (Port von
/// `RecipeViewModel`, Teil Kochpläne).
final class CookPlanController extends ChangeNotifier {
  CookPlanController({Future<Directory> Function()? folder, DateTime Function()? clock})
    : _folder = folder ?? getApplicationSupportDirectory,
      _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _folder;
  final DateTime Function() _clock;

  /// Kochpläne dieses Geräts, neueste zuerst.
  List<CookPlan> cookPlans = [];
  List<String> cookNotes = const [];
  bool isCooking = false;
  String? cookError;
  bool _loaded = false;

  Future<File> _file() async => File(p.join((await _folder()).path, 'cook-plans.json'));

  /// Eigene Angaben für den Plan: dieselben Tagesziele wie in der Wochenübersicht ([targets] aus den Rezeptideen).
  CookPerson myself({
    required List<RecipeDayTarget> targets,
    required CoachSettings settings,
    required GarminProfile? garminProfile,
  }) {
    final body = settings.nutrition.profile(garminProfile, on: CalendarDay.fromDate(_clock()));
    final share = CookPlanner.share(
      name: 'Ich',
      week: targets,
      diet: settings.nutrition.diet,
      preferences: settings.recipes,
      fields: CookShareFields(),
      safety: GoalRules.weightGuard(settings.nutrition, body),
    );
    return CookPerson(id: CookPerson.meID, share: share);
  }

  /// Vorschläge erstellen. Freigaben werden vorher neu geholt: Was zurückgezogen ist, wird nicht mehr verwendet.
  Future<void> createCookPlans({
    required CookAudience audience,
    required CookPartner? partner,
    required MealCategory meal,
    required CookAmount amount,
    required List<RecipeDayTarget> targets,
    required AIClient ai,
    required CoachSettings settings,
    required GarminProfile? garminProfile,
    required List<String> favorites,
  }) async {
    if (!ai.isConfigured) {
      cookError = 'Für Rezeptideen muss der KI-Worker eingerichtet sein (Einstellungen › KI-Worker).';
      notifyListeners();
      return;
    }
    if (isCooking) return;
    isCooking = true;
    cookError = null;
    notifyListeners();
    try {
      final people = <CookPerson>[
        if (audience != CookAudience.partner)
          myself(targets: targets, settings: settings, garminProfile: garminProfile),
      ];
      if (audience != CookAudience.me) {
        if (partner == null) {
          cookError = 'Verbinde zuerst eine Person unter „Gemeinsam kochen“.';
          return;
        }
        final fresh = await CookShareService(ai).fetch(partner.code);
        settings.cookPartners = [
          for (final stored in settings.cookPartners)
            stored.code == partner.code ? CookPartner(code: stored.code, share: fresh) : stored,
        ];
        people.add(CookPerson(id: partner.code, share: fresh));
      }
      final input = CookPlanner.input(
        people: people,
        meal: meal,
        amount: amount,
        preferences: settings.recipes,
        favorites: favorites,
      );
      final response = await _run(ai, input);
      final result = CookPlanner.plans(
        response.output,
        people: people,
        meal: meal,
        amount: amount,
        source: 'KI · ${response.model}',
        created: _clock(),
      );
      cookNotes = result.notes;
      if (result.plans.isEmpty) {
        cookError = 'Kein vorgeschlagenes Rezept passte zu euren Angaben. Bitte erneut versuchen.';
        return;
      }
      cookPlans = [...result.plans, ...cookPlans.take(12)];
      await _store();
    } on AIHttpError catch (error) {
      if (error.status == 404) {
        if (partner != null) await forget(partner, settings: settings);
        cookError = 'Die Freigabe wurde zurückgezogen oder ist abgelaufen. Die gespeicherten Angaben wurden gelöscht.';
      } else {
        cookError = error.message;
      }
    } on AIClientError catch (error) {
      cookError = error.message;
    } on Object catch (error) {
      cookError = '$error';
    } finally {
      isCooking = false;
      notifyListeners();
    }
  }

  /// Bei einem vorübergehenden Ausfall genau ein zweiter Versuch.
  Future<AIResponse> _run(AIClient ai, Map<String, Object?> input) async {
    try {
      return await ai.run('cook_plan', input: input);
    } on AIHttpError catch (error) {
      if (!AIErrorText.isTemporary(error.status)) rethrow;
      await Future<void>.delayed(const Duration(seconds: 2));
      return ai.run('cook_plan', input: input);
    }
  }

  CookPlan? plan(String id) => cookPlans.where((plan) => plan.id == id).firstOrNull;

  void update(CookPlan plan) {
    final index = cookPlans.indexWhere((stored) => stored.id == plan.id);
    if (index < 0) return;
    cookPlans[index] = plan;
    unawaited(_store());
    notifyListeners();
  }

  void delete(CookPlan plan) {
    cookPlans.removeWhere((stored) => stored.id == plan.id);
    unawaited(_store());
    notifyListeners();
  }

  /// Verbindung lösen: Auch Pläne mit den Angaben dieser Person werden gelöscht.
  Future<void> forget(CookPartner partner, {required CoachSettings settings}) async {
    settings.cookPartners = [
      for (final stored in settings.cookPartners)
        if (stored.code != partner.code) stored,
    ];
    cookPlans.removeWhere((plan) => plan.people.any((person) => person.id == partner.code));
    notifyListeners();
    await _store();
  }

  /// Gespeicherte Pläne laden (im JSON-Format der Swift-App), nur beim ersten Mal.
  Future<void> load() async {
    if (_loaded || cookPlans.isNotEmpty) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return;
      cookPlans = [for (final item in json) ?CookPlan.fromJson(item)];
      notifyListeners();
    } on Object {
      // Keine oder unlesbare Pläne.
    }
  }

  Future<void> _store() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode([for (final plan in cookPlans) plan.toJson()]), flush: true);
    } on Object {
      // Die Pläne bleiben im Speicher.
    }
  }
}
