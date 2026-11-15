import '../nutrition/meal.dart' show newUuid;
import 'account_rules.dart';

/// Ein Benutzer auf diesem Gerät. Alle Daten (Datenbank, Einstellungen, Geheimnisse, Dateien) liegen in einem eigenen
/// Speicherbereich, der nur über [id] gefunden wird – nie über den Namen, der sich nicht ändern darf, aber zur Anzeige
/// dient. Der Benutzername folgt den Regeln der Konten (`AccountRules`), damit er zum Konto am Worker passen kann.
final class LocalUser {
  const LocalUser({required this.id, required this.username, required this.displayName, required this.createdAt});

  /// Kennung des Speicherbereichs: [UserDirectory.legacyID] für die Daten von vor der Mehrbenutzer-Version, sonst
  /// eine UUID (nur Großbuchstaben, Ziffern, Bindestriche – sicher als Datei- und Schlüsselname).
  final String id;

  /// Eindeutig auf dem Gerät, klein geschrieben.
  final String username;
  final String displayName;
  final DateTime createdAt;

  bool get isLegacy => id == UserDirectory.legacyID;

  /// Anzeigename, sonst der Benutzername.
  String get title => displayName.isEmpty ? username : displayName;

  LocalUser copyWith({String? displayName}) =>
      LocalUser(id: id, username: username, displayName: displayName ?? this.displayName, createdAt: createdAt);

  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static LocalUser? fromJson(Object? json) {
    if (json is! Map) return null;
    final (id, username, displayName, createdAt) = (
      json['id'],
      json['username'],
      json['displayName'],
      json['createdAt'],
    );
    if (id is! String || !UserDirectory.isValidID(id) || username is! String || displayName is! String) return null;
    if (AccountRules.usernameProblem(username) != null && id != UserDirectory.legacyID) return null;
    final created = createdAt is String ? DateTime.tryParse(createdAt) : null;
    return LocalUser(
      id: id,
      username: AccountRules.normalizeUsername(username),
      displayName: displayName,
      createdAt: created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LocalUser &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, username, displayName, createdAt);
}

/// Fehler beim Anlegen, Umbenennen oder Löschen – mit Text für die Anzeige.
final class UserDirectoryError implements Exception {
  const UserDirectoryError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Verzeichnis der Benutzer auf diesem Gerät und wer gerade aktiv ist (Datei `users.json` neben den Speicherbereichen,
/// selbst ohne persönliche Daten außer Benutzer- und Anzeigename). Feste Regeln:
/// - Es gibt immer mindestens einen Benutzer und genau einen aktiven.
/// - Benutzernamen sind eindeutig (ohne Groß-/Kleinschreibung).
/// - Der aktive Benutzer lässt sich nicht löschen (erst wechseln) – so wird nie ein geöffneter Speicher entfernt.
/// - Der ursprüngliche Benutzer ([legacyID]) bleibt immer bestehen.
/// - Ohne Datei (erster Start nach dem Update) gehört der vorhandene Speicher dem Benutzer [legacyID]; nichts wird
///   verschoben, damit keine Daten verloren gehen.
final class UserDirectory {
  UserDirectory._(this._users, this._activeID);

  static const legacyID = 'default';
  static const legacyUsername = 'ich';
  static const maxUsers = 20;
  static const fileName = 'users.json';

  static final _id = RegExp(r'^[A-Z0-9-]{8,64}$');

  static bool isValidID(String id) => id == legacyID || _id.hasMatch(id);

  /// Erster Start: ein Benutzer für den vorhandenen Speicher.
  factory UserDirectory.initial({String? username, String displayName = ''}) {
    final name = username == null || AccountRules.usernameProblem(username) != null
        ? legacyUsername
        : AccountRules.normalizeUsername(username);
    final user = LocalUser(
      id: legacyID,
      username: name,
      displayName: displayName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    return UserDirectory._([user], legacyID);
  }

  final List<LocalUser> _users;
  String _activeID;

  List<LocalUser> get users => List.unmodifiable(_users);

  LocalUser get active => _users.firstWhere((user) => user.id == _activeID);

  LocalUser? byID(String id) => _users.where((user) => user.id == id).firstOrNull;

  LocalUser? byUsername(String username) {
    final name = AccountRules.normalizeUsername(username);
    return _users.where((user) => user.username == name).firstOrNull;
  }

  /// `null`, wenn der Name frei und gültig ist.
  String? usernameProblem(String raw) {
    final problem = AccountRules.usernameProblem(raw);
    if (problem != null) return problem;
    if (byUsername(raw) != null) return 'Diesen Benutzernamen gibt es auf diesem Gerät schon.';
    return null;
  }

  /// Neuer Benutzer mit eigenem, leerem Speicher. Wird nicht automatisch aktiv.
  LocalUser add({required String username, String displayName = '', DateTime? now, String? id}) {
    if (_users.length >= maxUsers) throw const UserDirectoryError('Mehr Benutzer passen nicht auf ein Gerät.');
    if (usernameProblem(username) case final problem?) throw UserDirectoryError(problem);
    final name = AccountRules.displayName(displayName);
    if (name == null) throw const UserDirectoryError('Der Anzeigename darf höchstens 40 Zeichen haben.');
    final user = LocalUser(
      id: id ?? newUuid(),
      username: AccountRules.normalizeUsername(username),
      displayName: name,
      createdAt: (now ?? DateTime.now()).toUtc(),
    );
    if (!isValidID(user.id) || byID(user.id) != null) throw const UserDirectoryError('Ungültige Kennung.');
    _users.add(user);
    return user;
  }

  /// Anzeigename ändern (der Benutzername bleibt – er bindet die Daten nicht, ist aber die feste Kennung zum Anmelden).
  void rename(String id, String displayName) {
    final index = _users.indexWhere((user) => user.id == id);
    if (index < 0) throw const UserDirectoryError('Diesen Benutzer gibt es nicht.');
    final name = AccountRules.displayName(displayName);
    if (name == null) throw const UserDirectoryError('Der Anzeigename darf höchstens 40 Zeichen haben.');
    _users[index] = _users[index].copyWith(displayName: name);
  }

  void activate(String id) {
    if (byID(id) == null) throw const UserDirectoryError('Diesen Benutzer gibt es nicht.');
    _activeID = id;
  }

  /// Entfernt den Benutzer aus dem Verzeichnis; seinen Speicher löscht der Aufrufer danach.
  LocalUser remove(String id) {
    final user = byID(id);
    if (user == null) throw const UserDirectoryError('Diesen Benutzer gibt es nicht.');
    if (id == _activeID) {
      throw const UserDirectoryError('Der aktive Benutzer lässt sich nicht löschen – erst wechseln.');
    }
    // Sein Speicher liegt an den Stellen von vor der Mehrbenutzer-Version, zwischen den Verzeichnissen der anderen –
    // gezielt löschen ließe er sich nur unsicher.
    if (user.isLegacy) throw const UserDirectoryError('Der ursprüngliche Benutzer dieses Geräts bleibt bestehen.');
    _users.removeWhere((other) => other.id == id);
    return user;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'active': _activeID,
    'users': [for (final user in _users) user.toJson()],
  };

  /// Tolerant: unlesbare Einträge und doppelte Kennungen bzw. Namen fallen weg; ohne gültigen aktiven Benutzer wird der
  /// erste aktiv. `null`, wenn gar nichts Brauchbares übrig bleibt (dann [UserDirectory.initial]).
  static UserDirectory? fromJson(Object? json) {
    if (json is! Map || json['users'] is! List) return null;
    final users = <LocalUser>[];
    for (final raw in json['users'] as List) {
      final user = LocalUser.fromJson(raw);
      if (user == null || users.any((other) => other.id == user.id || other.username == user.username)) continue;
      users.add(user);
      if (users.length >= maxUsers) break;
    }
    if (users.isEmpty) return null;
    final active = json['active'];
    final activeID = active is String && users.any((user) => user.id == active) ? active : users.first.id;
    return UserDirectory._(users, activeID);
  }
}
