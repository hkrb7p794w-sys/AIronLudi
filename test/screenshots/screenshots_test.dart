// Screenshot-Prüfstand: rendert die erreichbaren Screens mit Demo-Daten als PNG nach docs/roast/screenshots/.
// Nicht Teil des normalen Testlaufs (übersprungen ohne `--dart-define=SCREENSHOTS=true`):
//
//   flutter test --tags screenshots --dart-define=SCREENSHOTS=true --update-goldens test/screenshots
//
// Geräte: iPhone 15 (393 × 852 pt, Faktor 3, iOS) und kleines Android-Gerät (360 × 640 dp, Faktor 2, Android);
// je hell, dunkel und große Schrift (Textskalierung 1,3). Schrift: Inter (SIL OFL, test/screenshots/fonts) anstelle
// von SF Pro bzw. Roboto – ähnliche Laufweite, aber nicht identisch.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:aironludi/app/app.dart';
import 'package:aironludi/app/day_change.dart';
import 'package:aironludi/data/secure/secret_store.dart';
import 'package:aironludi/data/settings/preferences.dart';
import 'package:aironludi/data/storage.dart';
import 'package:aironludi/features/activities/activities_screen.dart';
import 'package:aironludi/features/ai/ai_screen.dart';
import 'package:aironludi/features/game/game_views.dart';
import 'package:aironludi/features/health/body_battery_screen.dart';
import 'package:aironludi/features/health/mobility_screen.dart';
import 'package:aironludi/features/health/morning_report_views.dart';
import 'package:aironludi/features/nutrition/nutrition_screen.dart';
import 'package:aironludi/features/routes/route_planner_screen.dart';
import 'package:aironludi/features/settings/backup_screen.dart';
import 'package:aironludi/features/settings/data_sources_screen.dart';
import 'package:aironludi/features/settings/lock_screen_settings.dart';
import 'package:aironludi/features/settings/nutrition_settings_screen.dart';
import 'package:aironludi/features/settings/settings_screen.dart';
import 'package:aironludi/features/social/social_views.dart';
import 'package:aironludi/features/today/today_dashboard_editor.dart';
import 'package:aironludi/features/today/today_screen.dart';
import 'package:aironludi/features/training/training_screen.dart';
import 'package:aironludi/ui/liquid.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'demo_data.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

/// Nur einzelne Screens (Kommagetrennt, Teil des Namens), z. B. `--dart-define=SHOTS=heute,training`.
const _only = String.fromEnvironment('SHOTS');

final class Device {
  const Device(this.name, this.size, this.ratio, this.platform);

  final String name;
  final Size size;
  final double ratio;
  final TargetPlatform platform;
}

const devices = [
  Device('iphone15', Size(393, 852), 3, TargetPlatform.iOS),
  Device('android-klein', Size(360, 640), 2, TargetPlatform.android),
];

enum Look { hell, dunkel, grossschrift }

final _shot = GlobalKey();

/// Schriften laden: Inter unter den Familiennamen, die Material und Cupertino anfragen; dazu die Symbolschriften.
Future<void> loadFonts() async {
  final weights = [
    for (final w in [400, 500, 600, 700]) File('test/screenshots/fonts/Inter-$w.ttf').readAsBytesSync(),
  ];
  for (final family in [
    'Roboto',
    'Inter',
    '.SF UI Text',
    '.SF UI Display',
    '.SF Pro Text',
    '.SF Pro Display',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
    'monospace',
    'FlutterTest',
    'Ahem',
  ]) {
    final loader = FontLoader(family);
    for (final bytes in weights) {
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final materialIcons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (materialIcons.existsSync()) {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(materialIcons.readAsBytesSync())))).load();
  }
  // Cupertino-Symbole aus dem Pub-Cache (Paket cupertino_icons).
  final config = File('.dart_tool/package_config.json');
  if (config.existsSync()) {
    final match = RegExp(r'"rootUri":\s*"([^"]*cupertino_icons[^"]*)"').firstMatch(config.readAsStringSync());
    if (match != null) {
      final root = Uri.parse('${match.group(1)!}/');
      final file = File.fromUri(root.resolve('assets/CupertinoIcons.ttf'));
      if (file.existsSync()) {
        await (FontLoader(
          'packages/cupertino_icons/CupertinoIcons',
        )..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
      }
    }
  }
}

