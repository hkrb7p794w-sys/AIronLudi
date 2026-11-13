import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/settings/settings_store.dart';
import '../ai/ai_client.dart';

/// Profil des eigenen Kontos.
@immutable
final class Account {
  const Account({required this.id, required this.username, required this.displayName, required this.isAdmin});

  final String id;
  final String username;
  final String displayName;
  final bool isAdmin;

  Map<String, Object?> toJson() => {'id': id, 'username': username, 'displayName': displayName, 'isAdmin': isAdmin};

  static Account? fromJson(Object? json) => switch (json) {
    {
      'id': final String id,
      'username': final String username,
      'displayName': final String displayName,
      'isAdmin': final bool isAdmin,
    } =>
      Account(id: id, username: username, displayName: displayName, isAdmin: isAdmin),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.isAdmin == isAdmin;

  @override
  int get hashCode => Object.hash(id, username, displayName, isAdmin);
}

/// Angemeldetes Gerät.
@immutable
final class AccountSession {
  const AccountSession({required this.device, required this.createdAt, required this.lastUsed, required this.current});

  final String device;
  final String createdAt;
  final String lastUsed;
  final bool current;

  String get id => '$device-$createdAt';

  static AccountSession? fromJson(Object? json) => switch (json) {
    {
      'device': final String device,
      'createdAt': final String createdAt,
      'lastUsed': final String lastUsed,
      'current': final bool current,
    } =>
      AccountSession(device: device, createdAt: createdAt, lastUsed: lastUsed, current: current),
    _ => null,
  };
}

/// Offene Einladung.
@immutable
final class PendingInvite {
  const PendingInvite({required this.code, required this.expiresAt});

  final String code;
  final String expiresAt;

  String get id => code;

  static PendingInvite? fromJson(Object? json) => switch (json) {
    {'code': final String code, 'expiresAt': final String expiresAt} => PendingInvite(code: code, expiresAt: expiresAt),
    _ => null,
  };
}

/// Eigenes Konto am Worker (`worker/src/accounts.ts`): Registrieren mit Einladung, Anmelden, Sitzungen. Das
/// Sitzungs-Token liegt nur im sicheren Speicher dieses Geräts; Benutzername und Anzeigename zusätzlich in den
/// Einstellungen, damit die App sie auch offline zeigt. Gesundheitsdaten gehen dabei nicht an den Worker.
final class AccountService extends ChangeNotifier {
  AccountService({required this._ai, required this._settings, String? device}) : _device = device ?? _deviceName() {
    if (_ai.hasSession) account = Account.fromJson(_settings.json(accountKey));
    _ai.onSessionRejected = _signedOutByServer;
  }

  static const accountKey = SettingsKeys.accountProfile;

  final AIClient _ai;
  final SettingsStore _settings;
  final String _device;

  Account? account;
  List<AccountSession> sessions = const [];
  List<PendingInvite> invites = const [];

  /// Hinweis, wenn die Sitzung vom Worker abgelehnt wurde.
  String? notice;

  bool get isSignedIn => account != null && _ai.hasSession;

  /// Ohne App-Token braucht die Registrierung einen Einladungscode.
  bool get needsInviteCode => _ai.appToken == null;

  String get workerURL => _ai.workerURL;

  /// Gerätename für die Sitzungsliste, z. B. „iPhone (iOS 18.1)“.
  static String _deviceName() {
    final version = RegExp(r'\d+(\.\d+)*').firstMatch(Platform.operatingSystemVersion)?.group(0) ?? '';
    if (Platform.isIOS) return 'iPhone (iOS $version)';
    if (Platform.isAndroid) return 'Android (Android $version)';
    return '${Platform.operatingSystem} ($version)';
  }

  // Anmelden

  /// Server-Adresse übernehmen, falls noch keine gespeichert ist oder eine Einladung eine andere nennt.
  Future<void> useServer(String url) async {
    final normalized = AIClient.normalizedURL(url);
    if (normalized == null) throw AIClientError.invalidURL;
    if (AIClient.normalizedURL(_ai.workerURL) != normalized) {
      await _ai.configure(url: normalized.toString(), token: '');
    }
  }

  /// Neues Konto; liefert den Wiederherstellungscode (nur einmal anzeigen).
  Future<String> register({
    required String username,
    required String displayName,
    required String password,
    required String invite,
  }) async {
    final data = await _ai.send(
      'v1/account/register',
      method: 'POST',
      body: _json({
        'username': AccountRules.normalizeUsername(username),
        'displayName': AccountRules.displayName(displayName) ?? '',
        'password': password,
        'invite': AccountRules.normalizeCode(invite),
        'device': _device,
      }),
      auth: _ai.appToken == null ? AIAuth.none : AIAuth.appToken,
    );
    return _store(data);
  }

  Future<void> login({required String username, required String password}) async {
    final data = await _ai.send(
      'v1/account/login',
      method: 'POST',
      body: _json({'username': AccountRules.normalizeUsername(username), 'password': password, 'device': _device}),
      auth: AIAuth.none,
    );
    await _store(data);
  }

  /// Neues Passwort mit dem Wiederherstellungscode; liefert den neuen Code.
  Future<String> recover({required String username, required String recoveryCode, required String newPassword}) async {
    final data = await _ai.send(
      'v1/account/recover',
      method: 'POST',
      body: _json({
        'username': AccountRules.normalizeUsername(username),
        'recoveryCode': recoveryCode,
        'newPassword': newPassword,
        'device': _device,
      }),
      auth: AIAuth.none,
    );
    return _store(data);
  }

