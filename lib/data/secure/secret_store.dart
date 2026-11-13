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