Future<(Widget, ProviderContainer)> demoApp({required bool onboarded}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
    const EventChannel('com.llfbandit.app_links/events'),
    MockStreamHandler.inline(onListen: (_, _) {}),
  );
  // Ordner für Kartenkacheln und Exporte (Routenplaner): ein temporärer Ordner statt des Plattformteils.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final preferences = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
  final storage = await AppStorage.open(executor: NativeDatabase.memory(), secrets: InMemorySecretStore());
  final container = ProviderContainer(
    overrides: [
      preferencesProvider.overrideWithValue(preferences),
      appStorageProvider.overrideWithValue(storage),
      midnightTimerProvider.overrideWithValue(false),
    ],
  );
  if (onboarded) await seedDemo(container);
  return (
    RepaintBoundary(
      key: _shot,
      child: UncontrolledProviderScope(container: container, child: const AIronLudiApp()),
    ),
    container,
  );
}

/// Ein Screen des Prüfstands: [open] führt von der Startansicht dorthin (Reiter wählen, Knopf tippen, Seite öffnen).
final class Shot {
  const Shot(this.name, this.open, {this.long = false});

  final String name;
  final Future<void> Function(WidgetTester tester) open;

  /// Zusätzlich als Langbild (ganze Seite) für das iPhone hell.
  final bool long;
}

/// Layoutfehler (Überlauf u. Ä.) je Bild; das Bild entsteht trotzdem, mit den gelb-schwarzen Streifen.
final layoutErrors = <String, Set<String>>{};
String _current = '';

void _collect(WidgetTester tester) {
  final error = tester.takeException();
  if (error == null) return;
  final text = error.toString().split('\n').where((line) => line.trim().isNotEmpty).take(2).join(' ');
  layoutErrors.putIfAbsent(_current, () => {}).add(text);
}

/// Abgeschnittene Texte (Auslassungspunkte, `maxLines` überschritten) je Bild – sichtbare Texte innerhalb des Bildschirms.
final truncated = <String, Set<String>>{};

void _collectTruncated(WidgetTester tester) {
  final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph || !paragraph.attached || !paragraph.hasSize) continue;
    if (!paragraph.didExceedMaxLines) continue;
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    if (!rect.overlaps(screen)) continue;
    final text = paragraph.text.toPlainText().replaceAll('\n', ' ').trim();
    if (text.isNotEmpty) truncated.putIfAbsent(_current, () => {}).add(text);
  }
}

Future<void> settle(WidgetTester tester, {int frames = 12}) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    _collect(tester);
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 400));
  _collect(tester);
}

Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(LiquidTabBar), matching: find.text(label)));
  await settle(tester);
}

/// Seite im Navigationsstapel des Reiters öffnen, in dem [host] liegt.
Future<void> push(WidgetTester tester, Finder host, Widget page, {bool root = false}) async {
  final navigator = Navigator.of(tester.element(host.first), rootNavigator: root);
  // Absichtlich nicht abgewartet: Die Seite bleibt offen, bis der Prüfstand neu startet.
  // ignore: unawaited_futures
  navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  await settle(tester);
}

/// Zeile mit [text] in die Sicht scrollen und antippen.
Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isEmpty) {
    final scrollables = find.byType(Scrollable);
    await tester.scrollUntilVisible(target, 250, scrollable: scrollables.last, maxScrolls: 40);
  }
  await tester.ensureVisible(target.last);
  await tester.pump();
  await tester.tap(target.last, warnIfMissed: false);
  await settle(tester);
}

