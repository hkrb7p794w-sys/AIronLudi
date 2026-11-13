import 'dart:convert';

/// FNV-1a mit 64 Bit über die UTF-8-Bytes, wie in Swift mit `UInt64` und `&*`. Dart-Ganzzahlen auf iOS/Android sind
/// 64 Bit und laufen beim Multiplizieren genauso über; das Ergebnis ist das Bitmuster des vorzeichenlosen Werts.
int fnv1a64(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash *= 0x100000001b3;
  }
  return hash;
}

/// Der Hash als vorzeichenlose Zahl (für Modulo und Hex-Ausgabe wie in Swift).
BigInt fnv1a64Unsigned(List<int> bytes) => BigInt.from(fnv1a64(bytes)).toUnsigned(64);

/// FNV-1a eines Textes (UTF-8).
BigInt fnv1a64Text(String text) => fnv1a64Unsigned(utf8.encode(text));
