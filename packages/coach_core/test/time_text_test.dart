// Port aus `DisciplineAppTests` (TimeText).
import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

void main() {
  test('Zeiten lesen und schreiben', () {
    expect(TimeText.seconds('8:40'), 520);
    expect(TimeText.seconds(' 1:45:00 '), 6300);
    expect(TimeText.seconds('4:75'), isNull);
    expect(TimeText.seconds('abc'), isNull);
    expect(TimeText.hms(6300), '1:45:00');
  });
}
