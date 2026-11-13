import '../util/enum_codec.dart';

/// Tagesampel der Erholung. Die Regeln dazu (`RecoveryEvaluator`) folgen mit dem Coach-Modul.
enum RecoveryLevel implements RawEnum {
  normal('Normal trainieren', 'Geplante Einheit wie vorgesehen durchziehen.'),
  locker(
    'Locker / verkürzt',
    'Einheit machen, aber Intensität raus: harte Intervalle durch lockeres Training ersetzen oder um ein Drittel '
        'kürzen.',
  ),
  pause('Ruhetag oder sehr locker', 'Heute Ruhetag – höchstens 20–30 min sehr locker bewegen.');

  const RecoveryLevel(this.label, this.advice);

  final String label;
  final String advice;

  @override
  String get rawValue => name;

  bool operator <(RecoveryLevel other) => index < other.index;
  bool operator >(RecoveryLevel other) => index > other.index;
}
