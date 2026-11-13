// Diktat mit nachgebildeter Spracherkennung.
import 'package:aironludi/services/speech/dictation.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeSpeech implements SpeechEngine {
  FakeSpeech({this.allowed = true});

  final bool allowed;
  void Function(String text, bool finished)? result;
  void Function(String error)? failure;
  var stopped = 0;

  @override
  Future<bool> initialize({required void Function(String error) onError}) async {
    failure = onError;
    return allowed;
  }

  @override
  Future<void> listen({required String localeId, required void Function(String text, bool finished) onResult}) async {
    expect(localeId, 'de_DE');
    result = onResult;
  }

  @override
  Future<void> stop() async => stopped += 1;
}

void main() {
  test('Text wächst beim Sprechen, endgültiges Ergebnis beendet die Aufnahme', () async {
    final speech = FakeSpeech();
    final dictation = Dictation(engine: speech);
    await dictation.start();
    expect(dictation.isRecording, isTrue);
    speech.result!('Zwei Eier', false);
    expect(dictation.transcript, 'Zwei Eier');
    speech.result!('Zwei Eier und Toast.', true);
    expect(dictation.transcript, 'Zwei Eier und Toast.');
    expect(dictation.isRecording, isFalse);
    // Fehler nach vorhandenem Text bleibt still.
    speech.failure!('error_no_match');
    expect(dictation.error, isNull);
  });

  test('ohne Erlaubnis ein Hinweis', () async {
    final dictation = Dictation(engine: FakeSpeech(allowed: false));
    await dictation.start();
    expect(dictation.isRecording, isFalse);
    expect(dictation.error, contains('nicht erlaubt'));
  });

  test('nichts verstanden', () async {
    final speech = FakeSpeech();
    final dictation = Dictation(engine: speech);
    await dictation.start();
    speech.failure!('error_no_match');
    expect(dictation.error, 'Nichts verstanden – bitte noch einmal.');
  });
}
