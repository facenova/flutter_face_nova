import 'dart:io';
import 'package:flutter/material.dart';
import 'settings_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _matchThreshold;
  late double _livenessThreshold;
  late double _backCameraThreshold;

  static double get _minLiveness => Platform.isAndroid ? 5.0 : 30.0;
  static double get _maxLiveness => 100.0;
  static double get _minMatch    => Platform.isAndroid ? 5.0 : 30.0;
  static double get _maxMatch    => 100.0;

  @override
  void initState() {
    super.initState();
    _matchThreshold      = SettingsStore.matchThreshold;
    _livenessThreshold   = SettingsStore.livenessThreshold * 100;
    _backCameraThreshold = SettingsStore.backCameraThreshold * 100;
  }

  Future<void> _resetToDefaults() async {
    await SettingsStore.resetToDefaults();
    setState(() {
      _livenessThreshold   = SettingsStore.defaultLivenessThreshold;
      _backCameraThreshold = SettingsStore.defaultBackCameraThreshold;
      _matchThreshold      = SettingsStore.defaultMatchThreshold;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reset to ${Platform.isIOS ? "iOS" : "Android"} defaults'
                ' (Front ${SettingsStore.defaultLivenessThreshold.round()}%,'
                ' Back ${SettingsStore.defaultBackCameraThreshold.round()}%)',
          ),
          backgroundColor: const Color(0xFF22D37A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1E),
        foregroundColor: Colors.white,
        title: const Text('Settings',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF4D9EFF)),
            label: Text(
              'Reset ${Platform.isIOS ? "iOS" : "Android"}',
              style: const TextStyle(color: Color(0xFF4D9EFF), fontSize: 13),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('THRESHOLDS',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 14),

            _ThresholdCard(
              title: 'Front Camera Liveness',
              subtitle: 'Minimum liveness score for front (selfie) camera.',
              value: _livenessThreshold,
              min: _minLiveness,
              max: _maxLiveness,
              minLabel: '${_minLiveness.round()}%  (Lenient)',
              maxLabel: '${_maxLiveness.round()}%  (Strict)',
              color: const Color(0xFF4D9EFF),
              onChanged: (v) => setState(() => _livenessThreshold = v),
              onSave: (v) async => SettingsStore.setLivenessThreshold(v),
            ),

            const SizedBox(height: 16),

            _ThresholdCard(
              title: 'Back Camera Liveness',
              subtitle: 'Minimum liveness score for back (document/ID) camera.',
              value: _backCameraThreshold,
              min: _minLiveness,
              max: _maxLiveness,
              minLabel: '${_minLiveness.round()}%  (Lenient)',
              maxLabel: '${_maxLiveness.round()}%  (Strict)',
              color: const Color(0xFFFF9800),
              onChanged: (v) => setState(() => _backCameraThreshold = v),
              onSave: (v) async => SettingsStore.setBackCameraThreshold(v),
            ),

            const SizedBox(height: 16),

            _ThresholdCard(
              title: 'Face Match Threshold',
              subtitle: 'Face must match at least this % to pass identity verification.',
              value: _matchThreshold,
              min: _minMatch,
              max: _maxMatch,
              minLabel: '${_minMatch.round()}%  (Lenient)',
              maxLabel: '${_maxMatch.round()}%  (Strict)',
              color: const Color(0xFF22D37A),
              onChanged: (v) => setState(() => _matchThreshold = v),
              onSave: (v) async => SettingsStore.setMatchThreshold(v),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThresholdCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final String minLabel;
  final String maxLabel;
  final Color color;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSave;

  const _ThresholdCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.minLabel,
    required this.maxLabel,
    required this.color,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${value.round()}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: Colors.white12,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.15),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: onChanged,
              onChangeEnd: onSave,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(minLabel,
                  style: const TextStyle(color: Colors.white24, fontSize: 11)),
              Text(maxLabel,
                  style: const TextStyle(color: Colors.white24, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
