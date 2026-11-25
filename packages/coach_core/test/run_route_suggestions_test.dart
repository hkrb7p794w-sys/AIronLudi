// Routenvorschläge für Läufe: passend zur Einheit, abwechslungsreich, Stand je Benutzer.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

const home = GeoPoint(52.52, 13.405);
const day = CalendarDay(2026, 11, 26);

EnduranceWorkout run(EnduranceWorkoutType type, {int minutes = 50}) => EnduranceWorkout(
  sport: EnduranceSport.run,
  type: type,
  title: type.label,
  minutes: minutes,
  steps: const [],
  load: 50,
);

/// Runde mit Mittelpunkt in Richtung [bearing] vom Start.
List<GeoPoint> ring(double bearing, {double radius = 800}) {
  final center = Geo.destination(home, bearing, radius);
  return [for (var angle = 0; angle <= 360; angle += 10) Geo.destination(center, angle.toDouble(), radius)];
}

PlannedRoute route(String id, List<GeoPoint> points) => PlannedRoute(
  id: id,
  username: 'anna',
  name: id,
  request: const RouteRequest(
    discipline: RouteDiscipline.run,
    shape: RouteShape.loop,
    start: home,
    distanceMeters: 5000,
  ),
  variant: RouteVariant.balanced,
  points: points,
  engine: 'Test',
  createdAt: DateTime.utc(2026, 11, 20),
);

void main() {
  group('Strecke passend zur Einheit', () {
    test('Tempo, Schwelle und Intervalle: flach; Regeneration: flach und weich; lang: Vorlieben', () {
      final tempo = RunRouteBriefs.forWorkout(
        run(EnduranceWorkoutType.threshold),
        preferences: {RoutePreference.water},
      )!;
      expect(tempo.flat, isTrue);
      expect(tempo.preferences, {RoutePreference.water});
      expect(tempo.elevationGain, closeTo(tempo.kilometers * 4, 1));
      expect(tempo.request(home).shape, RouteShape.loop);

      final recovery = RunRouteBriefs.forWorkout(run(EnduranceWorkoutType.recovery, minutes: 30))!;
      expect(recovery.flat, isTrue);
      expect(recovery.preferences, {RoutePreference.nature});
      // Ausdrücklich Asphalt gewünscht: bleibt Asphalt.
      expect(
        RunRouteBriefs.forWorkout(
          run(EnduranceWorkoutType.recovery),
          preferences: {RoutePreference.paved},
        )!.preferences,
        {RoutePreference.paved},
      );

      final long = RunRouteBriefs.forWorkout(run(EnduranceWorkoutType.long, minutes: 100))!;
      expect(long.flat, isFalse);
      expect(long.elevationGain, isNull);
      expect(long.kilometers, greaterThan(recovery.kilometers));

      expect(RunRouteBriefs.forWorkout(run(EnduranceWorkoutType.race)), isNull);
      expect(RunRouteBriefs.forWorkout(run(EnduranceWorkoutType.rest)), isNull);
      expect(
        RunRouteBriefs.forWorkout(
          const EnduranceWorkout(
            sport: EnduranceSport.bike,
            type: EnduranceWorkoutType.endurance,
            title: 'Rad',
            minutes: 60,
            steps: [],
            load: 40,
          ),
        ),
        isNull,
      );
    });

    test('Wochenplan: Intensität bestimmt das Gelände; Hundewiese fällt beim Laufen weg', () {
      final hard = RunRouteBriefs.forSession(
        const SessionSlot(TrainingSport.run, SessionIntensity.hard),
        minutes: 45,
        preferences: {RoutePreference.dogPark, RoutePreference.nature},
      )!;
      expect(hard.flat, isTrue);
      expect(hard.preferences, {RoutePreference.nature});
      expect(RunRouteBriefs.forSession(const SessionSlot(TrainingSport.run), minutes: 40)!.flat, isFalse);
      expect(RunRouteBriefs.forSession(const SessionSlot(TrainingSport.bike), minutes: 60), isNull);
    });
  });

  group('Abwechslung', () {
    test('Überschneidung: gleiche Runde 100 %, andere Richtung kaum', () {
      final north = RouteFootprint.of(ring(0), day);
      expect(RouteVariety.overlap(ring(0), [north]), closeTo(1, 0.01));
      expect(RouteVariety.overlap(ring(180), [north]), lessThan(0.2));
      expect(RouteVariety.overlap(ring(0), const []), 0);
    });

    test('Richtung: die am wenigsten genutzte; ohne Verlauf wechselt sie mit dem Würfel', () {
      final recent = [RouteFootprint.of(ring(0), day), RouteFootprint.of(ring(90), day)];
      final bearing = RouteVariety.bearing(home, recent, seed: 0);
      // Nord, Ost und ihre Nachbarn sind belegt.
      expect([0.0, 45.0, 90.0, 135.0, 315.0], isNot(contains(bearing)));
      final free = {for (var seed = 0; seed < 8; seed++) RouteVariety.bearing(home, const [], seed: seed)};
      expect(free.length, 8);
      // Spuren an einem anderen Ort zählen nicht.
      final elsewhere = [
        RouteFootprint.of([for (final point in ring(0)) Geo.destination(point, 90, 20000)], day),
      ];
      expect(RouteVariety.bearing(home, elsewhere, seed: 3), RouteVariety.bearing(home, const [], seed: 3));
    });

    test('Auswahl: die Runde mit der geringsten Überschneidung; nur Spuren der letzten vier Wochen', () {
      final recent = [RouteFootprint.of(ring(0), day)];
      final picked = RouteVariety.pick([route('gleich', ring(0)), route('neu', ring(200))], recent)!;
      expect(picked.id, 'neu');
      // Fast gleich gut: der erste (beste Bewertung des Planers) bleibt.
      expect(RouteVariety.pick([route('a', ring(180)), route('b', ring(185))], recent)!.id, 'a');
      final old = RouteFootprint.of(ring(0), day.adding(-40));
      expect(RouteVariety.recent([old, ...recent], day).length, 1);
    });
  });

  test('Stand je Benutzer: Einstellungen, Vorschläge, abgelehnte Spuren, Aufräumen', () {
    final state = RunRouteSuggestions(username: 'anna', preferences: {RoutePreference.nature}, startFavoriteID: 'f1');
    state.entries['u1'] = RunSuggestionEntry(unitID: 'u1', day: day, route: route('r1', ring(0)), declines: 2);
    state.entries['alt'] = RunSuggestionEntry(unitID: 'alt', day: day.adding(-40));
    state.declined
      ..add(RouteFootprint.of(ring(90), day))
      ..add(RouteFootprint.of(ring(90), day.adding(-40)));
    final restored = RunRouteSuggestions.fromJson(jsonDecode(jsonEncode(state.toJson())), username: 'anna')!;
    expect(restored.enabled, isTrue);
    expect(restored.preferences, {RoutePreference.nature});
    expect(restored.startFavoriteID, 'f1');
    expect(restored.entries['u1']!.route!.id, 'r1');
    expect(restored.entries['u1']!.declines, 2);
    expect(restored.declined.length, 2);
    restored.prune(day);
    expect(restored.entries.keys, ['u1']);
    expect(restored.declined.length, 1);
    expect(RunRouteSuggestions.fromJson(state.toJson(), username: 'ben'), isNull);
  });
}
