import 'dart:typed_data';

/// Result returned from the liveness detection screen.
class LivenessResult {
  /// Whether the person is real (true) or a spoof (false).
  final bool isReal;

  /// Raw confidence score from the anti-spoof engine (0.0 – 1.0).
  final double score;

  /// Full camera frame captured at the moment of evaluation.
  final Uint8List? imageBytes;

  const LivenessResult({
    required this.isReal,
    required this.score,
    required this.imageBytes,
  });
}

/// A single enrolled person stored by the host application.
///
/// Create one via [FlutterFaceNova.generateFaceMetadata] and persist it
/// however you like (Hive, SQLite, SharedPreferences, etc.).
class FaceEntry {
  /// Unique identifier — use a UUID or any stable string.
  final String id;

  /// Display name shown in match results.
  final String name;

  /// 128-D face embedding stored as raw Float32 bytes
  /// (from [FaceMetadataResult.metadata]).
  final Uint8List metadata;

  /// Optional JPEG thumbnail of the cropped face
  /// (from [FaceMetadataResult.croppedImage]).
  final Uint8List? photo;

  const FaceEntry({
    required this.id,
    required this.name,
    required this.metadata,
    this.photo,
  });
}

/// Result returned from [FlutterFaceNova.startFaceMatch].
class FaceMatchResult {
  /// The best-matching enrolled face, or null if no match was found.
  final FaceEntry? matchedFace;

  /// Match score 0 – 100.  ≥ 75 is a strong match.
  final double score;

  /// True when [score] is above the threshold used for this session.
  final bool isMatch;

  /// JPEG bytes of the face captured during the match scan.
  final Uint8List? capturedImage;

  const FaceMatchResult({
    required this.matchedFace,
    required this.score,
    required this.isMatch,
    required this.capturedImage,
  });
}

/// Result returned when extracting a face embedding from an image.
class FaceMetadataResult {
  /// 128-D face embedding as raw Float32 bytes.
  /// Pass directly to [FlutterFaceNova.compareFaceMetadata] or store as-is.
  final Uint8List metadata;

  /// JPEG-encoded crop of the detected face.
  final Uint8List croppedImage;

  const FaceMetadataResult({
    required this.metadata,
    required this.croppedImage,
  });
}
