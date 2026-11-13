/// Zeiten als Text: „8:40“ (min:s) bzw. „1:45:00“ (h:min:s), wie `TimeText` der Swift-App.
abstract final class TimeText {
  static int? seconds(String text) {
    final parts = text.trim().split(':').where((part) => part.isNotEmpty).map(int.tryParse).toList();
    if (parts.isEmpty || parts.contains(null)) return null;
    final values = parts.nonNulls.toList();
    return switch (values.length) {
      2 when values[1] < 60 => values[0] * 60 + values[1],
      3 when values[1] < 60 && values[2] < 60 => values[0] * 3600 + values[1] * 60 + values[2],
      _ => null,
    };
  }

  static String hms(int seconds) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${seconds ~/ 3600}:${two((seconds % 3600) ~/ 60)}:${two(seconds % 60)}';
  }
}
