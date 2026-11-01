import 'package:dio/dio.dart';

import '../domain/marketplace_models.dart';

/// Raised when the SkillsMP catalog cannot be reached.
class SkillsMpException implements Exception {
  const SkillsMpException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SkillsMpPage {
  const SkillsMpPage({
    required this.skills,
    required this.page,
    required this.total,
    required this.hasNext,
  });

  final List<MarketplaceSkill> skills;
  final int page;
  final int total;
  final bool hasNext;
}

/// Client for the free SkillsMP REST catalog (skillsmp.com).
///
/// Anonymous access allows a limited number of searches per day; the UI
/// surfaces rate-limit errors instead of failing silently.
class SkillsMpClient {
  SkillsMpClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://skillsmp.com',
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 25),
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'Vina-Agent/2.1 (SkillsMP)',
                },
              ),
            );

  final Dio _dio;

  Future<SkillsMpPage> search(
    String query, {
    int page = 1,
    int limit = 20,
    String sortBy = 'stars',
    String? language,
  }) async {
    final keyword = query.trim().isEmpty ? 'agent' : query.trim();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/skills/search',
        queryParameters: {
          'q': keyword,
          'page': page,
          'limit': limit.clamp(1, 50),
          'sortBy': sortBy == 'recent' ? 'recent' : 'stars',
          if (language != null && language.isNotEmpty) 'language': language,
        },
      );
      final data = _map(response.data?['data']);
      final items = data['skills'];
      final pagination = _map(data['pagination']);
      final skills = <MarketplaceSkill>[];
      if (items is List) {
        for (final item in items) {
          final map = _map(item);
          final parsed = parseGithubUrl(map['githubUrl']?.toString() ?? '');
          if (parsed == null) continue;
          skills.add(MarketplaceSkill(
            source: parsed.source,
            directory: parsed.directory,
            branch: parsed.branch,
            name: map['name']?.toString() ?? parsed.directory.split('/').last,
            description: map['description']?.toString() ?? '',
            author: map['author']?.toString() ?? '',
            stars: (map['stars'] as num?)?.toInt() ?? 0,
            detailUrl: map['skillUrl']?.toString() ?? '',
            githubUrl: map['githubUrl']?.toString() ?? '',
          ));
        }
      }
      return SkillsMpPage(
        skills: skills,
        page: (pagination['page'] as num?)?.toInt() ?? page,
        total: (pagination['total'] as num?)?.toInt() ?? skills.length,
        hasNext: pagination['hasNext'] == true,
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 429) {
        throw const SkillsMpException(
          'SkillsMP search quota reached (anonymous limit). Try again later.',
        );
      }
      if (status != null) {
        throw SkillsMpException('SkillsMP request failed (HTTP $status).');
      }
      throw const SkillsMpException(
        'Could not reach SkillsMP. Check your internet connection.',
      );
    }
  }

  /// Parses a SkillsMP `githubUrl` into owner/repo, branch and skill folder.
  static ({MarketplaceSource source, String directory, String branch})?
      parseGithubUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host != 'github.com') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;

    final owner = segments[0];
    final repo = segments[1];
    var branch = 'main';
    var directory = '';

    if (segments.length >= 4 &&
        (segments[2] == 'tree' || segments[2] == 'blob')) {
      branch = segments[3];
      directory = segments.skip(4).join('/');
      if (segments[2] == 'blob') {
        if (directory.endsWith('SKILL.md')) {
          directory = directory.substring(0, directory.length - 8);
        }
        directory = directory.replaceFirst(RegExp(r'/$'), '');
      }
    }

    return (
      source: MarketplaceSource(
        owner: owner,
        repo: repo,
        title: repo,
        description: 'SkillsMP · $owner',
      ),
      directory: directory,
      branch: branch,
    );
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }
}
