import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../json/json_value.dart';
import '../profile/goal_rules.dart';
import '../util/enum_codec.dart';
import '../util/swift_date.dart';
import '../util/text_prefix.dart';
import 'hydration.dart';
import 'meal.dart';
import 'meal_category.dart';
import 'nutrient.dart';
import 'nutrition_settings.dart';
import 'recipe_plan.dart';

final _code = RegExp(r'^[a-z0-9]{10}$');

double? _number(Object? value) => value is num ? value.toDouble() : null;

/// Was eine Person für gemeinsame Rezepte ausdrücklich freigibt. Mehr verlässt das Gerät nicht: keine Körperwerte,
/// keine Gesundheitsangaben, kein Tagebuch. Fehlt ein Wert, ist er nicht freigegeben.
final class CookShare {
  CookShare({
    required this.name,
    this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.diet,
    Set<Allergen>? allergens,
    this.dislikes = '',
  }) : allergens = allergens ?? {};

  String name;

  /// Tagesziele im Mittel einer Woche; `null` = nicht freigegeben.
  double? kcal;
  double? protein;
  double? carbs;
  double? fat;
  Diet? diet;
  Set<Allergen> allergens;
  String dislikes;

  Map<String, Object?> toJson() => {
    'name': name,
    'kcal': ?kcal,
    'protein': ?protein,
    'carbs': ?carbs,
    'fat': ?fat,
    'diet': ?diet?.rawValue,
    'allergens': [
      for (final allergen in allergens.toList()..sort((a, b) => a.rawValue.compareTo(b.rawValue))) allergen.rawValue,
    ],
    'dislikes': dislikes,
  };

  /// Unbekannte Allergene oder Ernährungsweisen (neuere App-Version) lassen die Freigabe nicht scheitern.
  static CookShare fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    final (name, rawDiet, rawAllergens, dislikes) = (map['name'], map['diet'], map['allergens'], map['dislikes']);
    final allergens = <Allergen>{};
    if (rawAllergens is List && rawAllergens.every((value) => value is String)) {
      for (final raw in rawAllergens) {
        if (enumFromRaw(Allergen.values, raw) case final allergen?) allergens.add(allergen);
      }
    }
    return CookShare(
      name: name is String ? name : '',
      kcal: _number(map['kcal']),
      protein: _number(map['protein']),
      carbs: _number(map['carbs']),
      fat: _number(map['fat']),
      diet: rawDiet is String ? enumFromRaw(Diet.values, rawDiet) : null,
      allergens: allergens,
      dislikes: dislikes is String ? dislikes : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CookShare &&
      other.name == name &&
      other.kcal == kcal &&
      other.protein == protein &&
      other.carbs == carbs &&
      other.fat == fat &&
      other.diet == diet &&
      const SetEquality<Allergen>().equals(other.allergens, allergens) &&
      other.dislikes == dislikes;

  @override
  int get hashCode => Object.hash(name, kcal, protein, carbs, fat, diet, Object.hashAllUnordered(allergens), dislikes);
}

/// Welche Angaben die Person freigibt (einzeln abwählbar).
final class CookShareFields {
  CookShareFields({this.targets = true, this.diet = true, this.allergens = true, this.dislikes = true});

  bool targets;
  bool diet;
  bool allergens;
  bool dislikes;

  Map<String, Object?> toJson() => {'targets': targets, 'diet': diet, 'allergens': allergens, 'dislikes': dislikes};

  /// Wie das synthetisierte `Decodable`: alle vier Felder müssen vorhanden sein.
  static CookShareFields? fromJson(Object? json) {
    if (json is! Map) return null;
    final (targets, diet, allergens, dislikes) = (json['targets'], json['diet'], json['allergens'], json['dislikes']);
    if (targets is! bool || diet is! bool || allergens is! bool || dislikes is! bool) return null;
    return CookShareFields(targets: targets, diet: diet, allergens: allergens, dislikes: dislikes);
  }

