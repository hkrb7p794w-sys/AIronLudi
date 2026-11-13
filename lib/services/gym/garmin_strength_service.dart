import 'dart:convert';
import 'dart:io';

import 'package:coach_core/coach_core.dart';
import 'package:path/path.dart' as p;

import '../../data/repositories/gym_repository.dart';
import '../../data/repositories/metrics_repository.dart';
import '../garmin/garmin_connect_session.dart';

/// Gym-Einheiten mit Garmin Connect abgleichen: Sätze in die Aufzeichnung der Uhr schreiben (eine Aktivität mit
/// Kalorien, Herzfrequenz und Sätzen) oder – ohne Aufzeichnung nach `GarminStrengthSync.fallbackDelay` – als eigene
/// Aktivität hochladen. Läuft nach dem Speichern einer Einheit und nach jedem Abruf.
final class GarminStrengthService {
  /// [folder]: App-Support-Ordner für die Sicherung der ursprünglichen Sätze der Uhr.
  GarminStrengthService({required this._gym, required this._activities, required String? folder})
    : _backupDirectory = folder == null ? null : p.join(folder, 'garmin-exercise-sets');

  final GymRepository _gym;
  final ActivityRepository _activities;
  final String? _backupDirectory;

  File? _backupFile(int activityID) =>
      _backupDirectory == null ? null : File(p.join(_backupDirectory, '$activityID.json'));

  bool hasBackup(int activityID) => _backupFile(activityID)?.existsSync() ?? false;

  static String _message(Object error) => switch (error) {
    GarminAPIError(:final message) || GarminConnectError(:final message) => message,
    _ => '$error',
  };

  /// Wartende Einheiten der letzten 14 Tage abgleichen (auch nach längerer Zeit ohne Anmeldung); fehlgeschlagene werden
  /// nach 6 Stunden erneut versucht. Gibt eine Meldung für die zuletzt bearbeitete zurück.
  Future<String?> reconcile({required GarminConnectSession garmin, required GymSettings gym, DateTime? now}) async {
    if (!garmin.isLoggedIn) return null;
    final at = now ?? DateTime.now();
    final since = at.subtract(const Duration(days: 14));
    final records = [
      for (final stored in await _gym.all())
        if (!stored.session.start.isBefore(since)) stored,
    ];
    final pending = records.where((stored) {
      final link = stored.session.garmin;
      if (link == null) return false;
      final retry = link.status == GarminLinkStatus.failed && at.difference(link.updatedAt) >= const Duration(hours: 6);
      return link.status == GarminLinkStatus.pending || retry;
    }).toList();
    if (pending.isEmpty) return null;

    // Aktivitäten: gespeicherte und die neuesten direkt von Connect (die Uhr-Aufzeichnung kommt oft erst später).
    final sinceDay = CalendarDay.fromDate(since);
    final activities = [
      for (final activity in await _activities.all())
        if (activity.day case final day? when day >= sinceDay) activity,
    ];
    try {
      final json = await garmin.json(const ConnectEndpoint.recentActivities(limit: 20));
      final known = {for (final activity in activities) activity.id};
      activities.addAll(GarminActivityParser.activities(json).where((activity) => !known.contains(activity.id)));
    } on Object {
      // Ohne die neuesten weiter mit den gespeicherten.
    }
    final linked = {for (final stored in records) ?stored.session.garmin?.activityID};

    String? message;
    for (final stored in pending) {
      final session = stored.session.copy();
      // Erneuter Versuch nach einem Fehler: wie eine wartende Einheit behandeln.
      session.garmin?.status = GarminLinkStatus.pending;
      final action = GarminStrengthSync.action(
        session,
        activities: activities,
        linked: linked,
        now: at,
        fallbackUpload: gym.garminFallbackUpload,
      );
      switch (action) {
        case StrengthSyncEnrich(:final activityID):
          message = await enrich(session, activityID: activityID, garmin: garmin, gym: gym, now: at);
          linked.add(activityID);
        case _ when action == StrengthSyncAction.upload:
          message = await uploadToGarmin(session, garmin: garmin);
          final uploaded = (await _gym.byID(session.id))?.uploadedToGarmin ?? false;
          await _gym.setGarmin(
            session.id,
            GarminLink(
              status: uploaded ? GarminLinkStatus.uploaded : GarminLinkStatus.failed,
              note: message,
              updatedAt: at,
            ),
          );
        case _ when action == StrengthSyncAction.wait:
          message = 'Wartet auf die Aufzeichnung der Uhr – die Sätze werden ergänzt, sobald sie in Garmin Connect ist.';
        case _:
          break;
      }
    }
    return message;
  }

