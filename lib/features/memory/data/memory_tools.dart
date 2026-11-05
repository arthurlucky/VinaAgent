import 'package:pocketstrike/features/agent/domain/agent_tool.dart';
import 'package:pocketstrike/features/memory/data/memory_vault.dart';
import 'package:pocketstrike/features/memory/domain/memory_note.dart';

/// Agent tools for the local Obsidian-style memory vault.
class MemoryTools {
  const MemoryTools._();

  static List<AgentTool> all(MemoryVault vault) => [
        saveNote(vault),
        search(vault),
        readNote(vault),
        listNotes(vault),
        deleteNote(vault),
      ];

  static AgentTool saveNote(MemoryVault vault) => AgentTool(
        name: 'save_memory_note',
        description:
            'Creates or updates a Markdown note in the local memory vault. '
            'By default the note is tagged #notememori so it can be retrieved '
            'automatically by RAG. Use [[Other note]] inside the body to link '
            'notes and @path to reference files or folders.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Note title (used as the Markdown heading).',
            },
            'body': {
              'type': 'string',
              'description': 'Markdown body. Supports #tags, [[links]] and @file/path references.',
            },
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Extra hashtags to append (without the leading #).',
            },
            'path': {
              'type': 'string',
              'description': 'Existing note path to update. Omit to create a new note.',
            },
            'memory': {
              'type': 'boolean',
              'description':
                  'When true (default), add #notememori so the note is injected by RAG.',
            },
          },
          'required': ['title', 'body'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final title = (args['title'] as String?)?.trim() ?? '';
          var body = (args['body'] as String?)?.trim() ?? '';
          if (title.isEmpty && body.isEmpty) {
            return 'Error: a title or body is required.';
          }

          final tags = (args['tags'] as List<dynamic>? ?? const [])
              .map((item) => item.toString().trim().replaceFirst(RegExp(r'^#'), ''))
              .where((item) => item.isNotEmpty)
              .toSet();
          final memory = args['memory'] as bool? ?? true;
          if (memory) tags.add('notememori');

          final existingTags = MemoryVault.extractTags(body);
          final missing = tags.where((tag) => !existingTags.any(
                (existing) => existing.toLowerCase() == tag.toLowerCase(),
              ));
          if (missing.isNotEmpty) {
            body = '${body.trim()}\n\n${missing.map((tag) => '#$tag').join(' ')}';
          }

          final note = await vault.saveNote(
            path: (args['path'] as String?)?.trim(),
            title: title.isEmpty ? 'Memory note' : title,
            body: body,
          );
          return 'Saved memory note "${note.title}" at ${note.relativePath}. '
              'Tags: ${note.tags.map((tag) => '#$tag').join(' ')}';
        },
      );

  static AgentTool search(MemoryVault vault) => AgentTool(
        name: 'search_memory',
        description:
            'Searches the local Markdown memory vault by keyword. Returns the '
            'most relevant notes with a snippet. Set memory_only to true to '
            'search only notes tagged #notememori.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Words to search for.',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of notes to return (default 5).',
            },
            'memory_only': {
              'type': 'boolean',
              'description': 'Only search #notememori notes.',
            },
          },
          'required': ['query'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final query = (args['query'] as String?)?.trim() ?? '';
          if (query.isEmpty) return 'Error: query is empty.';
          final limit =
              ((args['limit'] as num?)?.toInt() ?? 5).clamp(1, 20).toInt();
          final memoryOnly = args['memory_only'] as bool? ?? false;
          final hits = await vault.search(
            query,
            limit: limit,
            memoryOnly: memoryOnly,
          );
          if (hits.isEmpty) return 'No matching memory notes found.';
          final buffer = StringBuffer('Found ${hits.length} memory note(s):\n');
          for (final hit in hits) {
            final note = hit.note;
            buffer.writeln(
              '• ${note.title} (score ${hit.score.toStringAsFixed(1)})',
            );
            buffer.writeln('  Path: ${note.relativePath}');
            if (note.tags.isNotEmpty) {
              buffer.writeln(
                '  Tags: ${note.tags.map((tag) => '#$tag').join(' ')}',
              );
            }
            buffer.writeln('  Snippet: ${hit.snippet}');
          }
          return buffer.toString().trim();
        },
      );

  static AgentTool readNote(MemoryVault vault) => AgentTool(
        name: 'read_memory_note',
        description:
            'Reads a note from the local memory vault by path or title.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Note path, relative to the Memory folder or absolute.',
            },
            'title': {
              'type': 'string',
              'description': 'Note title to look up when path is not provided.',
            },
          },
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final note = await _resolve(vault, args);
          if (note == null) return 'Memory note not found.';
          final body = note.body.length > 8000
              ? '${note.body.substring(0, 8000)}…'
              : note.body;
          return 'Note: ${note.title}\nPath: ${note.relativePath}\n\n$body';
        },
      );

  static AgentTool listNotes(MemoryVault vault) => AgentTool(
        name: 'list_memory_notes',
        description:
            'Lists notes in the local memory vault. Set memory_only to true to '
            'list only notes tagged #notememori.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'memory_only': {
              'type': 'boolean',
              'description': 'Only list #notememori notes.',
            },
          },
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final memoryOnly = args['memory_only'] as bool? ?? false;
          final notes = await vault.listNotes();
          final filtered =
              memoryOnly ? notes.where((note) => note.isMemory).toList() : notes;
          if (filtered.isEmpty) return 'The memory vault is empty.';
          final buffer = StringBuffer('Memory notes (${filtered.length}):\n');
          for (final note in filtered) {
            buffer.writeln(
              '• ${note.title} — ${note.relativePath}'
              '${note.isMemory ? ' [#notememori]' : ''}',
            );
          }
          return buffer.toString().trim();
        },
      );

  static AgentTool deleteNote(MemoryVault vault) => AgentTool(
        name: 'delete_memory_note',
        description:
            'Deletes a note from the local memory vault by path or title. '
            'This is destructive and cannot be undone.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Note path, relative to the Memory folder or absolute.',
            },
            'title': {
              'type': 'string',
              'description': 'Note title to delete when path is not provided.',
            },
          },
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          final note = await _resolve(vault, args);
          if (note == null) return 'Memory note not found.';
          await vault.deleteNote(note.path);
          return 'Deleted memory note "${note.title}" (${note.relativePath}).';
        },
      );

  static Future<MemoryNote?> _resolve(
    MemoryVault vault,
    Map<String, dynamic> args,
  ) async {
    final path = (args['path'] as String?)?.trim();
    if (path != null && path.isNotEmpty) {
      return vault.readNote(path);
    }
    final title = (args['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) {
      return vault.findByTitle(title);
    }
    return null;
  }
}
