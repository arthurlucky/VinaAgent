/// A Markdown note stored in the local memory vault.
///
/// Notes live as plain `.md` files under `VinaAgent/Memory`, so they can also
/// be opened from the built-in file manager and edited with any text editor.
class MemoryNote {
  const MemoryNote({
    required this.path,
    required this.relativePath,
    required this.title,
    required this.body,
    required this.tags,
    required this.updatedAt,
    required this.sizeBytes,
  });

  /// Absolute path on disk.
  final String path;

  /// Path relative to the vault root, using forward slashes.
  final String relativePath;

  /// Title parsed from the first `# Heading` (falls back to the filename).
  final String title;

  /// Full Markdown source, including the heading.
  final String body;

  /// Hashtags found in the body (without the leading `#`).
  final Set<String> tags;

  final DateTime updatedAt;
  final int sizeBytes;

  /// Notes tagged `#notememori` are injected into the agent's RAG context.
  bool get isMemory =>
      tags.any((tag) => tag.toLowerCase() == 'notememori');

  /// Short plain-text preview for the notes list.
  String get preview {
    final text = body
        .replaceFirst(RegExp(r'^\s*#\s+.*$', multiLine: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length <= 180) return text;
    return '${text.substring(0, 180)}…';
  }
}

/// A scored search result over the memory vault.
class MemorySearchHit {
  const MemorySearchHit({
    required this.note,
    required this.score,
    required this.snippet,
  });

  final MemoryNote note;
  final double score;
  final String snippet;
}

/// A file or folder referenced from a note or chat message with `@path`.
class MemoryReference {
  const MemoryReference({
    required this.raw,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    this.preview = '',
    this.entries = const [],
  });

  final String raw;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final String preview;
  final List<String> entries;
}
