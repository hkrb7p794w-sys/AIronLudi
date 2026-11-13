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
}
