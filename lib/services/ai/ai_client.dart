import 'dart:convert';
import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:crypto/crypto.dart';

import '../../data/secure/secret_store.dart';
import '../../data/settings/settings_store.dart';
import '../http/http_transport.dart';

/// Antwort des Workers auf eine KI-Aufgabe.
final class AIResponse {
  const AIResponse({required this.output, required this.model, required this.provider, this.usage});

  final JsonValue output;
  final String model;
  final String provider;
  final AIResponseUsage? usage;

  /// Wie `JSONDecoder().decode(AIResponse.self, …)`: Pflichtfelder fehlen → `null`.
  static AIResponse? fromJson(Object? json) {
    if (json is! Map || !json.containsKey('output')) return null;
    final (model, provider) = (json['model'], json['provider']);
    if (model is! String || provider is! String) return null;
    final rawUsage = json['usage'];
    AIResponseUsage? usage;
    if (rawUsage != null) {
      usage = AIResponseUsage.fromJson(rawUsage);
      if (usage == null) return null;
    }
    return AIResponse(output: JsonValue(json['output']), model: model, provider: provider, usage: usage);
  }
}

final class AIResponseUsage {
  const AIResponseUsage({required this.inputTokens, required this.outputTokens, this.listPriceUsd});

  final int inputTokens;
  final int outputTokens;
  final double? listPriceUsd;

  static AIResponseUsage? fromJson(Object? json) {
    if (json is! Map) return null;
    final (input, output, price) = (json['inputTokens'], json['outputTokens'], json['listPriceUsd']);
    if (input is! num || output is! num || input != input.roundToDouble() || output != output.roundToDouble()) {
      return null;
    }
    if (price != null && price is! num) return null;
    return AIResponseUsage(
      inputTokens: input.toInt(),
      outputTokens: output.toInt(),
      listPriceUsd: (price as num?)?.toDouble(),
    );
  }
}

/// Fehler im Umgang mit dem Worker (wie `AIClientError`).
sealed class AIClientError implements Exception {
  const AIClientError();

  static const notConfigured = _AIPlain(
    'notConfigured',
    'KI-Worker ist nicht eingerichtet (Adresse und App-Token in den Einstellungen).',
  );
  static const invalidURL = _AIPlain('invalidURL', 'Die Worker-Adresse muss mit https:// beginnen.');
  static const unauthorized = _AIPlain('unauthorized', 'Der Worker hat das App-Token abgelehnt.');

  /// Die Sitzung des Kontos gilt nicht mehr (abgemeldet, Passwort geändert, abgelaufen).
  static const signedOut = _AIPlain(
    'signedOut',
    'Deine Anmeldung gilt nicht mehr. Bitte unter Einstellungen › Konto neu anmelden.',
  );

  const factory AIClientError.http(int status, String message) = AIHttpError;
  const factory AIClientError.network(String detail) = AINetworkError;

  /// Die KI-Stufe in den Einstellungen erlaubt diese Anfrage nicht.
  const factory AIClientError.disabled(String message) = AIDisabledError;

  String get message;

  @override
  String toString() => message;
}

final class _AIPlain extends AIClientError {
  const _AIPlain(this.name, this.message);

  final String name;

  @override
  final String message;

  @override
  bool operator ==(Object other) => other is _AIPlain && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

final class AIHttpError extends AIClientError {
  const AIHttpError(this.status, this.message);

  final int status;

  @override
  final String message;

  @override
  bool operator ==(Object other) => other is AIHttpError && other.status == status && other.message == message;

  @override
  int get hashCode => Object.hash(status, message);
}

final class AINetworkError extends AIClientError {
  const AINetworkError(this.detail);

  final String detail;

  @override
  String get message => 'Netzwerkfehler: $detail';

  @override
  bool operator ==(Object other) => other is AINetworkError && other.detail == detail;

  @override
  int get hashCode => detail.hashCode;
}

final class AIDisabledError extends AIClientError {
  const AIDisabledError(this.message);

  @override
  final String message;

  @override
  bool operator ==(Object other) => other is AIDisabledError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Bild für KI-Aufgaben (JPEG, bereits verkleinert).
final class AIImage {
  const AIImage({required this.mimeType, required this.data});

  final String mimeType;
  final Uint8List data;
}

/// Welches Token eine Anfrage trägt.
enum AIAuth {
  /// Sitzung des Kontos, sonst App-Token.
  preferred,

  /// Nur das App-Token (Betreiber-Funktionen, Registrieren ohne Einladungscode).
  appToken,

  /// Nur die Sitzung.
  session,

  /// Ohne Token (Anmelden, Wiederherstellen).
  none,
}

/// Spricht mit dem Cloudflare Worker, der die KI-Anfragen weiterreicht. Die KI-Keys liegen nur dort; die App kennt nur
/// die Worker-Adresse und ein eigenes App-Token (im sicheren Speicher).
final class AIClient {
  AIClient({required this._secrets, required this._settings, HttpTransport? transport, DateTime Function()? clock})
    : _transport = transport ?? DioTransport(),
      _clock = clock ?? DateTime.now;

  static const urlKey = SettingsKeys.workerURL;