  @override
  bool operator ==(Object other) =>
      other is CookShareFields &&
      other.targets == targets &&
      other.diet == diet &&
      other.allergens == allergens &&
      other.dislikes == dislikes;

  @override
  int get hashCode => Object.hash(targets, diet, allergens, dislikes);
}

/// Eine verbundene Person: Code der Freigabe und zuletzt abgerufener Stand.
final class CookPartner {
  CookPartner({required this.code, required this.share});

  final String code;
  CookShare share;

  String get id => code;

  Map<String, Object?> toJson() => {'code': code, 'share': share.toJson()};

  static CookPartner? fromJson(Object? json) {
    if (json is! Map || json['code'] is! String || json['share'] is! Map) return null;
    return CookPartner(code: json['code'] as String, share: CookShare.fromJson(json['share']));
  }

  @override
  bool operator ==(Object other) => other is CookPartner && other.code == code && other.share == share;

  @override
  int get hashCode => Object.hash(code, share);
}

/// Die eigene Freigabe.
final class CookRelease {
  CookRelease({required this.code, required this.fields, required this.share, required this.expiresAt});

  final String code;
  CookShareFields fields;
  CookShare share;
  String? expiresAt;

  Map<String, Object?> toJson() => {
    'code': code,
    'fields': fields.toJson(),
    'share': share.toJson(),
    'expiresAt': ?expiresAt,
  };

  static CookRelease? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code'];
    final fields = CookShareFields.fromJson(json['fields']);
    final expiresAt = json['expiresAt'];
    if (code is! String || fields == null || json['share'] is! Map || (expiresAt != null && expiresAt is! String)) {
      return null;
    }
    return CookRelease(
      code: code,
      fields: fields,
      share: CookShare.fromJson(json['share']),
      expiresAt: expiresAt as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CookRelease &&
      other.code == code &&
      other.fields == fields &&
      other.share == share &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(code, fields, share, expiresAt);
}

/// Links rund ums gemeinsame Kochen. Sie tragen nie ein Token oder eine Worker-Adresse, nur den Code der Freigabe.
sealed class CookLink {
  const CookLink();

  String get id;

  /// `coach://cook/<code>` bzw. `coach://open/cookShare`; sonst `null`.
  static CookLink? fromUri(Uri url) {
    if (url.scheme != 'coach') return null;
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (url.host == 'open' && segments.isNotEmpty && segments.last == 'cookShare') return const CookReleaseLink();
    if (url.host == 'cook') {
      final code = CookPlanner.code(segments.isEmpty ? '/' : segments.last);
      if (code != null) return CookPartnerLink(code);
    }
    return null;
  }
}

/// `coach://cook/<code>`: Freigabe einer anderen Person übernehmen.
final class CookPartnerLink extends CookLink {
  const CookPartnerLink(this.code);

  final String code;

  @override
  String get id => code;

  @override
  bool operator ==(Object other) => other is CookPartnerLink && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// `coach://open/cookShare`: eigene Freigabe erteilen.
final class CookReleaseLink extends CookLink {
  const CookReleaseLink();

  @override
  String get id => 'release';

  @override
  bool operator ==(Object other) => other is CookReleaseLink;

  @override
  int get hashCode => 0;
}

/// Für wen gekocht wird.
enum CookAudience implements RawEnum {
  me,
  partner,
  both;

  @override
  String get rawValue => name;

  String get id => rawValue;
}

/// Wie viel gekocht wird: einzelne Portionen (Teller) oder Tage, an denen die Mahlzeit gegessen wird.
sealed class CookAmount {
  const CookAmount();

  static const maxPortions = 20;
  static const maxDays = 7;

  int get count;

  String get label;

  CookAmount get clamped;

  /// JSON wie das synthetisierte `Codable` eines Swift-Enums mit Wert: `{"portions": {"_0": 3}}`.
  Map<String, Object?> toJson();

