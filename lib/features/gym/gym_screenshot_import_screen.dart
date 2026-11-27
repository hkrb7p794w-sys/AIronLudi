import 'dart:typed_data';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../data/storage.dart';
import '../../services/nutrition/meal_photo.dart';
import '../../services/providers.dart';
import '../../ui/components.dart';
import '../../ui/liquid.dart';
import '../../ui/tokens.dart';
import 'gym_screenshot_controller.dart';

/// Screenshots aus der Mediathek (höchstens vier), verkleinert und ohne Metadaten; leer bei Abbruch.
Future<List<Uint8List>> pickWorkoutScreenshots() async {
  final files = await ImagePicker().pickMultiImage(
    limit: GymScreenshotController.maxImages,
    requestFullMetadata: false,
  );
  return [
    for (final file in files.take(GymScreenshotController.maxImages))
      ?await MealPhoto.screenshot(await file.readAsBytes()),
  ];
}

/// Krafttraining aus Screenshots übernehmen: Anleitung, Bilder wählen, Ergebnis prüfen und sichern.
class GymScreenshotImportScreen extends ConsumerStatefulWidget {
  const GymScreenshotImportScreen({super.key, this.pickImages = pickWorkoutScreenshots});

  final Future<List<Uint8List>> Function() pickImages;

  @override
  ConsumerState<GymScreenshotImportScreen> createState() => _GymScreenshotImportScreenState();
}

