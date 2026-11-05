import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/features/memory/application/memory_controller.dart';
import 'package:pocketstrike/features/memory/data/memory_vault.dart';
import 'package:pocketstrike/features/memory/domain/memory_note.dart';
import 'package:pocketstrike/features/memory/ui/sandbox_mention_sheet.dart';

/// Obsidian-style local Markdown memory vault.
class MemoryVaultScreen extends ConsumerStatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  ConsumerState<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends ConsumerState<MemoryVaultScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _memoryOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor(MemoryNote? note) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryNoteEditorScreen(note: note),
      ),
    );
    if (mounted) ref.invalidate(memoryNotesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final notesAsync = ref.watch(memoryNotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Memory Vault',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh notes',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await ref.read(memoryVaultProvider).rebuildIndex();
              ref.invalidate(memoryNotesProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('New note'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes, #tags, [[links]]…',
                prefixIcon: const Icon(Icons.search, size: 20),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('#notememori'),
                  selected: _memoryOnly,
                  onSelected: (value) => setState(() => _memoryOnly = value),
                  avatar: Icon(
                    Icons.psychology_outlined,
                    size: 17,
                    color: _memoryOnly ? tokens.accent : tokens.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tag a note with #notememori so RAG can recall it automatically.',
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: notesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not read the memory vault.\n$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                ),
              ),
              data: (notes) {
                final filtered = _filter(notes);
                if (filtered.isEmpty) {
                  return _EmptyVault(
                    hasNotes: notes.isNotEmpty,
                    memoryOnly: _memoryOnly,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final note = filtered[index];
                    return _NoteCard(
                      note: note,
                      onTap: () => _openEditor(note),
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

  List<MemoryNote> _filter(List<MemoryNote> notes) {
    final query = _query.toLowerCase();
    return notes.where((note) {
      if (_memoryOnly && !note.isMemory) return false;
      if (query.isEmpty) return true;
      return note.title.toLowerCase().contains(query) ||
          note.body.toLowerCase().contains(query) ||
          note.relativePath.toLowerCase().contains(query) ||
          note.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({
    required this.hasNotes,
    required this.memoryOnly,
  });

  final bool hasNotes;
  final bool memoryOnly;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              memoryOnly ? Icons.psychology_outlined : Icons.menu_book_outlined,
              size: 46,
              color: tokens.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              hasNotes
                  ? 'No notes match this filter.'
                  : 'Your memory vault is empty.',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Create Markdown notes, link them with [[other note]], '
              'and tag the ones the agent should remember with #notememori.',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap});

  final MemoryNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final date = note.updatedAt.toLocal();
    final updated =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.glassBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    note.isMemory
                        ? Icons.psychology_outlined
                        : Icons.article_outlined,
                    size: 19,
                    color: note.isMemory ? tokens.accent : tokens.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: tokens.textSecondary,
                  ),
                ],
              ),
              if (note.preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in note.tags.take(6))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: tag.toLowerCase() == 'notememori'
                            ? tokens.accent.withValues(alpha: 0.16)
                            : tokens.glassColor,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: tag.toLowerCase() == 'notememori'
                              ? tokens.accent.withValues(alpha: 0.4)
                              : tokens.glassBorder,
                        ),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: tag.toLowerCase() == 'notememori'
                              ? tokens.accent
                              : tokens.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '${note.relativePath} · $updated',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: tokens.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Markdown note editor with title/body split, tags, references and backlinks.
class MemoryNoteEditorScreen extends ConsumerStatefulWidget {
  const MemoryNoteEditorScreen({super.key, this.note});

  final MemoryNote? note;

  @override
  ConsumerState<MemoryNoteEditorScreen> createState() =>
      _MemoryNoteEditorScreenState();
}

class _MemoryNoteEditorScreenState
    extends ConsumerState<MemoryNoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  Timer? _relationDebounce;
  List<MemoryReference> _references = const [];
  List<MemoryNote> _backlinks = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _bodyController = TextEditingController(
      text: widget.note == null
          ? ''
          : MemoryVault.stripTitleHeading(widget.note!.body),
    );
    _titleController.addListener(_onChanged);
    _bodyController.addListener(_onChanged);
    _refreshRelations();
  }

  @override
  void dispose() {
    _relationDebounce?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _relationDebounce?.cancel();
    _relationDebounce = Timer(const Duration(milliseconds: 350), () {
      _refreshRelations();
    });
  }

  Future<void> _refreshRelations() async {
    final vault = ref.read(memoryVaultProvider);
    final body = _bodyController.text;
    final title = _titleController.text;
    try {
      final references = await vault.resolveReferences(body);
      final backlinks = await vault.backlinks(
        title,
        excludePath: widget.note?.path,
      );
      if (!mounted) return;
      setState(() {
        _references = references;
        _backlinks = backlinks;
      });
    } catch (_) {
      // Relation previews are best-effort and should never block editing.
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _snack('Give the note a title first.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(memoryVaultProvider).saveNote(
            path: widget.note?.path,
            title: title,
            body: _bodyController.text,
          );
      ref.invalidate(memoryNotesProvider);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      _snack('Could not save the note: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final note = widget.note;
    if (note == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          'Delete "${note.title}" from the memory vault? This cannot be undone.',
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
      await ref.read(memoryVaultProvider).deleteNote(note.path);
      ref.invalidate(memoryNotesProvider);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      _snack('Could not delete the note: $error');
    }
  }

  Future<void> _insertMention() async {
    final path = await SandboxMentionSheet.show(context);
    if (path == null || !mounted) return;
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final offset = selection.isValid
        ? selection.baseOffset.clamp(0, text.length).toInt()
        : text.length;
    final prefix = offset > 0 &&
            !text.substring(offset - 1, offset).contains(RegExp(r'\s'))
        ? ' '
        : '';
    final mention = path.contains(RegExp(r'\s')) ? '@"$path"' : '@$path';
    final insert = '$prefix$mention ';
    final next = text.replaceRange(offset, offset, insert);
    _bodyController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset + insert.length),
    );
    _refreshRelations();
  }

  void _openBacklink(MemoryNote note) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => MemoryNoteEditorScreen(note: note),
          ),
        )
        .then((_) {
      if (mounted) _refreshRelations();
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final tags = MemoryVault.extractTags(_bodyController.text);
    final links = MemoryVault.outgoingLinks(_bodyController.text);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.note == null ? 'New note' : 'Edit note',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          if (widget.note != null)
            IconButton(
              tooltip: 'Delete note',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          IconButton(
            tooltip: 'Save note',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _titleController,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            decoration: InputDecoration(
              labelText: 'Title',
              hintText: 'What should the agent remember?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            minLines: 12,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 13.5, height: 1.5),
            decoration: InputDecoration(
              labelText: 'Markdown body',
              alignLabelWithHint: true,
              hintText:
                  'Write notes, use #tags, [[links]] and @file/path references…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                Chip(
                  label: Text('#$tag', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: tag.toLowerCase() == 'notememori'
                      ? tokens.accent.withValues(alpha: 0.14)
                      : tokens.glassColor,
                  side: BorderSide(
                    color: tag.toLowerCase() == 'notememori'
                        ? tokens.accent.withValues(alpha: 0.4)
                        : tokens.glassBorder,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: tokens.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.psychology_outlined,
                    size: 18, color: tokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Add #notememori to make this note eligible for automatic '
                    'RAG recall. Use [[Another note]] for backlinks and '
                    '@Documents/file.txt or @Skills/ for file/folder references.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _insertMention,
              icon: const Icon(Icons.alternate_email, size: 18),
              label: const Text('Insert file/folder mention'),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(
            title: 'References',
            count: _references.length,
          ),
          if (_references.isEmpty)
            Text(
              'No @file/folder references yet.',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            )
          else
            for (final reference in _references)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  reference.isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 19,
                  color: tokens.textSecondary,
                ),
                title: Text(
                  '@${reference.relativePath}${reference.isDirectory ? '/' : ''}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                subtitle: Text(
                  reference.isDirectory
                      ? '${reference.entries.length} item(s)'
                      : reference.preview.replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                ),
              ),
          const SizedBox(height: 12),
          _SectionTitle(title: 'Backlinks', count: _backlinks.length),
          if (_backlinks.isEmpty)
            Text(
              'No other note links to this one yet.',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            )
          else
            for (final note in _backlinks)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.link,
                  size: 18,
                  color: tokens.accent,
                ),
                title: Text(
                  note.title,
                  style: const TextStyle(fontSize: 12.5),
                ),
                subtitle: Text(
                  note.relativePath,
                  style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                ),
                onTap: () => _openBacklink(note),
              ),
          const SizedBox(height: 12),
          _SectionTitle(title: 'Outgoing links', count: links.length),
          if (links.isEmpty)
            Text(
              'Use [[Note title]] to link another note.',
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final link in links)
                  Chip(
                    label: Text(link, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(fontSize: 10.5, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
