import 'dart:convert';
import 'dart:typed_data';

/// JSON-Bytes wie die `Data`-Felder der SwiftData-Modelle.
Uint8List encodeJson(Object? value) => utf8.encode(jsonEncode(value));

/// Liest JSON-Bytes; `null` bei kaputten Daten (wie `try? JSONDecoder().decode`).
T? decodeJson<T>(List<int> bytes, T? Function(Object? json) read) {
  try {
    return read(jsonDecode(utf8.decode(bytes)));
  } on Object {
    return null;
  }
}
