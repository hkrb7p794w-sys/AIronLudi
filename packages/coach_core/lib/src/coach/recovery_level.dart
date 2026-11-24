import '../util/enum_codec.dart';

/// Tagesampel der Erholung. Die Regeln dazu stehen in `RecoveryEvaluator`.
enum RecoveryLevel implements RawEnum {
  normal('Normal trainieren', 'Geplante Einheit wie vorgesehen durchziehen.', 'Bereit für dein Training'),
  locker(
    'Locker / verkürzt',
    'Einheit machen, aber Intensität raus: harte Intervalle durch lockeres Training ersetzen oder um ein Drittel '
        'kürzen.',
    'Heute lockerer',
  ),
  pause('Ruhetag oder sehr locker', 'Heute Ruhetag – höchstens 20–30 min sehr locker bewegen.', 'Heute Erholung');

  const RecoveryLevel(this.label, this.advice, this.headline);

  final String label;
  final String advice;

  /// Überschrift der Tagesbewertung – dieselbe auf „Heute“, im Morning Report und in den Empfehlungen (Roast B-29).
  final String headline;

  @override
  String get rawValue => name;

  bool operator <(RecoveryLevel other) => index < other.index;
  bool operator >(RecoveryLevel other) => index > other.index;
}
