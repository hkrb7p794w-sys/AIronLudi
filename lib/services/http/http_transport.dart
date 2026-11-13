import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// HTTP-Anfrage unabhängig vom Client (wie `URLRequest`).
final class HttpRequest {
  const HttpRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.timeout = const Duration(seconds: 30),
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int>? body;
  final Duration timeout;

  @override
  String toString() => 'HttpRequest($method $url)';
}

/// Antwort mit Status, Kopfzeilen (Namen klein geschrieben) und Rohdaten.
final class HttpResponse {
  HttpResponse(this.status, List<int> body, {Map<String, String>? headers})
    : body = body is Uint8List ? body : Uint8List.fromList(body),
      headers = headers ?? const {};

  final int status;
  final Uint8List body;
  final Map<String, String> headers;

  bool get isSuccess => status >= 200 && status < 300;
}

/// Keine Antwort (Netz weg, Zeitüberschreitung, TLS) – wie ein `URLError`.
final class HttpTransportException implements Exception {
  const HttpTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sendet Anfragen; im Test durch [FakeHttpTransport] ersetzt.
abstract interface class HttpTransport {
  /// Jeder Status ist eine Antwort; nur fehlende Antworten werfen [HttpTransportException].
  Future<HttpResponse> send(HttpRequest request);

  void close();
}

/// Erzeugt Transporte; `cookies: true` entspricht einer eigenen `URLSession` mit Cookie-Speicher (Anmeldung).
typedef HttpTransportFactory = HttpTransport Function({bool cookies});

/// Transport über dio. Weiterleitungen folgt er wie `URLSession`.
final class DioTransport implements HttpTransport {
  DioTransport({bool cookies = false, Dio? dio}) : _dio = dio ?? Dio() {
    final options = _dio.options;
    options.responseType = ResponseType.bytes;
    options.validateStatus = (_) => true;
    options.followRedirects = true;
    options.maxRedirects = 10;
    if (cookies) _dio.interceptors.add(CookieManager(CookieJar()));
  }

  static HttpTransport create({bool cookies = false}) => DioTransport(cookies: cookies);

  final Dio _dio;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    try {
      final response = await _dio.requestUri<List<int>>(
        request.url,
        data: request.body == null ? null : Stream.fromIterable([request.body!]),
        options: Options(
          method: request.method,
          headers: {...request.headers, if (request.body != null) Headers.contentLengthHeader: request.body!.length},
          sendTimeout: request.timeout,
          receiveTimeout: request.timeout,
        ),
      );
      return HttpResponse(
        response.statusCode ?? 0,
        response.data ?? const [],
        headers: {
          for (final MapEntry(:key, :value) in response.headers.map.entries) key.toLowerCase(): value.join(', '),
        },
      );
    } on DioException catch (error) {
      throw HttpTransportException(_describe(error));
    }
  }

  static String _describe(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => 'Zeitüberschreitung der Anfrage.',
    DioExceptionType.connectionError => 'Keine Verbindung zum Server.',
    DioExceptionType.badCertificate => 'Das Zertifikat des Servers ist ungültig.',
    DioExceptionType.cancel => 'Anfrage abgebrochen.',
    _ => error.message ?? error.error?.toString() ?? 'Unbekannter Netzwerkfehler.',
  };

  @override
  void close() => _dio.close();
}

/// Antwortet nach einer Funktion und merkt sich die Anfragen (Tests).
final class FakeHttpTransport implements HttpTransport {
  FakeHttpTransport(this.handler);

  final FutureOr<HttpResponse> Function(HttpRequest request) handler;
  final List<HttpRequest> requests = [];

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {}
}
