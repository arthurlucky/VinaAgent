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
  /// 
  /// SECURITY: Absolute block on external storage paths (/sdcard, /storage/emulated/0).
  /// Agent cannot read or write outside the app sandbox under any circumstances.
  static String? resolveWithRoot(String rawPath, String rootPath) {
    if (rootPath.trim().isEmpty) return null;

    var value = rawPath.trim().replaceAll('\\', '/');
    if (value.isEmpty || value == '.' || value == '~') {
      value = 'Documents';
    }
    if (value.contains('\u0000')) return null;

    // SECURITY: Reject any path pointing to external storage explicitly.
    // Do NOT map it; error is clearer to the user.
    final externalPattern = RegExp(r'^/?(?:storage|sdcard|mnt)(/|$)');
    if (externalPattern.hasMatch(value)) {
      throw StateError(
        'Access denied: agent cannot access $value. '
        'All reads/writes restricted to app sandbox: $rootPath'
      );
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
    // Path escapes sandbox
    throw StateError(
      'Access denied: $rawPath escapes sandbox. '
      'Restricted to: $rootPath'
    );
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
