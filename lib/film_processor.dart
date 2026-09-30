import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class CameraPhotoTask {
  const CameraPhotoTask({
    required this.photoBytes,
    required this.lutBytes,
    this.grainBytes,
    this.leakBytes,
    this.frameBytes,
    this.frameBottomBytes,
    this.stampDate = false,
  });

  final Uint8List photoBytes;
  final Uint8List lutBytes;
  final Uint8List? grainBytes;
  final Uint8List? leakBytes;
  final Uint8List? frameBytes;
  final Uint8List? frameBottomBytes;
  final bool stampDate;
}

/// Applies the 8x8 tiled 64-cube LUT used by the Dazz assets, then adds the
/// selected camera's grain, optional light leak, frame, and date stamp.
Uint8List processCameraPhoto(CameraPhotoTask task) {
  final photo = img.decodeImage(task.photoBytes);
  final lutImage = img.decodePng(task.lutBytes);
  if (photo == null || lutImage == null) {
    throw const FormatException('无法读取照片或相机 LUT');
  }
  if (lutImage.width != 512 || lutImage.height != 512) {
    throw const FormatException('LUT 必须是 512×512 图像');
  }
  final image = img.bakeOrientation(photo);
  final lut = _readLut(lutImage);
  _applyLut(image, lut);

  final grainBytes = task.grainBytes;
  if (grainBytes != null) {
    final grain = img.decodeImage(grainBytes);
    if (grain != null) _addGrain(image, grain);
  }
  final leakBytes = task.leakBytes;
  if (leakBytes != null) {
    final leak = img.decodeImage(leakBytes);
    if (leak != null) _blendLeak(image, leak);
  }
  _applyFrames(image, task.frameBytes, task.frameBottomBytes);
  if (task.stampDate) _stampDate(image);
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

Uint8List _readLut(img.Image tiled) {
  const edge = 64;
  const plane = edge * edge;
  final cube = Uint8List(edge * edge * edge * 3);
  for (var blue = 0; blue < edge; blue++) {
    final tileX = blue % 8;
    final tileY = blue ~/ 8;
    for (var green = 0; green < edge; green++) {
      for (var red = 0; red < edge; red++) {
        final pixel = tiled.getPixel(tileX * edge + red, tileY * edge + green);
        final index = ((blue * plane) + (green * edge) + red) * 3;
        cube[index] = pixel.r.toInt();
        cube[index + 1] = pixel.g.toInt();
        cube[index + 2] = pixel.b.toInt();
      }
    }
  }
  return cube;
}

void _applyLut(img.Image image, Uint8List cube) {
  const edge = 64;
  const plane = edge * edge;
  for (final pixel in image) {
    final r = pixel.r.toDouble() * 63 / 255;
    final g = pixel.g.toDouble() * 63 / 255;
    final b = pixel.b.toDouble() * 63 / 255;
    final r0 = r.floor();
    final g0 = g.floor();
    final b0 = b.floor();
    final r1 = math.min(r0 + 1, 63);
    final g1 = math.min(g0 + 1, 63);
    final b1 = math.min(b0 + 1, 63);
    final rf = r - r0;
    final gf = g - g0;
    final bf = b - b0;

    double channel(int c) {
      double at(int ri, int gi, int bi) =>
          cube[((bi * plane) + (gi * edge) + ri) * 3 + c].toDouble();
      final c00 = _mix(at(r0, g0, b0), at(r1, g0, b0), rf);
      final c10 = _mix(at(r0, g1, b0), at(r1, g1, b0), rf);
      final c01 = _mix(at(r0, g0, b1), at(r1, g0, b1), rf);
      final c11 = _mix(at(r0, g1, b1), at(r1, g1, b1), rf);
      return _mix(_mix(c00, c10, gf), _mix(c01, c11, gf), bf);
    }

    pixel
      ..r = channel(0).round()
      ..g = channel(1).round()
      ..b = channel(2).round();
  }
}

double _mix(double a, double b, double amount) => a + (b - a) * amount;

void _addGrain(img.Image image, img.Image grain) {
  for (final pixel in image) {
    final gx = pixel.x * grain.width ~/ image.width;
    final gy = pixel.y * grain.height ~/ image.height;
    final texture = grain.getPixel(gx, gy);
    final grainValue =
        (texture.r.toDouble() * 0.299 +
            texture.g.toDouble() * 0.587 +
            texture.b.toDouble() * 0.114 -
            128) *
        0.16;
    pixel
      ..r = (pixel.r + grainValue).round().clamp(0, 255)
      ..g = (pixel.g + grainValue).round().clamp(0, 255)
      ..b = (pixel.b + grainValue).round().clamp(0, 255);
  }
}

void _blendLeak(img.Image image, img.Image leak) {
  for (final pixel in image) {
    final lx = pixel.x * leak.width ~/ image.width;
    final ly = pixel.y * leak.height ~/ image.height;
    final light = leak.getPixel(lx, ly);
    pixel
      ..r = _screen(pixel.r, light.r.toInt(), 0.28)
      ..g = _screen(pixel.g, light.g.toInt(), 0.28)
      ..b = _screen(pixel.b, light.b.toInt(), 0.28);
  }
}

int _screen(num base, num light, double opacity) {
  final screen = 255 - ((255 - base) * (255 - light) / 255);
  return (base + (screen - base) * opacity).round().clamp(0, 255);
}

void _applyFrames(
  img.Image image,
  Uint8List? topBytes,
  Uint8List? bottomBytes,
) {
  for (final bytes in [topBytes, bottomBytes]) {
    if (bytes == null) continue;
    final frame = img.decodeImage(bytes);
    if (frame == null) continue;
    final resized = img.copyResize(
      frame,
      width: image.width,
      height: image.height,
    );
    img.compositeImage(image, resized);
  }
}

void _stampDate(img.Image image) {
  final now = DateTime.now();
  final stamp =
      '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
  img.drawString(
    image,
    stamp,
    font: img.arial24,
    x: math.max(8, image.width - stamp.length * 15 - 18),
    y: math.max(8, image.height - 38),
    color: img.ColorRgb8(255, 190, 80),
  );
}
