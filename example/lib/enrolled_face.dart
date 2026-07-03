import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';

const _boxName = 'enrolled_faces';

/// A persisted enrolled person.
class EnrolledFace {
  final String id;
  final String name;
  final Uint8List metadata; // 128-D embedding (Float32 bytes)
  final Uint8List photo;    // JPEG cropped face

  EnrolledFace({
    required this.id,
    required this.name,
    required this.metadata,
    required this.photo,
  });

  Map<String, dynamic> toMap() => {
    'id':       id,
    'name':     name,
    'metadata': metadata,
    'photo':    photo,
  };

  factory EnrolledFace.fromMap(Map map) => EnrolledFace(
    id:       map['id'] as String,
    name:     map['name'] as String,
    metadata: map['metadata'] as Uint8List,
    photo:    map['photo'] as Uint8List,
  );
}

/// Simple Hive-backed store for enrolled faces.
class FaceStore {
  static Box? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  static List<EnrolledFace> getAll() {
    return (_box?.values ?? [])
        .map((v) => EnrolledFace.fromMap(Map.from(v as Map)))
        .toList();
  }

  static Future<void> add(EnrolledFace face) async {
    await _box?.put(face.id, face.toMap());
  }

  static Future<void> remove(String id) async {
    await _box?.delete(id);
  }

  static Future<void> clear() async {
    await _box?.clear();
  }
}
