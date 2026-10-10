import 'package:camera_dazz/camera_model.dart';
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

  test('film profile adds lens falloff without crushing the center', () async {
    final source = img.Image(width: 101, height: 101);
    img.fill(source, color: img.ColorRgb8(160, 160, 160));
    final lut = await rootBundle.load('assets/dazz/lut/LookupTableDefault.png');

    final output = processCameraPhoto(
      CameraPhotoTask(
        photoBytes: Uint8List.fromList(img.encodePng(source)),
        lutBytes: lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes),
        profile: const FilmProfile(vignetteStrength: 0.35),
      ),
    );
    final decoded = img.decodeJpg(output)!;
    final center = decoded.getPixel(50, 50).r.toDouble();
    final corner = decoded.getPixel(0, 0).r.toDouble();

    expect(center, closeTo(160, 4));
    expect(corner, lessThan(center - 35));
  });

  test('opaque black frame artwork is screen blended over the photo', () async {
    final source = img.Image(width: 120, height: 142);
    img.fill(source, color: img.ColorRgb8(150, 90, 60));
    final lut = await rootBundle.load('assets/dazz/lut/LookupTableDefault.png');
    final frame = await rootBundle.load('assets/dazz/frame/s67_frame_b_01.jpg');

    final output = processCameraPhoto(
      CameraPhotoTask(
        photoBytes: Uint8List.fromList(img.encodePng(source)),
        lutBytes: lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes),
        frameBottomBytes: frame.buffer.asUint8List(
          frame.offsetInBytes,
          frame.lengthInBytes,
        ),
      ),
    );
    final center = img.decodeJpg(output)!.getPixel(60, 71);

    expect(center.r, greaterThan(135));
    expect(center.g, greaterThan(75));
    expect(center.b, greaterThan(45));
  });

  test('texture seed keeps a film exposure deterministic', () async {
    final source = img.Image(width: 48, height: 48);
    img.fill(source, color: img.ColorRgb8(120, 135, 150));
    final lut = await rootBundle.load('assets/dazz/lut/LookupTableDefault.png');
    final grain = await rootBundle.load('assets/dazz/grain/grain_s67.jpg');
    final task = CameraPhotoTask(
      photoBytes: Uint8List.fromList(img.encodePng(source)),
      lutBytes: lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes),
      grainBytes: grain.buffer.asUint8List(
        grain.offsetInBytes,
        grain.lengthInBytes,
      ),
      profile: const FilmProfile(grainStrength: 0.4),
      textureSeed: 1967,
    );

    expect(processCameraPhoto(task), processCameraPhoto(task));
  });

  test('camera recipe assets are present in the application bundle', () async {
    for (final model in CameraModel.models) {
      await expectLater(rootBundle.load(model.lutAsset), completes);
      await expectLater(rootBundle.load(model.sampleAsset), completes);
      for (final grainAsset in model.grainAssets) {
        await expectLater(rootBundle.load(grainAsset), completes);
      }
      final vignetteAsset = model.vignetteAsset;
      if (vignetteAsset != null) {
        await expectLater(rootBundle.load(vignetteAsset), completes);
      }
      final frameAsset = model.frameAsset;
      if (frameAsset != null) {
        await expectLater(rootBundle.load(frameAsset), completes);
      }
      final frameBottomAsset = model.frameBottomAsset;
      if (frameBottomAsset != null) {
        await expectLater(rootBundle.load(frameBottomAsset), completes);
      }
      for (final leakAsset in model.leakAssets) {
        await expectLater(rootBundle.load(leakAsset), completes);
      }
    }
  });

  test('camera catalog contains 33 distinct recipes', () {
    expect(CameraModel.models, hasLength(33));
    expect(CameraModel.models.map((model) => model.id).toSet(), hasLength(33));
    expect(
      CameraModel.models.map((model) => model.lutAsset).toSet(),
      hasLength(33),
    );
  });

  test('textured vignette preserves the center and darkens the edge', () async {
    final source = img.Image(width: 101, height: 101);
    img.fill(source, color: img.ColorRgb8(170, 170, 170));
    final lut = await rootBundle.load('assets/dazz/lut/LookupTableDefault.png');
    final vignette = await rootBundle.load(
      'assets/dazz/vignette/vignette_dexp.jpg',
    );
    final output = processCameraPhoto(
      CameraPhotoTask(
        photoBytes: Uint8List.fromList(img.encodePng(source)),
        lutBytes: lut.buffer.asUint8List(lut.offsetInBytes, lut.lengthInBytes),
        vignetteBytes: vignette.buffer.asUint8List(
          vignette.offsetInBytes,
          vignette.lengthInBytes,
        ),
        profile: const FilmProfile(vignetteStrength: 0.4),
      ),
    );
    final decoded = img.decodeJpg(output)!;
    final center = decoded.getPixel(50, 50).r;
    final corner = decoded.getPixel(0, 0).r;

    expect(center, closeTo(170, 8));
    expect(corner, lessThan(center - 20));
  });
}
