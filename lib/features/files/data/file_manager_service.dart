import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../core/storage/app_sandbox.dart';
import '../domain/file_item.dart';

/// Manages file operations within the app sandbox.
class FileManagerService {
  const FileManagerService();

  /// List files/folders in [folderPath] within sandbox.
  Future<List<FileItem>> listFiles(String folderPath) async {
    final rootDir = await AppSandbox.root();
    final resolved = AppSandbox.resolveWithRoot(folderPath, rootDir.path);
    if (resolved == null) {
      throw StateError('Invalid path: $folderPath');
    }

    final dir = Directory(resolved);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
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
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  /// Create a new file in [folderPath] with optional [content].
  Future<FileItem> createFile(
    String folderPath,
    String fileName, {
    String content = '',
  }) async {
    final rootDir = await AppSandbox.root();
    final targetFolder = AppSandbox.resolveWithRoot(folderPath, rootDir.path);
    if (targetFolder == null) {
      throw StateError('Invalid folder path: $folderPath');
    }

    final cleanFileName = fileName.trim();
    if (cleanFileName.isEmpty ||
        cleanFileName.contains('/') ||
        cleanFileName.contains('\\')) {
      throw ArgumentError('Invalid file name: $fileName');
    }

    final file = File(p.join(targetFolder, cleanFileName));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);

    final stat = await file.stat();
    return FileItem(
      name: cleanFileName,
      path: file.path,
      isDirectory: false,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
    );
  }

  /// Create new folder in sandbox.
  Future<void> createFolder(String path, String folderName) async {
    final rootDir = await AppSandbox.root();
    final resolved = AppSandbox.resolveWithRoot(
      p.join(path, folderName.trim()),
      rootDir.path,
    );
    if (resolved == null) {
      throw StateError('Invalid path');
    }

    await Directory(resolved).create(recursive: true);
  }

  /// Move a file or folder from [sourcePath] into [destFolderPath].
  Future<void> move(String sourcePath, String destFolderPath) async {
    final rootDir = await AppSandbox.root();
    final resolvedSource = AppSandbox.resolveWithRoot(sourcePath, rootDir.path);
    final resolvedDestFolder =
        AppSandbox.resolveWithRoot(destFolderPath, rootDir.path);
    if (resolvedSource == null || resolvedDestFolder == null) {
      throw StateError('Invalid source or destination path');
    }

    final targetDir = Directory(resolvedDestFolder);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final entityName = p.basename(resolvedSource);
    final newPath = p.join(resolvedDestFolder, entityName);

    final type = await FileSystemEntity.type(resolvedSource);
    if (type == FileSystemEntityType.directory) {
      await Directory(resolvedSource).rename(newPath);
    } else if (type == FileSystemEntityType.file) {
      await File(resolvedSource).rename(newPath);
    } else {
      throw StateError('Source entity does not exist');
    }
  }

  /// Compresses a file or directory into a `.zip` file in the sandbox.
  Future<String> compressToZip(
    String sourcePath, {
    String? zipFileName,
  }) async {
    final rootDir = await AppSandbox.root();
    final resolved = AppSandbox.resolveWithRoot(sourcePath, rootDir.path);
    if (resolved == null) throw StateError('Invalid source path');

    final type = await FileSystemEntity.type(resolved);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('Path "$sourcePath" does not exist.');
    }

    final baseName = p.basename(resolved);
    final rawZipName = zipFileName?.trim();
    final finalZipName = (rawZipName != null && rawZipName.isNotEmpty)
        ? (rawZipName.endsWith('.zip') ? rawZipName : '$rawZipName.zip')
        : (baseName.endsWith('.zip')
            ? '${baseName.replaceAll(RegExp(r'\.zip$'), '')}_archived.zip'
            : '$baseName.zip');

    final parentDir = p.dirname(resolved);
    final zipFilePath = p.join(parentDir, finalZipName);

