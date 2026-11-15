import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Foto des Begleiters: liegt nur auf diesem Gerät (`companion.jpg` im Ordner des Benutzers), höchstens 600 px, JPEG
/// 0,8 (Port von `CompanionPhoto`). Je Benutzer eine eigene Ablage (`companionPhotoProvider`).
final class CompanionPhoto {
  CompanionPhoto(this.folder);

  static const maxPixels = 600;

  final Future<Directory> Function() folder;

  Future<File> _file() async => File(p.join((await folder()).path, 'companion.jpg'));

  Future<Uint8List?> load() async {
    try {
      final file = await _file();
      return file.existsSync() ? await file.readAsBytes() : null;
    } on Object {
      return null;
    }
  }

  /// Verkleinert auf höchstens 600 Pixel und speichert als JPEG.
  Future<void> save(Uint8List data) async {
    final jpeg = await compute(resized, data);
    if (jpeg == null) return;
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsBytes(jpeg, flush: true);
  }

  static Uint8List? resized(Uint8List data) {
    final decoded = img.decodeImage(data);
    if (decoded == null) return null;
    final image = img.bakeOrientation(decoded)..exif = img.ExifData();
    final longest = math.max(image.width, image.height);
    final scaled = longest > maxPixels
        ? img.copyResize(
            image,
            width: image.width >= image.height ? maxPixels : null,
            height: image.height > image.width ? maxPixels : null,
          )
        : image;
    return img.encodeJpg(scaled, quality: 80);
  }

  Future<void> remove() async {
    try {
      final file = await _file();
      if (file.existsSync()) await file.delete();
    } on Object {
      // Nichts zu löschen.
    }
  }
}
