import 'dart:io';
import 'package:flutter/material.dart';
import 'settings_store.dart';

// Brand palette (matches main.dart)
const _kBlue    = Color(0xFF1565C0);
const _kIndigo  = Color(0xFF5C6BC0);
const _kTeal    = Color(0xFF00897B);
const _kTextPri = Color(0xFF0D1B2A);
const _kTextSec = Color(0xFF546E7A);
const _kTextHint= Color(0xFF90A4AE);
const _kSurface = Color(0xFFF5F7FA);
const _kBorder  = Color(0xFFE3E8EF);

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
            ' — Front ${SettingsStore.defaultLivenessThreshold.round()}%,'
            ' Back ${SettingsStore.defaultBackCameraThreshold.round()}%',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: _kBlue,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kTextPri,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text('Detection Settings',
            style: TextStyle(
                color: _kTextPri, fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Reset', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBlue,
                side: const BorderSide(color: _kBorder),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('LIVENESS'),
            const SizedBox(height: 10),

            _SliderCard(
              icon: Icons.camera_front_rounded,
              iconColor: _kIndigo,
              title: 'Front Camera',
              subtitle: 'Minimum score for selfie / front camera',
              value: _livenessThreshold,
              min: _minLiveness,
              max: _maxLiveness,
              color: _kIndigo,
              onChanged: (v) => setState(() => _livenessThreshold = v),
              onSave: (v) => SettingsStore.setLivenessThreshold(v),
            ),

            const SizedBox(height: 12),

            _SliderCard(
              icon: Icons.camera_rear_rounded,
              iconColor: _kTeal,
              title: 'Back Camera',
              subtitle: 'Minimum score for back / document camera',
              value: _backCameraThreshold,
              min: _minLiveness,
              max: _maxLiveness,
              color: _kTeal,
              onChanged: (v) => setState(() => _backCameraThreshold = v),
              onSave: (v) => SettingsStore.setBackCameraThreshold(v),
            ),

            const SizedBox(height: 24),
            const _SectionLabel('FACE MATCHING'),
            const SizedBox(height: 10),

            _SliderCard(
              icon: Icons.how_to_reg_rounded,
              iconColor: _kBlue,
              title: 'Match Confidence',
              subtitle: 'Minimum similarity % to confirm identity',
              value: _matchThreshold,
              min: _minMatch,
              max: _maxMatch,
              color: _kBlue,
              onChanged: (v) => setState(() => _matchThreshold = v),
              onSave: (v) => SettingsStore.setMatchThreshold(v),
            ),

            const SizedBox(height: 28),

            // Info note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBlue.withValues(alpha: 0.15)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: _kBlue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Higher values are stricter — they reduce false positives '
                      'but may reject genuine users in poor lighting. '
                      'Lower values are more lenient.',
                      style: TextStyle(
                          color: _kTextSec, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: _kTextHint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slider card
// ─────────────────────────────────────────────────────────────────────────────

class _SliderCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onSave;

  const _SliderCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final pct = value / max;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title row
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: _kTextPri,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 1),
              Text(subtitle,
                  style: const TextStyle(color: _kTextHint, fontSize: 11)),
            ]),
          ),
          // Value badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${value.round()}%',
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]),

        const SizedBox(height: 14),

        // Progress bar (visual indicator above slider)
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (value - min) / (max - min),
            minHeight: 4,
            backgroundColor: _kSurface,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),

        const SizedBox(height: 2),

        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: _kSurface,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.12),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
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

        // Min / Max labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${min.round()}%  Lenient',
                  style: const TextStyle(color: _kTextHint, fontSize: 10)),
              Text('${max.round()}%  Strict',
                  style: const TextStyle(color: _kTextHint, fontSize: 10)),
            ],
          ),
        ),
      ]),
    );
  }
}
