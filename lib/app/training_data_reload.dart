import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage.dart';

/// Lädt einen Bildschirm neu, sobald sich Trainingsdaten in der Datenbank ändern ([trainingDataChangesProvider]):
/// neuer Abruf (Garmin, WHOOP, Health), nachgetragene Aktivität, gesicherte oder gelöschte Gym-Einheit. Mehrere
/// Änderungen kurz hintereinander (ein Abruf schreibt viele Zeilen) ergeben ein einziges Neuladen.
mixin TrainingDataReload<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  StreamSubscription<void>? _changes;
  Timer? _pending;

  /// Wartezeit nach der letzten Änderung, bevor neu geladen wird.
  static const settle = Duration(milliseconds: 600);

  /// Neu laden (Daten aus der Datenbank lesen und neu rechnen).
  Future<void> reloadTrainingData();

  @override
  void initState() {
    super.initState();
    _changes = ref.read(trainingDataChangesProvider).listen((_) {
      _pending?.cancel();
      _pending = Timer(settle, () {
        if (mounted) unawaited(reloadTrainingData());
      });
    });
  }

  @override
  void dispose() {
    _pending?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
