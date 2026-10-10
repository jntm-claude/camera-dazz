import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class LutStyle {
  const LutStyle({
    required this.name,
    required this.matrix,
    this.offset = const [0, 0, 0],
    this.gamma = const [1, 1, 1],
    this.saturation = 1,
    this.contrast = 1,
    this.shadowTint = const [0, 0, 0],
    this.highlightTint = const [0, 0, 0],
  });

  final String name;
  final List<double> matrix;
  final List<double> offset;
  final List<double> gamma;
  final double saturation;
  final double contrast;
  final List<double> shadowTint;
  final List<double> highlightTint;
}

const styles = <LutStyle>[
  LutStyle(
    name: 'sclassic',
    matrix: [1.04, .02, 0, .01, 1, .01, 0, .03, .92],
    offset: [.02, .01, .015],
    gamma: [.96, 1, 1.04],
    saturation: .91,
    contrast: .94,
    shadowTint: [.012, .008, .02],
    highlightTint: [.025, .012, -.012],
  ),
  LutStyle(
    name: 'uclassic',
    matrix: [.98, .02, .01, .01, 1.02, .01, .01, .02, 1.05],
    offset: [.018, .02, .025],
    gamma: [1.02, 1, .96],
    saturation: .88,
    contrast: .90,
    shadowTint: [-.008, .012, .025],
    highlightTint: [.012, .018, .026],
  ),
  LutStyle(
    name: 'vclassic',
    matrix: [1.06, .01, .02, .01, .97, .02, .02, 0, .96],
    offset: [.01, .005, .018],
    gamma: [.95, 1.02, 1],
    saturation: .96,
    contrast: 1.04,
    shadowTint: [.018, -.006, .022],
    highlightTint: [.026, .005, .012],
  ),
  LutStyle(
    name: 'cpm35',
    matrix: [1.06, .03, 0, .02, 1, .02, 0, .025, .91],
    offset: [.035, .02, .03],
    gamma: [.92, .98, 1.05],
    saturation: .86,
    contrast: .87,
    shadowTint: [-.005, .012, .032],
    highlightTint: [.045, .026, .012],
  ),
  LutStyle(
    name: '135ne',
    matrix: [1.03, .02, 0, .01, 1.01, 0, 0, .015, .95],
    offset: [.015, .012, .008],
    gamma: [.98, 1, 1.03],
    saturation: .95,
    contrast: 1.02,
    shadowTint: [0, .012, .015],
    highlightTint: [.025, .015, -.008],
  ),
  LutStyle(
    name: 'grdr',
    matrix: [.96, .025, 0, 0, 1.04, .015, .01, .04, 1.06],
    offset: [0, .004, .008],
    gamma: [1.03, .98, .96],
    saturation: 1.02,
    contrast: 1.10,
    shadowTint: [-.015, .018, .028],
    highlightTint: [.018, .008, -.01],
  ),
  LutStyle(
    name: 'ct2f',
    matrix: [1.08, .025, 0, .01, 1.01, .015, 0, .02, .91],
    offset: [.018, .008, .002],
    gamma: [.94, .99, 1.06],
    saturation: 1.03,
    contrast: 1.07,
    shadowTint: [.008, .004, .014],
    highlightTint: [.034, .018, -.014],
  ),
  LutStyle(
    name: 'dblack',
    matrix: [.34, .52, .14, .34, .52, .14, .34, .52, .14],
    gamma: [.96, .96, .96],
    saturation: 0,
    contrast: 1.17,
    shadowTint: [.008, .01, .012],
    highlightTint: [.008, .006, .002],
  ),
  LutStyle(
    name: 'ir',
    matrix: [1.2, .18, -.08, .22, .78, -.08, .12, .05, .72],
    offset: [.015, 0, .01],
    gamma: [.88, 1.03, 1.14],
    saturation: .72,
    contrast: 1.12,
    shadowTint: [.025, -.005, .012],
    highlightTint: [.075, .018, -.025],
  ),
  LutStyle(
    name: 'hoga',
    matrix: [1.06, .02, 0, 0, .98, .04, .02, .06, 1.02],
    offset: [.008, .012, .02],
    gamma: [.96, 1.01, .98],
    saturation: 1.08,
    contrast: 1.09,
    shadowTint: [-.012, .026, .03],
    highlightTint: [.038, .018, -.014],
  ),
  LutStyle(
    name: 'half',
    matrix: [1.02, .02, 0, .01, 1.02, .01, .01, .02, .98],
    offset: [.028, .025, .024],
    gamma: [.95, .97, 1],
    saturation: .90,
    contrast: .91,
    shadowTint: [.006, .012, .022],
    highlightTint: [.025, .022, .014],
  ),
  LutStyle(
    name: 'collage',
    matrix: [1.08, .01, 0, 0, 1.04, .01, 0, .01, 1.07],
    gamma: [.97, .98, .96],
    saturation: 1.18,
    contrast: 1.08,
    shadowTint: [.008, -.004, .018],
    highlightTint: [.018, .012, .012],
  ),
  LutStyle(
    name: 'instsq',
    matrix: [1.05, .025, 0, .015, 1.02, .01, 0, .025, .94],
    offset: [.035, .03, .025],
    gamma: [.93, .96, 1.02],
    saturation: .88,
    contrast: .88,
    shadowTint: [.012, .016, .024],
    highlightTint: [.038, .028, .016],
  ),
  LutStyle(
    name: 'instbw',
    matrix: [.31, .57, .12, .31, .57, .12, .31, .57, .12],
    offset: [.018, .02, .022],
    gamma: [1.02, 1.02, 1.02],
    saturation: 0,
    contrast: .96,
    shadowTint: [.006, .01, .016],
    highlightTint: [.018, .016, .012],
  ),
  LutStyle(
    name: 'd3d',
    matrix: [1.12, -.04, .02, -.02, 1.01, .02, .03, -.02, 1.13],
    offset: [.008, 0, .012],
    gamma: [.96, 1, .95],
    saturation: 1.13,
    contrast: 1.12,
    shadowTint: [-.015, .012, .045],
    highlightTint: [.045, .005, -.012],
  ),
  LutStyle(
    name: 'golf',
    matrix: [1.09, .025, 0, .015, 1.03, .01, 0, .02, .93],
    offset: [.012, .006, .002],
    gamma: [.94, .98, 1.06],
    saturation: 1.12,
    contrast: 1.14,
    shadowTint: [.01, .002, .018],
    highlightTint: [.04, .018, -.016],
  ),
  LutStyle(
    name: '16mm',
    matrix: [1.01, .02, 0, .01, 1.04, .02, 0, .04, .91],
    offset: [.01, .012, .005],
    gamma: [.98, .97, 1.08],
    saturation: .82,
    contrast: 1.10,
    shadowTint: [-.008, .02, .018],
    highlightTint: [.028, .024, -.012],
  ),
  LutStyle(
    name: 'kino',
    matrix: [1.07, .015, -.01, 0, 1.01, .02, -.01, .055, 1.06],
    offset: [.004, .002, .006],
    gamma: [.96, 1, .97],
    saturation: .96,
    contrast: 1.15,
    shadowTint: [-.018, .022, .038],
    highlightTint: [.048, .018, -.018],
  ),
  LutStyle(
    name: 'fqsr',
    matrix: [.98, .02, .01, 0, 1.02, .02, .01, .02, 1.10],
    offset: [.012, .014, .028],
    gamma: [1.02, .99, .92],
    saturation: 1.06,
    contrast: 1.11,
    shadowTint: [-.012, .01, .038],
    highlightTint: [.018, .014, .026],
  ),
  LutStyle(
    name: 'fxnr',
    matrix: [1.04, .025, 0, .01, 1.03, .005, 0, .025, .92],
    offset: [.018, .012, .004],
    gamma: [.95, .98, 1.07],
    saturation: .91,
    contrast: 1.05,
    shadowTint: [-.004, .018, .02],
    highlightTint: [.036, .022, -.012],
  ),
];

