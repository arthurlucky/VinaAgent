import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/storage/app_sandbox.dart';
import '../domain/artifact.dart';

class ArtifactException implements Exception {
  const ArtifactException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Stores artifacts as versioned files under `<sandbox>/Artifacts/<id>/`.
class ArtifactStore {
  const ArtifactStore();

  static const List<String> allowedTypes = [
    'markdown',
    'html',
    'code',
    'text',
    'json',
    'csv',
  ];

  Future<Directory> _root() async {
    final sandbox = await AppSandbox.root();
    final dir = Directory(p.join(sandbox.path, 'Artifacts'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<List<Artifact>> list() async {
    final root = await _root();
    final artifacts = <Artifact>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final meta = File(p.join(entity.path, 'meta.json'));
      if (!await meta.exists()) continue;
      try {
        artifacts.add(
          Artifact.fromJson(
            jsonDecode(await meta.readAsString()) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    artifacts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return artifacts;
  }

  Future<Artifact?> get(String id) async {
    final root = await _root();
    final meta = File(p.join(root.path, id, 'meta.json'));
    if (!await meta.exists()) return null;
    try {
      return Artifact.fromJson(
        jsonDecode(await meta.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Artifact> create({
    required String title,
    required String type,
    required String content,
    String language = '',
    String note = '',
  }) async {
    final normalizedType = type.toLowerCase().trim();
    if (!allowedTypes.contains(normalizedType)) {
      throw ArtifactException(
        'Unsupported artifact type "$type". Use ${allowedTypes.join(', ')}.',
      );
    }
    final cleanTitle = title.trim().isEmpty ? 'Untitled artifact' : title.trim();
    final id = _slug(cleanTitle);
    final root = await _root();
    final dir = Directory(p.join(root.path, id));
    if (await dir.exists()) {
      throw ArtifactException(
        'An artifact with id "$id" already exists. Use update_artifact.',
      );
    }
    await dir.create(recursive: true);

    final now = DateTime.now();
    final file = _fileName(normalizedType, language, 1);
    await File(p.join(dir.path, file)).writeAsString(content, flush: true);
    final artifact = Artifact(
      id: id,
      title: cleanTitle,
      type: normalizedType,
      language: language.trim(),
      createdAt: now,
      updatedAt: now,
      versions: [
        ArtifactVersion(
          number: 1,
          file: file,
          createdAt: now,
          note: note.trim(),
        ),
      ],
    );
    await _writeMeta(dir, artifact);
    return artifact;
  }

  Future<Artifact> update({
    required String id,
    required String content,
    String note = '',
  }) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, id));
    final artifact = await get(id);
    if (artifact == null) {
      throw ArtifactException('Artifact "$id" not found.');
    }
    final number = artifact.versions.length + 1;
    final file = _fileName(artifact.type, artifact.language, number);
    await File(p.join(dir.path, file)).writeAsString(content, flush: true);
    final now = DateTime.now();
    final updated = Artifact(
      id: artifact.id,
      title: artifact.title,
      type: artifact.type,
      language: artifact.language,
      createdAt: artifact.createdAt,
      updatedAt: now,
      versions: [
        ...artifact.versions,
        ArtifactVersion(
          number: number,
          file: file,
          createdAt: now,
          note: note.trim(),
        ),
      ],
    );
    await _writeMeta(dir, updated);
    return updated;
  }

  Future<String> readVersion(String id, int number) async {
    final artifact = await get(id);
    if (artifact == null) {
      throw ArtifactException('Artifact "$id" not found.');
    }
    final version = artifact.versions
        .where((v) => v.number == number)
        .firstOrNull;
    if (version == null) {
      throw ArtifactException('Version $number not found.');
    }
    final root = await _root();
    final file = File(p.join(root.path, id, version.file));
    if (!await file.exists()) {
      throw ArtifactException('Artifact file is missing on disk.');
    }
    return file.readAsString();
  }

  Future<void> delete(String id) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, id));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _writeMeta(Directory dir, Artifact artifact) async {
    await File(p.join(dir.path, 'meta.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(artifact.toJson()),
      flush: true,
    );
  }

  static String _slug(String title) {
    var slug = title.toLowerCase();
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'-+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.length > 48) slug = slug.substring(0, 48);
    if (slug.isEmpty) slug = 'artifact';
    return '$slug-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  }

  static String _fileName(String type, String language, int number) {
    final ext = switch (type) {
      'markdown' => 'md',
      'html' => 'html',
      'json' => 'json',
      'csv' => 'csv',
      'code' => _codeExtension(language),
      _ => 'txt',
    };
    return 'v$number.$ext';
  }

  static String _codeExtension(String language) => switch (language
      .toLowerCase()
      .trim()) {
        'dart' => 'dart',
        'python' || 'py' => 'py',
        'javascript' || 'js' => 'js',
        'typescript' || 'ts' => 'ts',
        'kotlin' => 'kt',
        'swift' => 'swift',
        'java' => 'java',
        'html' => 'html',
        'css' => 'css',
        'sql' => 'sql',
        'bash' || 'sh' => 'sh',
        'yaml' || 'yml' => 'yaml',
        'xml' => 'xml',
        _ => 'txt',
      };
}
