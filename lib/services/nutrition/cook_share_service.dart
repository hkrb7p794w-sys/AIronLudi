import 'dart:convert';

import 'package:coach_core/coach_core.dart';

import '../ai/ai_client.dart';

/// Antwort des Workers beim Freigeben.
final class CookShareCreated {
  const CookShareCreated({required this.code, required this.expiresAt});

  final String code;
  final String? expiresAt;
}

/// Freigaben fürs gemeinsame Kochen über den Worker (`/v1/share/cook`). Die Worker-Adresse und das Token kommen aus den
/// eigenen Einstellungen (Port von `CookShareService`).
final class CookShareService {
  const CookShareService(this._ai);

  final AIClient _ai;

  static Object? _decode(List<int> data) => jsonDecode(utf8.decode(data));

  Future<CookShareCreated> publish(CookShare share) async {
    final data = await _ai.send('v1/share/cook', method: 'POST', body: utf8.encode(jsonEncode(share.toJson())));
    final json = _decode(data);
    if (json case {'code': final String code}) {
      return CookShareCreated(code: code, expiresAt: json['expiresAt'] is String ? json['expiresAt'] as String : null);
    }
    throw const AIClientError.http(200, 'Antwort des Workers unvollständig.');
  }

  /// Freigabe ersetzen; liefert das neue Ablaufdatum.
  Future<String?> update(CookShare share, {required String code}) async {
    final data = await _ai.send('v1/share/cook/$code', method: 'PUT', body: utf8.encode(jsonEncode(share.toJson())));
    return switch (_decode(data)) {
      {'expiresAt': final String expiresAt} => expiresAt,
      _ => null,
    };
  }

  Future<CookShare> fetch(String code) async {
    final data = await _ai.send('v1/share/cook/$code', method: 'GET');
    final json = _decode(data);
    if (json is! Map) throw const AIClientError.http(200, 'Freigabe nicht lesbar.');
    return CookShare.fromJson(json);
  }

  Future<void> revoke(String code) => _ai.send('v1/share/cook/$code', method: 'DELETE');

  /// https-Link der eigenen Freigabe (die Seite öffnet coach://cook/<code>).
  Uri? link(String code) => switch (AIClient.normalizedURL(_ai.workerURL)) {
    final base? => AIClient.appendingPath(base, 'k/$code'),
    null => null,
  };

  /// Einladungsseite: Die andere Person gibt dort ihre Angaben frei.
  Uri? inviteLink() => switch (AIClient.normalizedURL(_ai.workerURL)) {
    final base? => AIClient.appendingPath(base, 'k/einladen'),
    null => null,
  };
}
