import 'package:flutter/material.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/core/storage/sandbox_browser.dart';

/// Picker for `@file` and `@folder` mentions in the composer and note editor.
class SandboxMentionSheet extends StatefulWidget {
  const SandboxMentionSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SandboxMentionSheet(),
    );
  }

  @override
  State<SandboxMentionSheet> createState() => _SandboxMentionSheetState();
}

class _SandboxMentionSheetState extends State<SandboxMentionSheet> {
  final _searchController = TextEditingController();
  late Future<List<SandboxEntry>> _entries;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _entries = SandboxBrowser.listAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final height = MediaQuery.of(context).size.height * 0.72;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: tokens.textSecondary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(
              children: [
                Icon(Icons.alternate_email, color: tokens.accent, size: 21),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mention a file or folder',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search Documents, Downloads, Memory…',
                prefixIcon: const Icon(Icons.search, size: 19),
                isDense: true,
                filled: true,
                fillColor: tokens.glassColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.glassBorder),
                ),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: FutureBuilder<List<SandboxEntry>>(
              future: _entries,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not read the sandbox.',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  );
                }
                final all = snapshot.data ?? const <SandboxEntry>[];
                final query = _query.toLowerCase();
                final filtered = query.isEmpty
                    ? all
                    : all
                        .where((entry) =>
                            entry.relativePath.toLowerCase().contains(query))
                        .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      all.isEmpty
                          ? 'The sandbox is empty.'
                          : 'No matching files or folders.',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        entry.isDirectory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                        color: entry.isDirectory
                            ? tokens.accent
                            : tokens.textSecondary,
                        size: 21,
                      ),
                      title: Text(
                        entry.relativePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        entry.isDirectory ? 'Folder' : 'File',
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textSecondary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.add_circle_outline,
                        size: 19,
                        color: tokens.textSecondary,
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        '${entry.relativePath}${entry.isDirectory ? '/' : ''}',
                      ),
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
