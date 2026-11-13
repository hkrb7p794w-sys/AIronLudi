import '../motivation/league.dart';
import '../util/url_query.dart';

final _allowed = RegExp(r'^[a-z0-9_.]{3,20}$');
final _startAllowed = RegExp(r'^[a-z0-9]');
final _codeCharacter = RegExp('[A-Z0-9]');
final _whitespace = RegExp(r'\s+');

/// Regeln für Konten, gleich wie im Worker (`worker/src/accounts.ts`), damit die App Fehler schon beim Tippen zeigt.
/// Entscheidend bleibt der Worker.
abstract final class AccountRules {
  static const minPasswordLength = 10;
  static const maxPasswordLength = 128;
  static const reserved = {'admin', 'administrator', 'coach', 'ironludi', 'support', 'system', 'root', 'owner'};

  static String normalizeUsername(String text) => text.trim().toLowerCase();

  /// `null`, wenn der Benutzername passt; sonst der Hinweis für die Anzeige.
  static String? usernameProblem(String raw) {
    final username = normalizeUsername(raw);
    if (!_allowed.hasMatch(username) || !_startAllowed.hasMatch(username)) {
      return 'Benutzername: 3–20 Zeichen, nur a–z, 0–9, Punkt und Unterstrich, am Anfang ein Buchstabe oder eine '
          'Ziffer.';
    }
    if (reserved.contains(username)) return 'Dieser Benutzername ist reserviert.';
    return null;
  }

  /// Zeichen wie `String.count` in Swift (Unicode-Zeichen statt UTF-16-Einheiten).
  static int _length(String text) => text.runes.length;

  static String? passwordProblem(String password, {required String username}) {
    if (_length(password) < minPasswordLength) return 'Das Passwort braucht mindestens 10 Zeichen.';
    if (_length(password) > maxPasswordLength) return 'Das Passwort darf höchstens 128 Zeichen haben.';
    final name = normalizeUsername(username);
    if (name.isNotEmpty && password.toLowerCase().contains(name)) {
      return 'Das Passwort darf den Benutzernamen nicht enthalten.';
    }
    if (password.runes.toSet().length < 4) return 'Das Passwort ist zu einfach.';
    return null;
  }

  /// Anzeigename: 1–40 Zeichen, mehrfache Leerzeichen zusammengefasst; leer = Benutzername.
  static String? displayName(String raw) {
    final collapsed = raw.split(_whitespace).where((part) => part.isNotEmpty).join(' ');
    if (collapsed.isEmpty) return '';
    return _length(collapsed) <= 40 ? collapsed : null;
  }

  /// Einladungs- bzw. Wiederherstellungscode vereinheitlichen: Großbuchstaben, ohne Leer- und Bindestriche.
  static String normalizeCode(String text) => text.toUpperCase().split('').where(_codeCharacter.hasMatch).join();
}

/// Einladung zu einem Konto: Server und einmaliger Code, als Link `coach://account?worker=…&invite=…`.
/// Kommt über die Einladungsseite des Workers (`/i/<code>`), die iPhone- und Android-Link anbietet.
final class AccountInvite {
  AccountInvite({required this.workerURL, required String code}) : code = AccountRules.normalizeCode(code);

  final String workerURL;
  final String code;

  String get id => code;

  static AccountInvite? fromUri(Uri url) {
    if (url.scheme != LeagueInvite.scheme || url.host != 'account') return null;
    final items = queryItems(url);
    final worker = items['worker'] ?? '';
    final code = AccountRules.normalizeCode(items['invite'] ?? '');
    if (!worker.startsWith('https://') || urlHost(worker) == null || code.length != 10) return null;
    return AccountInvite(workerURL: worker, code: code);
  }

  String? get host => urlHost(workerURL);

  Uri? get url => Uri.tryParse(
    '${LeagueInvite.scheme}://account?worker=${percentEncodeUnreserved(workerURL)}'
    '&invite=${percentEncodeUnreserved(code)}',
  );

  /// Link zum Weitergeben: Seite des Workers, funktioniert in jeder Nachrichten-App und auf Android.
  Uri? get shareURL {
    final base = Uri.tryParse(workerURL);
    if (base == null) return null;
    final path = base.path.endsWith('/') ? '${base.path}i/$code' : '${base.path}/i/$code';
    return base.replace(path: path);
  }

  @override
  bool operator ==(Object other) => other is AccountInvite && other.workerURL == workerURL && other.code == code;

  @override
  int get hashCode => Object.hash(workerURL, code);
}
