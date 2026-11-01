import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/storage/app_sandbox.dart';
import '../domain/file_item.dart';

/// Manages file operations within the app sandbox.
class FileManagerService {
  const FileManagerService();

  /// List files/folders in [folderPath] within sandbox.
  Future<List<FileItem>> listFiles(String folderPath) async {
    final resolved = AppSandbox.resolveWithRoot(folderPath, (await AppSandbox.root()).path);
    if (resolved == null) {
      throw StateError('Invalid path: $folderPath');
    }

    final dir = Directory(resolved);
    if (!await dir.exists()) {
      throw StateError('Directory not found: $folderPath');
    }

    final items = <FileItem>[];
    await for (final entity in dir.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        items.add(FileItem(
          name: p.basename(entity.path),
          path: entity.path,
          isDirectory: entity is Directory,
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ));
      } catch (_) {
        // Skip inaccessible files
      }
    }
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return items;
  }

  /// Copy file from [sourcePath] (external) to [destPath] (sandbox).
  /// Validates both paths before copying.
  Future<void> copyToSandbox(String sourcePath, String destPath) async {
    final sandboxRoot = (await AppSandbox.root()).path;
    final resolved = AppSandbox.resolveWithRoot(destPath, sandboxRoot);
    if (resolved == null) {
      throw StateError('Destination path escapes sandbox: $destPath');
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('Source file not found: $sourcePath');
    }

    final destFile = File(resolved);
    final destDir = destFile.parent;
    await destDir.create(recursive: true);

    await sourceFile.copy(destFile.path);
  }

  /// Delete file or folder (recursively) in sandbox.
  Future<void> delete(String path) async {
    final resolved = AppSandbox.resolveWithRoot(path, (await AppSandbox.root()).path);
    if (resolved == null) {
      throw StateError('Invalid path: $path');
    }

    final entity = FileSystemEntity.typeSync(resolved) == FileSystemEntityType.directory
        ? Directory(resolved)
        : File(resolved);

    if (await entity.exists()) {
      await entity.delete(recursive: true);
    }
  }

  /// Rename or move file within sandbox.
  Future<void> rename(String oldPath, String newPath) async {
    final sandboxRoot = (await AppSandbox.root()).path;
    final resolvedOld = AppSandbox.resolveWithRoot(oldPath, sandboxRoot);
    final resolvedNew = AppSandbox.resolveWithRoot(newPath, sandboxRoot);

    if (resolvedOld == null || resolvedNew == null) {
      throw StateError('Invalid paths');
    }

    final entity = FileSystemEntity.typeSync(resolvedOld) == FileSystemEntityType.directory
        ? Directory(resolvedOld)
        : File(resolvedOld);

    if (await entity.exists()) {
      await entity.rename(resolvedNew);
    }
  }

  /// Create new folder in sandbox.
  Future<void> createFolder(String path, String folderName) async {
    final resolved = AppSandbox.resolveWithRoot(
      p.join(path, folderName),
      (await AppSandbox.root()).path,
    );
    if (resolved == null) {
      throw StateError('Invalid path');
    }

    await Directory(resolved).create(recursive: true);
  }
}
