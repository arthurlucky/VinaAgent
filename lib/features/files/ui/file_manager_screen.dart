import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/glass_tokens.dart';
import '../application/file_manager_controller.dart';
import '../domain/file_item.dart';

/// Browse and manage files in the app sandbox. Import files from device storage.
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
    _breadcrumb.add('Documents');
    _currentPath = 'Documents';
  }

  Future<void> _importFile() async {
    final file = await FilePicker.pickFile();
    if (file == null || file.path == null) return;

    try {
      final manager = ref.read(fileManagerProvider);
      final destName = file.name;
      await manager.copyToSandbox(file.path!, '$_currentPath/$destName');

      ref.invalidate(filesInFolderProvider(_currentPath));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported: $destName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  Future<void> _deleteFile(FileItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: Text(
          item.isDirectory
              ? 'This folder and all contents will be removed.'
              : 'This file will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(fileManagerProvider).delete(item.path);
      ref.invalidate(filesInFolderProvider(_currentPath));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted: ${item.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _navigateToFolder(FileItem folder) async {
    if (!folder.isDirectory) return;
    setState(() {
      _currentPath = folder.path;
      _breadcrumb.add(folder.name);
    });
  }

  void _goUp() {
    if (_breadcrumb.length <= 1) return;
    _breadcrumb.removeLast();
    setState(() {
      _currentPath = _breadcrumb.join('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final files = ref.watch(filesInFolderProvider(_currentPath));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'File Manager',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Import file',
            icon: const Icon(Icons.download),
            onPressed: _importFile,
          ),
        ],
      ),
      body: Column(
        children: [
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
                            Text(' / ', style: TextStyle(color: tokens.textSecondary)),
                          Text(
                            _breadcrumb[i],
                            style: TextStyle(
                              color: i == _breadcrumb.length - 1
                                  ? Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black
                                  : tokens.textSecondary,
                              fontSize: 12,
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
                      child: Text(
                        'Folder is empty. Tap download icon to import files.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: Icon(
                        item.isDirectory
                            ? Icons.folder_outlined
                            : Icons.description_outlined,
                        color: tokens.accent,
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        item.isDirectory
                            ? '${item.sizeDisplay} · folder'
                            : item.sizeDisplay,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                      trailing: PopupMenuButton(
                        itemBuilder: (context) => [
                          if (!item.isDirectory)
                            PopupMenuItem(
                              child: const Text('Copy path'),
                              onTap: () async {
                                // Copy to clipboard logic
                              },
                            ),
                          PopupMenuItem(
                            child: const Text('Delete'),
                            onTap: () => _deleteFile(item),
                          ),
                        ],
                      ),
                      onTap: item.isDirectory
                          ? () => _navigateToFolder(item)
                          : null,
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
