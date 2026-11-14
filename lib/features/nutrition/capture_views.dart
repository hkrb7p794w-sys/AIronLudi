import 'dart:async';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/nutrition/meal_photo.dart';
import '../../services/providers.dart';
import 'meal_shortcuts.dart';

/// Weitere Wege aus dem Erfassen-Bildschirm.
enum CaptureOther { barcode, quick, manual }

/// Ergebnis des Erfassen-Bildschirms: Analyse von Text/Foto oder ein anderer Weg.
sealed class CaptureResult {
  const CaptureResult();
}

final class CaptureAnalyze extends CaptureResult {
  const CaptureAnalyze(this.text, this.photo);

  final String text;
  final Uint8List? photo;
}

final class CaptureChoose extends CaptureResult {
  const CaptureChoose(this.other);

  final CaptureOther other;
}

/// Foto (Kamera oder Mediathek) bereits verkleinert und ohne Metadaten; `null` bei Abbruch.
Future<Uint8List?> pickMealPhoto(ImageSource source) async {
  final file = await ImagePicker().pickImage(source: source, requestFullMetadata: false);
  if (file == null) return null;
  return MealPhoto.jpeg(await file.readAsBytes());
}

/// Ein Bildschirm für alles: Foto (Kamera oder Mediathek) und Beschreibung zusammen – „Foto + ohne Soße“ ist ein
/// Vorgang. „Sprechen“ diktiert auf Deutsch in das Textfeld (zum Korrigieren vor dem Analysieren). Darunter die
/// anderen Wege (Port von `CaptureSheet`).
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, this.shortcuts = const CaptureShortcuts(), this.pickPhoto = pickMealPhoto});

  final CaptureShortcuts shortcuts;
  final Future<Uint8List?> Function(ImageSource source) pickPhoto;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Uint8List? _photo;

  /// Text vor der laufenden Aufnahme; das Diktat wird angehängt.
  String _textBeforeDictation = '';
  String _lastTranscript = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final photo = await widget.pickPhoto(source);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  void _finish(CaptureResult result) {
    final dictation = ref.read(dictationProvider);
    if (dictation.isRecording) unawaited(dictation.stop());
    Navigator.of(context).pop(result);
  }

  Widget _way(String title, IconData icon, CaptureOther other) => Expanded(
    child: Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56), padding: EdgeInsets.zero),
        onPressed: () => _finish(CaptureChoose(other)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 2),
            FittedBox(child: Text(title, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dictation = ref.watch(dictationProvider);
    // Diktat ins Feld übernehmen, sobald neuer Text erkannt wurde.
    if (dictation.transcript.isNotEmpty && dictation.transcript != _lastTranscript) {
      _lastTranscript = dictation.transcript;
      final spoken = dictation.transcript;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _text.text = _textBeforeDictation.isEmpty ? spoken : '$_textBeforeDictation $spoken';
      });
    }
    final theme = Theme.of(context);
    final canAnalyze = _text.text.trim().isNotEmpty || _photo != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Erfassen'),
        leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        leadingWidth: 100,
        actions: [
          TextButton(
            onPressed: canAnalyze ? () => _finish(CaptureAnalyze(_text.text, _photo)) : null,
            child: const Text('Analysieren', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Erst die Wege zum Erfassen, ohne Scrollen erreichbar; Vorschläge und Rezepte kommen danach.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Kamera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('Foto'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              spacing: 8,
              children: [
                _way('Barcode', Icons.qr_code_scanner, CaptureOther.barcode),
                _way('Manuell', Icons.edit_note, CaptureOther.manual),
                _way('Nur kcal', Icons.bolt, CaptureOther.quick),
              ],
            ),
          ),
          if (_photo case final photo?)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(photo, width: 64, height: 64, fit: BoxFit.cover),
              ),
              title: Text('Foto ausgewählt', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              trailing: TextButton(
                onPressed: () => setState(() => _photo = null),
                child: const Text('Entfernen', style: TextStyle(color: Colors.red)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _text,
              focusNode: _focus,
              minLines: 2,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'z. B. 200 g Hähnchen, 1 EL Öl, 150 g Reis – oder „halbe Portion, ohne Soße“',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Semantics(
              hint: 'Mahlzeit auf Deutsch diktieren, der Text erscheint im Feld darüber',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: dictation.isRecording ? Colors.red : null,
                ),
                onPressed: () {
                  if (!dictation.isRecording) {
                    _focus.unfocus();
                    _textBeforeDictation = _text.text.trim();
                    _lastTranscript = '';
                  }
                  unawaited(dictation.toggle());
                },
                icon: Icon(dictation.isRecording ? Icons.stop_circle : Icons.mic),
                label: Text(dictation.isRecording ? 'Fertig gesprochen' : 'Sprechen'),
              ),
            ),
          ),
          if (dictation.error case final error?)
            ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber, color: Colors.orange),
              title: Text(error, style: const TextStyle(color: Colors.orange)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              dictation.isRecording
                  ? 'Hört zu … Die Spracherkennung des Geräts wandelt die Sprache in Text um.'
                  : 'Mengen nennen, wenn bekannt – auch mehrere Mahlzeiten auf einmal. Tippen auf „Sprechen“ diktiert, '
                        'praktisch beim Kochen.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          CaptureShortcutsSection(shortcuts: widget.shortcuts, done: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

/// Barcode ohne Treffer: selbst anlegen (Etikett abtippen) oder die Nährwerttabelle fotografieren.
/// Ergebnis: `null` (Abbruch), ein Foto der Tabelle oder [MissingBarcodeSheet.create].
class MissingBarcodeSheet extends StatelessWidget {
  const MissingBarcodeSheet({super.key, required this.barcode, this.pickPhoto = pickMealPhoto});

  /// Rückgabewert für „Werte selbst eintragen“.
  static const create = 'create';

  final String barcode;
  final Future<Uint8List?> Function(ImageSource source) pickPhoto;

  @override
  Widget build(BuildContext context) {
    Future<void> photograph(ImageSource source) async {
      final photo = await pickPhoto(source);
      if (photo != null && context.mounted) Navigator.of(context).pop(photo);
    }

    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Produkt unbekannt', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Barcode $barcode ist bei Open Food Facts nicht bekannt. Einmal anlegen – beim nächsten Scan kennt die '
              'App das Produkt.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Nährwerttabelle fotografieren'),
            onTap: () => photograph(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Foto der Tabelle wählen'),
            onTap: () => photograph(ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Werte selbst eintragen'),
            onTap: () => Navigator.of(context).pop(create),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'Die KI liest die Werte je 100 g nur ab; du prüfst sie vor dem Speichern.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barcode per Kamera oder von Hand eingeben; gibt die Ziffern zurück.
class BarcodeEntryScreen extends StatefulWidget {
  const BarcodeEntryScreen({super.key, this.showsScanner = true});

  /// Im Test ohne Kamera.
  final bool showsScanner;

  @override
  State<BarcodeEntryScreen> createState() => _BarcodeEntryScreenState();
}

class _BarcodeEntryScreenState extends State<BarcodeEntryScreen> {
  final _manual = TextEditingController();
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _manual.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _finish(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (_reported || !OpenFoodFacts.isValidBarcode(digits)) return;
    _reported = true;
    Navigator.of(context).pop(digits);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Barcode'),
      leading: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
      leadingWidth: 100,
    ),
    body: Column(
      children: [
        Expanded(
          child: widget.showsScanner
              ? MobileScanner(
                  controller: MobileScannerController(
                    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcE],
                  ),
                  onDetect: (capture) {
                    for (final barcode in capture.barcodes) {
                      if (barcode.rawValue case final code?) _finish(code);
                    }
                  },
                  errorBuilder: (context, _) => const _ScannerUnavailable(),
                )
              : const _ScannerUnavailable(),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manual,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: 'Barcode eingeben', border: OutlineInputBorder()),
                    onSubmitted: _finish,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: OpenFoodFacts.isValidBarcode(_manual.text) ? () => _finish(_manual.text) : null,
                  child: const Text('Suchen'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_scanner, size: 48),
          SizedBox(height: 12),
          Text('Kamera-Scan nicht verfügbar', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('Barcode unten eingeben.'),
        ],
      ),
    ),
  );
}
