import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import 'liveness_guard.dart';

// Top-level so compute() can run it in a background isolate.
// Decodes any format (HEIC, JPEG, PNG…), bakes EXIF orientation,
// and downscales to ≤1280px — enough for ML Kit, avoids OOM on large photos.
Uint8List _decodeOrientAndDownscale(Uint8List bytes) {
  var src = img.decodeImage(bytes);
  if (src == null) throw Exception('Could not decode image');
  src = img.bakeOrientation(src);
  const maxDim = 1280;
  if (src.width > maxDim || src.height > maxDim) {
    final scale = maxDim / math.max(src.width, src.height);
    src = img.copyResize(src,
        width: (src.width * scale).round(),
        height: (src.height * scale).round());
  }
  return Uint8List.fromList(img.encodeJpg(src, quality: 90));
}

class FaceMatchEngine {
  OrtSession? _session;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      // Decrypt SFace model bytes via the license guard
      final bytes = await LivenessGuard.decryptModel(3);
      _session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
      _loaded = true;
    } catch (e) {
      _loaded = false;
      rethrow;
    }
  }

  bool get isLoaded => _loaded;

  /// Generates a 128D face embedding and returns the cropped face bytes.
  Future<Map<String, dynamic>> generateMetadata(Uint8List imageBytes) async {
    if (!_loaded || _session == null) throw StateError('FaceMatchEngine not loaded');

    // Decode, bake EXIF orientation, and downscale in a background isolate so
    // the UI thread stays responsive. Full-res gallery photos (12–50MP) would
    // otherwise freeze the UI for 5–15s and risk OOM on mid-range devices.
    final sw = Stopwatch()..start();
    final jpegBytes = await compute(_decodeOrientAndDownscale, imageBytes);
    debugPrint('[FaceMatch] decode+downscale: ${sw.elapsedMilliseconds}ms');

    // Re-decode the small JPEG (≤1280px) on the main thread — fast (<100ms).
    var src = img.decodeImage(jpegBytes);
    if (src == null) throw Exception('Could not decode processed image');

    Rect? faceRect;
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      // Random name prevents timing-based reads on rooted devices
      final name = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
      tempFile = File('${tempDir.path}/$name.tmp');
      await tempFile.writeAsBytes(jpegBytes);

      final faceDetector = FaceDetector(
          options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      if (faces.isNotEmpty) faceRect = faces.first.boundingBox;
      debugPrint('[FaceMatch] ML Kit detection: ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint("Warning: Face detection failed before extraction: $e");
    } finally {
      // Delete immediately — never leave biometric data on disk
      try { await tempFile?.delete(); } catch (_) {}
    }

    img.Image patch;
    img.Image displayCrop;
    if (faceRect != null) {
      int cx = (faceRect.left + faceRect.width / 2).round();
      int cy = (faceRect.top + faceRect.height / 2).round();
      int sideLen = (math.max(faceRect.width, faceRect.height) * 1.2).round();

      int x = (cx - sideLen ~/ 2).clamp(0, src.width - 1);
      int y = (cy - sideLen ~/ 2).clamp(0, src.height - 1);
      int w = sideLen.clamp(1, src.width - x);
      int h = sideLen.clamp(1, src.height - y);

      displayCrop = img.copyCrop(src, x: x, y: y, width: w, height: h);
      patch = img.copyResize(displayCrop, width: 112, height: 112);
    } else {
      displayCrop = src;
      patch = img.copyResize(src, width: 112, height: 112);
    }

    final tensor = _imageToTensor(patch, 112, 112);
    final inputs = {'data': tensor};
    List<OrtValue?>? results;
    try {
      results = await _session!.runAsync(OrtRunOptions(), inputs);
      results ??= _session!.run(OrtRunOptions(), inputs); // fallback
      final output = results[0]?.value as List<List<double>>;
      debugPrint('[FaceMatch] total generateMetadata: ${sw.elapsedMilliseconds}ms');
      return {
        'metadata': _normalize(output[0]),
        'croppedImage': Uint8List.fromList(img.encodeJpg(displayCrop))
      };
    } finally {
      results?.forEach((v) => v?.release());
      tensor.release();
    }
  }

  double compare(List<double> meta1, List<double> meta2) {
    if (meta1.length != meta2.length) return 0.0;
    double dotProduct = 0.0;
    for (int i = 0; i < meta1.length; i++) {
      dotProduct += meta1[i] * meta2[i];
    }
    double percentage = ((dotProduct + 1.0) / 2.0) * 100.0;
    return percentage;
  }

  List<double> _normalize(List<double> v) {
    double sumSq = 0.0;
    for (final val in v) sumSq += val * val;
    final length = math.sqrt(sumSq);
    if (length == 0) return v;
    return v.map((e) => e / length).toList();
  }

  OrtValueTensor _imageToTensor(img.Image patch, int H, int W) {
    final data = Float32List(3 * H * W);
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        final pixel = patch.getPixel(x, y);
        data[0 * H * W + y * W + x] = pixel.b.toDouble();
        data[1 * H * W + y * W + x] = pixel.g.toDouble();
        data[2 * H * W + y * W + x] = pixel.r.toDouble();
      }
    }
    return OrtValueTensor.createTensorWithDataList(data, [1, 3, H, W]);
  }

  void dispose() {
    _session?.release();
  }
}
