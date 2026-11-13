import 'package:coach_core/coach_core.dart';
import 'package:flutter/foundation.dart';

import '../../app/app_model.dart';
import '../../data/settings/settings_store.dart';
import '../../services/ai/ai_client.dart';
import '../../services/garmin/garmin_connect_session.dart';

/// Zustand der Einstellungsseite (Port von `SettingsViewModel`): Garmin-Key, Garmin-Konto, KI-Worker.
final class SettingsController extends ChangeNotifier {
  SettingsController({required this._model, required this._ai, required this._settings, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    final now = _clock();
    keyExpiry = _settings.date(keyExpiryKey) ?? DateTime(now.year + 1, now.month, now.day);
    workerURLInput = _ai.workerURL;
    connectEmail = _model.garmin.connect?.email ?? '';
    connectLoggedIn = _model.garmin.connect?.isLoggedIn ?? false;
  }

  static const keyExpiryKey = SettingsKeys.garminKeyExpiry;

  /// Ab so vielen Tagen vor Ablauf des Garmin-Keys warnt die App.
  static const expiryWarningDays = 14;

  final AppModel _model;
  final AIClient _ai;
  final SettingsStore _settings;
  final DateTime Function() _clock;

  String garminKeyInput = '';
  late DateTime keyExpiry;
  late String workerURLInput;
  String appTokenInput = '';
  late String connectEmail;
  String connectPassword = '';
  String connectCode = '';

  /// Garmin wartet auf einen Bestätigungscode (Methode, z. B. `email`).
  String? awaitingCodeVia;
  late bool connectLoggedIn;
  String? connectStatus;
  String? garminStatus;
  String? aiStatus;
  bool isBusy = false;

  /// Code eingegeben: „Code bestätigen“ ab vier Zeichen.
  void setConnectCode(String text) {
    connectCode = text;
    notifyListeners();
  }

  bool get hasGarminKey => _model.garmin.hasKey;
  bool get hasAIToken => _ai.hasToken;

  static String _message(Object error) => switch (error) {
    GarminAPIError(:final message) || GarminConnectError(:final message) || AIClientError(:final message) => message,
    _ => '$error',
  };

  void _busy(bool value) {
    isBusy = value;
    notifyListeners();
  }

  /// Warnung, wenn der Garmin-Key bald abläuft (Garmin erlaubt höchstens ein Jahr).
  String? get expiryWarning {
    if (!hasGarminKey || _settings.date(keyExpiryKey) == null) return null;
    final now = _clock();
    final days = DateTime(
      keyExpiry.year,
      keyExpiry.month,
      keyExpiry.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 0) return 'Der Garmin-Key ist abgelaufen. Bitte in Garmin Connect einen neuen erzeugen.';
    if (days <= expiryWarningDays) return 'Der Garmin-Key läuft in $days Tagen ab.';
    return null;
  }

  String _afterSync(String fallback) =>
      _model.lastError ?? (_model.lastReport == null ? fallback : 'Abgerufen: ${_model.lastReport!.summary}');

  Future<void> saveGarminKey() async {
    final key = garminKeyInput.trim();
    if (key.isEmpty) {
      garminStatus = 'Bitte den Key einfügen.';
      notifyListeners();
      return;
    }
    _busy(true);
    try {
      await _model.garmin.updateKey(key);
      await _settings.setDate(keyExpiryKey, keyExpiry);
      await _model.garmin.validToken(forceRefresh: true);
      garminKeyInput = '';
      garminStatus = 'Verbunden. Daten werden abgerufen …';
      notifyListeners();
      await _model.syncNow();
      garminStatus = _afterSync('Verbunden.');
    } on Object catch (error) {
      garminStatus = _message(error);
    } finally {
      _busy(false);
    }
  }

  // Garmin-Konto

  Future<void> loginConnect() async {
    final connect = _model.garmin.connect;
    if (connect == null) return;
    if (connectEmail.isEmpty || connectPassword.isEmpty) {
      connectStatus = 'Bitte E-Mail und Passwort eingeben.';
      notifyListeners();
      return;
    }
    _busy(true);
    connectStatus = 'Anmeldung läuft …';
    try {
      final state = await connect.login(email: connectEmail, password: connectPassword);
      connectPassword = '';
      await _finish(state);
    } on Object catch (error) {
      connectPassword = '';
      connectStatus = _message(error);
    } finally {
      _busy(false);
    }
  }

  Future<void> submitConnectCode() async {
    final connect = _model.garmin.connect;
    if (connect == null) return;
    _busy(true);
    try {
      final state = await connect.submitCode(connectCode);
      connectCode = '';
      await _finish(state);
    } on Object catch (error) {
      connectStatus = _message(error);
    } finally {
      _busy(false);
    }
  }

  Future<void> _finish(ConnectLoginState state) async {
    switch (state) {
      case ConnectNeedsCode(:final method):
        awaitingCodeVia = method;
        connectStatus = method.toLowerCase() == 'email'
            ? 'Garmin hat dir einen Code per E-Mail geschickt.'
            : 'Garmin hat dir einen Code geschickt ($method).';
      case ConnectLoggedIn():
        awaitingCodeVia = null;
        connectLoggedIn = true;
        connectStatus = 'Angemeldet. Daten werden abgerufen …';
        notifyListeners();
        await _model.syncNow();
        connectStatus = _afterSync('Angemeldet.');
    }
  }

  Future<void> logoutConnect() async {
    await _model.garmin.connect?.logout();
    connectLoggedIn = false;
    awaitingCodeVia = null;
    connectStatus = 'Abgemeldet.';
    notifyListeners();
  }

  Future<void> saveExpiry(DateTime date) async {
    keyExpiry = date;
    await _settings.setDate(keyExpiryKey, date);
    notifyListeners();
  }

  Future<void> removeGarminKey() async {
    await _model.garmin.updateKey('');
    await _settings.remove(keyExpiryKey);
    garminStatus = 'Key entfernt.';
    notifyListeners();
  }

  Future<void> saveAndTestAI() async {
    _busy(true);
    try {
      await _ai.configure(url: workerURLInput, token: appTokenInput);
      appTokenInput = '';
      workerURLInput = _ai.workerURL;
      final response = await _ai.run('ping');
      final greeting = response.output['gruss']?.stringValue ?? 'ok';
      aiStatus = '$greeting (${response.provider}, ${response.model})';
    } on Object catch (error) {
      aiStatus = _message(error);
    } finally {
      _busy(false);
    }
  }
}
