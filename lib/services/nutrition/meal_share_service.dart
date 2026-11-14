import 'dart:convert';

import 'package:coach_core/coach_core.dart';

import '../ai/ai_client.dart';

/// Antwort des Workers beim Teilen.
final class MealShareCreated {
  const MealShareCreated({required this.code, required this.expiresAt});

  final String code;
  final String expiresAt;
}

/// Teilen und Empfangen über den Worker (`/v1/share/meal`). Nur wer denselben App-Zugang hat, kann einen Code
/// abrufen; Codes verfallen nach 7 Tagen und lassen sich zurückziehen (Port von `MealShareService`).
final class MealShareService {
  const MealShareService(this._ai);

  final AIClient _ai;

  Future<MealShareCreated> share(SharedMeal meal) async {
    final data = await _ai.send('v1/share/meal', method: 'POST', body: utf8.encode(jsonEncode(meal.toJson())));
    final json = jsonDecode(utf8.decode(data));
    if (json case {'code': final String code, 'expiresAt': final String expiresAt}) {
      return MealShareCreated(code: code, expiresAt: expiresAt);
    }
    throw const AIClientError.http(200, 'Antwort des Workers unvollständig.');
  }

  Future<SharedMeal> fetch(String code) async {
    final data = await _ai.send('v1/share/meal/$code', method: 'GET');
    final meal = SharedMeal.fromJson(jsonDecode(utf8.decode(data)));
    if (meal == null) throw const AIClientError.http(200, 'Geteilte Mahlzeit nicht lesbar.');
    return meal;
  }

  Future<void> revoke(String code) => _ai.send('v1/share/meal/$code', method: 'DELETE');

  /// https-Link, den Messenger anklickbar machen (die Seite öffnet coach://meal/<code>).
  Uri? link(String code) => switch (AIClient.normalizedURL(_ai.workerURL)) {
    final base? => AIClient.appendingPath(base, 'm/$code'),
    null => null,
  };
}
