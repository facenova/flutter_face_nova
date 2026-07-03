import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'liveness_types.dart';
import 'anti_spoof_engine.dart';

List<Object> _processImageIsolate(Uint8List bytes) {
  var im = img.decodeJpg(bytes);
  if (im == null) return [bytes, Uint8List(0), 0, 0];
  im = img.bakeOrientation(im);
  final oriented = Uint8List.fromList(img.encodeJpg(im));
  final pixels   = Uint8List.fromList(im.getBytes(order: img.ChannelOrder.rgba));
  return [oriented, pixels, im.width, im.height];
}

class LivenessScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final double livenessThreshold;
  final double backCameraThreshold;
  final AntiSpoofEngine? preloadedEngine;

  // iOS defaults: front 60%, back 90%. Android defaults: front 30%, back 80%.
  LivenessScreen({
    super.key,
    required this.cameras,
    double? livenessThreshold,
    double? backCameraThreshold,
    this.preloadedEngine,
  })  : livenessThreshold   = livenessThreshold   ?? (Platform.isIOS ? 0.60 : 0.30),
        backCameraThreshold = backCameraThreshold ?? (Platform.isIOS ? 0.90 : 0.80);

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> {
  CameraController? _ctrl;
  int _camIdx = 0;

  late AntiSpoofEngine _fas;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
  );

  bool _engineLoaded = false;
  String _engineError = '';
  bool _processing = false;
  Timer? _timer;
  int _streamFrameCount = 0; // throttle iOS image stream

  // Live display state
  double _livenessScore  = 0.0;   // 0–1
  bool   _faceFound      = false;
  bool   _flashOn        = false;
  bool   _moireDetected  = false;
  bool   _tooClose       = false;
  Rect?  _faceBbox;
  int    _bboxImgW       = 0;
  int    _bboxImgH       = 0;

  @override
  void initState() {
    super.initState();
    // Use pre-loaded engine from FlutterFaceNova.initialize() if available
    _fas = widget.preloadedEngine ?? AntiSpoofEngine();
    _camIdx = widget.cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (_camIdx < 0) _camIdx = 0;
    _init();
  }

  Future<void> _init() async {
    try {
      OrtEnv.instance.init();
      // If engine was pre-loaded at startup it's already ready — skip load
      if (!_fas.isLoaded) await _fas.load();
      if (mounted) setState(() => _engineLoaded = true);
    } catch (e) {
      if (mounted) setState(() => _engineError = 'Model load failed: $e');
      return;
    }
    await _initCamera();
  }

  static const _nativeCh = MethodChannel('liveness_flutter/camera');

  Future<void> _initCamera() async {
    final cam = widget.cameras[_camIdx];
    final isBack = cam.lensDirection == CameraLensDirection.back;

    // Back camera: use low resolution to match front camera quality level
    // and reduce how much detail a spoofed screen image can show.
    final preset = isBack ? ResolutionPreset.low : ResolutionPreset.medium;
    final ctrl = CameraController(cam, preset, enableAudio: false);
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);

      // For back camera: lock focus immediately before AF can run,
      // so the lens stays at a fixed distance (typically hyperfocal ~1-2 m).
      // Anything held close (< 40 cm) will be blurry.
      if (isBack) {
        await _lockBackCameraFocus(ctrl);
      }
    } catch (e) {
      debugPrint('[Liveness] Camera init error: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _ctrl = ctrl);
    try { await ScreenBrightness().setScreenBrightness(1.0); } catch (_) {}

    if (Platform.isIOS) {
      // iOS: stream frames silently — takePicture() triggers shutter sound every call
      _streamFrameCount = 0;
      await ctrl.startImageStream(_onStreamFrame);
    } else {
      _timer = Timer.periodic(const Duration(milliseconds: 400), (_) => _run());
    }
  }

  Future<void> _switchCamera() async {
    _timer?.cancel();
    final old = _ctrl;
    if (old != null && old.value.isInitialized) {
      if (Platform.isIOS && old.value.isStreamingImages) {
        await old.stopImageStream();
      }
      await old.dispose();
    }
    if (mounted) setState(() { _ctrl = null; _faceFound = false; _livenessScore = 0; _flashOn = false; _moireDetected = false; _faceBbox = null; });
    _camIdx = (_camIdx + 1) % widget.cameras.length;
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final next = !_flashOn;
    try {
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _flashOn = next);
    } catch (_) {}
  }

  Future<void> _lockBackCameraFocus(CameraController ctrl) async {
    try {
      if (Platform.isAndroid) {
        // Android: check via Camera2 native whether this lens has autofocus
        final info = await _nativeCh.invokeMapMethod<String, dynamic>(
            'getBackCameraFocusInfo');
        final hasAF = info?['hasAutofocus'] as bool? ?? true;
        if (!hasAF) return; // Fixed-lens — already can't focus close
      }
      // iOS + Android: lock focus immediately before AF can run.
      // Lens rests at hyperfocal (~1-2 m). Screens held close (< 40 cm) blur.
      await ctrl.setFocusMode(FocusMode.locked);
      debugPrint('[Liveness] Back camera focus locked.');
    } catch (e) {
      debugPrint('[Liveness] Focus lock failed (non-fatal): $e');
    }
  }

  // iOS-only: called for every camera frame from startImageStream.
  // Throttle to ~1 frame per 500ms to match the Android takePicture cadence.
  void _onStreamFrame(CameraImage image) {
    _streamFrameCount++;
    if (_streamFrameCount % 15 != 0) return; // ~30fps → every 15th frame ≈ 500ms
    if (_processing || !_engineLoaded || _ctrl == null) return;
    _runFromStream(image);
  }

  Future<void> _runFromStream(CameraImage image) async {
    _processing = true;
    try {
      // Convert BGRA8888 (iOS) frame to img.Image with correct RGB color.
      // img.ChannelOrder.bgra doesn't reliably swap channels before JPEG encode,
      // so we manually reorder: B→R, G→G, R→B to get proper RGBA bytes.
      final plane = image.planes[0];
      final bgraBytes = plane.bytes;
      final rgbaBytes = Uint8List(bgraBytes.length);
      for (int i = 0; i < bgraBytes.length - 3; i += 4) {
        rgbaBytes[i]     = bgraBytes[i + 2]; // R ← B
        rgbaBytes[i + 1] = bgraBytes[i + 1]; // G ← G
        rgbaBytes[i + 2] = bgraBytes[i];     // B ← R
        rgbaBytes[i + 3] = bgraBytes[i + 3]; // A ← A
      }
      var decoded = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: rgbaBytes.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      // ML Kit face detection from raw bytes — no temp file needed on iOS
      final inputImage = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) setState(() { _faceFound = false; _livenessScore = 0; _moireDetected = false; _tooClose = false; _faceBbox = null; });
        return;
      }

      final bbox = faces.first.boundingBox;

      final isBack = widget.cameras[_camIdx].lensDirection == CameraLensDirection.back;
      final tooCloseThreshold = isBack ? 0.55 : 0.70;
      final faceRatio = bbox.width / image.width;
      if (faceRatio > tooCloseThreshold) {
        if (mounted) setState(() { _faceFound = true; _tooClose = true; _livenessScore = 0; _moireDetected = false; _faceBbox = bbox; _bboxImgW = image.width; _bboxImgH = image.height; });
        return;
      }

      final moire = _detectMoire(decoded, bbox);
      if (moire) {
        if (mounted) setState(() { _faceFound = true; _livenessScore = 0; _moireDetected = true; _tooClose = false; _faceBbox = bbox; _bboxImgW = image.width; _bboxImgH = image.height; });
        return;
      }

      final score = await _fas.predict(decoded, bbox);

      if (!mounted) return;
      setState(() { _faceFound = true; _livenessScore = score; _moireDetected = false; _tooClose = false; _faceBbox = bbox; _bboxImgW = image.width; _bboxImgH = image.height; });

      final threshold = isBack ? widget.backCameraThreshold : widget.livenessThreshold;
      if (score >= threshold) {
        final ctrl = _ctrl;
        if (ctrl != null && ctrl.value.isStreamingImages) {
          await ctrl.stopImageStream();
        }
        // Encode to JPEG for the result
        final oriented = Uint8List.fromList(img.encodeJpg(decoded));
        if (mounted) {
          Navigator.pop(context, LivenessResult(isReal: true, score: score, imageBytes: oriented));
        }
      }
    } catch (e) {
      debugPrint('[Liveness] stream error: $e');
    } finally {
      _processing = false;
    }
  }

  Future<void> _run() async {
    if (_processing || !_engineLoaded) return;
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    _processing = true;

    try {
      final xfile = await ctrl.takePicture();
      final bytes = await xfile.readAsBytes();

      final result    = await compute(_processImageIsolate, bytes);
      final oriented  = result[0] as Uint8List;
      final rawPixels = result[1] as Uint8List;
      final imgW      = result[2] as int;
      final imgH      = result[3] as int;
      if (imgW == 0 || rawPixels.isEmpty) return;

      final decoded = img.Image.fromBytes(
        width: imgW, height: imgH,
        bytes: rawPixels.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      await File(xfile.path).writeAsBytes(oriented);

      final faces = await _faceDetector.processImage(
          InputImage.fromFilePath(xfile.path));

      if (faces.isEmpty) {
        if (mounted) setState(() { _faceFound = false; _livenessScore = 0; _moireDetected = false; _tooClose = false; _faceBbox = null; });
        return;
      }

      final bbox = faces.first.boundingBox;

      // Distance gate: face too large = too close. Back camera is stricter (0.55)
      // since a spoofed screen held close fills the frame more than a real face.
      // Front camera uses 0.70 — selfies are naturally held closer.
      final isBack = widget.cameras[_camIdx].lensDirection == CameraLensDirection.back;
      final tooCloseThreshold = isBack ? 0.55 : 0.70;
      final faceRatio = bbox.width / imgW;
      if (faceRatio > tooCloseThreshold) {
        if (mounted) setState(() { _faceFound = true; _tooClose = true; _livenessScore = 0; _moireDetected = false; _faceBbox = bbox; _bboxImgW = imgW; _bboxImgH = imgH; });
        return;
      }

      // Screen-replay gate: moiré check before any model inference
      final moire = _detectMoire(decoded, bbox);
      if (moire) {
        if (mounted) setState(() { _faceFound = true; _livenessScore = 0; _moireDetected = true; _tooClose = false; _faceBbox = bbox; _bboxImgW = imgW; _bboxImgH = imgH; });
        return;
      }

      final score = await _fas.predict(decoded, bbox);

      if (!mounted) return;
      setState(() {
        _faceFound      = true;
        _livenessScore  = score;
        _moireDetected  = false;
        _tooClose       = false;
        _faceBbox       = bbox;
        _bboxImgW       = imgW;
        _bboxImgH       = imgH;
      });

      // Auto-pass when score exceeds per-camera threshold
      final threshold = isBack ? widget.backCameraThreshold : widget.livenessThreshold;
      if (score >= threshold) {
        _timer?.cancel();
        Navigator.pop(context, LivenessResult(
          isReal: true, score: score, imageBytes: oriented,
        ));
      }
    } catch (e) {
      if (e is CameraException && (e.description?.contains('disposed') ?? false)) return;
      debugPrint('[Liveness] error: $e');
    } finally {
      _processing = false;
    }
  }

  // Returns true if the face crop contains a periodic screen pixel-grid pattern.
  // Analyzes horizontal & vertical gradient autocorrelation at lags 2–14.
  bool _detectMoire(img.Image image, Rect bbox) {
    const size = 64;
    final srcW = image.width;
    final srcH = image.height;

    final x = bbox.left.round().clamp(0, srcW - 1);
    final y = bbox.top.round().clamp(0, srcH - 1);
    final w = bbox.width.round().clamp(1, srcW - x);
    final h = bbox.height.round().clamp(1, srcH - y);

    final crop  = img.copyCrop(image, x: x, y: y, width: w, height: h);
    final small = img.copyResize(crop, width: size, height: size,
        interpolation: img.Interpolation.linear);

    double _autocorr(List<double> signal) {
      double mean = 0;
      for (final v in signal) mean += v;
      mean /= signal.length;

      double variance = 0;
      for (final v in signal) variance += (v - mean) * (v - mean);
      variance /= signal.length;
      if (variance < 0.5) return 0.0;

      double maxCorr = 0;
      for (int lag = 2; lag <= 14; lag++) {
        double corr = 0;
        final n = signal.length - lag;
        for (int i = 0; i < n; i++) {
          corr += (signal[i] - mean) * (signal[i + lag] - mean);
        }
        corr /= n * variance;
        if (corr > maxCorr) maxCorr = corr;
      }
      return maxCorr;
    }

    // Horizontal gradients: average across rows for each column gap
    final hGrad = List<double>.filled(size - 1, 0.0);
    for (int col = 0; col < size - 1; col++) {
      double sum = 0;
      for (int row = 0; row < size; row++) {
        final p1 = small.getPixel(col, row);
        final p2 = small.getPixel(col + 1, row);
        sum += ((p2.r - p1.r).abs() + (p2.g - p1.g).abs() + (p2.b - p1.b).abs()) / 3.0;
      }
      hGrad[col] = sum / size;
    }

    // Vertical gradients: average across columns for each row gap
    final vGrad = List<double>.filled(size - 1, 0.0);
    for (int row = 0; row < size - 1; row++) {
      double sum = 0;
      for (int col = 0; col < size; col++) {
        final p1 = small.getPixel(col, row);
        final p2 = small.getPixel(col, row + 1);
        sum += ((p2.r - p1.r).abs() + (p2.g - p1.g).abs() + (p2.b - p1.b).abs()) / 3.0;
      }
      vGrad[row] = sum / size;
    }

    final maxCorr = math.max(_autocorr(hGrad), _autocorr(vGrad));
    return maxCorr > 0.80;
  }


  @override
  void dispose() {
    _timer?.cancel();
    final ctrl = _ctrl;
    _ctrl = null;
    if (ctrl != null && ctrl.value.isInitialized) {
      if (Platform.isIOS && ctrl.value.isStreamingImages) {
        ctrl.stopImageStream().catchError((_) {});
      }
      ctrl.dispose();
    }
    if (widget.preloadedEngine == null) _fas.dispose();
    _faceDetector.close();
    ScreenBrightness().resetScreenBrightness().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl  = _ctrl;
    final ready = ctrl != null && ctrl.value.isInitialized && _engineLoaded;
    final isBackCam = _camIdx < widget.cameras.length &&
        widget.cameras[_camIdx].lensDirection == CameraLensDirection.back;
    final threshold = isBackCam ? widget.backCameraThreshold : widget.livenessThreshold;
    final pass  = _livenessScore >= threshold;
    final boxColor = _tooClose || _moireDetected
        ? const Color(0xFFFF9800)
        : (_faceFound && _livenessScore > 0)
            ? (pass ? const Color(0xFF22D37A) : const Color(0xFFFF5C5C))
            : const Color(0xFFFF5C5C);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── Camera preview ─────────────────────────────────────────────────
          if (ready)
            _CameraFill(controller: ctrl)
          else
            Center(
              child: _engineError.isNotEmpty
                ? Text(_engineError,
                    style: const TextStyle(color: Color(0xFFFF5C5C)),
                    textAlign: TextAlign.center)
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(color: Color(0xFF22D37A)),
                    const SizedBox(height: 16),
                    Text(_engineLoaded ? 'Starting camera…' : 'Loading model…',
                        style: const TextStyle(color: Colors.white54)),
                  ]),
            ),

          // ── Face bounding box overlay ───────────────────────────────────────
          if (ready && _faceBbox != null && _bboxImgW > 0)
            CustomPaint(
              painter: _FaceBoxPainter(
                bbox: _faceBbox!,
                imgW: _bboxImgW,
                imgH: _bboxImgH,
                color: boxColor,
                scoreText: _tooClose
                    ? 'Too close'
                    : '${(_livenessScore * 100).toStringAsFixed(0)}%',
                flipHorizontal: !isBackCam,
              ),
            ),

          // ── Top bar ────────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Liveness Detection',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    Row(children: [
                      if (ready && widget.cameras[_camIdx].lensDirection == CameraLensDirection.back) ...[
                        _IconBtn(
                          icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          active: _flashOn,
                          onTap: _toggleFlash,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (widget.cameras.length > 1)
                        _IconBtn(icon: Icons.flip_camera_ios_rounded, onTap: _switchCamera),
                    ]),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom hint (no face / too close) ──────────────────────────────
          if (ready && !_faceFound)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.face_outlined, color: Colors.white38, size: 22),
                      SizedBox(width: 10),
                      Text('Position your face in the frame',
                          style: TextStyle(color: Colors.white38, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),

        ],
      ),
    );
  }
}

