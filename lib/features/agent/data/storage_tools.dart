import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/storage/app_sandbox.dart';
import '../../files/data/file_manager_service.dart';
import '../domain/agent_tool.dart';

/// Sandboxed storage tools for agent file system operations on mobile devices.
class StorageAgentTools {
  const StorageAgentTools._();

  static List<AgentTool> tools({
    required List<String> allowedRoots,
    String activeWorkdir = '',
  }) {
    return [
      listFiles(allowedRoots, activeWorkdir),
      readFile(allowedRoots, activeWorkdir),
      writeFile(allowedRoots, activeWorkdir),
      createFolder(allowedRoots, activeWorkdir),
      deleteFile(allowedRoots, activeWorkdir),
      moveFile(allowedRoots, activeWorkdir),
      batchMoveFiles(allowedRoots, activeWorkdir),
      organizeDirectory(allowedRoots, activeWorkdir),
      searchFiles(allowedRoots, activeWorkdir),
      compressToZip(allowedRoots, activeWorkdir),
      extractZip(allowedRoots, activeWorkdir),
      sendFileAttachment(allowedRoots, activeWorkdir),
      analyzeImage(allowedRoots, activeWorkdir),
      getWorkdir(activeWorkdir),
    ];
  }

  /// Resolves a path into an absolute path inside the app sandbox, taking the
  /// active working directory into account for relative paths.
  static String _resolvePath(
    String rawPath,
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) {
    if (allowedRoots.isEmpty) return rawPath.trim();
    final root = allowedRoots.first;
    final trimmed = rawPath.trim().replaceAll('\\', '/');

    if (trimmed.startsWith('/') || trimmed.startsWith(root)) {
      final stripped = trimmed.replaceFirst(RegExp(r'^/+'), '');
      return AppSandbox.resolveWithRoot(stripped, root) ??
          p.join(root, stripped);
    }

    final wd = activeWorkdir
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '');
    if (wd.isNotEmpty && wd != 'default' && wd != 'root') {
      final combined = p.join(wd, trimmed);
      return AppSandbox.resolveWithRoot(combined, root) ??
          p.join(root, combined);
    }