  static CookAmount? fromJson(Object? json) {
    if (json is! Map || json.length != 1) return null;
    final MapEntry(:key, :value) = json.entries.first;
    if (value is! Map || value['_0'] is! int) return null;
    final count = value['_0'] as int;
    return switch (key) {
      'portions' => CookPortions(count),
      'days' => CookDays(count),
      _ => null,
    };
  }
}

/// Teller insgesamt, auf alle Personen verteilt.
final class CookPortions extends CookAmount {
  const CookPortions(this.count);

  @override
  final int count;

  @override
  String get label => count == 1 ? '1 Portion' : '$count Portionen';

  @override
  CookAmount get clamped => CookPortions(count.clamp(1, CookAmount.maxPortions));

  @override
  Map<String, Object?> toJson() => {
    'portions': {'_0': count},
  };

  @override
  bool operator ==(Object other) => other is CookPortions && other.count == count;

  @override
  int get hashCode => Object.hash('portions', count);
}

/// Je Person ein Teller pro Tag.
final class CookDays extends CookAmount {
  const CookDays(this.count);

  @override
  final int count;

  @override
  String get label => count == 1 ? '1 Tag' : '$count Tage';

  @override
  CookAmount get clamped => CookDays(count.clamp(1, CookAmount.maxDays));

  @override
  Map<String, Object?> toJson() => {
    'days': {'_0': count},
  };

  @override
  bool operator ==(Object other) => other is CookDays && other.count == count;

  @override
  int get hashCode => Object.hash('days', count);
}

/// Anteil der Mahlzeit am Tagesziel.
final class CookMealTarget {
  const CookMealTarget({required this.kcal, this.protein, this.carbs, this.fat});

  final double kcal;
  final double? protein;
  final double? carbs;
  final double? fat;

  @override
  bool operator ==(Object other) =>
      other is CookMealTarget &&
      other.kcal == kcal &&
      other.protein == protein &&
      other.carbs == carbs &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(kcal, protein, carbs, fat);
}

/// Eine Person in einem Kochplan (Stand beim Erstellen).
final class CookPerson {
  CookPerson({required this.id, required this.share});

  static const meID = 'me';

  final String id;
  CookShare share;

  String get name => share.name;

  /// Anteil der Mahlzeit am Tagesziel (`MealSplit`, zur Orientierung).
  CookMealTarget? mealTarget(MealCategory meal) {
    final kcal = share.kcal;
    if (kcal == null || kcal <= 0) return null;
    final part = MealSplit.share(meal);
    double? scaled(double? value) => value == null ? null : value * part;
    return CookMealTarget(
      kcal: kcal * part,
      protein: scaled(share.protein),
      carbs: scaled(share.carbs),
      fat: scaled(share.fat),
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'share': share.toJson()};

  static CookPerson? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['share'] is! Map) return null;
    return CookPerson(id: json['id'] as String, share: CookShare.fromJson(json['share']));
  }

  @override
  bool operator ==(Object other) => other is CookPerson && other.id == id && other.share == share;

  @override
  int get hashCode => Object.hash(id, share);
}

/// Wo eine Portion bis zum Essen bleibt.
enum CookStorage implements RawEnum {
  fresh('Frisch'),
  fridge('Kühlschrank'),
  freezer('Einfrieren, am Vortag auftauen');

  const CookStorage(this.label);

  final String label;

  @override
  String get rawValue => name;
}

/// Teller einer Person: Mengen, Nährwerte je Teller und Anteil am ganzen Gericht.
final class CookPortion {
  const CookPortion({
    required this.person,
    required this.plates,
    required this.factor,
    required this.items,
    required this.nutrients,
    required this.grams,
    required this.sharePercent,
    required this.target,
    required this.notes,
  });

  final CookPerson person;
  final int plates;

  /// Mengen eines Tellers (roh) gegenüber der Basisportion.
  final double factor;
  final List<MealItem> items;
  final NutrientValues nutrients;

  /// Gramm roh je Teller.
  final double grams;

  /// Anteil eines Tellers am ganzen Gericht in Prozent.
  final double sharePercent;
  final CookMealTarget? target;
  final List<String> notes;

