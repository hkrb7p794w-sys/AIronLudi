// Treiber für `flutter drive`: führt integration_test/ aus und sichert Bildschirmfotos als PNG (Artefakt im Workflow
// `device-test.yml`).
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final folder = Directory(Platform.environment['SCREENSHOT_DIR'] ?? 'build/device-screenshots')
      ..createSync(recursive: true);
    File('${folder.path}/$name.png').writeAsBytesSync(bytes);
    return true;
  },
);
