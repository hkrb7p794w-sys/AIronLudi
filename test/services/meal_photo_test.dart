// Mahlzeit-Fotos: verkleinert, JPEG, ohne Metadaten (wie MealPhoto in Swift).
import 'dart:typed_data';

import 'package:aironludi/services/nutrition/meal_photo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('längste Seite höchstens 1280 px, Seitenverhältnis bleibt, GPS und EXIF entfernt', () {
    final source = img.Image(width: 3000, height: 2000);
    source.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(52, 1);
    source.exif.imageIfd['Make'] = img.IfdValueAscii('Kamera');
    final jpeg = MealPhoto.jpegSync(img.encodeJpg(source));
    final result = img.decodeJpg(jpeg!)!;
    expect(result.width, 1280);
    expect(result.height, 853);
    expect(result.exif.gpsIfd.isEmpty, isTrue);
    expect(result.exif.imageIfd.isEmpty, isTrue);
  });

  test('kleine Fotos bleiben in ihrer Größe, Hochformat nach Höhe', () {
    expect(img.decodeJpg(MealPhoto.jpegSync(img.encodeJpg(img.Image(width: 800, height: 600)))!)!.width, 800);
    final tall = img.decodeJpg(MealPhoto.jpegSync(img.encodeJpg(img.Image(width: 1000, height: 4000)))!)!;
    expect((tall.width, tall.height), (320, 1280));
  });

  test('kein Bild: null', () {
    expect(MealPhoto.jpegSync(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