  String get id => person.id;
}

/// Ein Rezept für eine oder zwei Personen. Gespeichert wird die Zusammensetzung einer Basisportion; Tellergrößen,
/// Gesamtmengen und Nährwerte werden immer daraus berechnet, damit sie auch nach dem Bearbeiten stimmen.
final class CookPlan {
  CookPlan({
    String? id,
    required this.created,
    required this.title,
    required this.meal,
    required this.minutes,
    required this.steps,
    required this.base,
    required this.people,
    required this.amount,
    required this.plates,
    required this.fridgeDays,
    required this.freezable,
    required this.storageHint,
    required this.reheatHint,
    required this.compromise,
    required this.source,
  }) : id = id ?? newUuid();

  final String id;
  DateTime created;
  String title;
  MealCategory meal;
  int minutes;
  List<String> steps;

  /// Zutaten einer Basisportion (roh, Nährwerte je 100 g).
  List<MealItem> base;
  List<CookPerson> people;
  CookAmount amount;

  /// Teller je Person (`CookPerson.id`).
  Map<String, int> plates;
  int fridgeDays;
  bool freezable;
  String storageHint;
  String reheatHint;

  /// Begründung der KI, wie unterschiedliche Ziele zusammengebracht wurden.
  String compromise;
  String source;

  NutrientValues get baseNutrients => NutritionSummary.totals(base);

  /// Tellergröße einer Person gegenüber der Basisportion: so, dass die Energie zum Mahlzeitenziel passt.
  double factor(CookPerson person) {
    final target = person.mealTarget(meal);
    final kcal = baseNutrients[Nutrient.kcal];
    if (target == null || kcal == null || kcal <= 0) return 1;
    return (target.kcal / kcal).clamp(CookPlanner.factorLower, CookPlanner.factorUpper);
  }

  /// Summe aller Teller in Basisportionen.
  double get totalFactor => people.fold(0.0, (sum, person) => sum + (plates[person.id] ?? 0) * factor(person));

  List<CookPortion> get portions {
    final baseValues = baseNutrients;
    final baseGrams = base.fold(0.0, (sum, item) => sum + item.grams);
    final total = totalFactor;
    return [
      for (final person in people)
        () {
          final factor = this.factor(person);
          final nutrients = scaled(baseValues, factor);
          final target = person.mealTarget(meal);
          return CookPortion(
            person: person,
            plates: plates[person.id] ?? 0,
            factor: factor,
            items: [
              for (final item in base)
                item.copy()
                  ..id = newUuid()
                  ..grams = (item.grams * factor).roundToDouble(),
            ],
            nutrients: nutrients,
            grams: baseGrams * factor,
            sharePercent: total > 0 ? factor / total * 100 : 0,
            target: target,
            notes: notesFor(person: person, nutrients: nutrients, target: target),
          );
        }(),
    ];
  }

  /// Nährwerte des ganzen Gerichts.
  NutrientValues get wholeNutrients => scaled(baseNutrients, totalFactor);

  /// Einkaufsmengen für alle Teller, auf 5 g gerundet.
  List<MealItem> get totalIngredients {
    final total = totalFactor;
    return [for (final item in base) item.copy()..grams = math.max((item.grams * total / 5).roundToDouble() * 5, 5)];
  }

  /// Teller, die eine Person nacheinander isst: danach richtet sich die Lagerung.
  int get mealsPerPerson => plates.values.fold(0, math.max);

  /// Lagerung je Tag ab dem Kochtag; `null`, wenn das Gericht nicht so lange hält.
  List<CookStorage>? get storagePlan =>
      CookPlanner.storagePlan(meals: mealsPerPerson, fridgeDays: fridgeDays, freezable: freezable);

  void setGrams(double grams, {required String itemID}) {
    final item = base.firstWhereOrNull((item) => item.id == itemID);
    if (item != null) item.grams = grams.clamp(1, 5000);
  }

