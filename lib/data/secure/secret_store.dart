import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Schlüssel für Geheimnisse, die nur im sicheren Speicher liegen (wie `SecretKey` der Swift-App).
enum SecretKey {
  garminAPIKey,
  garminBearerToken,

  /// Token des inoffiziellen Garmin-Connect-Zugangs (JSON, `ConnectToken`).
  garminConnectToken,
  aiAppToken,

  /// Sitzung des eigenen Kontos am Worker (`s1.…`). Nur auf diesem Gerät.
  accountSession,
}

/// Ablage für Geheimnisse; im Test durch [InMemorySecretStore] ersetzt.
abstract interface class SecretStore {
  Future<String?> read(SecretKey key);

  /// Leer oder `null` löscht den Eintrag.
  Future<void> write(SecretKey key, String? value);
}

/// iOS-Schlüsselbund bzw. Android-Keystore. Lesbar nach dem ersten Entsperren (Hintergrundabruf), nicht in Backups
/// anderer Geräte (iOS `first_unlock_this_device`; Android ist per `data_extraction_rules.xml` vom Auto-Backup
/// ausgenommen).
final class DeviceSecretStore implements SecretStore {
  DeviceSecretStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accountName: 'io.github.hkrb7p794w.coach',
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(SecretKey key) => _storage.read(key: key.name);

  @override
  Future<void> write(SecretKey key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key.name);
    } else {
      await _storage.write(key: key.name, value: value);
    }
  }
}

/// Speicher im Arbeitsspeicher für Tests und Vorschauen.
final class InMemorySecretStore implements SecretStore {
  InMemorySecretStore([Map<SecretKey, String>? values]) : _values = {...?values};

  final Map<SecretKey, String> _values;

  @override
  Future<String?> read(SecretKey key) async => _values[key];

  @override
  Future<void> write(SecretKey key, String? value) async {
    if (value == null || value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

/// Geheimnisse im Arbeitsspeicher, beim Start einmal geladen: synchron lesbar wie `SecretStore.string(for:)` der
/// Swift-App; Schreiben ändert sofort und speichert dann im sicheren Speicher.
final class Secrets {
  Secrets._(this._store, this._values);

  /// Liest alle Schlüssel aus [store]; nicht lesbare gelten als fehlend.
  static Future<Secrets> load(SecretStore store) async {
    final values = <SecretKey, String>{};
    for (final key in SecretKey.values) {
      try {
        if (await store.read(key) case final value? when value.isNotEmpty) values[key] = value;
      } on Object {
        // Nicht lesbar (z. B. Schlüsselbund gesperrt): wie in Swift als fehlend behandeln.
      }
    }
    return Secrets._(store, values);
  }

  /// Für Tests und Vorschauen.
  factory Secrets.memory([Map<SecretKey, String>? values]) =>
      Secrets._(InMemorySecretStore(values), {...?values}..removeWhere((_, value) => value.isEmpty));

  final SecretStore _store;
  final Map<SecretKey, String> _values;

  String? string(SecretKey key) => _values[key];

  /// Leer oder `null` löscht den Eintrag.
  Future<void> set(SecretKey key, String? value) {
    if (value == null || value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    return _store.write(key, value);
  }
}
