import 'dart:convert';

import '../util/swift_date.dart';

/// Bearer-Token der Personal API. Der API-Key wird per `POST` gegen ein Token getauscht, das laut Garmins offiziellem
/// Client 24 Stunden gilt; erneuert wird, wenn weniger als eine Stunde Restlaufzeit bleibt.
final class GarminBearerToken {
  const GarminBearerToken({required this.value, required this.expiresAt});

  static const refreshWindow = Duration(hours: 1);

  /// Rückfall, wenn das Token kein lesbares JWT ist.
  static const fallbackLifetime = Duration(hours: 23);

  final String value;
  final DateTime expiresAt;

  /// Baut das Token aus der Antwort des Token-Endpunkts (reiner Text, ein JWT).
  static GarminBearerToken? fromResponse(String responseBody, {DateTime? now}) {
    final token = responseBody.trim();
    if (token.isEmpty) return null;
    return GarminBearerToken(
      value: token,
      expiresAt: jwtExpiration(token) ?? (now ?? DateTime.now()).add(fallbackLifetime),
    );
  }

  bool needsRefresh({DateTime? now}) =>
      expiresAt.difference(now ?? DateTime.now()).inMicroseconds <= refreshWindow.inMicroseconds;

  /// Liest `exp` aus dem Payload eines JWT (ohne Signaturprüfung – nur für die Ablaufplanung).
  static DateTime? jwtExpiration(String token) {
    final parts = token.split('.').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return null;
    var base64 = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    base64 += '=' * ((4 - base64.length % 4) % 4);
    try {
      final payload = jsonDecode(utf8.decode(base64Decode(base64)));
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return null;
      return DateTime.fromMicrosecondsSinceEpoch((exp * 1000000).round(), isUtc: true);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> toJson() => {'value': value, 'expiresAt': swiftDateToJson(expiresAt)};

  static GarminBearerToken? fromJson(Object? json) {
    if (json is! Map) return null;
    final value = json['value'];
    final expiresAt = swiftDateFromJson(json['expiresAt']);
    if (value is! String || expiresAt == null) return null;
    return GarminBearerToken(value: value, expiresAt: expiresAt);
  }

  @override
  bool operator ==(Object other) =>
      other is GarminBearerToken && other.value == value && other.expiresAt.isAtSameMomentAs(expiresAt);

  @override
  int get hashCode => Object.hash(value, expiresAt.microsecondsSinceEpoch);
}

/// Fehlerbilder der Personal API in Klartext.
sealed class GarminAPIError implements Exception {
  const GarminAPIError();

  static const missingKey = _Plain('missingKey', 'Kein Garmin-API-Key hinterlegt.');

  /// 401/403 beim Token-Tausch: Key falsch, abgelaufen oder gelöscht.
  static const keyRejected = _Plain(
    'keyRejected',
    'Garmin hat den API-Key abgelehnt. Er ist falsch, abgelaufen oder wurde gelöscht – bitte in Garmin Connect '
        'einen neuen Key erzeugen.',
  );

  /// 401 bei einem Datenabruf trotz frischem Token.
  static const unauthorized = _Plain('unauthorized', 'Garmin hat die Anfrage nicht autorisiert.');
  static const rateLimited = _Plain(
    'rateLimited',
    'Garmin begrenzt gerade die Anfragen. Bitte später erneut versuchen.',
  );
  static const invalidResponse = _Plain('invalidResponse', 'Unerwartete Antwort von Garmin.');

  /// 400/500 ohne Inhalt, typischerweise ein zu großer Datumsbereich.
  const factory GarminAPIError.rejectedRequest(int status) = GarminRejectedRequest;
  const factory GarminAPIError.server(int status) = GarminServerError;
  const factory GarminAPIError.network(String detail) = GarminNetworkError;

  static GarminAPIError? from({required int status, required bool isTokenExchange}) {
    if (status >= 200 && status < 300) return null;
    if (status == 401 || status == 403) return isTokenExchange ? keyRejected : unauthorized;
    if (status == 429) return rateLimited;
    if (status == 400 || status == 404 || status == 422) return GarminRejectedRequest(status);
    return GarminServerError(status);
  }

  String get message;

  @override
  String toString() => message;
}

final class _Plain extends GarminAPIError {
  const _Plain(this.name, this.message);

  final String name;

  @override
  final String message;

  @override
  bool operator ==(Object other) => other is _Plain && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

final class GarminRejectedRequest extends GarminAPIError {
  const GarminRejectedRequest(this.status);

  final int status;

  @override
  String get message => 'Garmin hat die Anfrage abgelehnt (HTTP $status).';

  @override
  bool operator ==(Object other) => other is GarminRejectedRequest && other.status == status;

  @override
  int get hashCode => status.hashCode;
}

final class GarminServerError extends GarminAPIError {
  const GarminServerError(this.status);

  final int status;

  @override
  String get message => 'Garmin-Server-Fehler (HTTP $status).';

  @override
  bool operator ==(Object other) => other is GarminServerError && other.status == status;

  @override
  int get hashCode => status.hashCode;
}

final class GarminNetworkError extends GarminAPIError {
  const GarminNetworkError(this.detail);

  final String detail;

  @override
  String get message => 'Netzwerkfehler: $detail';

  @override
  bool operator ==(Object other) => other is GarminNetworkError && other.detail == detail;

  @override
  int get hashCode => detail.hashCode;
}