  /// Die letzte Zutat bleibt: Ein Rezept ohne Zutaten ließe sich nicht mehr berechnen.
  void remove({required String itemID}) {
    if (base.length <= 1) return;
    base.removeWhere((item) => item.id == itemID);
  }

  static NutrientValues scaled(NutrientValues values, double factor) =>
      NutrientValues({for (final MapEntry(:key, :value) in values.values.entries) key: value * factor});

  /// Weicht Protein trotz passender Energie deutlich ab, sagt die App es offen.
  static List<String> notesFor({
    required CookPerson person,
    required NutrientValues nutrients,
    required CookMealTarget? target,
  }) {
    final result = <String>[];
    final kcal = nutrients[Nutrient.kcal];
    if (target != null && kcal != null && kcal > 0 && (kcal - target.kcal).abs() / target.kcal > 0.1) {
      result.add(
        '${person.name}: ${kcal.round()} statt ${target.kcal.round()} kcal, weil die Portion sonst '
        'unverhältnismäßig klein oder groß würde.',
      );
    }
    final wanted = target?.protein;
    final protein = nutrients[Nutrient.protein];
    if (wanted != null && protein != null && wanted - protein >= 10) {
      result.add(
        '${person.name}: ${protein.round()} g Protein, Ziel ${wanted.round()} g. Eine eiweißreiche Beilage gleicht '
        'das aus.',
      );
    }
    return result;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'created': swiftDateToJson(created),
    'title': title,
    'meal': meal.rawValue,
    'minutes': minutes,
    'steps': steps,
    'base': [for (final item in base) item.toJson()],
    'people': [for (final person in people) person.toJson()],
    'amount': amount.toJson(),
    'plates': plates,
    'fridgeDays': fridgeDays,
    'freezable': freezable,
    'storageHint': storageHint,
    'reheatHint': reheatHint,
    'compromise': compromise,
    'source': source,
  };

  static CookPlan? fromJson(Object? json) {
    if (json is! Map) return null;
    final created = swiftDateFromJson(json['created']);
    final rawMeal = json['meal'];
    final meal = rawMeal is String ? MealCategory.fromRaw(rawMeal) : null;
    final steps = listStrict(json['steps'], (value) => value is String ? value : null);
    final base = listStrict(json['base'], MealItem.fromJson);
    final people = listStrict(json['people'], CookPerson.fromJson);
    final amount = CookAmount.fromJson(json['amount']);
    final rawPlates = json['plates'];
    final (id, title, minutes, fridgeDays, freezable) = (
      json['id'],
      json['title'],
      json['minutes'],
      json['fridgeDays'],
      json['freezable'],
    );
    final (storageHint, reheatHint, compromise, source) = (
      json['storageHint'],
      json['reheatHint'],
      json['compromise'],
      json['source'],
    );
    if (id is! String ||
        created == null ||
        title is! String ||
        meal == null ||
        minutes is! int ||
        steps == null ||
        base == null ||
        people == null ||
        amount == null ||
        rawPlates is! Map ||
        fridgeDays is! int ||
        freezable is! bool ||
        storageHint is! String ||
        reheatHint is! String ||
        compromise is! String ||
        source is! String) {
      return null;
    }
    final plates = <String, int>{};
    for (final MapEntry(:key, :value) in rawPlates.entries) {
      if (key is! String || value is! int) return null;
      plates[key] = value;
    }
    return CookPlan(
      id: id,
      created: created,
      title: title,
      meal: meal,
      minutes: minutes,
      steps: steps,
      base: base,
      people: people,
      amount: amount,
      plates: plates,
      fridgeDays: fridgeDays,
      freezable: freezable,
      storageHint: storageHint,
      reheatHint: reheatHint,
      compromise: compromise,
      source: source,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CookPlan &&
      other.id == id &&
      other.created.isAtSameMomentAs(created) &&
      other.title == title &&
      other.meal == meal &&
      other.minutes == minutes &&
      const ListEquality<String>().equals(other.steps, steps) &&
      const ListEquality<MealItem>().equals(other.base, base) &&
      const ListEquality<CookPerson>().equals(other.people, people) &&
      other.amount == amount &&
      const MapEquality<String, int>().equals(other.plates, plates) &&
      other.fridgeDays == fridgeDays &&
      other.freezable == freezable &&
      other.storageHint == storageHint &&
      other.reheatHint == reheatHint &&
      other.compromise == compromise &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, title, meal, minutes, amount, fridgeDays, freezable, source);
}

/// Regeln rund um gemeinsames Kochen und Vorkochen. Die KI schlägt nur die Zusammensetzung vor; Teller,
/// Hochrechnung, Ausschlüsse und Lagerung entscheidet die App.
abstract final class CookPlanner {
  /// Tellergröße höchstens halb so groß oder 1,8-mal so groß wie die Basisportion.
  static const factorLower = 0.5;
  static const factorUpper = 1.8;

