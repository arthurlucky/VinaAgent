import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/glass_tokens.dart';
import '../../agent/application/agent_workdir_controller.dart';
import '../application/file_manager_controller.dart';
import '../domain/file_item.dart';

/// Browse and manage files in the app sandbox.
/// Features: create file/folder, extract/preview/compress ZIP, move, and set agent workdir.
class FileManagerScreen extends ConsumerStatefulWidget {
  const FileManagerScreen({super.key});

  @override
  ConsumerState<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends ConsumerState<FileManagerScreen> {
  late String _currentPath;
  final List<String> _breadcrumb = [];

  @override
  void initState() {
    super.initState();
    _currentPath = '';
    _breadcrumb.add('root');
  }

  void _refresh() {
    ref.invalidate(filesInFolderProvider(_currentPath));
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _importFile() async {
    final file = await FilePicker.pickFile();
    if (file == null || file.path == null) return;

    try {
      final manager = ref.read(fileManagerProvider);
      final destName = file.name;
      final destPath =
          _currentPath.isEmpty ? destName : '$_currentPath/$destName';
      await manager.copyToSandbox(file.path!, destPath);

      _refresh();
      _showSnack('Imported: $destName');
    } catch (e) {
      _showSnack('Import failed: $e');
    }
  }

  Future<void> _createFile() async {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'File Name',
                hintText: 'e.g. script.py, notes.txt',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Initial Content (optional)',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final fileName = nameCtrl.text.trim();
    if (fileName.isEmpty) return;

    try {
      await ref
          .read(fileManagerProvider)
          .createFile(_currentPath, fileName, content: contentCtrl.text);
      _refresh();
      _showSnack('File created: $fileName');
    } catch (e) {
      _showSnack('Error creating file: $e');
    }
  }

  Future<void> _createFolder() async {
    final nameCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'e.g. ProjectAlpha',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final folderName = nameCtrl.text.trim();
    if (folderName.isEmpty) return;

    try {
      await ref
          .read(fileManagerProvider)
          .createFolder(_currentPath, folderName);
      _refresh();
      _showSnack('Folder created: $folderName');
    } catch (e) {
      _showSnack('Error creating folder: $e');
    }
  }

  Future<void> _compressToZip(FileItem item) async {
    try {
      _showSnack('Compressing ${item.name}…');
      final outPath =
          await ref.read(fileManagerProvider).compressToZip(item.path);
      _refresh();
      _showSnack('Compressed: ${p.basename(outPath)}');
    } catch (e) {
      _showSnack('Compress failed: $e');
    }
  }

  Future<void> _extractZip(FileItem item) async {
    try {
      _showSnack('Extracting ${item.name}…');
      final outDir =
          await ref.read(fileManagerProvider).extractZip(item.path);
      _refresh();
      _showSnack('Extracted to: ${p.basename(outDir)}');
    } catch (e) {
      _showSnack('Extract failed: $e');
    }
  }

  Future<void> _previewZip(FileItem item) async {
    try {
      final entries =
          await ref.read(fileManagerProvider).previewZip(item.path);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.folder_zip, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 340,
            child: entries.isEmpty
                ? const Center(child: Text('Archive is empty.'))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          entry.isDirectory
                              ? Icons.folder_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 18,
                        ),
                        title: Text(entry.name,
                            style: const TextStyle(fontSize: 12.5)),
                        trailing: entry.isDirectory
                            ? null
                            : Text(
                                entry.sizeDisplay,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.unarchive, size: 16),
              label: const Text('Extract'),
              onPressed: () {
                Navigator.pop(context);
                _extractZip(item);
              },
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnack('Preview failed: $e');
    }
  }

  Future<void> _moveEntity(FileItem item) async {
    final folders =
        await ref.read(agentWorkdirProvider.notifier).listAvailableFolders();
    if (!mounted) return;

    final targetFolder = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${item.name} to:'),
        content: SizedBox(
          width: double.maxFinite,
          height: 250,
          child: ListView(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.home_outlined),
                title: const Text('root/ (Top-level)'),
                onTap: () => Navigator.pop(context, ''),
              ),
              const Divider(),
              for (final f in folders)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder),
                  title: Text('root/$f'),
                  onTap: () => Navigator.pop(context, f),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (targetFolder == null) return;

    try {
      await ref.read(fileManagerProvider).move(item.path, targetFolder);
      _refresh();
      _showSnack('Moved ${item.name} to ${targetFolder.isEmpty ? 'root/' : targetFolder}');
    } catch (e) {
      _showSnack('Move failed: $e');
    }
  }

