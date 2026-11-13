import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/settings/coach_settings.dart';
import '../ai/ai_client.dart';

/// Einladung eines anderen Servers: Der eigene Zugang bleibt, ein Beitritt geht so nicht.
final class LeagueInviteOtherServer implements Exception {
  const LeagueInviteOtherServer();

  String get message =>
      'Diese Einladung gehört zu einem anderen Server. Dein eigener Zugang bleibt unverändert, ein Beitritt ist so '
      'nicht möglich.';

  @override
  String toString() => message;
}

/// Rangliste über den eigenen Worker (`worker/src/league.ts`). Gesendet werden nur Anzeigename, Symbol und Punkte.
final class LeagueService extends ChangeNotifier {
  LeagueService({required this._ai, required this._settings, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AIClient _ai;
  final CoachSettings _settings;
  final DateTime Function() _clock;

  List<LeagueEntry> members = [];
  String? lastError;
  bool isLoading = false;
  DateTime? lastUpdate;

  bool get canUse => _ai.isConfigured;

  /// Einladungen verschickt nur, wer den Worker betreibt; Gäste geben den Code weiter.
  bool get canInvite => _settings.league.isJoined && _ai.isConfigured && _ai.isOwner;

  /// Einladungslink mit Worker-Adresse, eigens ausgestelltem Gast-Token und Code. Das Haupt-Token bleibt auf dem
  /// Gerät; jede Einladung bekommt ein eigenes Token, das sich im Worker einzeln sperren lässt.
  Future<Uri?> makeInvite() async {
    final base = AIClient.normalizedURL(_ai.workerURL);
    if (!canInvite || base == null) return null;
    final token = await _ai.createGuestToken();
    return LeagueInvite(workerURL: base.toString(), token: token, code: _settings.league.code).url;
  }

  /// Eigenen Stand hochladen und die Rangliste holen.
  Future<void> sync(MotivationSummary summary) async {
    final league = _settings.league;
    if (!league.isJoined || !_ai.isConfigured || isLoading) return;
    isLoading = true;
    notifyListeners();
    final name = league.name.trim();
    final companion = _settings.companion;
    final avatar = companion.isActive ? companion.kind.symbol : 'person.fill';
    final entry = LeagueEntry.fromSummary(
      id: league.memberID,
      name: name.isEmpty ? 'Ich' : name,
      avatar: avatar,
      summary: summary,
    );
    try {
      await _ai.send(
        'v1/league/${league.code}/members/${league.memberID}',
        method: 'PUT',
        body: utf8.encode(jsonEncode(entry.toJson())),
      );
      final data = await _ai.send('v1/league/${league.code}', method: 'GET', query: {'week': summary.week.monday.iso});
      final json = jsonDecode(utf8.decode(data));
      final list = json is Map && json['members'] is List ? listStrict(json['members'], LeagueEntry.fromJson) : null;
      if (list == null) throw AIClientError.network('Unerwartete Antwort des Workers.');
      members = list;
      lastError = null;
      lastUpdate = _clock();
    } on Object catch (error) {
      lastError = error is AIClientError ? error.message : '$error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void create() {
    _settings.league = _settings.league.copy()..code = LeagueCode.generate();
    members = [];
    notifyListeners();
  }

  void join(String code) {
    final trimmed = code.trim().toLowerCase();
    if (!LeagueCode.isValid(trimmed)) return;
    _settings.league = _settings.league.copy()..code = trimmed;
    members = [];
    notifyListeners();
  }

  /// Einladung annehmen und beitreten. Das Haupt-Token bleibt dabei immer auf diesem Gerät und unverändert.
  Future<void> accept(LeagueInvite invite) async {
    switch (invite.decision(currentURL: _ai.workerURL, currentToken: _ai.storedToken)) {
      case InviteDecision.keepCurrentToken:
        break;
      case InviteDecision.useInviteToken:
        await _ai.configure(url: invite.workerURL, token: invite.token);
      case InviteDecision.rejectOtherServer:
        throw const LeagueInviteOtherServer();
    }
    join(invite.code);
  }

  Future<void> leave() async {
    final league = _settings.league;
    if (league.isJoined && _ai.isConfigured) {
      try {
        await _ai.send('v1/league/${league.code}/members/${league.memberID}', method: 'DELETE');
      } on Object {
        // Austritt gilt lokal auch ohne Verbindung.
      }
    }
    _settings.league = _settings.league.copy()..code = '';
    members = [];
    notifyListeners();
  }
}
