import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'face_match_engine.dart';
import 'liveness_types.dart';

List<Object> _fmProcessIsolate(Uint8List bytes) {
  var im = img.decodeJpg(bytes);
  if (im == null) return [bytes, Uint8List(0), 0, 0];
  im = img.bakeOrientation(im);
  final oriented = Uint8List.fromList(img.encodeJpg(im));
  final pixels   = Uint8List.fromList(im.getBytes(order: img.ChannelOrder.rgba));
  return [oriented, pixels, im.width, im.height];
}

class FaceMatchScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final List<FaceEntry> enrolledFaces;
  final FaceMatchEngine preloadedEngine;
  final double matchThreshold;

  const FaceMatchScreen({
    super.key,
    required this.cameras,
    required this.enrolledFaces,
    required this.preloadedEngine,
    this.matchThreshold = 75.0,
  });

  @override
  State<FaceMatchScreen> createState() => _FaceMatchScreenState();
}

class _FaceMatchScreenState extends State<FaceMatchScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _ctrl;
  int _camIdx = 0;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
  );

  static const _nativeCh = MethodChannel('liveness_flutter/camera');

  bool _ready      = false;
  bool _processing = false;
  Timer? _timer;

  bool   _faceFound   = false;
  bool   _flashOn     = false;
  double _bestScore   = 0;
  String _statusLabel = 'Position your face in the frame';

  late AnimationController _scanAnim;

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _camIdx = widget.cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (_camIdx < 0) _camIdx = 0;
    _initCamera();
  }

  Future<void> _initCamera() async {
    OrtEnv.instance.init();
    final cam    = widget.cameras[_camIdx];
    final isBack = cam.lensDirection == CameraLensDirection.back;
    final ctrl   = CameraController(
      cam,
      isBack ? ResolutionPreset.low : ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      if (isBack) await _lockFocus(ctrl);
    } catch (e) {
      debugPrint('[FaceMatch] Camera init error: $e');
      if (ctrl.value.isInitialized) ctrl.dispose();
      return;
    }
    if (!mounted) {
      if (ctrl.value.isInitialized) ctrl.dispose();
      return;
    }
    setState(() { _ctrl = ctrl; _ready = true; });
    try { await ScreenBrightness().setScreenBrightness(1.0); } catch (_) {}
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) => _run());
  }

  Future<void> _lockFocus(CameraController ctrl) async {
    try {
      if (Platform.isAndroid) {
        final info = await _nativeCh.invokeMapMethod<String, dynamic>(
            'getBackCameraFocusInfo');
        if (!(info?['hasAutofocus'] as bool? ?? true)) return;
      }
      await ctrl.setFocusMode(FocusMode.locked);
    } catch (_) {}
  }

  Future<void> _run() async {
    if (_processing || !_ready) return;
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    _processing = true;

    try {
      final xfile     = await ctrl.takePicture();
      final bytes     = await xfile.readAsBytes();
      final result    = await compute(_fmProcessIsolate, bytes);
      final oriented  = result[0] as Uint8List;
      final rawPixels = result[1] as Uint8List;
      final imgW      = result[2] as int;
      if (imgW == 0 || rawPixels.isEmpty) return;

      await File(xfile.path).writeAsBytes(oriented);

      final faces = await _faceDetector.processImage(
          InputImage.fromFilePath(xfile.path));

      if (faces.isEmpty) {
        if (mounted) setState(() { _faceFound = false; _statusLabel = 'Position your face in the frame'; });
        return;
      }

      if (mounted) setState(() { _faceFound = true; _statusLabel = 'Scanning…'; });

      final matchData    = await widget.preloadedEngine.generateMetadata(oriented);
      final capturedMeta = matchData['metadata'] as List<double>;
      final capturedImg  = matchData['croppedImage'] as Uint8List;

      double bestScore = 0;
      FaceEntry? bestMatch;

      for (final face in widget.enrolledFaces) {
        final enrolled = Float32List.view(face.metadata.buffer).toList();
        final score    = widget.preloadedEngine.compare(capturedMeta, enrolled);
        if (score > bestScore) { bestScore = score; bestMatch = face; }
      }

      if (!mounted) return;
      setState(() { _bestScore = bestScore; });

      if (bestScore >= widget.matchThreshold && bestMatch != null) {
        _timer?.cancel();
        setState(() => _statusLabel = 'Matched · ${bestMatch!.name}');
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          Navigator.pop(context, FaceMatchResult(
            matchedFace: bestMatch,
            score: bestScore,
            isMatch: true,
            capturedImage: capturedImg,
          ));
        }
      } else {
        if (mounted) setState(() => _statusLabel = 'Scanning… (${bestScore.toStringAsFixed(0)}%)');
      }
    } catch (e) {
      debugPrint('[FaceMatch] error: $e');
    } finally {
      _processing = false;
    }
  }

  Future<void> _switchCamera() async {
    _timer?.cancel();
    final old = _ctrl;
    if (old != null && old.value.isInitialized) await old.dispose();
    if (mounted) setState(() { _ctrl = null; _ready = false; _faceFound = false; _flashOn = false; });
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

  @override
  void dispose() {
    _timer?.cancel();
    _scanAnim.dispose();
    final ctrl = _ctrl;
    _ctrl = null;
    if (ctrl != null && ctrl.value.isInitialized) ctrl.dispose();
    _faceDetector.close();
    ScreenBrightness().resetScreenBrightness().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl    = _ctrl;
    final ready   = ctrl != null && ctrl.value.isInitialized && _ready;
    final pct     = _bestScore;
    final isMatch = pct >= widget.matchThreshold;
    final activeColor = !_faceFound
        ? const Color(0xFF4D9EFF)
        : isMatch ? const Color(0xFF22D37A) : const Color(0xFF4D9EFF);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── Camera preview (fills behind everything) ──────────────────────
          if (ready)
            _CameraFill(controller: ctrl)
          else
            // While camera warms up — dark background, no black flash
            Container(color: const Color(0xFF0A0F1E)),

          // ── Gradient overlay (bottom) ─────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            height: MediaQuery.of(context).size.height * 0.45,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xF0000000), Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Scan line animation ───────────────────────────────────────────
          if (ready && _faceFound)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scanAnim,
                builder: (_, __) {
                  final y = _scanAnim.value * MediaQuery.of(context).size.height;
                  return CustomPaint(painter: _ScanLinePainter(y: y, color: activeColor));
                },
              ),
            ),

          // ── Top bar ───────────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Identity Verification',
                        style: TextStyle(color: Colors.white, fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (ready && widget.cameras[_camIdx].lensDirection == CameraLensDirection.back) ...[
                      _IconBtn(
                        icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        active: _flashOn, onTap: _toggleFlash,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (widget.cameras.length > 1)
                      _IconBtn(icon: Icons.flip_camera_ios_rounded, onTap: _switchCamera),
                  ],
                ),
              ),
            ),
          ),

          // ── Enrolled faces strip ──────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 0, right: 0,
            child: _EnrolledStrip(faces: widget.enrolledFaces),
          ),

          // ── Bottom status card ────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _StatusCard(
                  ready: ready,
                  faceFound: _faceFound,
                  score: pct,
                  label: _statusLabel,
                  color: activeColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Enrolled faces strip shown at top while scanning
