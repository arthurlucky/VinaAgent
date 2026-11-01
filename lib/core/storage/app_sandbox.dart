import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The single filesystem boundary for Vina Agent.
///
/// Everything the agent can touch lives under the app's private documents
/// directory (`<app documents>/VinaAgent`). External storage, `/sdcard` and
/// `/storage/emulated/0` are never exposed: paths that point there are mapped
/// back to the matching sandbox folder or rejected.
class AppSandbox {
  const AppSandbox._();

  static Directory? _cached;

  /// Friendly top-level folders created on first use.
  static const List<String> folders = [
    'Documents',
    'Downloads',
    'Artifacts',
    'Exports',
    'Skills',
  ];

  /// Absolute sandbox root, created lazily.
  static Future<Directory> root() async {
    final cached = _cached;
    if (cached != null) return cached;

    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'VinaAgent'));
    await dir.create(recursive: true);
    for (final folder in folders) {
      await Directory(p.join(dir.path, folder)).create(recursive: true);
    }
    _cached = dir;
    return dir;
  }

  /// Roots handed to the storage tools.
  static Future<List<String>> roots() async {
    final dir = await root();
    return [dir.path];
  }

  /// Resolves [rawPath] against [rootPath]. Returns `null` when the path
  /// escapes the sandbox or contains a null byte.
  static String? resolveWithRoot(String rawPath, String rootPath) {
    if (rootPath.trim().isEmpty) return null;

    var value = rawPath.trim().replaceAll('\\', '/');
    if (value.isEmpty || value == '.' || value == '~') {
      value = 'Documents';
    }
    if (value.contains('\u0000')) return null;

    // Common external paths are mapped to the sandbox equivalent instead of
    // being granted real device access.
    final external =
        RegExp(r'^/?(?:storage/emulated/\d+|sdcard)/(.*)$').firstMatch(value);
    if (external != null) {
      value = external.group(1) ?? '';
    }

    final rootNorm = p.canonicalize(rootPath);
    String candidate;
    if (value.startsWith('/')) {
      candidate = p.canonicalize(value);
    } else {
      value = value.replaceFirst(RegExp(r'^~/?'), '');
      candidate = p.canonicalize(p.join(rootNorm, value));
    }

    if (candidate == rootNorm || p.isWithin(rootNorm, candidate)) {
      return candidate;
    }
    return null;
  }

  /// True when [targetPath] is inside one of [allowedRoots].
  static bool isAllowed(String targetPath, List<String> allowedRoots) {
    if (allowedRoots.isEmpty || targetPath.trim().isEmpty) return false;
    final target = p.canonicalize(targetPath);
    for (final root in allowedRoots) {
      final rootNorm = p.canonicalize(root);
      if (target == rootNorm || p.isWithin(rootNorm, target)) return true;
    }
    return false;
  }
}
