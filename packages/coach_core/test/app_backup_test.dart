// Port von AppBackupTests.swift.
import 'dart:convert';

import 'package:coach_core/coach_core.dart';
import 'package:test/test.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1793500000 * 1000, isUtc: true);

AppBackup sample() => AppBackup(
  createdAt: now,
  settings: {
    'coach.profile': BackupData(utf8.encode('{"a":1}')),
    'coach.privacy': const BackupString('reduced'),
    'coach.showsEvidence': const BackupBool(true),
    'coach.count': const BackupInt(3),
    'coach.factor': const BackupDouble(1.5),
  },
  gym: [BackupGym(id: newUuid(), payload: utf8.encode('{}'), savedToHealth: true, uploadedToGarmin: false)],
  meals: [
    BackupMeal(
      id: newUuid(),
      dayKey: '2026-11-09',
      createdAt: now,
      category: 'lunch',
      title: 'Nudeln',
      hint: '',
      items: utf8.encode('[]'),
    ),
  ],
  foods: [BackupFood(key: 'x', name: 'Haferflocken', payload: utf8.encode('{}'), lastUsed: now, useCount: 4)],
);

void main() {
  test('hin und zurück bleibt alles erhalten', () {
    final backup = sample();
    final decoded = AppBackup.decode(backup.encoded());
    expect(decoded, backup);
    expect(decoded.summary, '1 Krafteinheiten, 1 Mahlzeiten, 1 eigene Lebensmittel, 5 Einstellungen');
  });

  test('Format wie die Swift-App: sortierte Schlüssel, ISO-Datum, Base64', () {
    final text = utf8.decode(sample().encoded());
    expect(text.startsWith('{"createdAt":"2026-11-01T02:26:40Z",'), isTrue);
    expect(text, contains('"coach.profile":{"type":"data","value":"eyJhIjoxfQ=="}'));
    expect(text, contains('"coach.factor":{"type":"double","value":1.5}'));
    expect(text, contains('"version":1}'));
    // Eine Datei im Format der Swift-App (Schrägstriche maskiert) wird gelesen.
    const swift =
        '{"createdAt":"2026-11-09T10:00:00Z","foods":[],"gym":[],"meals":[],"settings":{"ai.workerURL":'
        '{"type":"string","value":"https:\\/\\/w.example.dev"},"coach.count":{"type":"int","value":2}},"version":1}';
    final decoded = AppBackup.decode(utf8.encode(swift));
    expect(decoded.settings['ai.workerURL'], const BackupString('https://w.example.dev'));
    expect(decoded.settings['coach.count'], const BackupInt(2));
  });

  test('nur App-Einstellungen werden gesichert', () {
    expect(AppBackup.isBackedUp('coach.gym'), isTrue);
    expect(AppBackup.isBackedUp('coach.mobility'), isTrue);
    expect(AppBackup.isBackedUp('ai.workerURL'), isTrue);
    expect(AppBackup.isBackedUp('coach.wakeAlarm'), isFalse);
    expect(AppBackup.isBackedUp('garmin.lastSync'), isFalse);
    expect(AppBackup.isBackedUp('health.lastImport'), isFalse);
    expect(AppBackup.isBackedUp('gym.activeSession'), isFalse);
    expect(AppBackup.isBackedUp('backup.folderBookmark'), isFalse);
  });

  test('fremde und neuere Dateien werden abgelehnt', () {
    expect(() => AppBackup.decode(utf8.encode('hallo')), throwsA(const BackupUnreadable()));
    expect(() => AppBackup.decode(utf8.encode('{"version":1}')), throwsA(const BackupUnreadable()));
    expect(() => AppBackup.decode(utf8.encode('{"version":9}')), throwsA(const BackupNewerVersion(9)));
    expect(
      () => AppBackup.decode(
        utf8.encode(
          '{"createdAt":"2026-11-09T10:00:00Z","foods":[],"gym":[],"meals":[],"settings":{"a":{"type":"x","value":1}},"version":1}',
        ),
      ),
      throwsA(const BackupUnreadable()),
    );
  });

  test('Abstand der automatischen Sicherung', () {
    expect(AppBackup.isDue(last: null, now: now), isTrue);
    expect(AppBackup.isDue(last: now.subtract(const Duration(hours: 1)), now: now), isFalse);
    expect(AppBackup.isDue(last: now.subtract(const Duration(hours: 21)), now: now), isTrue);
    // Uhr zurückgestellt: lieber sichern als nie wieder.
    expect(AppBackup.isDue(last: now.add(const Duration(hours: 1)), now: now), isTrue);
  });

  test('Zusammenführen ergänzt nur Fehlendes, ohne Doppelte', () {
    final (a, b, c) = (newUuid(), newUuid(), newUuid());
    expect(AppBackup.missing([a, b, b, c], key: (id) => id, existing: {a}), [b, c]);
  });
}