  Future<void> _renameEntity(FileItem item) async {
    final nameCtrl = TextEditingController(text: item.name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${item.name}'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final newName = nameCtrl.text.trim();
    if (newName.isEmpty || newName == item.name) return;

    try {
      final parentDir = p.dirname(item.path);
      final newPath = p.join(parentDir, newName);
      await ref.read(fileManagerProvider).rename(item.path, newPath);
      _refresh();
      _showSnack('Renamed to $newName');
    } catch (e) {
      _showSnack('Rename failed: $e');
    }
  }

  Future<void> _deleteEntity(FileItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: Text(
          item.isDirectory
              ? 'This folder and all its contents will be permanently removed.'
              : 'This file will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(fileManagerProvider).delete(item.path);
      _refresh();
      _showSnack('Deleted: ${item.name}');
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }

  void _previewFile(FileItem item) {
    final file = File(item.path);
    if (!file.existsSync()) return;

    final isImg = item.name.toLowerCase().endsWith('.png') ||
        item.name.toLowerCase().endsWith('.jpg') ||
        item.name.toLowerCase().endsWith('.jpeg') ||
        item.name.toLowerCase().endsWith('.webp');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String? content;
        if (!isImg) {
          try {
            content = file.readAsStringSync();
            if (content.length > 4000) {
              content = '${content.substring(0, 4000)}\n\n… [truncated]';
            }
          } catch (_) {
            content = '[Binary file cannot be previewed]';
          }
        }

        return Container(
          padding: const EdgeInsets.all(18),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Text(
                  '${item.sizeDisplay} · ${item.path}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (isImg)
                  Expanded(
                    child: Center(
                      child: Image.file(file, fit: BoxFit.contain),
                    ),
                  )
                else if (content != null)
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          content,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy Path'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: item.path));
                          Navigator.pop(context);
                          _showSnack('Path copied');
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _navigateToFolder(FileItem folder) {
    if (!folder.isDirectory) return;
    setState(() {
      _breadcrumb.add(folder.name);
      _currentPath = _breadcrumb.skip(1).join('/');
    });
  }

  void _goUp() {
    if (_breadcrumb.length <= 1) return;
    setState(() {
      _breadcrumb.removeLast();
      _currentPath =
          _breadcrumb.length == 1 ? '' : _breadcrumb.skip(1).join('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final activeWorkdir = ref.watch(agentWorkdirProvider);
    final files = ref.watch(filesInFolderProvider(_currentPath));

    final currentIsWorkdir =
        (activeWorkdir.isEmpty && _currentPath.isEmpty) ||
            (activeWorkdir.isNotEmpty && activeWorkdir == _currentPath);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'File Manager',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        actions: [
          IconButton(
            tooltip: 'New file',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: _createFile,
          ),
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _createFolder,
          ),
          IconButton(
            tooltip: 'Import file',
            icon: const Icon(Icons.download),
            onPressed: _importFile,
          ),
        ],
      ),
      body: Column(
        children: [
          // Agent Workdir Indicator Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.08),
              border: Border(
                bottom: BorderSide(
                  color: tokens.accent.withValues(alpha: 0.2),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_outlined, size: 16, color: tokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      children: [
                        const TextSpan(
                          text: 'Agent Workdir: ',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: activeWorkdir.isEmpty
                              ? 'root/'
                              : 'root/$activeWorkdir',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: tokens.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!currentIsWorkdir && _currentPath.isNotEmpty)
                  InkWell(
                    onTap: () async {
                      await ref
                          .read(agentWorkdirProvider.notifier)
                          .setWorkdir(_currentPath);
                      _showSnack('Set workdir to: root/$_currentPath');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Text(
                        'Set this as Workdir',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: tokens.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Breadcrumb Navigation Row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                if (_breadcrumb.length > 1)
                  TextButton.icon(
                    onPressed: _goUp,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back'),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < _breadcrumb.length; i++) ...[
                          if (i > 0)
                            Text(
                              ' / ',
                              style: TextStyle(color: tokens.textSecondary),
                            ),
                          InkWell(
                            onTap: () {
                              if (i < _breadcrumb.length - 1) {
                                setState(() {
                                  _breadcrumb.removeRange(
                                      i + 1, _breadcrumb.length);
                                  _currentPath = i == 0
                                      ? ''
                                      : _breadcrumb.skip(1).join('/');
                                });
                              }
                            },
                            child: Text(
                              _breadcrumb[i],
                              style: TextStyle(
                                color: i == _breadcrumb.length - 1
                                    ? Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color ??
                                        Colors.black
                                    : tokens.textSecondary,
                                fontWeight: i == _breadcrumb.length - 1
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),

          // File List View
          Expanded(
            child: files.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Error: $error')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open_outlined,
                            size: 48,
                            color: tokens.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Folder is empty.\nUse buttons above to create files, folders or import.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: tokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isWorkdir = item.isDirectory &&
                        activeWorkdir ==
                            (_currentPath.isEmpty
                                ? item.name
                                : '$_currentPath/${item.name}');

                    return ListTile(
                      leading: Icon(
                        item.isDirectory
                            ? (isWorkdir
                                ? Icons.folder_special
                                : Icons.folder_outlined)
                            : (item.isZip
                                ? Icons.folder_zip
                                : Icons.description_outlined),
                        color: isWorkdir ? Colors.amber : tokens.accent,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isWorkdir) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Workdir',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        item.isDirectory
                            ? '${item.sizeDisplay} · folder'
                            : item.sizeDisplay,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          switch (action) {
                            case 'workdir':
                              final relPath = _currentPath.isEmpty
                                  ? item.name
                                  : '$_currentPath/${item.name}';
                              ref
                                  .read(agentWorkdirProvider.notifier)
                                  .setWorkdir(relPath);
                              _showSnack('Workdir set to: root/$relPath');
                              break;
                            case 'preview_zip':
                              _previewZip(item);
                              break;
                            case 'extract_zip':
                              _extractZip(item);
                              break;
                            case 'compress_zip':
                              _compressToZip(item);
                              break;
                            case 'move':
                              _moveEntity(item);
                              break;
                            case 'rename':
                              _renameEntity(item);
                              break;
                            case 'copy_path':
                              Clipboard.setData(
                                  ClipboardData(text: item.path));
                              _showSnack('Path copied');
                              break;
                            case 'delete':
                              _deleteEntity(item);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          if (item.isDirectory)
                            const PopupMenuItem(
                              value: 'workdir',
                              child: Row(
                                children: [
                                  Icon(Icons.terminal, size: 16),
                                  SizedBox(width: 8),
                                  Text('Set as Agent Workdir'),
                                ],
                              ),
                            ),
                          if (item.isZip) ...[
                            const PopupMenuItem(
                              value: 'preview_zip',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text('Preview Zip'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'extract_zip',
                              child: Row(
                                children: [
                                  Icon(Icons.unarchive_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text('Extract Zip Here'),
                                ],
                              ),
                            ),
                          ],
                          if (!item.isZip)
                            const PopupMenuItem(
                              value: 'compress_zip',
                              child: Row(
                                children: [
                                  Icon(Icons.archive_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text('Compress to .zip'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'move',
                            child: Row(
                              children: [
                                Icon(Icons.drive_file_move_outlined,
                                    size: 16),
                                SizedBox(width: 8),
                                Text('Move'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 16),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'copy_path',
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 16),
                                SizedBox(width: 8),
                                Text('Copy path'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 16, color: Colors.redAccent),
                                SizedBox(width: 8),
                                Text('Delete',
                                    style:
                                        TextStyle(color: Colors.redAccent)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        if (item.isDirectory) {
                          _navigateToFolder(item);
                        } else if (item.isZip) {
                          _previewZip(item);
                        } else {
                          _previewFile(item);
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