  /// Gekochtes hält im Kühlschrank 2–3 Tage (BfR, „Vorkochen für mehrere Tage“); mehr sagt die App nicht zu.
  static const maxFridgeDays = 3;
  static const ideaCount = 3;

  /// Teller je Person. Portionen werden gleichmäßig verteilt, ein Rest geht an die erste Person.
  static Map<String, int> plates(CookAmount amount, List<CookPerson> people) {
    if (people.isEmpty) return {};
    return switch (amount.clamped) {
      CookDays(:final count) => {for (final person in people) person.id: count},
      CookPortions(:final count) => {
        for (var index = 0; index < people.length; index++)
          people[index].id: count ~/ people.length + (index < count % people.length ? 1 : 0),
      },
    };
  }

  /// Die strengste Ernährungsweise gilt für das gemeinsame Gericht.
  static Diet mergedDiet(List<CookPerson> people) {
    const order = [Diet.omnivore, Diet.pescetarian, Diet.vegetarian, Diet.vegan];
    Diet? result;
    for (final diet in people.map((person) => person.share.diet).nonNulls) {
      // Wie `max(by:)` in Swift: bei Gleichstand der erste.
      if (result == null || order.indexOf(result) < order.indexOf(diet)) result = diet;
    }
    return result ?? Diet.omnivore;
  }

  static Set<Allergen> mergedAllergens(List<CookPerson> people) => {
    for (final person in people) ...person.share.allergens,
  };

  /// Lagerung je Tag ab dem Kochtag; `null`, wenn die Portionen nicht sicher bis zum letzten Tag reichen.
  static List<CookStorage>? storagePlan({required int meals, required int fridgeDays, required bool freezable}) {
    final limit = fridgeDays.clamp(0, maxFridgeDays);
    final result = <CookStorage>[];
    for (var day = 0; day < math.max(meals, 0); day++) {
      if (day == 0) {
        result.add(CookStorage.fresh);
      } else if (day <= limit) {
        result.add(CookStorage.fridge);
      } else if (freezable) {
        result.add(CookStorage.freezer);
      } else {
        return null;
      }
    }
    return result;
  }

