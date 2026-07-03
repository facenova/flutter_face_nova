import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_face_nova/flutter_face_nova.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'enrolled_face.dart';
import 'settings_screen.dart';
import 'settings_store.dart';
import 'store_preview_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// License keys
// ─────────────────────────────────────────────────────────────────────────────
const _kLicenseKeyAndroid =
    'LxkrQhkdAlYcLkAKcV5fVykYIx8GKxVDAjcBSG0EGxF6W3VcCT4zfVkpYEEydGVq'
    'ODMzQzQSIUcxOmNLM39wcXgzCjg7B0MLNw4CEDFadGRx';

const _kLicenseKeyIOS =
    'LxkrQhkdAlYcLkAKcV5fVykYIx8GNQRDDnkDS2gfBxNhRXcQR0YiYQomRE0aRkcX'
    'GzUMXk0OJnldfgA4O1pSaSQbBCY+RAFDGwV2G2d1Dhw=';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────
const _kBlue      = Color(0xFF1565C0);
const _kBlueLight = Color(0xFF1E88E5);
const _kGreen     = Color(0xFF2E7D32);
const _kGreenMid  = Color(0xFF43A047);
const _kRed       = Color(0xFFC62828);
const _kTextPri   = Color(0xFF0D1B2A);
const _kTextSec   = Color(0xFF546E7A);
const _kTextHint  = Color(0xFF90A4AE);
const _kSurface   = Color(0xFFF5F7FA);
const _kBorder    = Color(0xFFE3E8EF);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FaceStore.init();
  await SettingsStore.init();
  await Permission.camera.request();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FaceNova',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: _kSurface,
        colorScheme: ColorScheme.fromSeed(
            seedColor: _kBlue, brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Screen
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _MatchStep { idle, liveness, matching }

class _HomeScreenState extends State<HomeScreen> {
  List<EnrolledFace> _enrolled       = [];
  FaceMatchResult?   _matchResult;
  LivenessResult?    _livenessFailResult;
  _MatchStep         _step    = _MatchStep.idle;
  bool               _enrolling = false;

  @override
  void initState() {
    super.initState();
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSdk());
  }

  Future<void> _initSdk() async {
    try {
      final key = Platform.isIOS ? _kLicenseKeyIOS : _kLicenseKeyAndroid;
      await LivenessFlutter.initialize(licenseKey: key);
    } catch (e) {
      debugPrint('[FaceNova] SDK init error: $e');
    }
    if (mounted) setState(() {});
  }

  void _reload() => setState(() => _enrolled = FaceStore.getAll());

  // ── Enrol from gallery ──────────────────────────────────────────────────────
  Future<void> _enrollFromGallery() async {
    if (_step != _MatchStep.idle) return;
    final xfile = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile == null || !mounted) return;

    final bytes = await xfile.readAsBytes();
    if (!mounted) return;

    setState(() { _step = _MatchStep.liveness; _enrolling = true; });
    try {
      final meta = await LivenessFlutter.generateFaceMetadata(bytes);
      if (meta == null) { _showSnack('No face found in that photo.'); return; }

      final name = await _askName();
      if (name == null || name.trim().isEmpty) return;

      await FaceStore.add(EnrolledFace(
        id: const Uuid().v4(),
        name: name.trim(),
        metadata: meta.metadata,
        photo: meta.croppedImage,
      ));
      _reload();
      _showSnack('${name.trim()} added.');
    } finally {
      if (mounted) setState(() { _step = _MatchStep.idle; _enrolling = false; });
    }
  }

  Future<String?> _askName() => showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text('Enter name'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Full name'),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text),
                  child: const Text('Save')),
            ],
          );
        },
      );

  // ── Verify ─────────────────────────────────────────────────────────────────
  Future<void> _verify() async {
    if (_step != _MatchStep.idle) return;
    if (_enrolled.isEmpty) {
      _showSnack('Register at least one person first.');
      return;
    }

    setState(() {
      _step = _MatchStep.liveness;
      _matchResult = null;
      _livenessFailResult = null;
    });

    final liveness = await LivenessFlutter.startLiveness(
      context,
      livenessThreshold: SettingsStore.livenessThreshold,
      backCameraThreshold: SettingsStore.backCameraThreshold,
    );
    if (!mounted) return;

    if (liveness == null || !liveness.isReal) {
      setState(() { _step = _MatchStep.idle; _livenessFailResult = liveness; });
      return;
    }

    setState(() => _step = _MatchStep.matching);

    bool dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _VerifyingDialog(),
    ).then((_) => dialogOpen = false);

    final result = await LivenessFlutter.matchFaceFromImage(
      liveness.imageBytes!,
      enrolledFaces: _enrolled
          .map((e) =>
              FaceEntry(id: e.id, name: e.name, metadata: e.metadata, photo: e.photo))
          .toList(),
      matchThreshold: SettingsStore.matchThreshold,
    );
    if (!mounted) return;
    if (dialogOpen) Navigator.of(context, rootNavigator: true).pop();

    setState(() {
      _step        = _MatchStep.idle;
      _matchResult = (result != null && result.isMatch) ? result : null;
    });

    final pct = (liveness.score * 100).toStringAsFixed(1);
    if (result == null || !result.isMatch) {
      _showSnack(result?.matchedFace != null
          ? 'No match — closest: ${result!.matchedFace!.name} (${result.score.toStringAsFixed(1)}%)'
          : 'No face matched. Liveness: $pct%');
    } else {
      _showSnack('Verified: ${result.matchedFace?.name}  ·  ${result.score.toStringAsFixed(1)}% match');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: _kTextPri,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _remove(EnrolledFace face) async {
    await FaceStore.remove(face.id);
    _reload();
    _showSnack('${face.name} removed.');
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final busy = _step != _MatchStep.idle;
    final ready = LivenessFlutter.isInitialized;

    return Scaffold(
      backgroundColor: _kSurface,
      // ── Top app bar ──────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 16,
        title: Row(children: [
          Image.asset('assets/icon/facenova_logo.png', width: 34, height: 34),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('FaceNova',
                  style: TextStyle(
                      color: _kTextPri,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2)),
              Text('AI Face Verification',
                  style: TextStyle(color: _kTextHint, fontSize: 10.5)),
            ],
          ),
        ]),
        actions: [
          // SDK status chip
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: ready
                  ? _kGreenMid.withValues(alpha: 0.10)
                  : _kTextHint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                ready ? Icons.shield_rounded : Icons.hourglass_bottom_rounded,
                size: 11,
                color: ready ? _kGreenMid : _kTextHint,
              ),
              const SizedBox(width: 4),
              Text(
                ready ? 'Ready' : 'Loading…',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ready ? _kGreenMid : _kTextHint),
              ),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _kTextSec, size: 22),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
              setState(() {});
            },
          ),
        ],
      ),

      // ── Body ─────────────────────────────────────────────────────────────────
      body: Column(children: [
        // Result banner (show only when there's a result)
        if (_livenessFailResult != null)
          _ResultBanner(
            success: false,
            message: 'Liveness check failed — please try again.',
          )
        else if (_matchResult != null)
          _ResultBanner(
            success: true,
            message:
                '${_matchResult!.matchedFace?.name ?? "Identity"} verified  ·  ${_matchResult!.score.toStringAsFixed(1)}% match',
            photos: (_matchResult!.matchedFace?.photo != null &&
                    _matchResult!.capturedImage != null)
                ? (
                    enrolled: _matchResult!.matchedFace!.photo!,
                    captured: _matchResult!.capturedImage!,
                  )
                : null,
          ),

        // ── Scrollable content ─────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // Section header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Registered People  (${_enrolled.length})',
                    style: const TextStyle(
                        color: _kTextPri,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  TextButton.icon(
                    onPressed: busy || !ready ? null : _enrollFromGallery,
                    icon: const Icon(Icons.person_add_rounded,
                        size: 15, color: _kBlue),
                    label: const Text('Register',
                        style: TextStyle(color: _kBlue, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Empty / loading / list
              if (_enrolling)
                _InfoTile(
                  icon: Icons.hourglass_top_rounded,
                  iconColor: _kBlue,
                  text: 'Scanning photo…',
                  trailing: const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kBlue),
                  ),
                )
              else if (_enrolled.isEmpty)
                _InfoTile(
                  icon: Icons.group_add_rounded,
                  iconColor: _kTextHint,
                  text: 'No people registered yet.\nTap Register to add someone.',
                )
              else
                ..._enrolled.map((face) => _PersonTile(
                      face: face,
                      onRemove: () => _remove(face),
                    )),
            ],
          ),
        ),
      ]),

      // ── Bottom verify button ──────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: busy || !ready ? null : _verify,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.verified_user_rounded,
                    color: Colors.white, size: 20),
            label: Text(
              busy
                  ? (_step == _MatchStep.liveness
                      ? 'Checking liveness…'
                      : 'Matching face…')
                  : !ready
                      ? 'Initialising SDK…'
                      : 'Verify Identity',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _kBlue,
              disabledBackgroundColor: _kBlue.withValues(alpha: 0.45),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result banner (replaces card — full-width at top of body)
// ─────────────────────────────────────────────────────────────────────────────

class _ResultBanner extends StatelessWidget {
  final bool success;
  final String message;
  final ({Uint8List enrolled, Uint8List captured})? photos;

  const _ResultBanner({
    required this.success,
    required this.message,
    this.photos,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? _kGreen : _kRed;
    final bg    = success
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFFFEBEE);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: bg,
      child: Row(children: [
        Icon(
          success ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: color,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        if (photos != null) ...[
          _MiniAvatar(bytes: photos!.enrolled),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, size: 14, color: color),
          const SizedBox(width: 6),
          _MiniAvatar(bytes: photos!.captured, borderColor: color),
        ],
      ]),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final Uint8List bytes;
  final Color borderColor;
  const _MiniAvatar({required this.bytes, this.borderColor = _kBorder});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: ClipOval(child: Image.memory(bytes, fit: BoxFit.cover)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Person tile (vertical list item)
// ─────────────────────────────────────────────────────────────────────────────

class _PersonTile extends StatelessWidget {
  final EnrolledFace face;
  final VoidCallback onRemove;
  const _PersonTile({required this.face, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _kBlue.withValues(alpha: 0.3), width: 2),
          ),
          child: ClipOval(child: Image.memory(face.photo, fit: BoxFit.cover)),
        ),
        const SizedBox(width: 14),
        // Name
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(face.name,
                style: const TextStyle(
                    color: _kTextPri,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            const Text('Registered · ready to verify',
                style: TextStyle(color: _kTextHint, fontSize: 11)),
          ]),
        ),
        // Remove
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_rounded,
              color: _kTextHint, size: 20),
          onPressed: onRemove,
          tooltip: 'Remove',
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info tile (empty state / loading)
// ─────────────────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final Widget? trailing;
  const _InfoTile(
      {required this.icon,
      required this.iconColor,
      required this.text,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: _kTextSec, fontSize: 13, height: 1.5)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verifying dialog
// ─────────────────────────────────────────────────────────────────────────────

class _VerifyingDialog extends StatelessWidget {
  const _VerifyingDialog();
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Step 1 done
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: _kGreenMid),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Step 1',
                  style: TextStyle(color: _kTextHint, fontSize: 11)),
              Text('Liveness Passed',
                  style: TextStyle(
                      color: _kGreenMid,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
          ]),
          Container(
              width: 2,
              height: 20,
              color: _kBorder,
              margin: const EdgeInsets.only(left: 15, top: 4, bottom: 4)),
          // Step 2 in progress
          Row(children: [
            const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: _kBlue)),
            const SizedBox(width: 14),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Step 2',
                  style: TextStyle(color: _kTextHint, fontSize: 11)),
              Text('Comparing Face…',
                  style: TextStyle(
                      color: _kBlue,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
          ]),
        ]),
      ),
    );
  }
}
