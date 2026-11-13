import 'dart:convert';

/// JSON wie `JSONEncoder` mit `.sortedKeys` in Swift: Schlüssel sortiert, ganzzahlige Double ohne „.0“ und „/“ als
/// „\/“. Gebraucht für Prüfsummen, die mit denen der Swift-App übereinstimmen sollen.
String swiftSortedJson(Object? value) {
  final buffer = StringBuffer();
  void write(Object? value) {
    switch (value) {
      case null:
        buffer.write('null');
      case bool():
        buffer.write(value);
      case int():
        buffer.write(value);
      case double():
        buffer.write(
          value.isFinite && value == value.truncateToDouble() && value.abs() < 1e16
              ? value.toInt().toString()
              : value.toString(),
        );
      case String():
        buffer.write(jsonEncode(value).replaceAll('/', r'\/'));
      case Map():
        final keys = value.keys.map((key) => key as String).toList()..sort();
        buffer.write('{');
        for (var index = 0; index < keys.length; index++) {
          if (index > 0) buffer.write(',');
          write(keys[index]);
          buffer.write(':');
          write(value[keys[index]]);
        }
        buffer.write('}');
      case Iterable():
        buffer.write('[');
        var first = true;
        for (final element in value) {
          if (!first) buffer.write(',');
          first = false;
          write(element);
        }
        buffer.write(']');
      default:
        write((value as dynamic).toJson());
    }
  }

  write(value);
  return buffer.toString();
}

/// JSON wie `JSONEncoder` mit `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`: zwei Leerzeichen Einzug,
/// „"schlüssel" : wert“, ganzzahlige Double ohne „.0“.
String swiftPrettyJson(Object? value) {
  final buffer = StringBuffer();
  void write(Object? value, String indent) {
    final inner = '$indent  ';
    switch (value) {
      case null:
        buffer.write('null');
      case bool() || int():
        buffer.write(value);
      case double():
        buffer.write(
          value.isFinite && value == value.truncateToDouble() && value.abs() < 1e16
              ? value.toInt().toString()
              : value.toString(),
        );
      case String():
        buffer.write(jsonEncode(value));
      case Map():
        final keys = value.keys.map((key) => key as String).toList()..sort();
        if (keys.isEmpty) {
          buffer.write('{\n\n$indent}');
          return;
        }
        buffer.write('{\n');
        for (var index = 0; index < keys.length; index++) {
          buffer.write('$inner${jsonEncode(keys[index])} : ');
          write(value[keys[index]], inner);
          buffer.write(index < keys.length - 1 ? ',\n' : '\n');
        }
        buffer.write('$indent}');
      case Iterable():
        final items = value.toList();
        if (items.isEmpty) {
          buffer.write('[\n\n$indent]');
          return;
        }
        buffer.write('[\n');
        for (var index = 0; index < items.length; index++) {
          buffer.write(inner);
          write(items[index], inner);
          buffer.write(index < items.length - 1 ? ',\n' : '\n');
        }
        buffer.write('$indent]');
      default:
        write((value as dynamic).toJson(), indent);
    }
  }

  write(value, '');
  return buffer.toString();
}
