import 'package:camera_dazz/film_processor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identity camera LUT preserves source colors', () async {
    final source = img.Image(width: 3, height: 3);
    img.fill(source, color: img.ColorRgb8(100, 130, 160));
    final lut = await rootBundle.load('assets/dazz/lut/LookupTableDefault.png');

    final output = processCameraPhoto(
      CameraPhotoTask(
        photoBytes: Uint8List.fromList(img.encodeJpg(source, quality: 100)),
        lutBytes: lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes),
      ),
    );
    final decoded = img.decodeJpg(output)!;
    final pixel = decoded.getPixel(1, 1);

    expect(pixel.r, closeTo(100, 4));
    expect(pixel.g, closeTo(130, 4));
    expect(pixel.b, closeTo(160, 4));
  });

  test('camera LUT changes captured colors', () async {
    final source = img.Image(width: 3, height: 3);
    img.fill(source, color: img.ColorRgb8(100, 130, 160));
    final lut = await rootBundle.load('assets/dazz/lut/lookup_dcr.png');

    final output = processCameraPhoto(
      CameraPhotoTask(
        photoBytes: Uint8List.fromList(img.encodeJpg(source, quality: 100)),
        lutBytes: lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes),
      ),
    );
    final pixel = img.decodeJpg(output)!.getPixel(1, 1);

    expect([
      pixel.r.round(),
      pixel.g.round(),
      pixel.b.round(),
    ], isNot([100, 130, 160]));
  });
}