final shots = <Shot>[
  Shot('01-heute', (t) async {}, long: true),
  Shot('02-verlauf', (t) => tab(t, 'Verlauf'), long: true),
  Shot('03-plan', (t) => tab(t, 'Plan'), long: true),
  Shot('04-ernaehrung', (t) => tab(t, 'Ernährung'), long: true),
  Shot('05-ich', (t) => tab(t, 'Ich'), long: true),
  Shot('06-auswertungen', (t) async {
    await tab(t, 'Verlauf');
    await t.tap(find.byTooltip('Auswertungen'));
    await settle(t);
  }, long: true),
  // Heute
  Shot('10-ki-empfehlungen', (t) => push(t, find.byType(TodayScreen), const AIScreen()), long: true),
  Shot('11-heute-anpassen', (t) => push(t, find.byType(TodayScreen), const TodayDashboardEditor())),
  Shot('12-einstellungen', (t) => push(t, find.byType(TodayScreen), const SettingsScreen(), root: true), long: true),
  Shot('13-einst-datenquellen', (t) => push(t, find.byType(TodayScreen), const DataSourcesScreen(), root: true)),
  Shot('14-einst-ernaehrung', (t) => push(t, find.byType(TodayScreen), const NutritionSettingsScreen(), root: true)),
  Shot('15-einst-sicherung', (t) => push(t, find.byType(TodayScreen), const BackupScreen(), root: true)),
  Shot(
    '16-einst-sperrbildschirm',
    (t) => push(t, find.byType(TodayScreen), const LockScreenSettingsScreen(), root: true),
  ),
  // Aktivitäten
  Shot('20-freunde', (t) async {
    await tab(t, 'Verlauf');
    await push(t, find.byType(ActivitiesScreen), const FriendsScreen());
  }),
  Shot('21-spiel', (t) async {
    await tab(t, 'Verlauf');
    await push(t, find.byType(ActivitiesScreen), const GameScreen());
  }),
  // Training
  for (final (name, row) in const [
    ('30-plan-woche', 'Woche'),
    ('31-ausdauerplan', 'Ausdauerplan'),
    ('32-gym', 'Gym'),
    ('33-gesundheit', 'Gesundheit'),
    ('34-erholung', 'Erholung'),
    ('35-herzfrequenz', 'Herzfrequenz'),
    ('36-trends', 'Trends'),
    ('37-schlaf-coach', 'Schlaf-Coach'),
    ('38-fitness-form', 'Fitness & Form'),
    ('39-wochenbericht', 'Wochenbericht'),
    ('40-routen', 'Routen'),
  ])
    Shot(name, (t) async {
      const planRows = {'Woche', 'Ausdauerplan', 'Gym', 'Routen'};
      if (planRows.contains(row)) {
        await tab(t, 'Plan');
      } else {
        await tab(t, 'Verlauf');
        await t.tap(find.byTooltip('Auswertungen'));
        await settle(t);
      }
      await tapText(t, row);
    }, long: name == '31-ausdauerplan' || name == '32-gym'),
  Shot('41-body-battery', (t) async {
    await tab(t, 'Plan');
    await push(t, find.byType(TrainingScreen), const BodyBatteryScreen());
  }),
  Shot('42-morning-report', (t) async {
    await tab(t, 'Plan');
    await push(t, find.byType(TrainingScreen), const MorningReportScreen());
  }),
  Shot('43-mobility', (t) async {
    await tab(t, 'Plan');
    await push(t, find.byType(TrainingScreen), const MobilityScreen());
  }),
  Shot('44-routenplaner', (t) async {
    await tab(t, 'Plan');
    await push(t, find.byType(TrainingScreen), const RoutePlannerScreen());
  }),
  // Ernährung
  for (final (name, row) in const [
    ('50-ernaehrung-woche', 'Woche und Auswertung'),
    ('51-fuel-planner', 'Verpflegung'),
    ('52-gewicht', 'Gewichtsverlauf'),
    ('53-rezeptideen', 'Rezeptideen für die kommende Woche'),
    ('54-eigene-rezepte', 'Eigene Rezepte und Meal-Prep'),
  ])
    Shot(name, (t) async {
      await tab(t, 'Ernährung');
      await tapText(t, row);
    }, long: name == '51-fuel-planner'),
  Shot('55-erfassen', (t) async {
    await tab(t, 'Ernährung');
    await t.tap(find.byTooltip('Erfassen').first);
    await settle(t);
  }),
  Shot('56-ernaehrung-uebersicht', (t) async {
    await tab(t, 'Ernährung');
    await push(t, find.byType(NutritionScreen), const NutritionSettingsScreen());
  }),
];

String _path(Device device, Look look, String name) =>
    '../../docs/roast/screenshots/${device.name}/${look.name}/$name.png';

