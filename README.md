# flutter_face_nova — Flutter SDK

> **Flutter SDK for Android & iOS** — offline face liveness detection and face identity verification.  
> No server. No internet. All AI inference runs fully on-device.

<p align="left">
  <img src="https://raw.githubusercontent.com/facenova/flutter_face_nova/main/screenshots/1.jpg" width="200"/>
  <img src="https://raw.githubusercontent.com/facenova/flutter_face_nova/main/screenshots/2.jpg" width="200"/>
  <img src="https://raw.githubusercontent.com/facenova/flutter_face_nova/main/screenshots/3.jpg" width="200"/>
  <img src="https://raw.githubusercontent.com/facenova/flutter_face_nova/main/screenshots/4.jpg" width="200"/>
</p>

---

## Platform Support

| Platform | Support | Minimum Version |
|---|---|---|
| 🤖 Android | ✅ Supported | API 24+ (Android 7.0) |
| 🍎 iOS | ✅ Supported | iOS 14.0+ |

**Android architectures:** arm64-v8a, armeabi-v7a, x86_64  
**iOS targets:** Physical device (arm64) + Simulator (arm64, x86_64)

---

## What it does

| Capability | Description |
|---|---|
| **Liveness detection** | Rejects photos, video replays, and masks — real faces only |
| **Face enrolment** | Extract a face embedding from any gallery image |
| **Face matching** | Compare an enrolled face against a live capture |
| **Single-camera flow** | Liveness + match in one camera session — no double prompt |

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_face_nova:
    git:
      url: https://github.com/facenova/flutter_face_nova.git
  permission_handler: ^11.4.0
```

Then run:

```bash
flutter pub get
```

---

## Platform Setup

### Android

**`android/app/build.gradle.kts`**
```kotlin
android {
    defaultConfig {
        minSdk = 24
        compileSdk = 35
    }
}
```

**`android/app/src/main/AndroidManifest.xml`**
```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

### iOS

**`ios/Runner/Info.plist`**
```xml
<key>NSCameraUsageDescription</key>
<string>Required for liveness detection</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Required to enrol faces from your photo library</string>
```

**`ios/Podfile`**
```ruby
platform :ios, '14.0'
```

---

## Quick Start

### 1 — Initialize once at startup

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterFaceNova.initialize(licenseKey: 'YOUR_LICENSE_KEY');

  await Permission.camera.request();
  runApp(const MyApp());
}
```

### 2 — Liveness detection

```dart
final LivenessResult? result = await FlutterFaceNova.startLiveness(context);

if (result == null) {
  // user cancelled
  return;
}

if (!result.isReal) {
  print('Liveness failed. Score: ${(result.score * 100).toStringAsFixed(1)}%');
  return;
}

// Passed
print('Real face confirmed. Score: ${(result.score * 100).toStringAsFixed(1)}%');
```

### 3 — Liveness + Face Match (single camera session)

```dart
// Camera opens once — liveness and match use the same captured frame
final liveness = await FlutterFaceNova.startLiveness(context);
if (liveness == null || !liveness.isReal) return;

final FaceMatchResult? match = await FlutterFaceNova.matchFaceFromImage(
  liveness.imageBytes!,
  enrolledFaces: myEnrolledFaces,
  matchThreshold: 75.0,
);

if (match != null && match.isMatch) {
  print('Identity verified: ${match.matchedFace?.name}  (${match.score.toStringAsFixed(1)}%)');
}
```

### 4 — Enrol a face from gallery

```dart
final Uint8List imageBytes = await xfile.readAsBytes();

final FaceMetadataResult? meta = await FlutterFaceNova.generateFaceMetadata(imageBytes);
if (meta == null) return; // no face found

final face = FaceEntry(
  id:       const Uuid().v4(),
  name:     'Jane Doe',
  metadata: meta.metadata,      // store this — used for matching
  photo:    meta.croppedImage,  // optional face thumbnail
);
```

### 5 — Compare two embeddings directly

```dart
final double score = FlutterFaceNova.compareFaceMetadata(meta1.metadata, meta2.metadata);
// Returns 0–100. ≥ 75 is a confident match.
```

---

## Custom Thresholds

Thresholds have sensible platform defaults. Pass custom values to override:

```dart
// Use defaults (recommended)
await FlutterFaceNova.startLiveness(context);

// Override
await FlutterFaceNova.startLiveness(
  context,
  livenessThreshold:   0.70,  // front camera — 70%
  backCameraThreshold: 0.85,  // back camera  — 85%
);
```

Default values baked into the package:

| Camera | iOS | Android |
|---|---|---|
| Front | **60%** | **30%** |
| Back  | **90%** | **80%** |

---

## API Reference

### `FlutterFaceNova`

| Method | Returns | Description |
|---|---|---|
| `initialize({licenseKey})` | `Future<void>` | Verify license and prepare the SDK |
| `isInitialized` | `bool` | `true` once `initialize()` succeeds |
| `startLiveness(context, {livenessThreshold, backCameraThreshold})` | `Future<LivenessResult?>` | Open camera screen; resolves when liveness passes or user cancels |
| `matchFaceFromImage(bytes, {enrolledFaces, matchThreshold})` | `Future<FaceMatchResult?>` | Match enrolled faces against an image — no camera |
| `startLivenessAndMatch(context, {enrolledFaces, livenessThreshold, backCameraThreshold, matchThreshold})` | `Future<FaceMatchResult?>` | Combined liveness + match, single camera session |
| `generateFaceMetadata(imageBytes)` | `Future<FaceMetadataResult?>` | Extract a face embedding from any image |
| `startFaceMatch(context, {enrolledFaces, matchThreshold})` | `Future<FaceMatchResult?>` | Open a face-match camera screen |
| `compareFaceMetadata(meta1, meta2)` | `double` | Compare two embeddings, returns 0–100 |

### Types

```dart
class LivenessResult {
  final bool       isReal;      // true = real person passed the check
  final double     score;       // 0.0–1.0  (×100 = display %)
  final Uint8List? imageBytes;  // JPEG frame at the moment liveness passed
}

class FaceMetadataResult {
  final Uint8List metadata;     // face embedding — store and reuse for matching
  final Uint8List croppedImage; // JPEG crop of the detected face
}

class FaceEntry {
  final String     id;
  final String     name;
  final Uint8List  metadata;   // from FaceMetadataResult.metadata
  final Uint8List? photo;      // optional face thumbnail JPEG
}

class FaceMatchResult {
  final FaceEntry? matchedFace;   // best-matching enrolled face
  final double     score;         // 0–100 confidence
  final bool       isMatch;       // true if score >= matchThreshold
  final Uint8List? capturedImage; // cropped face JPEG from the scanned image
}
```

---

## License

Commercial use requires a valid license key tied to your app bundle ID / package name.

**Contact us to get your license key or a free trial:**

- Email: [support@facenova.uk](mailto:support@facenova.uk)
- Telegram: [@Error_zoom_404](https://t.me/Error_zoom_404)
