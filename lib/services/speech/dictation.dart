import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Spracherkennung des Geräts; in Tests nachgebildet.
abstract interface class SpeechEngine {
  /// Erlaubnis für Mikrofon und Spracherkennung einholen; `false` ohne Erlaubnis oder Erkennung.
  Future<bool> initialize({required void Function(String error) onError});

  /// Startet die Aufnahme; [onResult] bekommt den bisher erkannten Text und ob er endgültig ist.
  Future<void> listen({required String localeId, required void Function(String text, bool finished) onResult});

  Future<void> stop();
}

/// Umsetzung mit `speech_to_text` (Apple-Spracherkennung bzw. Android-Spracherkennung).
final class DeviceSpeechEngine implements SpeechEngine {
  final SpeechToText _speech = SpeechToText();

  @override
  Future<bool> initialize({required void Function(String error) onError}) =>
      _speech.initialize(onError: (SpeechRecognitionError error) => onError(error.errorMsg));

  @override
  Future<void> listen({required String localeId, required void Function(String text, bool finished) onResult}) =>
      _speech.listen(
        onResult: (SpeechRecognitionResult result) => onResult(result.recognizedWords, result.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          partialResults: true,
          autoPunctuation: true,
          listenMode: ListenMode.dictation,
        ),
      );

  @override
  Future<void> stop() => _speech.stop();
}

/// Diktieren auf Deutsch mit der Spracherkennung des Geräts. Braucht weder Entitlement noch bezahlten Account – nur
/// die Erlaubnis für Mikrofon und Spracherkennung.
final class Dictation extends ChangeNotifier {
  Dictation({SpeechEngine? engine}) : _engine = engine ?? DeviceSpeechEngine();

  static const localeId = 'de_DE';

  final SpeechEngine _engine;

  bool isRecording = false;

  /// Bisher erkannter Text der laufenden Aufnahme (wächst während des Sprechens).
  String transcript = '';
  String? error;

  /// Erkennung läuft auf dem Gerät (nichts verlässt das Gerät). Das Plugin meldet das nicht, siehe `docs/decisions.md`.
  bool isOnDevice = false;

  Future<void> toggle() => isRecording ? stop() : start();

  Future<void> start() async {
    error = null;
    final bool ready;
    try {
      ready = await _engine.initialize(onError: _failed);
    } on Object {
      error = 'Spracherkennung ist gerade nicht verfügbar.';
      notifyListeners();
      return;
    }
    if (!ready) {
      error = 'Mikrofon oder Spracherkennung nicht erlaubt – in den Einstellungen › AIronLudi einschalten.';
      notifyListeners();
      return;
    }
    transcript = '';
    try {
      await _engine.listen(localeId: localeId, onResult: _receive);
      isRecording = true;
    } on Object catch (failure) {
      await _engine.stop();
      error = 'Aufnahme ließ sich nicht starten: $failure';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _engine.stop();
    isRecording = false;
    notifyListeners();
  }

  void _receive(String text, bool finished) {
    transcript = text;
    if (finished) {
      isRecording = false;
      _engine.stop();
    }
    notifyListeners();
  }

  void _failed(String _) {
    // „Kein Sprachsignal“ nach Stopp ist kein Fehler, wenn schon Text da ist.
    if (transcript.isEmpty) error = 'Nichts verstanden – bitte noch einmal.';
    isRecording = false;
    notifyListeners();
  }
}
