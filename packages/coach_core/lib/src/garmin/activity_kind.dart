import '../nutrition/food_search.dart';
import 'garmin_activity.dart';

/// Feinere Sportart einer Aufzeichnung für Anzeige und Zählung. Die gespeicherte Grobeinteilung [ActivitySport]
/// (Laufen, Rad, Schwimmen, Kraft, Anderes) bleibt unverändert – Bouldern, Yoga & Co. sind dort „Anderes“, zählen hier
/// aber als Training (statt wie ein Spaziergang nur, wenn geplant).
enum ActivityKind {
  running('Laufen', workout: true),
  cycling('Radfahren', workout: true),
  swimming('Schwimmen', workout: true),
  strength('Krafttraining', workout: true),
  bouldering('Bouldern', workout: true),
  climbing('Klettern', workout: true),
  hiking('Wandern', workout: true),
  rowing('Rudern', workout: true),
  paddling('Paddeln', workout: true),
  yoga('Yoga', workout: true),
  mobility('Mobilität', workout: true),
  hiit('HIIT', workout: true),
  cardio('Crosstrainer/Cardio', workout: true),
  dance('Tanzen', workout: true),
  winter('Wintersport', workout: true),
  racket('Tennis/Squash/Badminton', workout: true),
  team('Mannschaftssport', workout: true),
  martialArts('Kampfsport', workout: true),
  walking('Gehen', workout: false),
  other('Training', workout: false);

  const ActivityKind(this.label, {required this.workout});

  final String label;

  /// Zählt als Training, auch ohne Eintrag im Plan (Gehen und Unbekanntes nicht).
  final bool workout;

  /// Schlüsselwörter je Art (Typ-Schlüssel von Garmin, Health, WHOOP; deutsche und englische Namen). Reihenfolge zählt:
  /// „stair_climbing“ ist Cardio, nicht Klettern; „indoor_rowing“ Rudern, nicht Radfahren.
  static const _keywords = <(ActivityKind, List<String>)>[
    (bouldering, ['boulder']),
    (cardio, ['stair', 'stepper', 'elliptical', 'crosstrainer', 'cross_trainer', 'climber', 'cardio']),
    (climbing, ['climb', 'kletter', 'mountaineering', 'bergsteig']),
    (rowing, ['rowing', 'rudern', 'ruderger']),
    (paddling, ['paddl', 'kayak', 'kajak', 'canoe', 'kanu', 'stand_up']),
    (hiit, ['hiit', 'interval_training', 'crossfit', 'functional', 'bootcamp', 'tabata', 'circuit', 'zirkel']),
    (yoga, ['yoga']),
    (mobility, ['pilates', 'stretch', 'dehn', 'mobility', 'mobilit', 'flexibility', 'breathwork', 'mind_and_body']),
    (dance, ['danc', 'tanz', 'zumba']),
    (winter, ['ski', 'snowboard', 'langlauf', 'skating', 'eislauf']),
    (racket, ['tennis', 'squash', 'badminton', 'padel', 'racquet', 'pickleball', 'tischtennis', 'table_tennis']),
    (team, ['soccer', 'fussball', 'football', 'basketball', 'volleyball', 'handball', 'hockey', 'rugby']),
    (martialArts, ['boxing', 'boxen', 'kickbox', 'martial', 'kampfsport', 'judo', 'karate', 'mma']),
    (hiking, ['hiking', 'wander', 'rucking', 'trekking']),
    (walking, ['walk', 'spazier', 'gehen']),
    (swimming, ['swim', 'schwimm']),
    (cycling, ['cycl', 'bik', 'ride', 'rad', 'spin', 'zwift']),
    (running, ['run', 'lauf', 'jogg']),
    (strength, ['strength', 'weight', 'kraft', 'gym', 'fitness_equipment']),
  ];

  /// Typ-Schlüssel: Teilwort genügt („indoor_climbing“). Namen: nur am Wortanfang, damit „Abendrunde“ kein Lauf ist.
  static ActivityKind? _match(String text, {required bool name}) {
    final value = FoodSearch.normalized(text).replaceAll(RegExp(r'[\s-]+'), '_');
    if (value.isEmpty) return null;
    final words = value.split(RegExp('[^a-z0-9]+')).where((word) => word.isNotEmpty).toList();
    for (final (kind, keywords) in _keywords) {
      if (name ? keywords.any((key) => words.any((word) => word.startsWith(key))) : keywords.any(value.contains)) {
        return kind;
      }
    }
    return null;
  }

  /// Art aus Typ-Schlüssel und – falls der nichts sagt („other“, „training“) – aus dem Namen der Aktivität.
  static ActivityKind of(String? typeKey, {String? name}) {
    final key = typeKey ?? '';
    final generic = key.isEmpty || const ['other', 'training', 'generic', 'activity', 'workout'].contains(key);
    if (!generic) {
      if (_match(key, name: false) case final kind?) return kind;
    }
    if (name != null) {
      if (_match(name, name: true) case final kind?) return kind;
    }
    return other;
  }

  static ActivityKind ofActivity(GarminActivity activity) => of(activity.typeKey, name: activity.name);
}
