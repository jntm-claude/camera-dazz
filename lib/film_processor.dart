import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Camera-specific film response layered around the color LUT.
///
/// The LUT establishes the palette. These parameters reproduce the physical
/// characteristics that a LUT cannot express on its own: shoulder/toe shape,
/// grain, edge falloff, and the strength of optical light leaks.
class FilmProfile {
  const FilmProfile({
    this.lutStrength = 1,
    this.contrast = 0,
    this.saturation = 1,
    this.blackLift = 0,
    this.highlightRolloff = 0,
    this.warmth = 0,
    this.grainStrength = 0,
    this.vignetteStrength = 0,
    this.leakStrength = 0.35,
    this.leakProbability = 0.35,
  });

  final double lutStrength;
  final double contrast;
  final double saturation;
  final double blackLift;
  final double highlightRolloff;
  final double warmth;
  final double grainStrength;
  final double vignetteStrength;
  final double leakStrength;
  final double leakProbability;
}

class CameraPhotoTask {
  const CameraPhotoTask({
    required this.photoBytes,
    required this.lutBytes,
    this.grainBytes,
    this.leakBytes,
    this.frameBytes,
    this.frameBottomBytes,
    this.stampDate = false,
    this.profile = const FilmProfile(),
    this.textureSeed = 0,
  });

  final Uint8List photoBytes;
  final Uint8List lutBytes;
  final Uint8List? grainBytes;
  final Uint8List? leakBytes;
  final Uint8List? frameBytes;
  final Uint8List? frameBottomBytes;
  final bool stampDate;
  final FilmProfile profile;
  final int textureSeed;
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
  _applyLutAndFilmResponse(image, lut, task.profile);
  final random = math.Random(task.textureSeed);

  final grainBytes = task.grainBytes;
  if (grainBytes != null && task.profile.grainStrength > 0) {
    final grain = img.decodeImage(grainBytes);
    if (grain != null) {
      _addGrain(image, grain, task.profile.grainStrength, random);
    }
  }
  final leakBytes = task.leakBytes;
  if (leakBytes != null && task.profile.leakStrength > 0) {
    final leak = img.decodeImage(leakBytes);
    if (leak != null) {
      _blendLeak(image, leak, task.profile.leakStrength, random);
    }
  }
  _applyFrames(image, task.frameBytes, task.frameBottomBytes);
  if (task.stampDate) _stampDate(image);
  // Fine grain is the first detail JPEG quantization removes. A high export
  // quality keeps the texture visible without switching the app to PNG files.
  return Uint8List.fromList(img.encodeJpg(image, quality: 96));
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

void _applyLutAndFilmResponse(
  img.Image image,
  Uint8List cube,
  FilmProfile profile,
) {
  const edge = 64;
  const plane = edge * edge;
  final widthScale = math.max(1, image.width - 1);
  final heightScale = math.max(1, image.height - 1);
  final lutStrength = _clamp01(profile.lutStrength);
  final responseCurve = Float64List(256);
  for (var value = 0; value < responseCurve.length; value++) {
    responseCurve[value] = _filmCurve(value / 255, profile);
  }
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

    var red = _mix(
      pixel.r.toDouble(),
      channel(0),
      lutStrength,
    );
    var green = _mix(
      pixel.g.toDouble(),
      channel(1),
      lutStrength,
    );
    var blue = _mix(
      pixel.b.toDouble(),
      channel(2),
      lutStrength,
    );

    red = responseCurve[red.round().clamp(0, 255).toInt()];
    green = responseCurve[green.round().clamp(0, 255).toInt()];
    blue = responseCurve[blue.round().clamp(0, 255).toInt()];

    final luminance = red * 0.299 + green * 0.587 + blue * 0.114;
    red = luminance + (red - luminance) * profile.saturation;
    green = luminance + (green - luminance) * profile.saturation;
    blue = luminance + (blue - luminance) * profile.saturation;

    // A small red/yellow bias in highlights and a matching blue reduction is
    // enough to suggest emulsion warmth without baking another color matrix.
    final warmth = profile.warmth;
    red += warmth * (0.65 + luminance * 0.35);
    green += warmth * 0.18;
    blue -= warmth * (0.75 - luminance * 0.15);

    final nx = (pixel.x / widthScale - 0.5) * 2;
    final ny = (pixel.y / heightScale - 0.5) * 2;
    final radiusSquared = (nx * nx + ny * ny) / 2;
    final vignette = _smoothstep(0.43 * 0.43, 1, radiusSquared) *
        profile.vignetteStrength.clamp(0, 0.8);
    final edgeFalloff = 1 - vignette;

    pixel
      ..r = (red * edgeFalloff * 255).round().clamp(0, 255)
      ..g = (green * edgeFalloff * 255).round().clamp(0, 255)
      ..b = (blue * edgeFalloff * 255).round().clamp(0, 255);
  }
}

double _mix(double a, double b, double amount) => a + (b - a) * amount;

double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

double _filmCurve(double value, FilmProfile profile) {
  var result = _clamp01(value);
  final smooth = result * result * (3 - 2 * result);
  result = _mix(
    result,
    smooth,
    profile.contrast.clamp(-1.0, 1.0).toDouble(),
  );

  if (result > 0.52 && profile.highlightRolloff > 0) {
    final t = ((result - 0.52) / 0.48).clamp(0.0, 1.0);
    final exponent =
        1 - profile.highlightRolloff.clamp(0.0, 0.8).toDouble() * 0.72;
    result =
        0.52 + 0.48 * (1 - math.pow(1 - t, exponent).toDouble());
  }

  // Lift mostly affects the toe; whites remain anchored at 1.0.
  result += profile.blackLift * math.pow(1 - result, 2).toDouble();
  return _clamp01(result);
}

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0))
      .clamp(0.0, 1.0)
      .toDouble();
  return t * t * (3 - 2 * t);
}

