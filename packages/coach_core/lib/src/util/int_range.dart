/// Geschlossener Bereich ganzer Zahlen wie `ClosedRange<Int>` in Swift (`lower...upper`).
final class IntRange {
  const IntRange(this.lower, this.upper) : assert(lower <= upper);

  final int lower;
  final int upper;

  bool contains(int value) => lower <= value && value <= upper;

  @override
  bool operator ==(Object other) => other is IntRange && other.lower == lower && other.upper == upper;

  @override
  int get hashCode => Object.hash(lower, upper);

  @override
  String toString() => '$lower...$upper';
}