// ─────────────────────────────────────────────────────────────────────────────

class _EnrolledStrip extends StatelessWidget {
  final List<FaceEntry> faces;
  const _EnrolledStrip({required this.faces});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.manage_search_rounded, color: Color(0xFF4D9EFF), size: 18),
          const SizedBox(width: 8),
          Text('Matching against ${faces.length} face${faces.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const Spacer(),
          SizedBox(
            height: 32,
            child: ListView.separated(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              itemCount: faces.length > 4 ? 4 : faces.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, i) {
                final face = faces[i];
                return Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF4D9EFF), width: 1.5),
                  ),
                  child: ClipOval(
                    child: face.photo != null
                        ? Image.memory(face.photo!, fit: BoxFit.cover)
                        : const ColoredBox(color: Color(0xFF1A2540)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom status card
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool ready;
  final bool faceFound;
  final double score;
  final String label;
  final Color color;
  const _StatusCard({
    required this.ready, required this.faceFound, required this.score,
    required this.label, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: !ready
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color)),
              const SizedBox(width: 12),
              const Text('Starting camera…',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ])
          : faceFound
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${score.toStringAsFixed(0)}%',
                      style: TextStyle(color: color, fontSize: 52,
                          fontWeight: FontWeight.w800, letterSpacing: -1)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.radar_rounded, color: color, size: 16),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(color: color, fontSize: 14,
                        fontWeight: FontWeight.w600)),
                  ]),
                ])
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.face_outlined, color: Colors.white38, size: 22),
                  const SizedBox(width: 10),
                  Text(label,
                      style: const TextStyle(color: Colors.white54, fontSize: 14)),
                ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scan line painter
// ─────────────────────────────────────────────────────────────────────────────

class _ScanLinePainter extends CustomPainter {
  final double y;
  final Color color;
  const _ScanLinePainter({required this.y, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, color.withValues(alpha: 0.6), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, y - 40, size.width, 80))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.y != y;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

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
