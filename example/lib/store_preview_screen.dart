import 'package:flutter/material.dart';

class StorePreviewScreen extends StatefulWidget {
  const StorePreviewScreen({super.key});

  @override
  State<StorePreviewScreen> createState() => _StorePreviewScreenState();
}

class _StorePreviewScreenState extends State<StorePreviewScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.72);
  int _currentPage = 0;

  static const _screenshots = [
    _ScreenshotMeta(
      asset: 'assets/screenshots/1.png',
      title: 'Clean Home Screen',
      subtitle: 'Simple, dark UI — enroll faces and start matching in one tap',
    ),
    _ScreenshotMeta(
      asset: 'assets/screenshots/2.png',
      title: 'Face Enrollment',
      subtitle: 'Add faces from your gallery — stored securely on-device only',
    ),
    _ScreenshotMeta(
      asset: 'assets/screenshots/3.png',
      title: 'Liveness Detection',
      subtitle: 'Real-time AI detects if you\'re a live person, not a photo',
    ),
    _ScreenshotMeta(
      asset: 'assets/screenshots/4.png',
      title: 'Identity Verified',
      subtitle: 'Confidence score shown — fully offline, zero data sent out',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060B16),
      body: CustomScrollView(
        slivers: [
          // ── Feature Graphic ───────────────────────────────────────────────
          SliverToBoxAdapter(child: _FeatureGraphic()),

          // ── App Info Row ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A6FFF), Color(0xFF22D37A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22D37A).withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.fingerprint_rounded,
                        color: Colors.white, size: 34),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FaceNova',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'FaceNova Labs',
                          style: TextStyle(color: Color(0xFF22D37A), fontSize: 13),
                        ),
                        SizedBox(height: 8),
                        _RatingRow(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Tags ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Wrap(
                spacing: 8,
                children: const [
                  _Tag('100% Offline'),
                  _Tag('On-Device AI'),
                  _Tag('No Data Sent'),
                  _Tag('Face Match'),
                  _Tag('Liveness Check'),
                ],
              ),
            ),
          ),

          // ── Description ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About this app',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'FaceNova uses cutting-edge on-device AI to verify that a person is real (liveness detection) and matches an enrolled face — all without sending a single byte to the cloud.\n\nPowered by silent face anti-spoofing (MiniFASNet) and SFace recognition models running fully offline via ONNX Runtime.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13.5,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Screenshot Carousel Section ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 0, 10),
              child: const Text(
                'Screenshots',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: SizedBox(
              height: 520,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _screenshots.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) {
                  final isActive = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    margin: EdgeInsets.only(
                      left: 8,
                      right: 8,
                      top: isActive ? 0 : 24,
                      bottom: isActive ? 0 : 24,
                    ),
                    child: _PhoneMockup(
                      asset: _screenshots[i].asset,
                      isActive: isActive,
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Page Indicator ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _screenshots.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _currentPage ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _currentPage
                        ? const Color(0xFF22D37A)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),

          // ── Caption ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Padding(
                key: ValueKey(_currentPage),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  children: [
                    Text(
                      _screenshots[_currentPage].title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _screenshots[_currentPage].subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Feature Highlights ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
              child: const Text(
                'Features',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _FeatureRow(
                  icon: Icons.shield_rounded,
                  color: Color(0xFF22D37A),
                  title: 'Anti-Spoofing Liveness',
                  subtitle: 'Detects printed photos, screens and masks in real-time',
                ),
                const _FeatureRow(
                  icon: Icons.face_retouching_natural_rounded,
                  color: Color(0xFF4D9EFF),
                  title: 'Face Recognition',
                  subtitle: 'SFace model with 128D embeddings — 81%+ accuracy',
                ),
                const _FeatureRow(
                  icon: Icons.wifi_off_rounded,
                  color: Color(0xFFFFB347),
                  title: '100% Offline',
                  subtitle: 'No internet required — all processing stays on your device',
                ),
                const _FeatureRow(
                  icon: Icons.lock_rounded,
                  color: Color(0xFFFF6B9D),
                  title: 'Private by Design',
                  subtitle: 'No biometric data ever leaves your phone',
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feature Graphic Banner
// ─────────────────────────────────────────────────────────────────────────────

class _FeatureGraphic extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A1628), Color(0xFF0D2137), Color(0xFF0A1628)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Glow orbs
          Positioned(
            left: -40,
            top: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A6FFF).withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            right: -30,
            bottom: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF22D37A).withValues(alpha: 0.12),
              ),
            ),
          ),
          // Center content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated ring + icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A6FFF), Color(0xFF22D37A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22D37A).withValues(alpha: 0.4),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.fingerprint_rounded,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 14),
                const Text(
                  'FaceNova',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Liveness Detection  ·  Face Matching  ·  100% Offline',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone Mockup Frame
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneMockup extends StatelessWidget {
  final String asset;
  final bool isActive;
  const _PhoneMockup({required this.asset, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        border: Border.all(
          color: isActive
              ? const Color(0xFF22D37A).withValues(alpha: 0.6)
              : Colors.white12,
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF22D37A).withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF111827),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_rounded,
                    color: Colors.white24, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Drop screenshot here:\n$asset',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RatingRow extends StatelessWidget {
  const _RatingRow();
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      ...List.generate(
        5,
        (i) => const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFC107)),
      ),
      const SizedBox(width: 6),
      const Text('4.9',
          style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF22D37A).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF22D37A).withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF22D37A),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12.5,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotMeta {
  final String asset;
  final String title;
  final String subtitle;
  const _ScreenshotMeta(
      {required this.asset, required this.title, required this.subtitle});
}
