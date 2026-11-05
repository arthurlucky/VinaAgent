import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pocketstrike/core/storage/app_sandbox.dart';
import 'package:pocketstrike/features/memory/domain/memory_note.dart';

/// Local-first Markdown memory vault with tags, backlinks and lightweight RAG.
///
/// The vault is a normal folder (`VinaAgent/Memory`) of `.md` files, so it can
/// also be opened from the built-in file manager. Notes tagged `#notememori`
/// are eligible for automatic retrieval into the agent's context.
class MemoryVault {
  MemoryVault({Future<Directory> Function()? rootProvider})
      : _rootProvider = rootProvider ?? _defaultRoot;

  final Future<Directory> Function() _rootProvider;

  List<MemoryNote>? _cache;
  DateTime? _cacheAt;
  static const Duration _cacheTtl = Duration(seconds: 5);
  static const int _maxNotes = 500;
  static const int _maxNoteBytes = 200 * 1024;

  static Future<Directory> _defaultRoot() async {
    final sandbox = await AppSandbox.root();
    final dir = Directory(p.join(sandbox.path, 'Memory'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> root() async {
    final dir = await _rootProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Lists all notes, newest first. Results are cached briefly because RAG
  /// runs on every chat turn.
  Future<List<MemoryNote>> listNotes({bool force = false}) async {
    final now = DateTime.now();
    final cached = _cache;
    final cachedAt = _cacheAt;
    if (!force &&
        cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _cacheTtl) {
      return cached;
    }

    final dir = await root();
    final notes = <MemoryNote>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.md')) continue;
        final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
        if (rel.startsWith('.')) continue;
        try {
          final stat = await entity.stat();
          if (stat.size > _maxNoteBytes) continue;
          final body = await entity.readAsString();
          notes.add(_parseNote(entity, rel, body, stat));
        } catch (_) {
          // Ignore unreadable notes and keep scanning the vault.
        }
        if (notes.length >= _maxNotes) break;
      }
    } catch (_) {}

    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _cache = notes;
    _cacheAt = now;
    return notes;
  }

  MemoryNote _parseNote(
    File file,
    String relativePath,
    String body,
    FileStat stat,
  ) {
    final fallback = p.basenameWithoutExtension(file.path);
    return MemoryNote(
      path: file.path,
      relativePath: relativePath,
      title: extractTitle(body, fallback),
      body: body,
      tags: extractTags(body),
      updatedAt: stat.modified,
      sizeBytes: stat.size,
    );
  }

  Future<MemoryNote?> readNote(String path) async {
    final dir = await root();
    try {
      final file = _resolveNoteFile(dir, path);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      final body = await file.readAsString();
      final rel = p.relative(file.path, from: dir.path).replaceAll('\\', '/');
      return _parseNote(file, rel, body, stat);
    } catch (_) {
      return null;
    }
  }

  Future<MemoryNote?> findByTitle(String title) async {
    final target = title.trim().toLowerCase();
    if (target.isEmpty) return null;
    final notes = await listNotes();
    return notes.where((n) => n.title.toLowerCase() == target).firstOrNull ??
        notes
            .where((n) => n.relativePath.toLowerCase().contains(target))
            .firstOrNull;
  }

  Future<MemoryNote> createNote({
    required String title,
    required String body,
  }) async {
    final dir = await root();
    final slug = slugify(title);
    var file = File(p.join(dir.path, '$slug.md'));
    var counter = 2;
    while (await file.exists()) {
      file = File(p.join(dir.path, '$slug-$counter.md'));
      counter++;
    }
    final content = ensureHeading(title, body);
    await file.writeAsString(content, flush: true);
    _invalidate();
    final stat = await file.stat();
    final rel = p.relative(file.path, from: dir.path).replaceAll('\\', '/');
    return _parseNote(file, rel, content, stat);
  }

  Future<MemoryNote> saveNote({
    String? path,
    required String title,
    required String body,
  }) async {
    if (path == null || path.trim().isEmpty) {
      return createNote(title: title, body: body);
    }
    final dir = await root();
    final file = _resolveNoteFile(dir, path);
    await file.parent.create(recursive: true);
    final content = ensureHeading(title, body);
    await file.writeAsString(content, flush: true);
    _invalidate();
    final stat = await file.stat();
    final rel = p.relative(file.path, from: dir.path).replaceAll('\\', '/');
    return _parseNote(file, rel, content, stat);
  }

  Future<void> deleteNote(String path) async {
    final dir = await root();
    final file = _resolveNoteFile(dir, path);
    if (await file.exists()) {
      await file.delete();
    }
    _invalidate();
  }

  Future<void> rebuildIndex() async {
    await listNotes(force: true);
  }

  File _resolveNoteFile(Directory root, String path) {
    var value = path.trim();
    if (!p.isAbsolute(value)) {
      if (value == 'Memory') {
        value = '';
      } else if (value.startsWith('Memory/')) {
        value = value.substring('Memory/'.length);
      }
    }
    final abs = p.isAbsolute(value) ? value : p.join(root.path, value);
    final resolved = p.canonicalize(abs);
    final rootNorm = p.canonicalize(root.path);
    if (resolved != rootNorm && !p.isWithin(rootNorm, resolved)) {
      throw StateError('Note path escapes the memory vault.');
    }
    if (!resolved.toLowerCase().endsWith('.md')) {
      throw StateError('Memory notes must be .md files.');
    }
    return File(resolved);
  }

  /// Full-text keyword search with title/tag boosts and a recency tiebreaker.
  Future<List<MemorySearchHit>> search(
    String query, {
    int limit = 5,
    bool memoryOnly = false,
  }) async {
    final queryTokens = _tokenize(query);
    if (queryTokens.isEmpty) return const [];
    final notes = await listNotes();
    final hits = <MemorySearchHit>[];
    final now = DateTime.now();
    final lowerQuery = query.trim().toLowerCase();

    for (final note in notes) {
      if (memoryOnly && !note.isMemory) continue;
      final titleTokens = _tokenize(note.title).toSet();
      final tagTokens = note.tags.expand(_tokenize).toSet();
      final bodyFreq = <String, int>{};
      for (final token in _tokenize(note.body)) {
        bodyFreq[token] = (bodyFreq[token] ?? 0) + 1;
      }

      var score = 0.0;
      for (final token in queryTokens) {
        if (titleTokens.contains(token)) score += 6;
        if (tagTokens.contains(token)) score += 4;
        score += (bodyFreq[token] ?? 0).clamp(0, 5).toDouble();
      }
      if (lowerQuery.isNotEmpty && note.title.toLowerCase().contains(lowerQuery)) {
        score += 10;
      }
      if (score <= 0) continue;

      final days = now.difference(note.updatedAt).inDays;
      score += 2 / (1 + days / 30);
      hits.add(MemorySearchHit(
        note: note,
        score: score,
        snippet: _snippet(note.body, queryTokens),
      ));
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  /// Builds the system-prompt block for RAG-injected `#notememori` notes.
  Future<String> buildRagContext(String query, {int limit = 4}) async {
    final hits = await search(query, limit: limit, memoryOnly: true);
    if (hits.isEmpty) return '';
    final buffer = StringBuffer(
      '## Relevant memory notes (RAG)\n'
      'These local Markdown notes were retrieved for the current request. '
      'Use them when they help and do not invent facts that are not present.\n',
    );
    for (final hit in hits) {
      final note = hit.note;
      buffer.writeln('\n### ${note.title}');
      buffer.writeln('Path: ${note.relativePath}');
      if (note.tags.isNotEmpty) {
        buffer.writeln('Tags: ${note.tags.map((t) => '#$t').join(' ')}');
      }
      final body = note.body.trim();
      buffer.writeln(body.length > 1400 ? '${body.substring(0, 1400)}…' : body);
    }
    return buffer.toString().trim();
  }

  /// Resolves `@path` mentions in the user's message into file/folder context.
  Future<String> buildReferenceContext(String text) async {
    final refs = await resolveReferences(text);
    if (refs.isEmpty) return '';
    final buffer = StringBuffer(
      '## Referenced files and folders\n'
      'The user referenced these paths with @mentions. Treat their contents '
      'as context for the current request.\n',
    );
    for (final ref in refs) {
      buffer.writeln(
        '\n### @${ref.relativePath}${ref.isDirectory ? '/' : ''}',
      );
      if (ref.isDirectory) {
        if (ref.entries.isEmpty) {
          buffer.writeln('(empty folder)');
        } else {
          for (final entry in ref.entries) {
            buffer.writeln('- $entry');
          }
        }
      } else {
        buffer.writeln('```');
        buffer.writeln(ref.preview);
        buffer.writeln('```');
      }
    }
    return buffer.toString().trim();
  }

  Future<List<MemoryReference>> resolveReferences(String text) async {
    final matches = RegExp(r'(?<!\S)@(?:"([^"]+)"|([^\s@]+))').allMatches(text);
    if (matches.isEmpty) return const [];

    final sandbox = await AppSandbox.root();
    final sandboxRoot = sandbox.path;
    final refs = <MemoryReference>[];
    final seen = <String>{};

    for (final match in matches) {
      var raw = (match.group(1) ?? match.group(2) ?? '').trim();
      raw = raw.replaceFirst(RegExp(r'[.,;:!?\)\]\}]+$'), '');
      if (raw.isEmpty) continue;

      String? resolved;
      try {
        resolved = AppSandbox.resolveWithRoot(raw, sandboxRoot);
      } catch (_) {
        continue;
      }
      if (resolved == null || !seen.add(resolved)) continue;

      final type = FileSystemEntity.typeSync(resolved);
      if (type == FileSystemEntityType.directory) {
        final entries = <String>[];
        try {
          await for (final entity in Directory(resolved).list(followLinks: false)) {
            final name = p.basename(entity.path);
            entries.add(entity is Directory ? '$name/' : name);
            if (entries.length >= 50) break;
          }
        } catch (_) {}
        entries.sort();
        refs.add(MemoryReference(
          raw: raw,
          relativePath:
              p.relative(resolved, from: sandboxRoot).replaceAll('\\', '/'),
          absolutePath: resolved,
          isDirectory: true,
          entries: entries,
        ));
      } else if (type == FileSystemEntityType.file) {
        final file = File(resolved);
        var preview = '[unreadable file]';
        try {
          final stat = await file.stat();
          final ext = p.extension(resolved).toLowerCase();
          final isText = _textExtensions.contains(ext);
          if (isText && stat.size <= 120 * 1024) {
            final content = await file.readAsString();
            preview =
                content.length > 6000 ? '${content.substring(0, 6000)}…' : content;
          } else {
            preview =
                '[${isText ? 'file' : 'binary file'}, ${stat.size} bytes]';
          }
        } catch (_) {}
        refs.add(MemoryReference(
          raw: raw,
          relativePath:
              p.relative(resolved, from: sandboxRoot).replaceAll('\\', '/'),
          absolutePath: resolved,
          isDirectory: false,
          preview: preview,
        ));
      }

      if (refs.length >= 5) break;
    }
    return refs;
  }

  /// Saves a chat message containing `#notememori` as a memory note.
  Future<MemoryNote?> captureChatNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    var body = trimmed;
    if (!extractTags(body).any((t) => t.toLowerCase() == 'notememori')) {
      body = '$body\n\n#notememori';
    }

    final existing = (await listNotes()).where((note) {
      final plain = stripTitleHeading(note.body).trim();
      return plain == body.trim() || note.body.trim() == body.trim();
    }).firstOrNull;
    if (existing != null) return existing;

    final firstLine = trimmed.split('\n').first.trim();
    var title = firstLine
        .replaceAll(RegExp(r'#notememori', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .trim();
    if (title.isEmpty) title = 'Chat memory';
    if (title.length > 80) title = title.substring(0, 80).trim();
    return createNote(title: title, body: body);
  }

  /// Links to other notes written as `[[Note title]]` or `[[Note|alias]]`.
  static List<String> outgoingLinks(String body) {
    final links = <String>[];
    for (final match in RegExp(r'\[\[([^\]]+)\]\]').allMatches(body)) {
      var target = match.group(1)?.trim() ?? '';
      final pipe = target.indexOf('|');
      if (pipe >= 0) target = target.substring(0, pipe).trim();
      final hash = target.indexOf('#');
      if (hash >= 0) target = target.substring(0, hash).trim();
      if (target.isNotEmpty && !links.contains(target)) {
        links.add(target);
      }
    }
    return links;
  }

  Future<List<MemoryNote>> backlinks(
    String title, {
    String? excludePath,
  }) async {
    final target = title.trim().toLowerCase();
    if (target.isEmpty) return const [];
    final notes = await listNotes();
    return notes.where((note) {
      if (excludePath != null && note.path == excludePath) return false;
      return outgoingLinks(note.body)
          .map((link) => link.toLowerCase())
          .any((link) => link == target || link.startsWith('$target#'));
    }).toList();
  }

  static String extractTitle(String body, String fallback) {
    final match = RegExp(r'^\s*#\s+(.+)$', multiLine: true).firstMatch(body);
    final title = match?.group(1)?.trim() ?? '';
    if (title.isNotEmpty) return title;
    final clean = fallback.trim();
    return clean.isEmpty ? 'Untitled note' : clean;
  }

  static Set<String> extractTags(String body) {
    final cleaned = body.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    final tags = <String>{};
    for (final match
        in RegExp(r'(?<![\w#])#([A-Za-z0-9_][A-Za-z0-9_\-/]*)').allMatches(cleaned)) {
      final tag = match.group(1);
      if (tag != null && tag.isNotEmpty) tags.add(tag);
    }
    return tags;
  }

  static String slugify(String title) {
    var slug = title.trim().toLowerCase();
    slug = slug.replaceAll(RegExp(r'[^a-z0-9\u00c0-\u024f]+'), '-');
    slug = slug.replaceAll(RegExp(r'-+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) slug = 'note-${DateTime.now().millisecondsSinceEpoch}';
    if (slug.length > 64) {
      slug = slug.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
    }
    return slug;
  }

  static String ensureHeading(String title, String body) {
    final safeTitle = title.trim().isEmpty ? 'Untitled note' : title.trim();
    final trimmedBody = body.trim();
    if (trimmedBody.startsWith('# ')) return trimmedBody;
    return '# $safeTitle\n\n$trimmedBody';
  }

  /// Removes the first Markdown heading so the editor can show title/body
  /// separately.
  static String stripTitleHeading(String body) {
    final trimmed = body.trimLeft();
    final match = RegExp(r'^#\s+.*(?:\r?\n|$)').firstMatch(trimmed);
    if (match == null) return body;
    return trimmed.substring(match.end).replaceFirst(RegExp(r'^\s*\n'), '').trim();
  }

  static final RegExp _wordPattern = RegExp(r'[a-z0-9\u00c0-\u024f]+');

  static const Set<String> _stopwords = {
    'the', 'and', 'for', 'with', 'this', 'that', 'from', 'are', 'was',
    'were', 'have', 'has', 'had', 'you', 'your', 'but', 'not', 'can',
    'will', 'would', 'should', 'about', 'into', 'than', 'then', 'them',
    'they', 'there', 'here', 'what', 'when', 'where', 'which', 'who',
    'how', 'why', 'all', 'any', 'our', 'out', 'use', 'using', 'used',
    'dan', 'yang', 'untuk', 'dengan', 'dari', 'ini', 'itu', 'adalah',
    'pada', 'akan', 'tidak', 'bisa', 'dalam', 'juga', 'atau', 'karena',
    'saya', 'kamu', 'anda', 'kita', 'mereka', 'dia', 'ke', 'di', 'se',
  };

  static List<String> _tokenize(String text) => _wordPattern
      .allMatches(text.toLowerCase())
      .map((match) => match.group(0)!)
      .where((token) => token.length >= 2 && !_stopwords.contains(token))
      .toList();

  static String _snippet(String body, List<String> tokens) {
    final plain = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (plain.isEmpty) return '';
    final lower = plain.toLowerCase();
    var index = -1;
    for (final token in tokens) {
      final found = lower.indexOf(token);
      if (found >= 0 && (index < 0 || found < index)) index = found;
    }
    if (index < 0) {
      return plain.length <= 220 ? plain : '${plain.substring(0, 220)}…';
    }
    final start = (index - 80).clamp(0, plain.length).toInt();
    final end = (start + 220).clamp(0, plain.length).toInt();
    final snippet = plain.substring(start, end).trim();
    return '${start > 0 ? '…' : ''}$snippet${end < plain.length ? '…' : ''}';
  }

  void _invalidate() {
    _cache = null;
    _cacheAt = null;
  }

  static const Set<String> _textExtensions = {
    '.txt', '.md', '.markdown', '.dart', '.json', '.yaml', '.yml', '.xml',
    '.html', '.htm', '.css', '.js', '.ts', '.jsx', '.tsx', '.py', '.java',
    '.kt', '.kts', '.swift', '.c', '.cc', '.cpp', '.h', '.hpp', '.sh',
    '.bash', '.csv', '.tsv', '.log', '.ini', '.toml', '.sql', '.rs', '.go',
    '.rb', '.php', '.env', '.gitignore',
  };
}