  /// Eingabe der Worker-Aufgabe `cook_plan`. Namen gehen nicht an die KI, die Personen heißen „Person 1“ und „Person 2“.
  static Map<String, Object?> input({
    required List<CookPerson> people,
    required MealCategory meal,
    required CookAmount amount,
    required RecipePreferences preferences,
    required List<String> favorites,
  }) {
    final plates = CookPlanner.plates(amount, people);
    final lines = [
      for (var index = 0; index < people.length; index++)
        () {
          final person = people[index];
          final target = person.mealTarget(meal);
          return <String, Object?>{
            'bezeichnung': 'Person ${index + 1}',
            'teller': (plates[person.id] ?? 0).toDouble(),
            if (target != null) 'kcal': target.kcal.roundToDouble(),
            if (target?.protein case final protein?) 'protein_g': protein.roundToDouble(),
            if (target?.carbs case final carbs?) 'kohlenhydrate_g': carbs.roundToDouble(),
            if (target?.fat case final fat?) 'fett_g': fat.roundToDouble(),
          };
        }(),
    ];
    final meals = plates.isEmpty ? 1 : plates.values.fold(0, math.max);
    final dislikes = [
      for (final person in people)
        if (person.share.dislikes.isNotEmpty) person.share.dislikes,
      if (preferences.dislikes.isNotEmpty) preferences.dislikes,
    ];
    final allergens = mergedAllergens(people).toList()..sort((a, b) => a.rawValue.compareTo(b.rawValue));
    return {
      'personen': lines,
      'mahlzeit': meal.rawValue,
      'mahlzeiten_je_person': meals.toDouble(),
      'vorkochen': meals > 1,
      'diet': mergedDiet(people).rawValue,
      'allergens': [for (final allergen in allergens) allergen.label],
      'dislikes': textPrefix(dislikes.join('; '), 200),
      'maxMinutes': preferences.maxMinutes.toDouble(),
      'favorites': favorites.take(10).toList(),
    };
  }

  /// Antwort prüfen: Ernährungsweise, Allergene und Nährwerte wie bei den Wochenrezepten, dazu die Eignung zum
  /// Vorkochen. Wer nur die Menge vervielfacht, ohne dass das Gericht hält, wird verworfen.
  static ({List<CookPlan> plans, List<String> notes}) plans(
    JsonValue output, {
    required List<CookPerson> people,
    required MealCategory meal,
    required CookAmount amount,
    required String source,
    required DateTime created,
  }) {
    final diet = mergedDiet(people);
    final allergens = mergedAllergens(people);
    final plates = CookPlanner.plates(amount, people);
    final meals = plates.values.fold(0, math.max);
    final result = <CookPlan>[];
    final notes = <String>[];
    for (final value in (output['rezepte']?.arrayValue ?? const <JsonValue>[]).take(ideaCount)) {
      final recipe = RecipePlanner.recipe(value);
      if (recipe == null) continue;
      if (!RecipePlanner.accept(recipe, diet: diet, allergens: allergens, notes: notes)) continue;
      final fridge = value['haltbarkeit_tage']?.clampedInt(0, 30) ?? 0;
      final freezable = value['einfrierbar']?.boolValue == true;
      if (meals > 1) {
        if (value['vorkochen_geeignet']?.boolValue != true) {
          notes.add('„${recipe.title}“ verworfen: eignet sich nicht zum Vorkochen.');
          continue;
        }
        if (storagePlan(meals: meals, fridgeDays: fridge, freezable: freezable) == null) {
          notes.add('„${recipe.title}“ verworfen: hält nicht für $meals Mahlzeiten.');
          continue;
        }
      }
      result.add(
        CookPlan(
          created: created,
          title: recipe.title,
          meal: meal,
          minutes: recipe.minutes,
          steps: recipe.steps,
          base: recipe.ingredients,
          people: people,
          amount: amount.clamped,
          plates: plates,
          fridgeDays: math.min(fridge, maxFridgeDays),
          freezable: freezable,
          storageHint: textPrefix(value['lagerung']?.stringValue ?? '', 300),
          reheatHint: textPrefix(value['aufwaermen']?.stringValue ?? '', 200),
          compromise: people.length > 1 ? textPrefix(value['kompromiss']?.stringValue ?? '', 400) : '',
          source: source,
        ),
      );
    }
    return (plans: result, notes: notes);
  }

  /// Aus dem Link `coach://cook/<code>`, dem https-Link oder dem Code selbst.
  static String? code(String text) {
    final trimmed = text.trim().toLowerCase();
    final parts = trimmed.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty || !_code.hasMatch(parts.last)) return null;
    if (trimmed.contains('/') && !(trimmed.contains('coach://cook/') || trimmed.contains('/k/'))) return null;
    return parts.last;
  }

