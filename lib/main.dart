import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'camera_model.dart';
import 'film_preview.dart';
import 'film_processor.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CameraDazzApp());
}

class CameraDazzApp extends StatelessWidget {
  const CameraDazzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera Dazz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101113),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6B4A),
          surface: Color(0xFF101113),
        ),
        fontFamily: '.SF Pro Text',
      ),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _cream = Color(0xFFF1EEE6);
  static const _muted = Color(0xFF8F9091);
  static const _panel = Color(0xFF1B1C1E);
  static const _orange = Color(0xFFFF6B4A);

  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  CameraDescription? _selectedCamera;
  CameraModel _model = CameraModel.defaultModel;
  FlashMode _flash = FlashMode.off;
  bool _grid = false;
  bool _frameEnabled = false;
  bool _dateStampEnabled = false;
  bool _lightLeaksEnabled = true;
  bool _busy = false;
  bool _loading = true;
  bool _gallerySaved = true;
  String? _error;
  File? _lastPhoto;
  int _frame = 1;
  int _cameraGeneration = 0;
  Offset? _focusPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCameras();
    _loadLastPhoto();
  }

  Future<void> _loadLastPhoto() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photos =
          directory
              .listSync()
              .whereType<File>()
              .where(
                (file) =>
                    file.path.contains('camera_dazz_') &&
                    file.path.endsWith('.jpg'),
              )
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
      if (mounted && photos.isNotEmpty) {
        setState(() => _lastPhoto = photos.first);
      }
    } catch (_) {
      // The camera remains usable even if recent photo lookup is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _cameraGeneration++;
      final old = _controller;
      _controller = null;
      old?.dispose();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _loadCameras();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration++;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      _cameras = cameras;
      if (cameras.isEmpty) {
        setState(() {
          _loading = false;
          _error = '此设备未检测到相机';
        });
        return;
      }
      final preferred = _selectedCamera != null
          ? cameras.where((camera) => camera.name == _selectedCamera!.name)
          : <CameraDescription>[];
      final camera = preferred.isNotEmpty
          ? preferred.first
          : cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first,
            );
      await _openCamera(camera);
    } on CameraException catch (e) {
      _setCameraError(e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法启动相机，请检查设备权限';
      });
    }
  }

  Future<void> _openCamera(CameraDescription camera) async {
    final generation = ++_cameraGeneration;
    final old = _controller;
    _controller = null;
    await old?.dispose();
    if (!mounted || generation != _cameraGeneration) return;

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      if (_flash != FlashMode.off) {
        try {
          await controller.setFlashMode(_flash);
        } on CameraException {
          _flash = FlashMode.off;
        }
      }
      await _applyCaptureRecipe(controller, _model);
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _selectedCamera = camera;
        _loading = false;
        _error = null;
      });
    } on CameraException catch (e) {
      await controller.dispose();
      _setCameraError(e);
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '相机初始化失败，请重试';
      });
    }
  }

  void _setCameraError(CameraException error) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error =
          error.code.contains('AccessDenied') ||
              error.code.contains('AccessRestricted')
          ? '请在系统设置中允许访问相机'
          : '相机暂时不可用，请重试';
    });
  }

  Future<void> _toggleCamera() async {
    if (_busy || _loading || _cameras.length < 2) return;
    final current = _selectedCamera?.lensDirection;
    final target = _cameras.firstWhere(
      (camera) => camera.lensDirection != current,
      orElse: () => _cameras.first,
    );
    setState(() => _loading = true);
    await _openCamera(target);
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flash = next);
    } on CameraException {
      _showNotice('当前镜头不支持此闪光灯模式');
    }
  }

  Future<void> _applyCaptureRecipe(
    CameraController controller,
    CameraModel model,
  ) async {
    try {
      final minimum = await controller.getMinExposureOffset();
      final maximum = await controller.getMaxExposureOffset();
      final offset = model.captureExposureOffset
          .clamp(minimum, maximum)
          .toDouble();
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setExposureOffset(offset);
    } on CameraException {
      // Fixed-exposure and front-facing cameras can reject these controls.
    }
  }

  Future<void> _focus(TapDownDetails details, Size size) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final point = Offset(
      (details.localPosition.dx / size.width).clamp(0, 1),
      (details.localPosition.dy / size.height).clamp(0, 1),
    );
    setState(() => _focusPoint = details.localPosition);
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } on CameraException {
      // Some front cameras have fixed focus; the rest of the camera still works.
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _focusPoint = null);
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (_busy || controller == null || !controller.value.isInitialized) return;
    setState(() => _busy = true);
    await HapticFeedback.mediumImpact();
    try {
      final picture = await controller.takePicture();
      final source = await picture.readAsBytes();
      final model = _model;
      final lut = await _assetBytes(model.lutAsset);
      final textureSeed = DateTime.now().microsecondsSinceEpoch;
      final textureRandom = math.Random(textureSeed);
      final grainAssets = model.grainAssets;
      final grainPath = grainAssets.isEmpty
          ? null
          : grainAssets[textureRandom.nextInt(grainAssets.length)];
      final grain = await _assetBytes(grainPath);
      final vignette = await _assetBytes(model.vignetteAsset);
      final shouldAddLeak =
          _lightLeaksEnabled &&
          model.leakAssets.isNotEmpty &&
          textureRandom.nextDouble() < model.filmProfile.leakProbability;
      final leakPath = shouldAddLeak
          ? model.leakAssets[textureRandom.nextInt(model.leakAssets.length)]
          : null;
      final frame = _frameEnabled ? await _assetBytes(model.frameAsset) : null;
      final frameBottom = _frameEnabled
          ? await _assetBytes(model.frameBottomAsset)
          : null;
      final processed = await compute(
        processCameraPhoto,
        CameraPhotoTask(
          photoBytes: source,
          lutBytes: lut!,
          grainBytes: grain,
          leakBytes: leakPath == null ? null : await _assetBytes(leakPath),
          vignetteBytes: vignette,
          frameBytes: frame,
          frameBottomBytes: frameBottom,
          stampDate: _dateStampEnabled,
          profile: model.filmProfile,
          textureSeed: textureSeed,
        ),
      );
      final folder = await getApplicationDocumentsDirectory();
      final file = File(
        '${folder.path}/camera_dazz_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(processed, flush: true);
      var gallerySaved = true;
      try {
        await Gal.putImage(file.path);
      } catch (_) {
        gallerySaved = false;
      }
      if (!mounted) return;
      setState(() {
        _lastPhoto = file;
        _gallerySaved = gallerySaved;
        _frame++;
      });
      _showNotice(gallerySaved ? '照片已保存到相册' : '照片已保存在应用中，相册写入失败');
    } catch (_) {
      _showNotice('拍摄失败，请再试一次');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List?> _assetBytes(String? path) async {
    if (path == null) return null;
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _panel,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _openPhoto() {
    final file = _lastPhoto;
    if (file == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoPage(file: file, gallerySaved: _gallerySaved),
      ),
    );
  }

  void _openFilmPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.86,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '选择相机',
                        style: TextStyle(
                          color: _cream,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${CameraModel.models.length} 台',
                      style: const TextStyle(
                        color: _orange,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '上下滑动查看全部相机，选择它的色彩与质感',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GridView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    semanticChildCount: CameraModel.models.length,
                    itemCount: CameraModel.models.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.78,
                        ),
                    itemBuilder: (context, index) {
                      final model = CameraModel.models[index];
                      return _CameraChoice(
                        model: model,
                        selected: _model.id == model.id,
                        onTap: () {
                          setState(() {
                            _model = model;
                            _frameEnabled = false;
                            _dateStampEnabled = model.showDateByDefault;
                          });
                          final controller = _controller;
                          if (controller != null) {
                            unawaited(_applyCaptureRecipe(controller, model));
                          }
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.62,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, sheetSetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
            children: [
              const Text(
                '拍摄设置',
                style: TextStyle(
                  color: _cream,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _model.name,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _SettingSwitch(
                icon: Icons.crop_16_9_rounded,
                title: '相机边框',
                subtitle: _model.frameAsset == null
                    ? '此相机没有专属边框'
                    : '将 ${_model.name} 的边框合成到成片',
                value: _frameEnabled,
                enabled: _model.frameAsset != null,
                onChanged: (value) {
                  setState(() => _frameEnabled = value);
                  sheetSetState(() {});
                },
              ),
              _SettingSwitch(
                icon: Icons.calendar_month_outlined,
                title: '日期戳',
                subtitle: '在照片右下角打印拍摄日期',
                value: _dateStampEnabled,
                onChanged: (value) {
                  setState(() => _dateStampEnabled = value);
                  sheetSetState(() {});
                },
              ),
              _SettingSwitch(
                icon: Icons.wb_twilight_outlined,
                title: '随机漏光',
                subtitle: _model.leakAssets.isEmpty
                    ? '此相机没有漏光素材'
                    : '按胶卷概率随机出现，位置与方向每张不同',
                value: _lightLeaksEnabled,
                enabled: _model.leakAssets.isNotEmpty,
                onChanged: (value) {
                  setState(() => _lightLeaksEnabled = value);
                  sheetSetState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 19),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 14),
                  Expanded(child: _buildViewfinder(controller)),
                  const SizedBox(height: 18),
                  _buildFilmBar(),
                  const SizedBox(height: 16),
                  _buildControls(),
                  const SizedBox(height: 17),
                  _buildFooter(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          const Text(
            'DAZZ',
            style: TextStyle(
              color: _cream,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'CAM',
            style: TextStyle(
              color: _orange,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
            ),
          ),
          const Spacer(),
          _TopButton(
            label: _grid ? '关闭网格' : '打开网格',
            icon: Icons.grid_on_rounded,
            active: _grid,
            onTap: () => setState(() => _grid = !_grid),
          ),
          const SizedBox(width: 8),
          _TopButton(
            label: '闪光灯：${_flash.name}',
            icon: switch (_flash) {
              FlashMode.off => Icons.flash_off_rounded,
              FlashMode.auto => Icons.flash_auto_rounded,
              _ => Icons.flash_on_rounded,
            },
            active: _flash != FlashMode.off,
            onTap: _cycleFlash,
          ),
          const SizedBox(width: 8),
          _TopButton(
            label: '拍摄设置',
            icon: Icons.tune_rounded,
            onTap: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinder(CameraController? controller) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF292B2D),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF404244)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              onTapDown: (details) => _focus(details, size),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF303331)),
                  if (controller != null && controller.value.isInitialized)
                    _CameraFeed(controller: controller, film: _model)
                  else
                    _buildCameraState(),
                  // This subtle overlay remains visible even when the camera is
                  // unavailable, so the layout can be inspected on simulators.
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.30),
                          ],
                          stops: const [0.56, 1],
                          radius: 0.86,
                        ),
                      ),
                    ),
                  ),
                  if (_grid) const _GridOverlay(),
                  if (_frameEnabled && _model.frameAsset != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Image.asset(
                          _model.frameAsset!,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                  if (_frameEnabled && _model.frameBottomAsset != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Image.asset(
                          _model.frameBottomAsset!,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 17,
                    left: 18,
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'LIVE VIEW',
                          style: TextStyle(
                            color: _cream,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 18,
                    child: Text(
                      _frame.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        color: _cream,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Center(child: _Crosshair()),
                  if (_focusPoint != null)
                    Positioned(
                      left: _focusPoint!.dx - 26,
                      top: _focusPoint!.dy - 26,
                      child: const _FocusReticle(),
                    ),
                  Positioned(
                    bottom: 16,
                    left: 18,
                    right: 18,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _model.name,
                          style: const TextStyle(
                            color: _cream,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const Text(
                          'AUTO  ·  4:3',
                          style: TextStyle(
                            color: _cream,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCameraState() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _orange, strokeWidth: 2),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: _muted, size: 42),
            const SizedBox(height: 14),
            Text(
              _error ?? '相机未就绪',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _cream, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadCameras,
              child: const Text('重试', style: TextStyle(color: _orange)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilmBar() {
    return InkWell(
      onTap: _openFilmPicker,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFF353638)),
        ),
        child: Row(
          children: [
            _FilmIcon(film: _model, size: 50),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _model.name,
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _model.tagline,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_up_rounded, color: _cream),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return SizedBox(
      height: 100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Semantics(
            button: true,
            label: '查看上一张照片',
            child: InkWell(
              onTap: _lastPhoto == null ? null : _openPhoto,
              borderRadius: BorderRadius.circular(11),
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFF4C4D4F)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _lastPhoto == null
                    ? const Icon(Icons.photo_outlined, color: _muted, size: 23)
                    : Image.file(_lastPhoto!, fit: BoxFit.cover),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: _busy ? '正在处理照片' : '拍照',
            child: InkWell(
              onTap: _busy ? null : _takePhoto,
              customBorder: const CircleBorder(),
              child: Container(
                width: 82,
                height: 82,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _cream, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 10),
                  ],
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: _cream,
                    shape: BoxShape.circle,
                  ),
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: _panel,
                            strokeWidth: 2,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
          _TopButton(
            label: '切换前后摄像头',
            icon: Icons.cameraswitch_outlined,
            size: 54,
            onTap: _toggleCamera,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ModeLine(),
        SizedBox(width: 10),
        Text(
          'PHOTO',
          style: TextStyle(
            color: _cream,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
          ),
        ),
        SizedBox(width: 10),
        _ModeLine(),
      ],
    );
  }
}

class _CameraFeed extends StatelessWidget {
  const _CameraFeed({required this.controller, required this.film});

  final CameraController controller;
  final CameraModel film;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: preview.height,
            height: preview.width,
            child: FilmPreview(model: film, child: CameraPreview(controller)),
          ),
        ),
      ),
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.size = 43,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF202123),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? const Color(0xFFFF6B4A) : const Color(0xFF37383A),
            ),
          ),
          child: Icon(
            icon,
            color: active ? const Color(0xFFFF6B4A) : const Color(0xFFF1EEE6),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _FilmIcon extends StatelessWidget {
  const _FilmIcon({required this.film, required this.size});

  final CameraModel film;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: ColorFiltered(
      colorFilter: ColorFilter.matrix(film.previewMatrix),
      child: Image.asset(
        film.sampleAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    ),
  );
}

class _CameraChoice extends StatelessWidget {
  const _CameraChoice({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final CameraModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(13),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252628),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected ? const Color(0xFFFF6B4A) : const Color(0xFF38393B),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.matrix(model.previewMatrix),
                  child: Image.asset(model.sampleAsset, fit: BoxFit.cover),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                if (selected)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.check_circle,
                      color: Color(0xFFFF6B4A),
                      size: 20,
                    ),
                  ),
                Positioned(
                  left: 10,
                  right: 8,
                  bottom: 9,
                  child: Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
            child: Text(
              model.tagline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFAAA9A5), fontSize: 10),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white54, width: 0.8),
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Center(
        child: Icon(Icons.add, size: 12, color: Colors.white70),
      ),
    ),
  );
}

class _FocusReticle extends StatelessWidget {
  const _FocusReticle();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFFC483), width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}

class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _GridPainter()));
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.36)
      ..strokeWidth = 0.6;
    for (var line = 1; line < 3; line++) {
      final x = size.width * line / 3;
      final y = size.height * line / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

class _ModeLine extends StatelessWidget {
  const _ModeLine();

  @override
  Widget build(BuildContext context) =>
      Container(width: 19, height: 1, color: const Color(0xFFFF6B4A));
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: enabled ? onChanged : null,
    activeTrackColor: const Color(0xFFFF6B4A),
    secondary: Icon(icon, color: const Color(0xFFF1EEE6)),
    title: Text(title, style: const TextStyle(fontSize: 15)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
  );
}

class _PhotoPage extends StatelessWidget {
  const _PhotoPage({required this.file, required this.gallerySaved});

  final File file;
  final bool gallerySaved;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101113),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101113),
        title: const Text('刚刚拍摄', style: TextStyle(fontSize: 16)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Image.file(file, fit: BoxFit.contain),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                gallerySaved ? '已保存到系统相册' : '已保存在应用中',
                style: const TextStyle(color: Color(0xFFAAA9A5), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
