import 'dart:typed_data';
import 'package:flutter/services.dart';

// ─── License exception types ──────────────────────────────────────────────────

class LicenseException implements Exception {
  final String message;
  const LicenseException(this.message);
  @override
  String toString() => 'LicenseException: $message';
}

class LicenseExpiredException extends LicenseException {
  const LicenseExpiredException() : super('License key has expired.');
}

class LicensePackageMismatchException extends LicenseException {
  const LicensePackageMismatchException()
      : super('License key is not valid for this app package/bundle ID.');
}

class LicenseTamperedException extends LicenseException {
  const LicenseTamperedException()
      : super('License key integrity check failed. Token may be tampered.');
}

class LicenseFormatException extends LicenseException {
  const LicenseFormatException() : super('License key format is invalid.');
}

// ─── LivenessGuard ────────────────────────────────────────────────────────────

/// Internal license gate. All crypto and model decryption is handled in native
/// C++ (Android) / ObjC++ (iOS) via the 'liveness_flutter/secure' MethodChannel.
///
/// Call [verifyLicense] once at startup before using any SDK feature.
/// All model-loading methods check [isVerified].
class LivenessGuard {
  static const _ch = MethodChannel('liveness_flutter/secure');
  static bool _verified = false;

  static bool get isVerified => _verified;

  /// Verifies the offline license token via native layer.
  ///
  /// [token] — the Base64-encoded, XOR-encrypted license token.
  /// The package name is read from the OS by native C++ — never trusted from Dart.
  ///
  /// Throws a [LicenseException] subclass on failure.
  static Future<void> verifyLicense(String token) async {
    _verified = false;
    if (token.isEmpty) throw const LicenseFormatException();
    try {
      final ok = await _ch.invokeMethod<bool>('verifyLicense', {'token': token});
      if (ok == true) {
        _verified = true;
      } else {
        throw const LicenseException(
            'License verification failed. Check token, package ID, and expiry.');
      }
    } on PlatformException catch (e) {
      throw LicenseException('Native error: ${e.message}');
    }
  }

  /// Decrypts and returns model bytes for modelId = 1, 2, or 3.
  ///
  /// Decryption happens entirely in native C++/ObjC++ — keys never appear in
  /// Dart code. Throws [LicenseException] if not verified or decryption fails.
  static Future<Uint8List> decryptModel(int modelId) async {
    if (!_verified) {
      throw const LicenseException(
          'SDK not initialized. Call FlutterFaceNova.initialize() first.');
    }
    try {
      final result = await _ch.invokeMethod('decryptModel', {'modelId': modelId});
      if (result == null) {
        throw const LicenseException(
            'Model decryption failed — license may not be valid for this device.');
      }
      if (result is Uint8List) return result;
      if (result is List<int>) return Uint8List.fromList(result);
      // FlutterStandardTypedData from iOS
      try {
        // ignore: avoid_dynamic_calls
        final buf = (result as dynamic).buffer;
        if (buf != null) return (buf as ByteBuffer).asUint8List();
      } catch (_) {}
      return Uint8List.fromList(List<int>.from(result as List));
    } on LicenseException {
      rethrow;
    } on PlatformException catch (e) {
      throw LicenseException('Model load error: ${e.message}');
    }
  }
}
