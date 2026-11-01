import 'package:dio/dio.dart';

import '../domain/agent_skill.dart';
import '../domain/marketplace_models.dart';
import 'skill_parser.dart';
import 'skill_store.dart';

/// Raised when the marketplace cannot reach GitHub or the repo is invalid.
class MarketplaceException implements Exception {
  MarketplaceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _RepoFile {
  const _RepoFile(this.path, this.size);

  final String path;
  final int size;
}

class _RepoTree {
  const _RepoTree(this.branch, this.files);

  final String branch;
  final List<_RepoFile> files;
}

/// Reads Agent Skills straight from public GitHub repositories.
///
/// This is the same upstream that marketplaces such as skills.sh and ClawHub
/// index (`npx skills add owner/repo`), so the catalog stays current without
/// needing an API key.
class GithubMarketplaceClient {
  GithubMarketplaceClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 25),
                headers: const {
                  'Accept': 'application/vnd.github+json',
                  'User-Agent': 'Vina-Agent-Skill-Marketplace',
                },
              ),
            );

  static const String _api = 'https://api.github.com';
  static const String _raw = 'https://raw.githubusercontent.com';
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const int _maxFilesPerSkill = 40;
  static const int _maxFileBytes = 512 * 1024;
  static const int _maxTotalBytes = 4 * 1024 * 1024;
  static const Set<String> _binaryExtensions = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'ico', 'pdf', 'zip', 'gz', 'tar',
    'ttf', 'otf', 'woff', 'woff2', 'so', 'dll', 'jar', 'mp3', 'mp4', 'mov',
  };

  final Dio _dio;
  final Map<String, _RepoTree> _treeCache = {};
  final Map<String, DateTime> _treeCacheAt = {};

  /// Lists every valid skill in [source].
  Future<List<MarketplaceSkill>> listSkills(MarketplaceSource source) async {
    final tree = await _tree(source);
    final directories = <String>{};

    for (final file in tree.files) {
      if (!file.path.endsWith('SKILL.md')) continue;
      final directory = file.path.substring(
        0,
        file.path.length - 'SKILL.md'.length,
      );
      directories.add(
        directory.endsWith('/')
            ? directory.substring(0, directory.length - 1)
            : directory,
      );
    }

    final futures = directories.map((directory) async {
      final slug = directory.isEmpty ? source.repo : directory.split('/').last;
      final path = directory.isEmpty ? 'SKILL.md' : '$directory/SKILL.md';
      try {
        final raw = await _rawText(source, tree.branch, path);
        final parsed = SkillParser.parse(raw, fallbackName: slug);
        return MarketplaceSkill(
          source: source,
          directory: directory,
          name: parsed.name,
          description: parsed.description,
        );
      } catch (_) {
        return null;
      }
    });

    final results = await Future.wait(futures);
    final skills = results.whereType<MarketplaceSkill>().toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return skills;
  }

  /// Free-text search over the featured sources (name + description).
  Future<List<MarketplaceSkill>> search(String query, {int limit = 20}) async {
    final needle = query.trim().toLowerCase();
    final matches = <MarketplaceSkill>[];

    for (final source in kFeaturedSkillSources) {
      try {
        final skills = await listSkills(source);
        for (final skill in skills) {
          if (needle.isEmpty ||
              skill.name.toLowerCase().contains(needle) ||
              skill.description.toLowerCase().contains(needle) ||
              skill.source.id.toLowerCase().contains(needle)) {
            matches.add(skill);
          }
        }
      } catch (_) {
        // A single unreachable source must not break the whole search.
      }
      if (matches.length >= limit) break;
    }

    matches.sort((a, b) => a.name.compareTo(b.name));
    return matches.take(limit).toList();
  }

  /// Downloads and installs [skill] into [store].
  Future<AgentSkill> install(
    MarketplaceSkill skill,
    SkillStore store,
  ) async {
    final prefix = skill.directory.isEmpty ? '' : '${skill.directory}/';
    final files = <String, String>{};
    var branch = skill.branch.isEmpty ? 'main' : skill.branch;

    try {
      final tree = await _tree(
        skill.source,
        branch: skill.branch.isEmpty ? null : skill.branch,
      );
      branch = tree.branch;
      final candidates = tree.files.where((file) {
        if (prefix.isEmpty) return !file.path.contains('/');
        return file.path.startsWith(prefix);
      }).toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final selected = <_RepoFile>[];
      var totalBytes = 0;
      for (final file in candidates) {
        if (selected.length >= _maxFilesPerSkill) break;
        if (file.size > _maxFileBytes) continue;
        if (totalBytes + file.size > _maxTotalBytes) break;
        if (_isBinary(file.path)) continue;
        selected.add(file);
        totalBytes += file.size;
      }

      for (final file in selected) {
        final relative =
            prefix.isEmpty ? file.path : file.path.substring(prefix.length);
        files[relative] = await _rawText(skill.source, tree.branch, file.path);
      }
    } catch (_) {
      // GitHub's tree API is rate-limited anonymously; SKILL.md alone is
      // enough to install and still works through raw.githubusercontent.com.
    }

    if (!files.containsKey('SKILL.md')) {
      final skillPath =
          prefix.isEmpty ? 'SKILL.md' : '${prefix}SKILL.md';
      try {
        files['SKILL.md'] = await _rawText(skill.source, branch, skillPath);
      } catch (_) {
        throw MarketplaceException('Skill "${skill.slug}" has no SKILL.md.');
      }
    }

    return store.installSkill(
      name: skill.name,
      files: files,
      metadata: {
        'source': skill.source.id,
        'directory': skill.directory,
        'url': skill.githubUrl.isEmpty ? skill.source.url : skill.githubUrl,
      },
    );
  }

  /// Resolves `owner/repo` + slug and installs it.
  Future<AgentSkill> installBySlug(
    String sourceId,
    String slug,
    SkillStore store,
  ) async {
    final source = _sourceById(sourceId);
    final skills = await listSkills(source);
    for (final skill in skills) {
      if (skill.slug == slug || skill.name == slug) {
        return install(skill, store);
      }
    }
    throw MarketplaceException('Skill "$slug" not found in $sourceId.');
  }

  MarketplaceSource _sourceById(String id) {
    for (final source in kFeaturedSkillSources) {
      if (source.id == id) return source;
    }
    return MarketplaceSource.parse(id);
  }

  String _treeKey(MarketplaceSource source, String? branch) =>
      '${source.id}@${branch ?? 'default'}';

  Future<_RepoTree> _tree(
    MarketplaceSource source, {
    String? branch,
  }) async {
    final key = _treeKey(source, branch);
    final cached = _treeCache[key];
    final cachedAt = _treeCacheAt[key];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }

    try {
      var resolvedBranch = branch;
      if (resolvedBranch == null || resolvedBranch.isEmpty) {
        final repo = await _dio.get<Map<String, dynamic>>(
          '$_api/repos/${source.owner}/${source.repo}',
        );
        resolvedBranch =
            repo.data?['default_branch'] as String? ?? 'main';
      }

      final branchName = resolvedBranch;
      final tree = await _dio.get<Map<String, dynamic>>(
        '$_api/repos/${source.owner}/${source.repo}/git/trees/$branchName',
        queryParameters: const {'recursive': 1},
      );

      final entries = tree.data?['tree'];
      final files = <_RepoFile>[];
      if (entries is List) {
        for (final entry in entries) {
          if (entry is! Map) continue;
          if (entry['type'] != 'blob') continue;
          final path = entry['path'] as String? ?? '';
          if (path.isEmpty) continue;
          files.add(_RepoFile(path, (entry['size'] as num?)?.toInt() ?? 0));
        }
      }

      final result = _RepoTree(branchName, files);
      _treeCache[key] = result;
      _treeCacheAt[key] = DateTime.now();
      return result;
    } on DioException catch (error) {
      throw MarketplaceException(_describe(error));
    }
  }

  Future<String> _rawText(
    MarketplaceSource source,
    String branch,
    String path,
  ) async {
    final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
    final encodedBranch = Uri.encodeComponent(branch);
    final response = await _dio.get<String>(
      '$_raw/${source.owner}/${source.repo}/$encodedBranch/$encodedPath',
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  String _describe(DioException error) {
    final status = error.response?.statusCode;
    if (status == 403 || status == 429) {
      return 'GitHub rate limit reached. Try again in a few minutes.';
    }
    if (status == 404) return 'Repository not found on GitHub.';
    if (status != null) return 'GitHub request failed ($status).';
    return 'Could not reach GitHub. Check your connection.';
  }

  bool _isBinary(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return _binaryExtensions.contains(path.substring(dot + 1).toLowerCase());
  }
}