double clamp(double value) => value.clamp(0.0, 1.0).toDouble();

List<int> transform(LutStyle style, double red, double green, double blue) {
  final m = style.matrix;
  var r = m[0] * red + m[1] * green + m[2] * blue + style.offset[0];
  var g = m[3] * red + m[4] * green + m[5] * blue + style.offset[1];
  var b = m[6] * red + m[7] * green + m[8] * blue + style.offset[2];
  final luminance = clamp(r * .299 + g * .587 + b * .114);
  r = luminance + (r - luminance) * style.saturation;
  g = luminance + (g - luminance) * style.saturation;
  b = luminance + (b - luminance) * style.saturation;
  final shadow = math.pow(1 - luminance, 2).toDouble();
  final highlight = math.pow(luminance, 2).toDouble();
  r += style.shadowTint[0] * shadow + style.highlightTint[0] * highlight;
  g += style.shadowTint[1] * shadow + style.highlightTint[1] * highlight;
  b += style.shadowTint[2] * shadow + style.highlightTint[2] * highlight;
  r = (r - .5) * style.contrast + .5;
  g = (g - .5) * style.contrast + .5;
  b = (b - .5) * style.contrast + .5;
  r = math.pow(clamp(r), style.gamma[0]).toDouble();
  g = math.pow(clamp(g), style.gamma[1]).toDouble();
  b = math.pow(clamp(b), style.gamma[2]).toDouble();
  return [
    (clamp(r) * 255).round(),
    (clamp(g) * 255).round(),
    (clamp(b) * 255).round(),
  ];
}

void main() {
  final output = Directory('assets/dazz/lut')..createSync(recursive: true);
  for (final style in styles) {
    final image = img.Image(width: 512, height: 512, numChannels: 3);
    for (var blue = 0; blue < 64; blue++) {
      final tileX = blue % 8;
      final tileY = blue ~/ 8;
      for (var green = 0; green < 64; green++) {
        for (var red = 0; red < 64; red++) {
          final color = transform(style, red / 63, green / 63, blue / 63);
          image.setPixelRgb(
            tileX * 64 + red,
            tileY * 64 + green,
            color[0],
            color[1],
            color[2],
          );
        }
      }
    }
    File(
      '${output.path}/lookup_${style.name}.png',
    ).writeAsBytesSync(img.encodePng(image, level: 6));
  }
}
