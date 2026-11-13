import 'dart:convert';

final _unreserved = RegExp(r'[A-Za-z0-9\-._~]');

/// Prozentkodierung, die nur unreservierte Zeichen (RFC 3986) stehen lässt – wie in Swift mit
/// `addingPercentEncoding(withAllowedCharacters:)` und genau diesem Zeichensatz. `+`, `&` und `=` kommen so sicher an.
String percentEncodeUnreserved(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (rune < 128 && _unreserved.hasMatch(char)) {
      buffer.write(char);
    } else {
      for (final byte in utf8.encode(char)) {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
  }
  return buffer.toString();
}

/// Query-Parameter wie `URLComponents.queryItems`: Prozentzeichen werden dekodiert, `+` bleibt ein Plus (anders als
/// `Uri.queryParameters`, das `+` zu einem Leerzeichen macht). Bei mehrfachen Namen gilt der erste.
Map<String, String> queryItems(Uri url) {
  final result = <String, String>{};
  if (url.query.isEmpty) return result;
  for (final part in url.query.split('&')) {
    if (part.isEmpty) continue;
    final separator = part.indexOf('=');
    final name = separator < 0 ? part : part.substring(0, separator);
    final value = separator < 0 ? '' : part.substring(separator + 1);
    String decode(String text) {
      try {
        return Uri.decodeComponent(text);
      } on Object {
        return text;
      }
    }

    result.putIfAbsent(decode(name), () => decode(value));
  }
  return result;
}

/// Host einer Adresse (klein), `null` ohne Host – wie `URL(string:)?.host()`.
String? urlHost(String text) {
  final url = Uri.tryParse(text);
  if (url == null || url.host.isEmpty) return null;
  return url.host.toLowerCase();
}