void _addGrain(
  img.Image image,
  img.Image grain,
  double strength,
  math.Random random,
) {
  final stats = _grainStats(grain);
  final offsetX = random.nextInt(math.max(1, grain.width));
  final offsetY = random.nextInt(math.max(1, grain.height));
  final flipX = random.nextBool();
  final flipY = random.nextBool();

  for (final pixel in image) {
    var gx = (pixel.x + offsetX) % grain.width;
    var gy = (pixel.y + offsetY) % grain.height;
    if (flipX) gx = grain.width - 1 - gx;
    if (flipY) gy = grain.height - 1 - gy;
    final texture = grain.getPixel(gx, gy);
    final textureLuminance =
        texture.r.toDouble() * 0.299 +
        texture.g.toDouble() * 0.587 +
        texture.b.toDouble() * 0.114;
    final normalizedNoise =
        ((textureLuminance - stats.mean) / stats.deviation).clamp(-2.8, 2.8);
    final imageLuminance =
        (pixel.r.toDouble() * 0.299 +
            pixel.g.toDouble() * 0.587 +
            pixel.b.toDouble() * 0.114) /
        255;
    final tonalWeight =
        0.32 + 0.68 * (1 - _smoothstep(0.48, 0.96, imageLuminance));
    final grainValue = normalizedNoise * 28 * strength * tonalWeight;
    pixel
      ..r = (pixel.r + grainValue).round().clamp(0, 255)
      ..g = (pixel.g + grainValue).round().clamp(0, 255)
      ..b = (pixel.b + grainValue).round().clamp(0, 255);
  }
}

_GrainStats _grainStats(img.Image grain) {
  final step = math.max(1, math.min(grain.width, grain.height) ~/ 256);
  var count = 0;
  var mean = 0.0;
  var squaredDelta = 0.0;
  for (var y = 0; y < grain.height; y += step) {
    for (var x = 0; x < grain.width; x += step) {
      final pixel = grain.getPixel(x, y);
      final value =
          pixel.r.toDouble() * 0.299 +
          pixel.g.toDouble() * 0.587 +
          pixel.b.toDouble() * 0.114;
      count++;
      final delta = value - mean;
      mean += delta / count;
      squaredDelta += delta * (value - mean);
    }
  }
  final deviation = count > 1 ? math.sqrt(squaredDelta / (count - 1)) : 1.0;
  return _GrainStats(mean, math.max(4.0, deviation).toDouble());
}

void _blendLeak(
  img.Image image,
  img.Image leak,
  double opacity,
  math.Random random,
) {
  // Preserve the source texture's aspect ratio and vary the crop/flip so the
  // same leak asset does not stamp an identical pattern onto every exposure.
  final scale = math.max(image.width / leak.width, image.height / leak.height);
  final visibleWidth = image.width / scale;
  final visibleHeight = image.height / scale;
  final cropX =
      random.nextDouble() * math.max(0.0, leak.width - visibleWidth);
  final cropY =
      random.nextDouble() * math.max(0.0, leak.height - visibleHeight);
  final flipX = random.nextBool();
  final flipY = random.nextBool();
  for (final pixel in image) {
    var lx = (cropX + pixel.x / scale)
        .floor()
        .clamp(0, leak.width - 1)
        .toInt();
    var ly = (cropY + pixel.y / scale)
        .floor()
        .clamp(0, leak.height - 1)
        .toInt();
    if (flipX) lx = leak.width - 1 - lx;
    if (flipY) ly = leak.height - 1 - ly;
    final light = leak.getPixel(lx, ly);
    pixel
      ..r = _screen(pixel.r, light.r.toInt(), opacity)
      ..g = _screen(pixel.g, light.g.toInt(), opacity)
      ..b = _screen(pixel.b, light.b.toInt(), opacity);
  }
}

int _screen(num base, num light, double opacity) {
  final screen = 255 - ((255 - base) * (255 - light) / 255);
  return (base + (screen - base) * opacity)
      .round()
      .clamp(0, 255)
      .toInt();
}

void _applyFrames(
  img.Image image,
  Uint8List? topBytes,
  Uint8List? bottomBytes,
) {
  if (topBytes == null && bottomBytes == null) return;
  final bottom = bottomBytes == null ? null : img.decodeImage(bottomBytes);
  if (bottom != null) {
    final resized = img.copyResize(
      bottom,
      width: image.width,
      height: image.height,
    );
    // Some Dazz frame layers are opaque JPEGs with artwork on black. They are
    // optical overlays, so normal alpha compositing would hide the photograph.
    for (final pixel in image) {
      final overlay = resized.getPixel(pixel.x, pixel.y);
      pixel
        ..r = _screen(pixel.r, overlay.r, 1)
        ..g = _screen(pixel.g, overlay.g, 1)
        ..b = _screen(pixel.b, overlay.b, 1);
    }
  }
  final top = topBytes == null ? null : img.decodeImage(topBytes);
  if (top != null) {
    final resized = img.copyResize(
      top,
      width: image.width,
      height: image.height,
    );
    img.compositeImage(image, resized);
  }
}

class _GrainStats {
  const _GrainStats(this.mean, this.deviation);

  final double mean;
  final double deviation;
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