class _GymScreenshotImportScreenState extends ConsumerState<GymScreenshotImportScreen> {
  late final GymScreenshotController _controller = GymScreenshotController(
    ai: ref.read(aiClientProvider),
    gym: ref.read(gymRepositoryProvider),
    settings: ref.read(coachSettingsProvider),
    activities: () => ref.read(activityRepositoryProvider).all(),
  )..addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final images = await widget.pickImages();
    if (images.isNotEmpty && mounted) await _controller.analyze(images);
  }

  Future<void> _save() async {
    final message = await _controller.save();
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop(true);
  }

  Future<void> _changeDate() async {
    final session = _controller.session;
    if (session == null) return;
    final start = session.start;
    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('de'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    final at = time ?? TimeOfDay.fromDateTime(start);
    await _controller.moveTo(DateTime(date.year, date.month, date.day, at.hour, at.minute));
  }

  Future<void> _editSet(LoggedExercise exercise, LoggedSet set) async {
    final reps = TextEditingController(text: '${set.reps}');
    final weight = TextEditingController(text: set.weightKg == 0 ? '' : GermanFormat.number(set.weightKg));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exercise.name),
        contentPadding: const EdgeInsets.only(top: LiquidSpacing.m),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NumberField(label: 'Wiederholungen bzw. Sekunden', controller: reps, decimal: false),
            NumberField(label: 'Gewicht in kg (leer = Körpergewicht)', controller: weight),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Satz löschen', style: TextStyle(color: AppColors.of(context).alert)),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Übernehmen')),
        ],
      ),
    );
    if (result == false) {
      _controller.removeSet(exercise, set);
    } else if (result == true) {
      final count = int.tryParse(reps.text.trim());
      if (count != null && count > 0) {
        _controller.updateSet(set, reps: count, weightKg: parseNumber(weight.text) ?? 0);
      }
    }
    reps.dispose();
    weight.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final session = controller.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aus Screenshots'),
        actions: [
          if (session != null)
            TextButton(
              onPressed: controller.isWorking || session.exercises.isEmpty ? null : _save,
              child: const Text('Sichern', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (controller.isWorking)
            const FormSection(
              footer:
                  'Die KI liest Übungen, Sätze, Wiederholungen und Gewichte ab. Das kann bis zu einer Minute dauern.',
              children: [
                ListTile(
                  leading: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  title: Text('Wird ausgelesen …'),
                ),
              ],
            )
          else if (session == null) ...[
            _instructions(context),
            if (controller.errorMessage case final message?) _error(message),
          ] else
            ..._review(context, session),
        ],
      ),
    );
  }

  Widget _instructions(BuildContext context) => FormSection(
    header: 'So geht’s',
    footer: !controller.isAvailable
        ? 'Dafür den KI-Worker unter Ich › KI einrichten bzw. die KI einschalten.'
        : 'Die Bilder gehen nur zum Auslesen an die KI und werden nicht gespeichert. Du prüfst alles vor dem Sichern.',
    children: [
      const ListTile(
        leading: Text('1'),
        title: Text('In WHOOP das Krafttraining öffnen und unter den Übungen „Alle anzeigen“ tippen.'),
      ),
      const ListTile(
        leading: Text('2'),
        title: Text(
          'Screenshots der Übungsliste machen – bei langen Listen mehrere (bis zu 4), gern auch den Kopf mit '
          'Datum und Uhrzeit.',
        ),
      ),
      const ListTile(
        leading: Text('3'),
        title: Text('Hier die Screenshots wählen. Klappt auch mit Hevy, Strong und anderen Apps.'),
      ),
      ListTile(
        leading: Icon(Icons.photo_library_outlined, color: Theme.of(context).colorScheme.primary),
        title: const Text('Screenshots wählen'),
        textColor: Theme.of(context).colorScheme.primary,
        enabled: controller.isAvailable,
        onTap: _pick,
      ),
    ],
  );

  GymScreenshotController get controller => _controller;

  Widget _error(String message) => FormSection(
    header: 'Hat nicht geklappt',
    footer: 'Die Bilder sind noch da – erneut versuchen oder andere wählen.',
    children: [
      ListTile(
        leading: Icon(Icons.error_outline, color: AppColors.of(context).alert),
        title: Text(message),
      ),
      ListTile(leading: const Icon(Icons.refresh), title: const Text('Erneut versuchen'), onTap: controller.retry),
      ListTile(
        leading: const Icon(Icons.photo_library_outlined),
        title: const Text('Andere Screenshots'),
        onTap: _pick,
      ),
    ],
  );

  List<Widget> _review(BuildContext context, GymSession session) {
    final end = session.end;
    final when =
        '${DateFormat('EEE, d. MMM yyyy', 'de_DE').format(session.start)} · '
        '${DateFormat.Hm('de_DE').format(session.start)}${end == null ? '' : '–${DateFormat.Hm('de_DE').format(end)}'}';
    final newIDs = {for (final info in controller.newCustom) info.id};
    return [
      FormSection(
        header: 'Einheit',
        footer: [
          if (controller.guessedDate) 'Datum oder Uhrzeit standen nicht auf den Bildern – bitte prüfen.',
          if (controller.sameDay.isNotEmpty)
            'Am selben Tag gibt es schon: ${controller.sameDay.join(', ')}. Beide bleiben gespeichert.',
          'Antippen, um einen Satz zu ändern oder zu löschen.',
        ].join(' '),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LiquidSpacing.l),
            child: TextFormField(
              initialValue: session.title,
              decoration: const InputDecoration(labelText: 'Name', border: InputBorder.none),
              onChanged: controller.rename,
            ),
          ),
          ListTile(
            title: const Text('Wann'),
            subtitle: Text(when),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _changeDate,
          ),
          LabeledRow(label: 'Bewegte Last', value: '${GermanFormat.number(session.volumeKg)} kg'),
        ],
      ),
      for (final exercise in [...session.exercises])
        FormSection(
          header: newIDs.contains(exercise.exerciseID) ? '${exercise.name} · neue Übung' : exercise.name,
          children: [
            for (final (index, set) in exercise.sets.indexed)
              ListTile(
                title: Text('Satz ${index + 1}'),
                trailing: Text(
                  set.weightKg > 0 ? '${GermanFormat.number(set.weightKg)} kg × ${set.reps}' : '${set.reps} Wdh.',
                  style: AppText.body(context),
                ),
                onTap: () => _editSet(exercise, set),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.of(context).alert),
              title: Text('Übung entfernen', style: TextStyle(color: AppColors.of(context).alert)),
              onTap: () => controller.removeExercise(exercise),
            ),
          ],
        ),
      if (session.exercises.isEmpty) const FormSection(children: [ListTile(title: Text('Keine Übungen mehr übrig.'))]),
      Padding(
        padding: const EdgeInsets.fromLTRB(LiquidSpacing.page, LiquidSpacing.l, LiquidSpacing.page, 0),
        child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: session.exercises.isEmpty ? null : _save,
          child: const Text('Einheit sichern'),
        ),
      ),
    ];
  }
}
