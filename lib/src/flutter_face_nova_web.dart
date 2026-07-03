import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'liveness_types.dart';

/// Web-compatible implementation of FlutterFaceNova that avoids native/FFI dependencies.
class FlutterFaceNova {
  /// Start liveness detection. Not supported on web.
  static Future<LivenessResult?> startLiveness(
    BuildContext context, {
    double livenessThreshold = 0.99,
  }) async {
    debugPrint("Liveness detection UI is not supported on Web.");
    return null;
  }

  /// Generate face metadata. Returns null on web because native ONNX is not supported.
  /// Web clients should delegate metadata generation to the SFace Python backend.
  static Future<FaceMetadataResult?> generateFaceMetadata(
    Uint8List imageBytes,
  ) async {
    debugPrint("Local face metadata generation is not supported on Web. Use the server API instead.");
    return null;
  }

  /// Compares two metadata arrays and returns a strict match percentage (0 to 100).
  /// This works on Web because it is pure Dart code.
  static double compareFaceMetadata(
    Uint8List metadata1, 
    Uint8List metadata2, {
    double matchThreshold = 0.363,
  }) {
    final floatList1 = Float32List.view(metadata1.buffer);
    final floatList2 = Float32List.view(metadata2.buffer);

    if (floatList1.length != floatList2.length) return 0.0;
    int len = floatList1.length;

    double dotProduct = 0.0;
    for (int i = 0; i < len; i++) {
      dotProduct += floatList1[i] * floatList2[i];
    }

    // Similarity is cosine similarity since vectors are normalized (-1.0 to 1.0)
    double similarity = dotProduct;

    // SFace threshold mapping (same as mobile)
    double percentage;
    if (similarity >= matchThreshold) {
      percentage = 80.0 + ((similarity - matchThreshold) / (1.0 - matchThreshold)) * 20.0;
    } else {
      percentage = math.max(0.0, ((similarity + 1.0) / (matchThreshold + 1.0)) * 79.0);
    }

    return percentage.clamp(0.0, 100.0);
  }
}