    return AppSandbox.resolveWithRoot(trimmed, root) ?? p.join(root, trimmed);
  }

  static bool _isAllowed(String targetPath, List<String> allowedRoots) {
    return AppSandbox.isAllowed(targetPath, allowedRoots);
  }

  static AgentTool listFiles(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'list_files',
        description:
            'Lists files and directories at the specified path (e.g. "." or "Downloads"). Defaults to current workdir.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Directory path to list (e.g. "." or "Downloads").',
            },
          },
          'required': ['path'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['path'] as String? ?? '.';
          final path = _resolvePath(rawPath, allowedRoots, activeWorkdir);

          if (!_isAllowed(path, allowedRoots)) {
            return 'Error: Access denied. Path "$path" is outside allowed root folders.';
          }
          final dir = Directory(path);
          if (!await dir.exists()) {
            return 'Directory "$path" does not exist.';
          }
          final entries = await dir.list().toList();
          if (entries.isEmpty) return 'Directory "$path" is empty.';
          final buffer = StringBuffer('Contents of $path:\n');
          for (final entry in entries) {
            final isDir = entry is Directory;
            final name = p.basename(entry.path);
            buffer.writeln('${isDir ? "[DIR] " : "[FILE]"} $name');
          }
          return buffer.toString().trim();
        },
      );

  static AgentTool readFile(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'read_file',
        description:
            'Reads text content from a file at the specified path (e.g. "notes.txt").',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'File path to read.',
            },
          },
          'required': ['path'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['path'] as String? ?? '';
          final path = _resolvePath(rawPath, allowedRoots, activeWorkdir);

          if (!_isAllowed(path, allowedRoots)) {
            return 'Error: Access denied. Path "$path" is outside allowed root folders.';
          }
          final file = File(path);
          if (!await file.exists()) {
            return 'Error: File "$path" does not exist.';
          }
          final content = await file.readAsString();
          return content;
        },
      );

  static AgentTool writeFile(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'write_file',
        description:
            'Writes or overwrites text content to a file at the specified path. Creates file if missing. Relative paths resolve to current workdir.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'File path to write to.',
            },
            'content': {
              'type': 'string',
              'description': 'Text content to write.',
            },
          },
          'required': ['path', 'content'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['path'] as String? ?? '';
          final path = _resolvePath(rawPath, allowedRoots, activeWorkdir);
          final content = args['content'] as String? ?? '';

          if (!_isAllowed(path, allowedRoots)) {
            return 'Error: Access denied. Path "$path" is outside allowed root folders.';
          }
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsString(content);
          return 'Successfully wrote ${content.length} characters to "$path".';
        },
      );

  static AgentTool createFolder(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'create_folder',
        description:
            'Creates a new directory folder at the specified path. Relative paths resolve to current workdir.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Directory path to create.',
            },
          },
          'required': ['path'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['path'] as String? ?? '';
          final path = _resolvePath(rawPath, allowedRoots, activeWorkdir);

          if (!_isAllowed(path, allowedRoots)) {
            return 'Error: Access denied. Path "$path" is outside allowed root folders.';
          }
          final dir = Directory(path);
          await dir.create(recursive: true);
          return 'Successfully created folder "$path".';
        },
      );

  static AgentTool deleteFile(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'delete_file',
        description: 'Deletes a file or directory at the specified path.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'File or directory path to delete.',
            },
          },
          'required': ['path'],
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          final rawPath = args['path'] as String? ?? '';
          final path = _resolvePath(rawPath, allowedRoots, activeWorkdir);

          if (!_isAllowed(path, allowedRoots)) {
            return 'Error: Access denied. Path "$path" is outside allowed root folders.';
          }
          final type = await FileSystemEntity.type(path);
          if (type == FileSystemEntityType.notFound) {
            return 'Path "$path" does not exist.';
          }
          if (type == FileSystemEntityType.directory) {
            await Directory(path).delete(recursive: true);
          } else {
            await File(path).delete();
          }
          return 'Successfully deleted "$path".';
        },
      );

  static AgentTool moveFile(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'move_file',
        description:
            'Moves or renames a file/directory from source to destination.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'sourcePath': {
              'type': 'string',
              'description': 'Original path.',
            },
            'destinationPath': {
              'type': 'string',
              'description': 'New path.',
            },
          },
          'required': ['sourcePath', 'destinationPath'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final src = _resolvePath(
              args['sourcePath'] as String? ?? '', allowedRoots, activeWorkdir);
          final dst = _resolvePath(args['destinationPath'] as String? ?? '',
              allowedRoots, activeWorkdir);
          if (!_isAllowed(src, allowedRoots) ||
              !_isAllowed(dst, allowedRoots)) {
            return 'Error: Access denied. Both source and destination must be inside allowed root folders.';
          }
          final type = await FileSystemEntity.type(src);
          if (type == FileSystemEntityType.notFound) {
            return 'Source path "$src" does not exist.';
          }
          try {
            if (type == FileSystemEntityType.directory) {
              await Directory(dst).parent.create(recursive: true);
              await Directory(src).rename(dst);
            } else {
              final file = File(src);
              await File(dst).parent.create(recursive: true);
              try {
                await file.rename(dst);
              } catch (_) {
                await file.copy(dst);
                await file.delete();
              }
            }
            return 'Successfully moved "$src" to "$dst".';
          } catch (e) {
            return 'Failed to move "$src" to "$dst": $e';
          }
        },
      );

  static AgentTool batchMoveFiles(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'batch_move_files',
        description:
            'Moves multiple files or organizes a list of files into target directories in a single operation. '
            'Each item must specify "sourcePath" and "destinationPath".',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'moves': {
              'type': 'array',
              'description':
                  'List of move operations with sourcePath and destinationPath.',
              'items': {
                'type': 'object',
                'properties': {
                  'sourcePath': {'type': 'string'},
                  'destinationPath': {'type': 'string'},
                },
                'required': ['sourcePath', 'destinationPath'],
              },
            },
          },
          'required': ['moves'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final movesRaw = args['moves'];
          if (movesRaw is! List || movesRaw.isEmpty) {
            return 'Error: "moves" list must contain at least one operation.';
          }
          var movedCount = 0;
          final errors = <String>[];

          for (final item in movesRaw) {
            if (item is! Map) continue;
            final src = _resolvePath(item['sourcePath'] as String? ?? '',
                allowedRoots, activeWorkdir);
            final dst = _resolvePath(item['destinationPath'] as String? ?? '',
                allowedRoots, activeWorkdir);
            if (!_isAllowed(src, allowedRoots) ||
                !_isAllowed(dst, allowedRoots)) {
              errors.add('Access denied for $src -> $dst');
              continue;
            }
            try {
              final type = await FileSystemEntity.type(src);
              if (type == FileSystemEntityType.notFound) {
                errors.add('Not found: $src');
                continue;
              }
              if (type == FileSystemEntityType.directory) {
                await Directory(dst).parent.create(recursive: true);
                await Directory(src).rename(dst);
              } else {
                final file = File(src);
                await File(dst).parent.create(recursive: true);
                try {
                  await file.rename(dst);
                } catch (_) {
                  await file.copy(dst);
                  await file.delete();
                }
              }
              movedCount++;
            } catch (e) {
              errors.add('Error moving $src: $e');
            }
          }

          final buffer =
              StringBuffer('Successfully moved $movedCount file(s).');
          if (errors.isNotEmpty) {
            buffer.write('\nWarnings/Errors:\n• ${errors.join("\n• ")}');
          }
          return buffer.toString();
        },
      );

  static AgentTool organizeDirectory(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'organize_directory',
        description:
            'Automatically organizes and sorts all files in a directory into categorized subfolders '
            '(Documents, Images, Audio, Videos, Archives, Code, Others) based on file extensions.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'directory': {
              'type': 'string',
              'description': 'Directory path to organize.',
            },
          },
          'required': ['directory'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['directory'] as String? ?? '.';
          final dirPath = _resolvePath(rawPath, allowedRoots, activeWorkdir);

          if (!_isAllowed(dirPath, allowedRoots)) {
            return 'Error: Access denied. Path "$dirPath" is outside allowed root folders.';
          }
          final dir = Directory(dirPath);
          if (!await dir.exists()) return 'Directory "$dirPath" does not exist.';

          const extensionsToFolder = <String, String>{
            '.pdf': 'Documents',
            '.doc': 'Documents',
            '.docx': 'Documents',
            '.txt': 'Documents',
            '.xlsx': 'Documents',
            '.csv': 'Documents',
            '.pptx': 'Documents',
            '.epub': 'Documents',
            '.jpg': 'Images',
            '.jpeg': 'Images',
            '.png': 'Images',
            '.gif': 'Images',
            '.webp': 'Images',
            '.svg': 'Images',
            '.mp3': 'Audio',
            '.m4a': 'Audio',
            '.wav': 'Audio',
            '.mp4': 'Videos',
            '.mkv': 'Videos',
            '.mov': 'Videos',
            '.zip': 'Archives',
            '.rar': 'Archives',
            '.7z': 'Archives',
            '.tar': 'Archives',
            '.gz': 'Archives',
            '.apk': 'APKs',
            '.dart': 'Code',
            '.py': 'Code',
            '.js': 'Code',
            '.json': 'Code',
            '.html': 'Code',
          };

          var moved = 0;
          final categoriesUsed = <String>{};
          final entries = await dir.list().toList();

          for (final entity in entries) {
            if (entity is! File) continue;
            final ext = p.extension(entity.path).toLowerCase();
            final category = extensionsToFolder[ext] ?? 'Others';
            final targetDir = p.join(dirPath, category);
            final targetPath = p.join(targetDir, p.basename(entity.path));

            try {
              await Directory(targetDir).create(recursive: true);
              try {
                await entity.rename(targetPath);
              } catch (_) {
                await entity.copy(targetPath);
                await entity.delete();
              }
              moved++;
              categoriesUsed.add(category);
            } catch (_) {}
          }

          if (moved == 0) return 'No unorganized files found in "$dirPath".';
          return 'Successfully organized $moved file(s) into subfolders: ${categoriesUsed.join(", ")}.';
        },
      );

  static AgentTool searchFiles(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'search_files',
        description:
            'Searches for files matching a pattern inside a directory.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'directory': {
              'type': 'string',
              'description': 'Root directory to search.',
            },
            'query': {
              'type': 'string',
              'description': 'Filename substring or extension to match.',
            },
          },
          'required': ['directory', 'query'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['directory'] as String? ?? '.';
          final dirPath = _resolvePath(rawPath, allowedRoots, activeWorkdir);
          final query = (args['query'] as String? ?? '').toLowerCase();

          if (!_isAllowed(dirPath, allowedRoots)) {
            return 'Error: Access denied. Path "$dirPath" is outside allowed root folders.';
          }
          final dir = Directory(dirPath);
          if (!await dir.exists()) return 'Directory "$dirPath" does not exist.';
          final matches = <String>[];
          await for (final entity in dir.list(recursive: true)) {
            final name = p.basename(entity.path);
            if (name.toLowerCase().contains(query)) {
              matches.add(entity.path);
            }
          }
          if (matches.isEmpty) {
            return 'No files matched "$query" in "$dirPath".';
          }
          return 'Found ${matches.length} matching files:\n${matches.join("\n")}';
        },
      );

  static AgentTool compressToZip(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'compress_to_zip',
        description:
            'Compresses a file or directory into a .zip archive inside the sandbox.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'sourcePath': {
              'type': 'string',
              'description':
                  'Path of file or directory to compress (relative to workdir or root).',
            },
            'zipFileName': {
              'type': 'string',
              'description':
                  'Optional name for the output zip file (e.g. "archive.zip").',
            },
          },
          'required': ['sourcePath'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['sourcePath'] as String? ?? '';
          final sourcePath =
              _resolvePath(rawPath, allowedRoots, activeWorkdir);
          if (!_isAllowed(sourcePath, allowedRoots)) {
            return 'Error: Access denied. Path "$sourcePath" is outside allowed root folders.';
          }
          final zipName = args['zipFileName'] as String?;
          const manager = FileManagerService();
          final outZip =
              await manager.compressToZip(sourcePath, zipFileName: zipName);
          return 'Successfully compressed to "$outZip".';
        },
      );

  static AgentTool extractZip(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'extract_zip',
        description:
            'Extracts a .zip archive into a target folder in the sandbox.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'zipPath': {
              'type': 'string',
              'description':
                  'Path of the .zip file to extract (relative to workdir or root).',
            },
            'targetFolder': {
              'type': 'string',
              'description': 'Optional target folder to extract into.',
            },
          },
          'required': ['zipPath'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['zipPath'] as String? ?? '';
          final zipPath = _resolvePath(rawPath, allowedRoots, activeWorkdir);
          if (!_isAllowed(zipPath, allowedRoots)) {
            return 'Error: Access denied. Path "$zipPath" is outside allowed root folders.';
          }
          final rawTarget = args['targetFolder'] as String?;
          final targetFolder = (rawTarget != null && rawTarget.isNotEmpty)
              ? _resolvePath(rawTarget, allowedRoots, activeWorkdir)
              : null;
          const manager = FileManagerService();
          final outDir =
              await manager.extractZip(zipPath, targetFolderPath: targetFolder);
          return 'Successfully extracted zip to "$outDir".';
        },
      );

  static AgentTool sendFileAttachment(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'send_file_attachment',
        description:
            'Sends and attaches a file from the app sandbox to the chat message so the user can easily view, preview, or download it.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Sandbox path of the file to attach (relative to workdir or root).',
            },
            'name': {
              'type': 'string',
              'description': 'Optional display name for the attachment.',
            },
          },
          'required': ['path'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['path'] as String? ?? '';
          final path = _resolvePath(rawPath, allowedRoots, activeWorkdir);
          if (!_isAllowed(path, allowedRoots)) {
            return 'Error: Access denied. Path "$path" is outside allowed root folders.';
          }
          final file = File(path);
          if (!await file.exists()) {
            return 'Error: File "$path" does not exist.';
          }
          final stat = await file.stat();
          final displayName = (args['name'] as String?)?.trim().isNotEmpty == true
              ? (args['name'] as String).trim()
              : p.basename(file.path);
          return 'ATTACHMENT_SENT: {"name": "$displayName", "path": "${file.path}", "size": ${stat.size}}';
        },
      );

  static AgentTool analyzeImage(
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) =>
      AgentTool(
        name: 'analyze_image',
        description:
            'Inspects an image file inside the sandbox and extracts detailed metadata (dimensions, format, file size, color channels, aspect ratio).',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Sandbox path of the image to analyze (e.g. "photo.jpg" or "Pictures/screenshot.png").',
            },
          },
          'required': ['path'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawPath = args['path'] as String? ?? '';
          final path = _resolvePath(rawPath, allowedRoots, activeWorkdir);
          if (!_isAllowed(path, allowedRoots)) {
            return 'Error: Access denied. Path "$path" is outside allowed root folders.';
          }
          final file = File(path);
          if (!await file.exists()) {
            return 'Error: Image file "$path" does not exist.';
          }
          try {
            final bytes = await file.readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded == null) {
              return 'Error: Unable to decode image data from "$path". File may be corrupt or unsupported.';
            }
            final stat = await file.stat();
            final aspect = (decoded.width / (decoded.height > 0 ? decoded.height : 1))
                .toStringAsFixed(2);
            final kb = (stat.size / 1024).toStringAsFixed(1);
            return 'Image Analysis for "${p.basename(path)}":\n'
                '• Resolution: ${decoded.width} x ${decoded.height} px\n'
                '• Aspect Ratio: $aspect\n'
                '• File Size: $kb KB (${stat.size} bytes)\n'
                '• Channels / Bits per Channel: ${decoded.numChannels} / ${decoded.bitsPerChannel}\n'
                '• Has Alpha (Transparency): ${decoded.hasAlpha}\n'
                '• Path: ${file.path}';
          } catch (e) {
            return 'Error analyzing image: $e';
          }
        },
      );

  static AgentTool getWorkdir([String activeWorkdir = '']) => AgentTool(
        name: 'get_workdir',
        description:
            'Returns the current working directory of the agent inside the app sandbox.',
        inputSchema: const {
          'type': 'object',
          'properties': {},
        },
        risk: ToolRisk.safe,
        run: (_) async {
          final cur = activeWorkdir.trim();
          return (cur.isEmpty ||
                  cur == 'default' ||
                  cur == 'root' ||
                  cur == '/')
              ? 'Current working directory: root/'
              : 'Current working directory: root/$cur';
        },
      );
}