  final Secrets _secrets;
  final SettingsStore _settings;
  final HttpTransport _transport;
  final DateTime Function() _clock;

  /// Eigene Quellen aus den Einstellungen; gehen bei jeder passenden Aufgabe als belegte Regeln mit.
  List<UserSource> Function() userSources = () => const [];

  /// KI-Stufe und Anbieter (aus den Einstellungen); gilt für jede Aufgabe.
  AISettings Function() settings = () => const AISettings();

  /// Meldet jede Anfrage für das interne Nutzungsprotokoll (ohne Inhalte).
  void Function(AIUsageEntry entry) onUsage = (_) {};

  /// Meldet, dass der Worker die Sitzung abgelehnt hat (das Konto zeigt dann „abgemeldet“).
  void Function() onSessionRejected = () {};

  String get workerURL => _settings.string(urlKey) ?? '';

  bool get hasToken => (_secrets.string(SecretKey.aiAppToken) ?? '').isNotEmpty;

  /// Sitzung des eigenen Kontos; hat Vorrang vor dem App-Token (Betreiber- oder Gast-Token).
  String? get sessionToken => _nonEmpty(_secrets.string(SecretKey.accountSession));

  bool get hasSession => sessionToken != null;

  Future<void> setSession(String? token) => _secrets.set(SecretKey.accountSession, token);

  bool get isConfigured => normalizedURL(workerURL) != null && (hasToken || hasSession);

  /// App-Token für die Anmeldung am Worker.
  String? get appToken => _nonEmpty(_secrets.string(SecretKey.aiAppToken));

  /// Token für den Abgleich mit einer Einladung; verlässt die App nicht.
  String? get storedToken => _secrets.string(SecretKey.aiAppToken);

  /// Eingeladen (Gast-Token) statt Betreiber:in des Workers.
  bool get isGuest => appToken != null && GuestToken.isGuest(appToken!);

  /// Haupt-Token hinterlegt: darf Gast-Tokens ausstellen und Konten zurücksetzen.
  bool get isOwner => appToken != null && !isGuest;

  static String? _nonEmpty(String? text) => text == null || text.isEmpty ? null : text;

  /// Private SideStore-Quelle des Workers (`worker/src/sidestore.ts`): Pfad aus SHA-256("sidestore:" + Token). Nur mit
  /// dem Haupt-Token: Ein Gast-Token öffnet die Quelle nicht (`worker/src/auth.ts`).
  Uri? get sideStoreSourceURL {
    final (base, token) = (normalizedURL(workerURL), _ownerToken);
    if (base == null || token == null) return null;
    return appendingPath(base, 'sidestore/${sideStoreKey(token)}/source.json');
  }

  /// Private Download-Seite der Android-App (`worker/src/android.ts`): Pfad aus SHA-256("android:" + Token). Wie die
  /// SideStore-Quelle nur mit dem Haupt-Token.
  Uri? get androidDownloadURL {
    final (base, token) = (normalizedURL(workerURL), _ownerToken);
    if (base == null || token == null) return null;
    return appendingPath(base, 'android/${secretPath(prefix: 'android', token: token)}/');
  }

  String? get _ownerToken {
    final token = _secrets.string(SecretKey.aiAppToken);
    if (token == null || token.isEmpty || GuestToken.isGuest(token)) return null;
    return token;
  }

  static String secretPath({required String prefix, required String token}) =>
      sha256.convert(utf8.encode('$prefix:$token')).toString().substring(0, 32);

  static String sideStoreKey(String token) => secretPath(prefix: 'sidestore', token: token);

  /// Speichert Adresse und (falls angegeben) Token. Ein leeres Token-Feld lässt das gespeicherte stehen, außer der
  /// Server wechselt: Dann wird es gelöscht, damit es nie an eine andere Adresse geht.
  Future<void> configure({required String url, required String token}) async {
    final normalized = normalizedURL(url);
    if (normalized == null) throw AIClientError.invalidURL;
    final previousHost = normalizedURL(workerURL)?.host.toLowerCase();
    await _settings.setString(urlKey, normalized.toString());
    final trimmed = token.trim();
    final serverChanged = previousHost != normalized.host.toLowerCase();
    if (trimmed.isNotEmpty) {
      await _secrets.set(SecretKey.aiAppToken, trimmed);
    } else if (serverChanged) {
      await _secrets.set(SecretKey.aiAppToken, null);
    }
    // Eine Sitzung gehört zu genau einem Server.
    if (serverChanged) await _secrets.set(SecretKey.accountSession, null);
  }

  /// `https://…` mit Host, ohne abschließende Schrägstriche; sonst `null`.
  static Uri? normalizedURL(String text) {
    var trimmed = text.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final url = Uri.tryParse(trimmed);
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
    return url;
  }

  /// Wie `URL.appending(path:)`: Pfad mit Schrägstrich anhängen.
  static Uri appendingPath(Uri base, String path) {
    final text = base.toString();
    return Uri.parse(text.endsWith('/') ? '$text$path' : '$text/$path');
  }