// ─── helpers ──────────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _IconBtn({required this.icon, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFD600) : Colors.black45,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: active ? Colors.black87 : Colors.white, size: 22),
      ),
    );
  }
}

class _CameraFill extends StatelessWidget {
  final CameraController controller;
  const _CameraFill({required this.controller});
  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize!;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(width: size.height, height: size.width,
          child: CameraPreview(controller)),
    );
  }
}

class _FaceBoxPainter extends CustomPainter {
  final Rect   bbox;
  final int    imgW;
  final int    imgH;
  final Color  color;
  final String scoreText;
  final bool   flipHorizontal;

  const _FaceBoxPainter({
    required this.bbox,
    required this.imgW,
    required this.imgH,
    required this.color,
    required this.scoreText,
    required this.flipHorizontal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // BoxFit.cover scale: fill the screen, preserve aspect ratio, centre.
    final scaleX = size.width  / imgW;
    final scaleY = size.height / imgH;
    final scale  = scaleX > scaleY ? scaleX : scaleY;
    final dx = (size.width  - imgW * scale) / 2;
    final dy = (size.height - imgH * scale) / 2;

    // Map bbox from image coords → screen coords.
    double left  = bbox.left  * scale + dx;
    double top   = bbox.top   * scale + dy;
    double right = bbox.right * scale + dx;
    double bot   = bbox.bottom * scale + dy;

    // Front camera preview is mirrored — flip horizontally.
    if (flipHorizontal) {
      final newLeft  = size.width - right;
      final newRight = size.width - left;
      left  = newLeft;
      right = newRight;
    }

    final rect = Rect.fromLTRB(left, top, right, bot);

    // Draw box
    final boxPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(rect, boxPaint);

    // Corner accents
    const cLen = 18.0;
    final cp = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;
    // top-left
    canvas.drawLine(Offset(left, top + cLen), Offset(left, top), cp);
    canvas.drawLine(Offset(left, top), Offset(left + cLen, top), cp);
    // top-right
    canvas.drawLine(Offset(right - cLen, top), Offset(right, top), cp);
    canvas.drawLine(Offset(right, top), Offset(right, top + cLen), cp);
    // bottom-left
    canvas.drawLine(Offset(left, bot - cLen), Offset(left, bot), cp);
    canvas.drawLine(Offset(left, bot), Offset(left + cLen, bot), cp);
    // bottom-right
    canvas.drawLine(Offset(right - cLen, bot), Offset(right, bot), cp);
    canvas.drawLine(Offset(right, bot), Offset(right, bot - cLen), cp);

    // Score label — pill above the box
    final tp = TextPainter(
      text: TextSpan(
        text: ' $scoreText ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 6.0;
    const padV = 4.0;
    final pillW = tp.width + padH * 2;
    final pillH = tp.height + padV * 2;
    final pillLeft  = (left + right) / 2 - pillW / 2;
    final pillTop   = top - pillH - 6;

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pillLeft, pillTop, pillW, pillH),
      const Radius.circular(6),
    );
    canvas.drawRRect(pillRect, Paint()..color = color.withOpacity(0.85));
    tp.paint(canvas, Offset(pillLeft + padH, pillTop + padV));
  }

  @override
  bool shouldRepaint(_FaceBoxPainter old) =>
      old.bbox != bbox || old.color != color || old.scoreText != scoreText;
}


