import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

GarminActivity _activity(int id, String typeKey, String start, double minutes) => GarminActivity(id)
  ..typeKey = typeKey
  ..startLocal = start
  ..durationSeconds = minutes * 60;

void main() {
  const today = CalendarDay(2026, 11, 24);
  final from = today.adding(-6);

  group('CardioLoad', () {
    test('Minuten je Muskel: Hauptmuskeln voll, mitarbeitende halb, nur im Zeitraum', () {
      final activities = [
        _activity(1, 'running', '2026-11-23 07:00:00', 40),
        _activity(2, 'cycling', '2026-11-20 18:00:00', 60),
        _activity(3, 'running', '2026-11-17 07:00:00', 30), // vor dem Zeitraum
        _activity(4, 'strength_training', '2026-11-22 18:00:00', 50), // Kraft zählt hier nicht
      ];
      final minutes = CardioLoad.minutes(activities, from: from, to: today);
      expect(minutes[Muscle.quads], 100);
      expect(minutes[Muscle.calves], 40 + 30);
      expect(minutes[Muscle.hamstrings], 40 + 30);
      expect(minutes[Muscle.adductors], 20);
      expect(minutes.containsKey(Muscle.chest), isFalse);
      expect(CardioLoad.bySport(activities, from: from, to: today), [
        (ActivitySport.bike, 60.0),
        (ActivitySport.run, 40.0),
      ]);
    });

    test('Schwimmen beansprucht den Oberkörper', () {
      final minutes = CardioLoad.minutes(
        [_activity(1, 'lap_swimming', '2026-11-24 06:30:00', 30)],
        from: from,
        to: today,
      );
      expect(minutes[Muscle.lats], 30);
      expect(minutes[Muscle.triceps], 15);
      expect(minutes.containsKey(Muscle.quads), isFalse);
    });

    test('ohne Dauer oder Datum zählt nichts', () {
      final missing = GarminActivity(1)..typeKey = 'running';
      expect(CardioLoad.minutes([missing], from: from, to: today), isEmpty);
    });
  });

  group('StretchLoad', () {
    test('Minuten verteilen sich auf die Schwerpunkte, Muskeln in zwei Schwerpunkten zählen doppelt', () {
      final log = [
        MobilityLogEntry(day: today, minutes: 10, areas: const [MobilityArea.hips, MobilityArea.shoulders]),
        MobilityLogEntry(day: today.adding(-2), minutes: 6, areas: const [MobilityArea.thoracicSpine]),
        MobilityLogEntry(day: today.adding(-9), minutes: 20, areas: const [MobilityArea.ankles]), // zu alt
      ];
      final minutes = StretchLoad.minutes(log, from: from, to: today);
      expect(minutes[Muscle.glutes], 5);
      expect(minutes[Muscle.adductors], 5);
      expect(minutes[Muscle.chest], 5);
      expect(minutes[Muscle.lats], 5 + 6);
      expect(minutes[Muscle.traps], 6);
      expect(minutes.containsKey(Muscle.calves), isFalse);
      expect(StretchLoad.areaMinutes(log, from: from, to: today), {
        MobilityArea.hips: 5,
        MobilityArea.shoulders: 5,
        MobilityArea.thoracicSpine: 6,
      });
    });

    test('jeder Schwerpunkt dehnt mindestens einen Muskel', () {
      for (final area in MobilityArea.values) {
        expect(StretchLoad.muscles(area), isNotEmpty, reason: area.name);
      }
    });
  });
}
