import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _kMatchThreshold      = 'match_threshold';
  static const _kLivenessThreshold   = 'liveness_threshold';
  static const _kBackCameraThreshold = 'back_camera_threshold';

  // Mirror the package-side platform defaults
  static double get defaultLivenessThreshold   => Platform.isIOS ? 60.0 : 30.0;
  static double get defaultBackCameraThreshold => Platform.isIOS ? 90.0 : 80.0;
  static const double defaultMatchThreshold    = 50.0;

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static double get matchThreshold =>
      _prefs?.getDouble(_kMatchThreshold) ?? defaultMatchThreshold;

  static double get livenessThreshold =>
      (_prefs?.getDouble(_kLivenessThreshold) ?? defaultLivenessThreshold) / 100.0;

  static double get backCameraThreshold =>
      (_prefs?.getDouble(_kBackCameraThreshold) ?? defaultBackCameraThreshold) / 100.0;

  static Future<void> setMatchThreshold(double value) =>
      _prefs!.setDouble(_kMatchThreshold, value);

  static Future<void> setLivenessThreshold(double value) =>
      _prefs!.setDouble(_kLivenessThreshold, value);

  static Future<void> setBackCameraThreshold(double value) =>
      _prefs!.setDouble(_kBackCameraThreshold, value);

  static Future<void> resetToDefaults() async {
    await _prefs!.setDouble(_kLivenessThreshold, defaultLivenessThreshold);
    await _prefs!.setDouble(_kBackCameraThreshold, defaultBackCameraThreshold);
    await _prefs!.setDouble(_kMatchThreshold, defaultMatchThreshold);
  }
}
