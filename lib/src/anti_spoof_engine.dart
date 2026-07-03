import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'liveness_guard.dart';

const double kLivenessThreshold = 0.99;

class _ModelConfig {
  final int modelId;   // matches LivenessGuard.decryptModel(id)
  final int hInput;
  final int wInput;
  final double scale;

  const _ModelConfig({
    required this.modelId,
    required this.hInput,
    required this.wInput,
    required this.scale,
  });
}

const List<_ModelConfig> kModels = [
  _ModelConfig(modelId: 1, hInput: 80, wInput: 80, scale: 2.7),
  _ModelConfig(modelId: 2, hInput: 80, wInput: 80, scale: 4.0),
];

class AntiSpoofEngine {
  final List<OrtSession> _sessions = [];
  bool _loaded = false;
  String? loadError;

  Future<void> load() async {
    _sessions.clear();
    loadError = null;
    try {
      for (final cfg in kModels) {
        // Decrypt model bytes via the license guard — will throw if not licensed
        final bytes = await LivenessGuard.decryptModel(cfg.modelId);
        final session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
        _sessions.add(session);
      }
      _loaded = true;
    } catch (e) {
      loadError = e.toString();
      _loaded = false;
      rethrow;
    }
  }

  bool get isLoaded => _loaded;

  Future<double> predict(img.Image fullImage, Rect faceBbox) async {
    if (!_loaded || _sessions.isEmpty) throw StateError('Engine not loaded');

    final List<double> scores = [];

    for (int i = 0; i < kModels.length; i++) {
      final cfg = kModels[i];
      final session = _sessions[i];

      final patch = _cropPatch(fullImage, faceBbox, cfg);
      final tensor = _imageToTensor(patch, cfg.hInput, cfg.wInput);

      final inputs = {'input': tensor};
      List<OrtValue?>? results;
      try {
        // runAsync dispatches to OrtIsolateSession (background isolate),
        // keeping the main thread free and preventing ANR.
        results = await session.runAsync(OrtRunOptions(), inputs);
        results ??= session.run(OrtRunOptions(), inputs); // fallback
      } finally {
        tensor.release();
      }

      if (results.isEmpty || results[0] == null) {
        throw StateError('ONNX run returned null result for model $i');
      }

      final classifierOutput = results[0]!.value as List;
      final List<double> logits = (classifierOutput[0] as List)
          .map((e) => (e as num).toDouble())
          .toList();

      final probs = _softmax(logits);
      scores.add(probs[1]);

      for (final r in results) {
        r?.release();
      }
    }

    // Use minimum score across all models — both must independently agree
    // the face is real. Averaging allows one weak model to be pulled up by
    // a strong one; minimum requires every model to be convinced.
    return scores.reduce(math.min);
  }

  img.Image _cropPatch(img.Image src, Rect bbox, _ModelConfig cfg) {
    final cx = bbox.left + bbox.width / 2;
    final cy = bbox.top + bbox.height / 2;
    final sideLen = math.max(bbox.width, bbox.height) * cfg.scale;

    final x = (cx - sideLen / 2).round().clamp(0, src.width - 1);
    final y = (cy - sideLen / 2).round().clamp(0, src.height - 1);
    final w = sideLen.round().clamp(1, src.width - x);
    final h = sideLen.round().clamp(1, src.height - y);

    final cropped = img.copyCrop(src, x: x, y: y, width: w, height: h);
    return img.copyResize(cropped, width: cfg.wInput, height: cfg.hInput);
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

  List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(math.max);
    final exp = logits.map((v) => math.exp(v - maxVal)).toList();
    final sum = exp.reduce((a, b) => a + b);
    return exp.map((e) => e / sum).toList();
  }

  void dispose() {
    for (final s in _sessions) {
      s.release();
    }
    OrtEnv.instance.release();
  }
}
