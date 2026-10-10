import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_model.dart';

/// GPU preview for the same LUT and film recipe used by the export pipeline.
///
/// Custom image filters require Impeller. Devices using another rendering
/// backend retain the lightweight matrix preview instead of losing the camera.
class FilmPreview extends StatefulWidget {
  const FilmPreview({
    required this.model,
    required this.child,
    super.key,
  });

  final CameraModel model;
  final Widget child;

  @override
  State<FilmPreview> createState() => _FilmPreviewState();
}

class _FilmPreviewState extends State<FilmPreview> {
  static ui.FragmentProgram? _cachedProgram;

  ui.FragmentShader? _shader;
  ui.Image? _lutImage;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadResources();
  }

  @override
  void didUpdateWidget(FilmPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.lutAsset != widget.model.lutAsset) {
      _loadResources();
    } else {
      _configureShader();
    }
  }

  Future<void> _loadResources() async {
    final generation = ++_loadGeneration;
    try {
      final program = _cachedProgram ??=
          await ui.FragmentProgram.fromAsset('shaders/film_preview.frag');
      final data = await rootBundle.load(widget.model.lutAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || generation != _loadGeneration) {
        frame.image.dispose();
        return;
      }

      final previousImage = _lutImage;
      _lutImage = frame.image;
      _shader = program.fragmentShader();
      _configureShader();
      previousImage?.dispose();
      setState(() {});
    } catch (_) {
      // Unsupported renderers and shader compilation failures use the matrix
      // fallback below, keeping the camera operational.
    }
  }

  void _configureShader() {
    final shader = _shader;
    final lutImage = _lutImage;
    if (shader == null || lutImage == null) return;
    final profile = widget.model.filmProfile;

    // Float slots 0 and 1 are reserved for the input size by ImageFilter.
    shader
      ..setFloat(2, profile.lutStrength)
      ..setFloat(3, profile.contrast)
      ..setFloat(4, profile.saturation)
      ..setFloat(5, profile.blackLift)
      ..setFloat(6, profile.highlightRolloff)
      ..setFloat(7, profile.warmth)
      ..setFloat(8, profile.grainStrength)
      ..setFloat(9, profile.vignetteStrength)
      ..setFloat(10, (widget.model.id.hashCode & 0xFFFF).toDouble())
      // Image sampler 0 is supplied automatically with the filter input.
      ..setImageSampler(1, lutImage);
  }

  @override
  void dispose() {
    _loadGeneration++;
    _lutImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ColorFiltered(
      colorFilter: ColorFilter.matrix(widget.model.previewMatrix),
      child: widget.child,
    );
    final shader = _shader;
    if (shader == null || !ui.ImageFilter.isShaderFilterSupported) {
      return fallback;
    }

    try {
      return ImageFiltered(
        imageFilter: ui.ImageFilter.shader(shader),
        child: widget.child,
      );
    } catch (_) {
      return fallback;
    }
  }
}
