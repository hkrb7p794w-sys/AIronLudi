import 'dart:convert';

import 'package:coach_core/coach_core.dart';

import '../http/http_transport.dart';

/// Fehler beim Nachschlagen eines Barcodes.
sealed class FoodLookupError implements Exception {
  const FoodLookupError();

  static const invalidBarcode = _LookupPlain('invalidBarcode', 'Ungültiger Barcode (Prüfziffer stimmt nicht).');
  static const notFound = _LookupPlain('notFound', 'Produkt nicht bei Open Food Facts gefunden oder ohne Nährwerte.');

  const factory FoodLookupError.network(String detail) = FoodLookupNetwork;

  String get message;

  @override
  String toString() => message;
}

final class _LookupPlain extends FoodLookupError {
  const _LookupPlain(this.name, this.message);

  final String name;

  @override
  final String message;

  @override
  bool operator ==(Object other) => other is _LookupPlain && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

final class FoodLookupNetwork extends FoodLookupError {
  const FoodLookupNetwork(this.detail);

  final String detail;

  @override
  String get message => 'Open Food Facts nicht erreichbar: $detail';

  @override
  bool operator ==(Object other) => other is FoodLookupNetwork && other.detail == detail;

  @override
  int get hashCode => detail.hashCode;
}

/// Open Food Facts per Barcode. Gefundene Produkte merkt sich die App als eigenes Lebensmittel, ein zweiter Scan braucht
/// dann keinen Netzzugriff.
final class OpenFoodFactsClient {
  OpenFoodFactsClient({HttpTransport? transport}) : _transport = transport ?? DioTransport();

  final HttpTransport _transport;

  Future<OpenFoodFactsProduct> product(String barcode) async {
    if (!OpenFoodFacts.isValidBarcode(barcode)) throw FoodLookupError.invalidBarcode;
    final HttpResponse response;
    try {
      response = await _transport.send(
        HttpRequest(
          method: 'GET',
          url: OpenFoodFacts.productUri(barcode),
          headers: const {'User-Agent': OpenFoodFacts.userAgent},
          timeout: const Duration(seconds: 20),
        ),
      );
    } on HttpTransportException catch (error) {
      throw FoodLookupError.network(error.message);
    }
    final JsonValue json;
    try {
      json = JsonValue(jsonDecode(utf8.decode(response.body)));
    } on FormatException {
      throw FoodLookupError.notFound;
    }
    return OpenFoodFacts.product(json, barcode: barcode) ?? (throw FoodLookupError.notFound);
  }

  /// Ergebnisse je Suchbegriff (normalisiert) für diese App-Sitzung – spart Anfragen, wenn dieselbe Suche aus der
  /// Schnellsuche und aus „Erfassen“ kommt (Open Food Facts begrenzt Suchen auf wenige je Minute).
  final _cache = <String, List<OpenFoodFactsProduct>>{};
  static const _cacheLimit = 40;

  /// Markenprodukte per Suchbegriff. Zuerst die Volltextsuche (Search-a-licious), bei Fehler oder ohne brauchbaren
  /// Treffer die klassische Suche (`cgi/search.pl`, Produkte aus Deutschland zuerst). Leere Liste nur, wenn wirklich
  /// nichts passt; ist keine der beiden erreichbar, ein [FoodLookupNetwork] statt einer stillen leeren Liste.
  Future<List<OpenFoodFactsProduct>> search(String query) async {
    final key = FoodSearch.normalized(query);
    if (key.isEmpty) return const [];
    if (_cache[key] case final cached?) return cached;
    FoodLookupError? failure;
    var answered = false;
    var results = const <OpenFoodFactsProduct>[];
    for (final url in [ProductSearch.fullTextUri(query), ProductSearch.searchUri(query)]) {
      try {
        results = await _searchAt(url);
        answered = true;
        if (results.isNotEmpty) break;
      } on FoodLookupError catch (error) {
        failure ??= error;
      }
    }
    // Fehler nur, wenn keine der beiden Suchen geantwortet hat; nicht gemerkt, damit „Erneut“ wirklich neu fragt.
    if (!answered) throw failure!;
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    return _cache[key] = results;
  }

  Future<List<OpenFoodFactsProduct>> _searchAt(Uri url) async {
    final HttpResponse response;
    try {
      response = await _transport.send(
        HttpRequest(
          method: 'GET',
          url: url,
          headers: const {'User-Agent': OpenFoodFacts.userAgent, 'Accept': 'application/json'},
          timeout: const Duration(seconds: 15),
        ),
      );
    } on HttpTransportException catch (error) {
      throw FoodLookupError.network(error.message);
    }
    if (response.status == 429) throw const FoodLookupError.network('zu viele Suchen – bitte kurz warten');
    if (response.status < 200 || response.status >= 300) {
      throw FoodLookupError.network('Server antwortet mit Fehler ${response.status}');
    }
    try {
      return ProductSearch.searchResults(JsonValue(jsonDecode(utf8.decode(response.body))));
    } on FormatException {
      // Statt JSON eine Fehlerseite (z. B. „vorübergehend nicht verfügbar“): als Fehler melden, nicht als „nichts“.
      throw const FoodLookupError.network('unerwartete Antwort des Servers');
    }
  }
}