  static List<int> _json(Object value) => utf8.encode(jsonEncode(value));

  static Object? _decode(List<int> data) {
    try {
      return jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
  }

  static Never _unexpected() => throw AIClientError.network('Unerwartete Antwort des Workers.');

  /// Speichert Sitzung und Profil; liefert den Wiederherstellungscode (leer, wenn keiner kam).
  Future<String> _store(List<int> data) async {
    final json = _decode(data);
    final (token, profile) = switch (json) {
      {'token': final String token, 'account': final Object? raw} => (token, Account.fromJson(raw)),
      _ => (null, null),
    };
    if (token == null || profile == null) _unexpected();
    final recovery = (json! as Map)['recoveryCode'];
    await _ai.setSession(token);
    account = profile;
    notice = null;
    await _settings.setJson(accountKey, profile.toJson());
    notifyListeners();
    return recovery is String ? recovery : '';
  }

  Future<void> _clearLocal() async {
    await _ai.setSession(null).catchError((Object _) {});
    account = null;
    sessions = const [];
    invites = const [];
    await _settings.remove(accountKey);
    notifyListeners();
  }

  void _signedOutByServer() {
    if (account == null) return;
    notice = 'Du wurdest abgemeldet (Passwort geändert, auf einem anderen Gerät abgemeldet oder lange nicht genutzt).';
    // Sofort abgemeldet zeigen; das Aufräumen im Speicher folgt.
    account = null;
    _clearLocal();
  }

  // Konto verwalten

  Future<void> refresh() async {
    if (!isSignedIn) return;
    final data = await _ai.send('v1/account/me', method: 'GET', auth: AIAuth.session);
    final json = _decode(data);
    final (profile, rawSessions) = switch (json) {
      {'account': final Object? raw, 'sessions': final List<Object?> list} => (Account.fromJson(raw), list),
      _ => (null, null),
    };
    final parsed = rawSessions?.map(AccountSession.fromJson).toList();
    if (profile == null || parsed == null || parsed.contains(null)) _unexpected();
    account = profile;
    sessions = parsed.nonNulls.toList();
    await _settings.setJson(accountKey, profile.toJson());
    notifyListeners();
    await loadInvites();
  }

  Future<void> logout({bool everywhere = false}) async {
    try {
      await _ai.send('v1/account/logout', method: 'POST', body: _json({'all': everywhere}), auth: AIAuth.session);
    } on Object {
      // Abmelden gelingt lokal immer.
    }
    await _clearLocal();
  }

  Future<void> changePassword({required String old, required String newPassword}) async {
    await _ai.send(
      'v1/account/password',
      method: 'POST',
      body: _json({'oldPassword': old, 'newPassword': newPassword}),
      auth: AIAuth.session,
    );
    await refresh();
  }

  Future<void> updateDisplayName(String name) async {
    final data = await _ai.send(
      'v1/account/profile',
      method: 'PATCH',
      body: _json({'displayName': AccountRules.displayName(name) ?? name}),
      auth: AIAuth.session,
    );
    final updated = switch (_decode(data)) {
      {'account': final Object? raw} => Account.fromJson(raw),
      _ => null,
    };
    if (updated == null) _unexpected();
    account = updated;
    await _settings.setJson(accountKey, updated.toJson());
    notifyListeners();
  }

  Future<void> deleteAccount(String password) async {
    await _ai.send('v1/account/delete', method: 'POST', body: _json({'password': password}), auth: AIAuth.session);
    await _clearLocal();
  }

  // Einladungen

  Future<void> loadInvites() async {
    final data = await _ai.send('v1/account/invites', method: 'GET', auth: AIAuth.session);
    final list = switch (_decode(data)) {
      {'invites': final List<Object?> list} => list.map(PendingInvite.fromJson).toList(),
      _ => null,
    };
    if (list == null || list.contains(null)) _unexpected();
    invites = list.nonNulls.toList();
    notifyListeners();
  }

  /// Neue Einladung als Link zur Einladungsseite des Workers.
  Future<AccountInvite> createInvite() async {
    final data = await _ai.send('v1/account/invites', method: 'POST', body: utf8.encode('{}'), auth: AIAuth.session);
    final invite = PendingInvite.fromJson(_decode(data));
    if (invite == null) _unexpected();
    try {
      await loadInvites();
    } on Object {
      // Liste lädt beim nächsten Mal.
    }
    final base = AIClient.normalizedURL(_ai.workerURL);
    if (base == null) throw AIClientError.notConfigured;
    return AccountInvite(workerURL: base.toString(), code: invite.code);
  }

  Future<void> deleteInvite(String code) async {
    // Wie in Swift still: die Liste zeigt den Stand.
    try {
      await _ai.send('v1/account/invites/$code', method: 'DELETE', auth: AIAuth.session);
    } on Object {
      // Fehler zeigt die neu geladene Liste.
    }
    try {
      await loadInvites();
    } on Object {
      // Liste lädt beim nächsten Mal.
    }
  }

  AccountInvite? inviteLink(String code) {
    final base = AIClient.normalizedURL(_ai.workerURL);
    return base == null ? null : AccountInvite(workerURL: base.toString(), code: code);
  }
}
