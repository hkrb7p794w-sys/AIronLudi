import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Mahlzeit-Fotos für die KI: längste Seite höchstens 1280 px, JPEG mit Qualität 0,7 und ohne Metadaten (kein
/// EXIF/GPS) – wie `MealPhoto` in der Swift-App. Läuft in einem eigenen Isolate, damit die Oberfläche flüssig bleibt.
abstract final class MealPhoto {
  static const maxPixels = 1280;

  static Future<Uint8List?> jpeg(Uint8List data) => compute(jpegSync, data);

  static Uint8List? jpegSync(Uint8List data) {
    final decoded = img.decodeImage(data);
    if (decoded == null) return null;
    // Ausrichtung aus EXIF in die Pixel übernehmen, danach alle Metadaten verwerfen.
    final image = img.bakeOrientation(decoded)
      ..exif = img.ExifData()
      ..iccProfile = null
      ..textData = null;
    final longest = math.max(image.width, image.height);
    final resized = longest > maxPixels
        ? img.copyResize(
            image,
            width: image.width >= image.height ? maxPixels : null,
            height: image.height > image.width ? maxPixels : null,
            interpolation: img.Interpolation.average,
          )
        : image;
    resized
      ..exif = img.ExifData()
      ..textData = null;
    return img.encodeJpg(resized, quality: 70);
  }
}