void main() {
  setUpAll(() async {
    if (_enabled) await loadFonts();
  });

  final failures = <String>[];
  tearDownAll(() {
    if (_enabled && _only.isEmpty) {
      final lines = [
        '# Layoutfehler im Prüfstand',
        '',
        'Vom Prüfstand erzeugt (`test/screenshots`). Je Bild die erste Meldung des Frameworks.',
        '',
        for (final entry in (layoutErrors.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
          '- `${entry.key}`: ${entry.value.join('; ')}',
      ];
      File('docs/roast/screenshots/layoutfehler.md').writeAsStringSync('${lines.join('\n')}\n');
      final cut = [
        '# Abgeschnittene Texte im Prüfstand',
        '',
        'Vom Prüfstand erzeugt (`test/screenshots`): sichtbare Texte, die mit Auslassungspunkten oder nach `maxLines` '
            'enden. Bei langen Namen in Listen gewollt; bei Beschriftungen, Werten und Knöpfen ein Fehler.',
        '',
        for (final entry in (truncated.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
          '- `${entry.key}`: ${entry.value.map((text) => '„$text“').join(', ')}',
      ];
      File('docs/roast/screenshots/abgeschnitten.md').writeAsStringSync('${cut.join('\n')}\n');
    }
    if (failures.isNotEmpty) {
      // ignore: avoid_print
      print('Nicht erzeugt:\n${failures.join('\n')}');
    }
  });

  for (final device in devices) {
    for (final look in Look.values) {
      for (final shot in shots) {
        if (_only.isNotEmpty && !_only.split(',').any(shot.name.contains)) continue;
        final heights = [device.size.height, if (shot.long && device.name == 'iphone15' && look == Look.hell) 2600.0];
        for (final height in heights) {
          final suffix = height == device.size.height ? '' : '-lang';
          testWidgets('${device.name} ${look.name} ${shot.name}$suffix', skip: !_enabled, (tester) async {
            _current = '${device.name}/${look.name}/${shot.name}$suffix';
            debugDefaultTargetPlatformOverride = device.platform;
            tester.view.physicalSize = Size(device.size.width, height) * device.ratio;
            tester.view.devicePixelRatio = device.ratio;
            tester.platformDispatcher.platformBrightnessTestValue = look == Look.dunkel
                ? Brightness.dark
                : Brightness.light;
            tester.platformDispatcher.textScaleFactorTestValue = look == Look.grossschrift ? 1.3 : 1.0;
            try {
              final (widget, _) = (await tester.runAsync(() => demoApp(onboarded: true)))!;
              await tester.pumpWidget(widget);
              await settle(tester, frames: 20);
              await shot.open(tester);
              await settle(tester);
              _collectTruncated(tester);
              await expectLater(find.byKey(_shot), matchesGoldenFile(_path(device, look, '${shot.name}$suffix')));
            } on Object catch (error) {
              failures.add('${device.name}/${look.name}/${shot.name}$suffix: $error');
              rethrow;
            } finally {
              debugDefaultTargetPlatformOverride = null;
              tester.view.reset();
              tester.platformDispatcher.clearAllTestValues();
            }
          });
        }
      }
      testWidgets('${device.name} ${look.name} 00-einrichtung', skip: !_enabled || _only.isNotEmpty, (tester) async {
        _current = '${device.name}/${look.name}/00-einrichtung';
        debugDefaultTargetPlatformOverride = device.platform;
        tester.view.physicalSize = device.size * device.ratio;
        tester.view.devicePixelRatio = device.ratio;
        tester.platformDispatcher.platformBrightnessTestValue = look == Look.dunkel
            ? Brightness.dark
            : Brightness.light;
        tester.platformDispatcher.textScaleFactorTestValue = look == Look.grossschrift ? 1.3 : 1.0;
        try {
          final (widget, _) = (await tester.runAsync(() => demoApp(onboarded: false)))!;
          await tester.pumpWidget(widget);
          await settle(tester, frames: 20);
          _collectTruncated(tester);
          await expectLater(find.byKey(_shot), matchesGoldenFile(_path(device, look, '00-einrichtung')));
        } finally {
          debugDefaultTargetPlatformOverride = null;
          tester.view.reset();
          tester.platformDispatcher.clearAllTestValues();
        }
      });
    }
  }
}