  /// Als eigene Krafttraining-Aktivität hochladen (wie `GymViewModel.uploadToGarmin`).
  Future<String> uploadToGarmin(GymSession session, {required GarminConnectSession garmin}) async {
    final fit = StrengthFitExport.fit(session);
    final name = 'coach-kraft-${session.day.iso}-${session.id.toUpperCase().substring(0, 8)}.fit';
    try {
      final created = await garmin.upload(fit: fit, fileName: name);
      await _gym.setUploadedToGarmin(session.id, value: true);
      return created ? 'Nach Garmin Connect übertragen.' : 'War in Garmin Connect schon vorhanden.';
    } on Object catch (error) {
      return 'Garmin: ${_message(error)}';
    }
  }

  /// Sätze in die Aufzeichnung schreiben: Original sichern, Nutzdaten bauen, PUT; bei abgelehntem Übungsnamen erneut
  /// nur mit Kategorien.
  Future<String> enrich(
    GymSession session, {
    required int activityID,
    required GarminConnectSession garmin,
    required GymSettings gym,
    required DateTime now,
  }) async {
    try {
      final path = GarminConnect.exerciseSetsPath(activityID);
      final original = await garmin.data(path: path);
      backup(original, activityID: activityID);
      // Immer von der echten Aufzeichnung der Uhr ausgehen (Sicherung vom ersten Mal), damit erneutes Übertragen nicht
      // auf schon ersetzten Sätzen aufbaut.
      List<int> base = original;
      try {
        base = _backupFile(activityID)?.readAsBytesSync() ?? original;
      } on Object {
        base = original;
      }
      final existing = decodeGarminJson(base);
      var result = GarminStrengthSync.payload(existing: existing, session: session, custom: gym.customExercises);
      try {
        await garmin.sendJson(method: 'PUT', path: path, json: utf8.encode(jsonEncode(result.payload)));
      } on Object {
        result = GarminStrengthSync.payload(
          existing: existing,
          session: session,
          custom: gym.customExercises,
          useNames: false,
        );
        await garmin.sendJson(method: 'PUT', path: path, json: utf8.encode(jsonEncode(result.payload)));
      }
      final text =
          '${result.sets} Sätze in die Garmin-Aufzeichnung der Uhr geschrieben – eine Aktivität mit Kalorien, Puls und '
          'Übungen.';
      await _gym.setGarmin(
        session.id,
        GarminLink(status: GarminLinkStatus.enriched, activityID: activityID, note: text, updatedAt: now),
      );
      return text;
    } on Object catch (error) {
      final message = _message(error);
      await _gym.setGarmin(
        session.id,
        GarminLink(status: GarminLinkStatus.failed, activityID: activityID, note: message, updatedAt: now),
      );
      return 'Garmin: $message';
    }
  }

  /// Nur beim ersten Mal sichern – so bleibt die echte Aufzeichnung der Uhr wiederherstellbar.
  void backup(List<int> data, {required int activityID}) {
    final file = _backupFile(activityID);
    if (file == null || file.existsSync()) return;
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp')..writeAsBytesSync(data, flush: true);
    temp.renameSync(file.path);
  }

  /// Ursprüngliche Sätze der Uhr zurückschreiben.
  Future<String> restore(GymSession session, {required int activityID, required GarminConnectSession garmin}) async {
    try {
      final file = _backupFile(activityID);
      if (file == null) throw const FileSystemException('Keine Sicherung vorhanden.');
      final data = file.readAsBytesSync();
      await garmin.sendJson(method: 'PUT', path: GarminConnect.exerciseSetsPath(activityID), json: data);
      // Ohne Verbindung: „Abgleichen“ steht wieder zur Wahl; die Sicherung bleibt erhalten.
      await _gym.setGarmin(session.id, null);
      return 'Ursprüngliche Sätze der Uhr wiederhergestellt.';
    } on Object catch (error) {
      return 'Garmin: ${error is FileSystemException ? error.message : _message(error)}';
    }
  }
}
