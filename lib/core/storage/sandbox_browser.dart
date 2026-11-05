import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pocketstrike/core/storage/app_sandbox.dart';

/// One file or folder inside the app sandbox.
class SandboxEntry {
  const SandboxEntry({
    required this.relativePath,
    required this.isDirectory,
  });

  final String relativePath;
  final bool isDirectory;

  String get name => p.basename(relativePath);
}

/// Read-only browser used by the `@file/folder` mention picker.
class SandboxBrowser {
  const SandboxBrowser._();

  static Future<List<SandboxEntry>> listAll({int limit = 400}) async {
    final root = await AppSandbox.root();
    final entries = <SandboxEntry>[];
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        final relative = p
            .relative(entity.path, from: root.path)
            .replaceAll('\\', '/');
        if (relative.isEmpty || relative == '.' || relative.startsWith('.')) {
          continue;
        }
        if (entity is Directory) {
          entries.add(
            SandboxEntry(relativePath: relative, isDirectory: true),
          );
        } else if (entity is File) {
          entries.add(
            SandboxEntry(relativePath: relative, isDirectory: false),
          );
        }
        if (entries.length >= limit) break;
      }
    } catch (_) {
      // A partially readable sandbox should still open the picker.
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.relativePath.toLowerCase().compareTo(
            b.relativePath.toLowerCase(),
          );
    });
    return entries;
  }
}
