import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Plattformteil des gemeinsamen Speichers: Ordner, den App und Widgets teilen, und Neuladen der Widgets.
abstract interface class WidgetHost {
  /// Ordner der App Group (iOS) bzw. der App (Android); `null`, wenn es keinen gibt.
  Future<Directory?> container();

  /// Einträge der Warteschlange unter Dateikoordination entfernen (Widget und App können gleichzeitig schreiben).
  /// `false`: nicht unterstützt, Dart schreibt selbst.
  Future<bool> removeQueueEntries(File file, Set<String> ids);

  Future<void> reloadWidgets();
}

/// iOS: App Group aus dem Provisioning-Profil (SideStore hängt die Team-ID an), Widgets über WidgetKit neu laden.
/// Android: eigener Datenordner der App (Glance-Widgets laufen im selben Prozess). Kanal `aironludi/widgets`.
final class ChannelWidgetHost implements WidgetHost {
  ChannelWidgetHost({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('aironludi/widgets');

  final MethodChannel _channel;
  Directory? _container;
  bool _resolved = false;

  @override
  Future<Directory?> container() async {
    if (_resolved) return _container;
    _resolved = true;
    try {
      if (Platform.isIOS) {
        final profile = await _channel.invokeMethod<Uint8List>('profile');
        final candidates = AppGroupProfile.candidates(profile == null ? const [] : AppGroupProfile.groups(profile));
        for (final group in candidates) {
          final path = await _channel.invokeMethod<String>('containerPath', {'group': group});
          if (path != null) return _container = Directory(path);
        }
      } else if (Platform.isAndroid) {
        return _container = await getApplicationSupportDirectory();
      }
    } on Object {
      // Ohne Plattformteil (Tests, ältere Builds) keine Widgets.
    }
    return null;
  }

  @override
  Future<bool> removeQueueEntries(File file, Set<String> ids) async {
    if (!Platform.isIOS) return false;
    try {
      await _channel.invokeMethod<void>('removeQueueEntries', {'path': file.path, 'ids': ids.toList()});
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> reloadWidgets() async {
    try {
      await _channel.invokeMethod<void>('reload');
    } on Object {
      // Kein Plattformteil.
    }
  }
}

/// Fester Ordner (Tests).
final class DirectoryWidgetHost implements WidgetHost {
  DirectoryWidgetHost(this.directory);

  final Directory? directory;
  int reloads = 0;

  @override
  Future<Directory?> container() async => directory;

  @override
  Future<bool> removeQueueEntries(File file, Set<String> ids) async => false;

  @override
  Future<void> reloadWidgets() async => reloads++;
}

/// Gemeinsamer Speicher von App und Widgets (Port von `WidgetStore`). Ohne Ordner liefern alle Zugriffe `null` und die
/// Widgets bitten ums Öffnen. Gleiche Dateien und gleiches JSON wie in der Swift-App.
final class WidgetStore {
  WidgetStore(this._host);

  final WidgetHost _host;

  /// Widget-Arten (`kind`) – App und Erweiterung nutzen dieselben Namen zum Neuladen.
  static const kindToday = 'io.github.hkrb7p794w.coach.widget.today';
  static const kindNutrition = 'io.github.hkrb7p794w.coach.widget.nutrition';
  static const kindHealth = 'io.github.hkrb7p794w.coach.widget.health';
  static const kindGym = 'io.github.hkrb7p794w.coach.widget.gym';
  static const kindMeals = 'io.github.hkrb7p794w.coach.widget.meals';

  Future<bool> get isAvailable async => await _host.container() != null;

  Future<File?> _file(String name) async => switch (await _host.container()) {
    final folder? => File(p.join(folder.path, name)),
    null => null,
  };

  Future<Object?> _read(String name) async {
    final file = await _file(name);
    if (file == null || !file.existsSync()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on Object {
      return null;
    }
  }

  Future<void> _write(String name, Object json) async {
    final file = await _file(name);
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      // Erst schreiben, dann umbenennen: Das Widget liest nie eine halbe Datei (wie `.atomic`).
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(json), flush: true);
      await temp.rename(file.path);
    } on Object {
      // Widgets behalten den alten Stand.
    }
  }

  Future<WidgetSnapshot?> loadSnapshot() async => WidgetSnapshot.fromJson(await _read(WidgetSnapshot.fileName));

  Future<void> save(WidgetSnapshot snapshot) => _write(WidgetSnapshot.fileName, snapshot.toJson());

  Future<WidgetActionQueue> loadQueue() async =>
      WidgetActionQueue.fromJson(await _read(WidgetActionQueue.fileName)) ?? WidgetActionQueue();

  /// Genau diese Einträge entfernen; später hinzugekommene bleiben.
  Future<void> removeFromQueue(Set<String> ids) async {
    if (ids.isEmpty) return;
    final file = await _file(WidgetActionQueue.fileName);
    if (file == null) return;
    if (await _host.removeQueueEntries(file, ids)) return;
    final queue = await loadQueue()
      ..remove(ids);
    await _write(WidgetActionQueue.fileName, queue.toJson());
  }

  Future<void> reloadWidgets() => _host.reloadWidgets();

  /// Beim Benutzerwechsel: Stand und Warteschlange des bisherigen Benutzers entfernen, damit die Widgets nichts von
  /// ihm zeigen, bis der neue Benutzer seinen Stand schreibt.
  Future<void> clear() async {
    for (final name in const [WidgetSnapshot.fileName, WidgetActionQueue.fileName]) {
      final file = await _file(name);
      try {
        if (file != null && file.existsSync()) await file.delete();
      } on Object {
        // Bleibt stehen; der nächste Stand überschreibt ihn.
      }
    }
    await reloadWidgets();
  }
}