  /// Mittlere Tagesziele einer Woche für die Freigabe.
  static CookShare share({
    required String name,
    required List<RecipeDayTarget> week,
    required Diet diet,
    required RecipePreferences preferences,
    required CookShareFields fields,
    required WeightGoalGuard safety,
  }) {
    final share = CookShare(name: textPrefix(name.trim(), 30));
    // Schwangerschaft/Stillzeit oder Essstörung: keine Kalorienziele, auch nicht für andere.
    if (fields.targets && safety != WeightGoalGuard.noTargets && week.isNotEmpty) {
      double mean(double Function(RecipeDayTarget) value) =>
          (week.fold(0.0, (sum, target) => sum + value(target)) / week.length).roundToDouble();
      share
        ..kcal = mean((target) => target.kcal)
        ..protein = mean((target) => target.protein)
        ..carbs = mean((target) => target.carbs)
        ..fat = mean((target) => target.fat);
    }
    if (fields.diet) share.diet = diet;
    if (fields.allergens) share.allergens = {...preferences.allergens};
    if (fields.dislikes) share.dislikes = textPrefix(preferences.dislikes, 200);
    return share;
  }
}

/// Abfragen und Teilpläne der Rezeptideen (Erweiterungen aus `CookPlan.swift`).
abstract final class RecipeBatches {
  static const maxDaysPerRequest = 2;

  /// Eine Woche in Abfragen zu höchstens zwei Tagen: Eine Antwort über sieben Tage sprengt das Antwortlimit der KI.
  static List<List<RecipeDayTarget>> batches(List<RecipeDayTarget> targets) {
    if (targets.length <= maxDaysPerRequest) return targets.isEmpty ? [] : [targets];
    final parts = (targets.length / maxDaysPerRequest).ceil();
    final result = <List<RecipeDayTarget>>[];
    var start = 0;
    for (var part = 0; part < parts; part++) {
      final size = targets.length ~/ parts + (part < targets.length % parts ? 1 : 0);
      result.add(targets.sublist(start, start + size));
      start += size;
    }
    return result;
  }

  /// Teilpläne zusammenführen, Tage in der Reihenfolge des Kalenders.
  static WeeklyRecipePlan? merged(List<WeeklyRecipePlan> parts, {required DateTime created}) {
    if (parts.isEmpty) return null;
    final sources = <String>[];
    for (final part in parts) {
      if (!sources.contains(part.source)) sources.add(part.source);
    }
    final days = parts.expand((part) => part.days).toList();
    mergeSort(days, compare: (a, b) => a.day.compareTo(b.day));
    return WeeklyRecipePlan(
      created: created,
      days: days,
      source: sources.join(', '),
      notes: [for (final part in parts) ...part.notes],
    );
  }
}

/// Verständliche Meldung statt technischer Fehlertexte. Der Statuscode bleibt für Rückfragen sichtbar.
abstract final class AIErrorText {
  static String message({required int status, required String? code, required String detail}) {
    switch (status) {
      case 429:
        // Eigene Grenzen des Workers (Tageslimit, Sperre nach Fehlversuchen …) kommen mit Code und klarem Text.
        if (code != null && detail.isNotEmpty) return detail;
        return 'Das KI-Kontingent ist gerade ausgeschöpft. Bitte versuche es später noch einmal. (Fehlercode 429)';
      case 502 || 503 || 504:
        if (code == 'ai_invalid') {
          return 'Die KI hat keine brauchbare Antwort geliefert. Bitte versuche es noch einmal. (Fehlercode $status)';
        }
        return 'Die KI ist gerade nicht erreichbar oder überlastet. Bitte versuche es in ein paar Minuten noch einmal. '
            '(Fehlercode $status)';
      case >= 500:
        return 'Beim KI-Dienst ist ein Fehler aufgetreten. Bitte versuche es später noch einmal. (Fehlercode $status)';
      default:
        return detail;
    }
  }

  /// Lohnt ein zweiter Versuch? Nur bei vorübergehenden Ausfällen, nicht bei falschen Anfragen.
  static bool isTemporary(int status) => const [502, 503, 504].contains(status);
}
