import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../data/backup/backup_service.dart';
import '../../data/settings/settings_store.dart';
import '../../data/storage.dart';
import '../../ui/components.dart';

/// Datensicherung: automatisch in einen Ordner, als Datei teilen, Sicherung einspielen.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  File? _shared;

  static String format(DateTime date) => DateFormat('d. MMM y, HH:mm', 'de_DE').format(date.toLocal());

  Future<void> _message(String text) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Datensicherung'),
      content: Text(text),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ),
  );

  Future<void> _chooseFolder() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Ordner für die Sicherung');
    if (path == null || !mounted) return;
    final settings = ref.read(settingsStoreProvider);
    await settings.setString(SettingsKeys.backupFolder, path);
    final ok = await ref.read(backupServiceProvider).backupToFolder(force: true);
    setState(() {});
    await _message(
      ok
          ? 'Ordner „${p.basename(path)}“ gewählt und erste Sicherung angelegt.'
          : 'Ordner gewählt, die erste Sicherung hat aber nicht geklappt.',
    );
  }

  Future<void> _backupNow(String folder) async {
    final ok = await ref.read(backupServiceProvider).backupToFolder(force: true);
    setState(() {});
    await _message(ok ? 'Gesichert in „${p.basename(folder)}“.' : 'Sichern hat nicht geklappt.');
  }

  Future<void> _createFile() async {
    try {
      final backup = await ref.read(backupServiceProvider).make();
      final file = File(p.join(Directory.systemTemp.path, BackupService.shareFileName(backup.createdAt)));
      await file.writeAsBytes(backup.encoded());
      setState(() => _shared = file);
    } on Object catch (error) {
      await _message('Sicherung konnte nicht erstellt werden: $error');
    }
  }

  Future<void> _restore() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = files.isEmpty ? null : files.first.path;
    if (path == null || !mounted) return;
    final AppBackup backup;
    try {
      backup = AppBackup.decode(await File(path).readAsBytes());
    } on Object catch (error) {
      await _message('$error');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sicherung einspielen?'),
        content: Text('Sicherung vom ${format(backup.createdAt)}: ${backup.summary}.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Einspielen')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await ref.read(backupServiceProvider).restore(backup);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Sicherung eingespielt'),
          content: Text(
            '${result.text} Damit die Einstellungen gelten, schließt sich AIronLudi jetzt. Öffne die App danach '
            'einfach neu.',
          ),
          actions: [
            FilledButton(onPressed: () => SystemNavigator.pop(animated: true), child: const Text('App schließen')),
          ],
        ),
      );
    } on Object catch (error) {
      await _message('Einspielen hat nicht geklappt: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStoreProvider);
    final folder = settings.string(SettingsKeys.backupFolder);
    final lastSeconds = settings.doubleValue(SettingsKeys.backupLastAuto);
    final last = lastSeconds == null ? null : DateTime.fromMicrosecondsSinceEpoch((lastSeconds * 1e6).round());
    final error = settings.string(SettingsKeys.backupLastError);
    return Scaffold(
      appBar: AppBar(title: const Text('Datensicherung')),
      body: ListView(
        children: [
          FormSection(
            header: 'Automatisch',
            footer:
                'Einmal am Tag, wenn du die App verlässt, sichert AIronLudi in den Ordner – am besten in einen '
                'Cloud-Ordner. Die Datei liegt außerhalb der App und bleibt auch erhalten, wenn AIronLudi gelöscht '
                'wird. Die vorherige Sicherung bleibt als „…-vorher.json“ liegen.',
            children: folder == null
                ? [
                    ListTile(
                      leading: const Icon(Icons.create_new_folder_outlined),
                      title: const Text('Ordner wählen'),
                      onTap: _chooseFolder,
                    ),
                  ]
                : [
                    LabeledRow(label: 'Ordner', value: p.basename(folder)),
                    LabeledRow(label: 'Letzte Sicherung', value: last == null ? 'noch keine' : format(last)),
                    if (error != null)
                      ListTile(
                        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        title: Text(error, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: const Text('Jetzt sichern'),
                      onTap: () => _backupNow(folder),
                    ),
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('Anderen Ordner wählen'),
                      onTap: _chooseFolder,
                    ),
                    ListTile(
                      leading: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                      title: const Text('Automatische Sicherung beenden', style: TextStyle(color: Colors.red)),
                      onTap: () async {
                        await settings.remove(SettingsKeys.backupFolder);
                        setState(() {});
                      },
                    ),
                  ],
          ),
          FormSection(
            header: 'Von Hand',
            children: [
              if (_shared case final file?)
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Sicherung teilen oder in „Dateien“ sichern'),
                  onTap: () => SharePlus.instance.share(ShareParams(files: [XFile(file.path)])),
                )
              else
                ListTile(
                  leading: const Icon(Icons.note_add_outlined),
                  title: const Text('Sicherung erstellen'),
                  onTap: _createFile,
                ),
            ],
          ),
          FormSection(
            header: 'Einspielen',
            footer:
                'Führt zusammen: Vorhandene Krafteinheiten und Mahlzeiten bleiben, fehlende kommen dazu. Die '
                'Einstellungen werden durch die der Sicherung ersetzt. Nicht enthalten sind Zugangsdaten (Garmin, '
                'App-Token) – die gibst du nach einer Neuinstallation neu ein. Garmin- und Health-Werte kommen beim '
                'nächsten Abruf von selbst wieder.',
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Sicherung einspielen'),
                onTap: _restore,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