  /// Darf die Aufgabe laufen? Für Knöpfe und automatische Abläufe, bevor sie die KI fragen.
  bool allows(String task, {AITrigger trigger = AITrigger.user}) =>
      isConfigured && AIPolicy.allows(settings().mode, task: task, trigger: trigger);

  /// `trigger: automatic` für alles, was ohne Antippen startet (z. B. Notiz beim Öffnen).
  Future<AIResponse> run(
    String task, {
    Map<String, Object?> input = const {},
    List<AIImage> images = const [],
    AITrigger trigger = AITrigger.user,
  }) async {
    final current = settings();
    if (!AIPolicy.allows(current.mode, task: task, trigger: trigger)) {
      throw AIClientError.disabled(AIPolicy.blockedMessage(current.mode));
    }
    final started = _clock();
    try {
      final response = await _generate(task, input, images, current.provider);
      onUsage(
        AIUsageEntry(
          date: started,
          task: task,
          trigger: trigger,
          provider: response.provider,
          model: response.model,
          ok: true,
          inputTokens: response.usage?.inputTokens,
          outputTokens: response.usage?.outputTokens,
          listPriceUsd: response.usage?.listPriceUsd,
          milliseconds: _milliseconds(started),
        ),
      );
      return response;
    } on Object catch (error) {
      if (error != AIClientError.notConfigured) {
        onUsage(
          AIUsageEntry(
            date: started,
            task: task,
            trigger: trigger,
            provider: null,
            model: null,
            ok: false,
            milliseconds: _milliseconds(started),
            error: '$error',
          ),
        );
      }
      rethrow;
    }
  }

  int _milliseconds(DateTime start) => _clock().difference(start).inMilliseconds;

  Future<AIResponse> _generate(
    String task,
    Map<String, Object?> input,
    List<AIImage> images,
    AIProviderChoice provider,
  ) async {
    final body = <String, Object?>{
      'task': task,
      'input': UserSources.inject(userSources(), input, task: task),
      'provider': provider.rawValue,
      if (images.isNotEmpty)
        'images': [
          for (final image in images) {'mimeType': image.mimeType, 'data': base64Encode(image.data)},
        ],
    };
    final data = await send(
      'v1/ai/generate',
      method: 'POST',
      body: utf8.encode(jsonEncode(body)),
      timeout: const Duration(seconds: 120),
    );
    final response = AIResponse.fromJson(_decode(data));
    if (response == null) throw AIClientError.network('Unerwartete Antwort des Workers.');
    return response;
  }

  /// Neues Gast-Token für eine Einladung (nur mit dem Haupt-Token).
  Future<String> createGuestToken() async {
    final data = await send('v1/invite', method: 'POST', auth: AIAuth.appToken);
    final token = switch (_decode(data)) {
      {'token': final String token} => token,
      _ => null,
    };
    if (token == null) throw AIClientError.network('Unerwartete Antwort des Workers.');
    return token;
  }

  static Object? _decode(List<int> data) {
    try {
      return jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
  }

  /// Anfrage an den Worker; liefert den Antwortkörper bei Status 2xx.
  Future<Uint8List> send(
    String path, {
    required String method,
    List<int>? body,
    Map<String, String> query = const {},
    Duration timeout = const Duration(seconds: 30),
    AIAuth auth = AIAuth.preferred,
  }) async {
    final base = normalizedURL(workerURL);
    if (base == null) throw AIClientError.notConfigured;
    final token = switch (auth) {
      AIAuth.preferred => sessionToken ?? appToken,
      AIAuth.appToken => appToken,
      AIAuth.session => sessionToken,
      AIAuth.none => null,
    };
    if (auth != AIAuth.none && token == null) throw AIClientError.notConfigured;
    final usedSession = token != null && token == sessionToken;
    var url = appendingPath(base, path);
    if (query.isNotEmpty) {
      final encoded = [
        for (final MapEntry(:key, :value) in query.entries)
          '${percentEncodeUnreserved(key)}=${percentEncodeUnreserved(value)}',
      ].join('&');
      url = Uri.parse('$url?$encoded');
    }
    final HttpResponse response;
    try {
      response = await _transport.send(
        HttpRequest(
          method: method,
          url: url,
          headers: {'Content-Type': 'application/json', 'Authorization': ?(token == null ? null : 'Bearer $token')},
          body: body,
          timeout: timeout,
        ),
      );
    } on HttpTransportException catch (error) {
      throw AIClientError.network(error.message);
    }
    final status = response.status;
    if (response.isSuccess) return response.body;
    // 401 ohne Token (z. B. falsches Passwort) trägt eine eigene Meldung des Workers.
    if (status == 401 && auth != AIAuth.none) {
      if (usedSession) {
        onSessionRejected();
        throw AIClientError.signedOut;
      }
      throw AIClientError.unauthorized;
    }
    final failure = _decode(response.body);
    final (detail, code) = switch (failure) {
      {'error': final String error} => (error, failure['code'] is String ? failure['code'] as String : null),
      _ => (null, null),
    };
    throw AIClientError.http(
      status,
      AIErrorText.message(status: status, code: code, detail: detail ?? 'Unbekannter Fehler (Fehlercode $status).'),
    );
  }
}