    final archive = Archive();
    if (type == FileSystemEntityType.file) {
      final bytes = await File(resolved).readAsBytes();
      archive.addFile(ArchiveFile(baseName, bytes.length, bytes));
    } else {
      final dir = Directory(resolved);
      final entities = dir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is File) {
          final relPath = p.relative(entity.path, from: resolved);
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
        }
      }
    }

    final zipData = ZipEncoder().encode(archive);
    final outFile = File(zipFilePath);
    await outFile.writeAsBytes(zipData);
    return outFile.path;
  }

  /// Extracts [zipFilePath] into [targetFolderPath] (defaults to folder with zip name).
  Future<String> extractZip(
    String zipFilePath, {
    String? targetFolderPath,
  }) async {
    final rootDir = await AppSandbox.root();
    final resolvedZip = AppSandbox.resolveWithRoot(zipFilePath, rootDir.path);
    if (resolvedZip == null) throw StateError('Invalid zip file path');

    final zipFile = File(resolvedZip);
    if (!await zipFile.exists()) {
      throw StateError('Zip file not found: $zipFilePath');
    }

    String extractDir;
    if (targetFolderPath != null && targetFolderPath.trim().isNotEmpty) {
      final resolvedTarget =
          AppSandbox.resolveWithRoot(targetFolderPath, rootDir.path);
      if (resolvedTarget == null) throw StateError('Invalid target folder');
      extractDir = resolvedTarget;
    } else {
      final baseName = p.basenameWithoutExtension(resolvedZip);
      extractDir = p.join(p.dirname(resolvedZip), baseName);
    }

    final destDir = Directory(extractDir);
    await destDir.create(recursive: true);

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive.files) {
      final filename = file.name;
      final outPath = p.normalize(p.join(destDir.path, filename));

      // Zip-slip security protection:
      if (!p.isWithin(destDir.path, outPath) && outPath != destDir.path) {
        continue;
      }

      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        final data = file.content as List<int>;
        await outFile.writeAsBytes(data);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    return destDir.path;
  }

  /// Returns the entries inside [zipFilePath] without extracting.
  Future<List<ZipEntryItem>> previewZip(String zipFilePath) async {
    final rootDir = await AppSandbox.root();
    final resolvedZip = AppSandbox.resolveWithRoot(zipFilePath, rootDir.path);
    if (resolvedZip == null) throw StateError('Invalid zip file path');

    final zipFile = File(resolvedZip);
    if (!await zipFile.exists()) {
      throw StateError('Zip file not found: $zipFilePath');
    }

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final entries = <ZipEntryItem>[];
    for (final file in archive.files) {
      entries.add(ZipEntryItem(
        name: file.name,
        sizeBytes: file.size,
        isDirectory: !file.isFile,
      ));
    }
    return entries;
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
    final resolved =
        AppSandbox.resolveWithRoot(path, (await AppSandbox.root()).path);
    if (resolved == null) {
      throw StateError('Invalid path: $path');
    }

    final entity =
        FileSystemEntity.typeSync(resolved) == FileSystemEntityType.directory
            ? Directory(resolved)
            : File(resolved);

    if (await entity.exists()) {
      await entity.delete(recursive: true);
    }
  }

  /// Rename file or folder within sandbox.
  Future<void> rename(String oldPath, String newPath) async {
    final sandboxRoot = (await AppSandbox.root()).path;
    final resolvedOld = AppSandbox.resolveWithRoot(oldPath, sandboxRoot);
    final resolvedNew = AppSandbox.resolveWithRoot(newPath, sandboxRoot);

    if (resolvedOld == null || resolvedNew == null) {
      throw StateError('Invalid paths');
    }

    final entity =
        FileSystemEntity.typeSync(resolvedOld) == FileSystemEntityType.directory
            ? Directory(resolvedOld)
            : File(resolvedOld);

    if (await entity.exists()) {
      await entity.rename(resolvedNew);
    }
  }
}
