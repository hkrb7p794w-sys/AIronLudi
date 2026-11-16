import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/settings/settings_store.dart';
import '../ai/ai_client.dart';

/// Neueste Android-Version laut Worker (`GET /v1/app/android`, `worker/src/android.ts`).
@immutable
final class AndroidUpdate {
  const AndroidUpdate({required this.versionName, required this.versionCode, required this.url, this.notes});

  final String versionName;

  /// Build-Nummer wie in `android.yml` (10000 + Laufnummer); entspricht `PackageInfo.buildNumber`.
  final int versionCode;

  /// Download-Seite des Workers (privater Link).
  final Uri url;
  final String? notes;

  /// Pflichtfelder fehlen oder Adresse nicht `https://` → `null`.
  static AndroidUpdate? fromJson(Object? json) {
    if (json is! Map) return null;
    final (name, code, url, notes) = (json['versionName'], json['versionCode'], json['url'], json['notes']);
    if (name is! String || code is! num || code != code.roundToDouble() || url is! String) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return AndroidUpdate(
      versionName: name,
      versionCode: code.toInt(),
      url: uri,
      notes: notes is String && notes.trim().isNotEmpty ? notes.trim() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AndroidUpdate &&
      other.versionName == versionName &&
      other.versionCode == versionCode &&
      other.url == url &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(versionName, versionCode, url, notes);
}

/// Update-Hinweis für Android: Die App kommt nicht aus dem Play Store und aktualisiert sich nicht selbst. Beim Start und
/// beim Zurückkehren (höchstens alle [interval]) fragt sie den Worker nach der neuesten Version; ist sie neuer als die
/// installierte und nicht mit „Später“ ausgeblendet, steht sie in [available]. Installieren muss die Person selbst
/// (Download-Seite öffnen) – Android erlaubt außerhalb des Play Stores kein stilles Update.
///
/// Ohne Worker, im Demo-Modus, auf dem iPhone (Updates über SideStore) und ohne Netz passiert nichts.
final class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    required this._ai,
    required this._settings,
    required this._installedBuild,
    bool? isAndroid,
    DateTime Function()? clock,
  }) : _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
       _clock = clock ?? DateTime.now;

  /// Gerätestand, nicht in der Sicherung (`AppBackup.isBackedUp`).
  static const lastCheckKey = 'update.lastCheck';
  static const dismissedKey = 'update.dismissedVersion';
  static const interval = Duration(hours: 6);

  final AIClient _ai;
  final SettingsStore _settings;
  final Future<int?> Function() _installedBuild;
  final bool _isAndroid;
  final DateTime Function() _clock;

  AndroidUpdate? _available;
  bool _checking = false;

  /// Neuere Version, die angezeigt werden soll; sonst `null`.
  AndroidUpdate? get available => _available;

  bool get isSupported => _isAndroid;

  /// Fragt den Worker, wenn die letzte Prüfung länger als [interval] her ist (oder mit [force]). Fehler bleiben still:
  /// Ein fehlender Hinweis darf nichts anderes stören.
  Future<void> check({bool force = false, bool isDemo = false}) async {
    if (!_isAndroid || isDemo || _checking || !_ai.isConfigured) return;
    final now = _clock();
    final last = _settings.date(lastCheckKey);
    // Kurz nach der letzten Prüfung bleibt der Hinweis, wie er ist (Uhr zurückgestellt: neu prüfen).
    if (!force && last != null && !now.isBefore(last) && now.difference(last) < interval) return;
    _checking = true;
    try {
      final data = await _ai.send('v1/app/android', method: 'GET', timeout: const Duration(seconds: 15));
      final update = AndroidUpdate.fromJson(_decode(data));
      await _settings.setDate(lastCheckKey, now);
      _update(await _newer(update));
    } on Object {
      // Kein Netz, Worker alt (404) oder noch keine Version hochgeladen: kein Hinweis.
    } finally {
      _checking = false;
    }
  }

  /// „Später“: Diese Version nicht mehr anzeigen; eine neuere erscheint wieder.
  Future<void> dismiss() async {
    final update = _available;
    if (update == null) return;
    await _settings.setInt(dismissedKey, update.versionCode);
    _update(null);
  }

  Future<AndroidUpdate?> _newer(AndroidUpdate? update) async {
    if (update == null) return null;
    final installed = await _installedBuild();
    if (installed == null || update.versionCode <= installed) return null;
    return _visible(update);
  }

  AndroidUpdate? _visible(AndroidUpdate? update) {
    if (update == null) return null;
    final dismissed = _settings.intValue(dismissedKey);
    return dismissed != null && update.versionCode <= dismissed ? null : update;
  }

  void _update(AndroidUpdate? value) {
    if (value == _available) return;
    _available = value;
    notifyListeners();
  }

  static Object? _decode(List<int> data) {
    try {
      return jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
  }
}
