import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/secure_keys.dart';

/// Supported web search backends.
enum WebSearchProvider {
  tavily,
  brave,
  serper,
  exa,
  duckduckgo;

  String get id => name;

  String get label => switch (this) {
        WebSearchProvider.tavily => 'Tavily',
        WebSearchProvider.brave => 'Brave Search',
        WebSearchProvider.serper => 'Serper (Google)',
        WebSearchProvider.exa => 'Exa',
        WebSearchProvider.duckduckgo => 'DuckDuckGo (no key)',
      };

  bool get requiresKey => this != WebSearchProvider.duckduckgo;

  String get hint => switch (this) {
        WebSearchProvider.tavily => 'tvly-…',
        WebSearchProvider.brave => 'Brave Search API key',
        WebSearchProvider.serper => 'Serper API key',
        WebSearchProvider.exa => 'Exa API key',
        WebSearchProvider.duckduckgo => 'No API key required',
      };

  static WebSearchProvider fromId(String? id) =>
      WebSearchProvider.values.where((p) => p.id == id).firstOrNull ??
      WebSearchProvider.duckduckgo;
}

class WebSearchConfig {
  const WebSearchConfig({
    this.provider = WebSearchProvider.duckduckgo,
    this.maxResults = 5,
  });

  final WebSearchProvider provider;
  final int maxResults;

  WebSearchConfig copyWith({WebSearchProvider? provider, int? maxResults}) =>
      WebSearchConfig(
        provider: provider ?? this.provider,
        maxResults: maxResults ?? this.maxResults,
      );
}

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;
}

class WebSearchResponse {
  const WebSearchResponse({
    required this.provider,
    required this.query,
    required this.results,
    this.answer,
  });

  final WebSearchProvider provider;
  final String query;
  final List<WebSearchResult> results;
  final String? answer;

  String toPrompt() {
    final buffer = StringBuffer()
      ..writeln('Web search (${provider.label}) for "$query":');
    if (answer != null && answer!.trim().isNotEmpty) {
      buffer.writeln('Answer: ${answer!.trim()}');
    }
    if (results.isEmpty) {
      buffer.writeln('No results returned.');
      return buffer.toString().trim();
    }
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. ${r.title}');
      if (r.url.isNotEmpty) buffer.writeln('   ${r.url}');
      if (r.snippet.isNotEmpty) buffer.writeln('   ${r.snippet}');
    }
    return buffer.toString().trim();
  }
}

class WebSearchException implements Exception {
  const WebSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Configurable web search used by the `web_search` agent tool.
class WebSearchService {
  WebSearchService({
    required SharedPreferences prefs,
    required SecureKeyStore keys,
    Dio? dio,
  })  : _prefs = prefs,
        _keys = keys,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'User-Agent': 'VinaAgent/2.0 (Android; web_search)',
              },
            ));

  final SharedPreferences _prefs;
  final SecureKeyStore _keys;
  final Dio _dio;

  static const _providerKey = 'websearch_provider';
  static const _maxResultsKey = 'websearch_max_results';

  WebSearchConfig get config => WebSearchConfig(
        provider:
            WebSearchProvider.fromId(_prefs.getString(_providerKey)),
        maxResults: _prefs.getInt(_maxResultsKey) ?? 5,
      );

  Future<void> saveConfig(WebSearchConfig config) async {
    await _prefs.setString(_providerKey, config.provider.id);
    await _prefs.setInt(_maxResultsKey, config.maxResults);
  }

  Future<String?> readKey(WebSearchProvider provider) =>
      _keys.readWebSearchKey(provider.id);

  Future<void> saveKey(WebSearchProvider provider, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _keys.deleteWebSearchKey(provider.id);
    } else {
      await _keys.writeWebSearchKey(provider.id, trimmed);
    }
  }

  Future<WebSearchResponse> search(
    String query, {
    WebSearchProvider? provider,
    int? maxResults,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      throw const WebSearchException('Search query cannot be empty.');
    }
    final cfg = config;
    final selected = provider ?? cfg.provider;
    final limit = (maxResults ?? cfg.maxResults).clamp(1, 10);

    try {
      final future = switch (selected) {
        WebSearchProvider.tavily => _tavily(clean, limit),
        WebSearchProvider.brave => _brave(clean, limit),
        WebSearchProvider.serper => _serper(clean, limit),
        WebSearchProvider.exa => _exa(clean, limit),
        WebSearchProvider.duckduckgo => _duckDuckGo(clean, limit),
      };
      return await future;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final detail = _errorDetail(e.response?.data);
      if (status == 401 || status == 403) {
        throw WebSearchException(
          '${selected.label} rejected the API key. Check it in Settings → Web Search.',
        );
      }
      if (status == 429) {
        throw WebSearchException(
          '${selected.label} rate limit reached. Try again later or switch provider.',
        );
      }
      throw WebSearchException(
        '${selected.label} request failed'
        '${status == null ? '' : ' (HTTP $status)'}'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  }

  Future<String?> _keyFor(WebSearchProvider provider) async {
    final key = await readKey(provider);
    if (key == null || key.trim().isEmpty) {
      throw WebSearchException(
        '${provider.label} needs an API key. Add it in Settings → Web Search.',
      );
    }
    return key.trim();
  }

  Future<WebSearchResponse> _tavily(String query, int limit) async {
    final key = await _keyFor(WebSearchProvider.tavily);
    final response = await _dio.post<dynamic>(
      'https://api.tavily.com/search',
      data: {
        'api_key': key,
        'query': query,
        'max_results': limit,
        'search_depth': 'basic',
        'include_answer': true,
      },
    );
    final data = _asMap(response.data);
    final items = (data['results'] as List<dynamic>? ?? const []);
    return WebSearchResponse(
      provider: WebSearchProvider.tavily,
      query: query,
      answer: data['answer']?.toString(),
      results: items
          .map((e) => _asMap(e))
          .map((m) => WebSearchResult(
                title: m['title']?.toString() ?? 'Result',
                url: m['url']?.toString() ?? '',
                snippet: m['content']?.toString() ?? '',
              ))
          .toList(),
    );
  }

  Future<WebSearchResponse> _brave(String query, int limit) async {
    final key = await _keyFor(WebSearchProvider.brave);
    final response = await _dio.get<dynamic>(
      'https://api.search.brave.com/res/v1/web/search',
      queryParameters: {'q': query, 'count': limit},
      options: Options(headers: {
        'X-Subscription-Token': key,
        'Accept': 'application/json',
      }),
    );
    final data = _asMap(response.data);
    final web = _asMap(data['web']);
    final items = (web['results'] as List<dynamic>? ?? const []);
    return WebSearchResponse(
      provider: WebSearchProvider.brave,
      query: query,
      results: items
          .map((e) => _asMap(e))
          .map((m) => WebSearchResult(
                title: m['title']?.toString() ?? 'Result',
                url: m['url']?.toString() ?? '',
                snippet: m['description']?.toString() ?? '',
              ))
          .toList(),
    );
  }

  Future<WebSearchResponse> _serper(String query, int limit) async {
    final key = await _keyFor(WebSearchProvider.serper);
    final response = await _dio.post<dynamic>(
      'https://google.serper.dev/search',
      data: {'q': query, 'num': limit},
      options: Options(headers: {
        'X-API-KEY': key,
        'Content-Type': 'application/json',
      }),
    );
    final data = _asMap(response.data);
    final items = (data['organic'] as List<dynamic>? ?? const []);
    return WebSearchResponse(
      provider: WebSearchProvider.serper,
      query: query,
      answer: _asMap(data['answerBox'])['answer']?.toString(),
      results: items
          .map((e) => _asMap(e))
          .map((m) => WebSearchResult(
                title: m['title']?.toString() ?? 'Result',
                url: m['link']?.toString() ?? '',
                snippet: m['snippet']?.toString() ?? '',
              ))
          .toList(),
    );
  }

  Future<WebSearchResponse> _exa(String query, int limit) async {
    final key = await _keyFor(WebSearchProvider.exa);
    final response = await _dio.post<dynamic>(
      'https://api.exa.ai/search',
      data: {
        'query': query,
        'numResults': limit,
        'contents': {
          'text': {'maxCharacters': 600},
        },
      },
      options: Options(headers: {
        'x-api-key': key,
        'Content-Type': 'application/json',
      }),
    );
    final data = _asMap(response.data);
    final items = (data['results'] as List<dynamic>? ?? const []);
    return WebSearchResponse(
      provider: WebSearchProvider.exa,
      query: query,
      results: items
          .map((e) => _asMap(e))
          .map((m) => WebSearchResult(
                title: m['title']?.toString() ?? 'Result',
                url: m['url']?.toString() ?? '',
                snippet: (m['text'] ?? m['summary'] ?? '').toString(),
              ))
          .toList(),
    );
  }

  Future<WebSearchResponse> _duckDuckGo(String query, int limit) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
      );
      final html = response.data.toString();
      final links = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
        dotAll: true,
      ).allMatches(html).toList();
      final snippets = RegExp(
        r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
        dotAll: true,
      ).allMatches(html).toList();

      final results = <WebSearchResult>[];
      for (var i = 0; i < links.length && results.length < limit; i++) {
        final title = _cleanHtml(links[i].group(2) ?? '');
        final url = _cleanDuckUrl(links[i].group(1) ?? '');
        final snippet =
            i < snippets.length ? _cleanHtml(snippets[i].group(1) ?? '') : '';
        if (title.isEmpty && snippet.isEmpty) continue;
        results.add(WebSearchResult(
          title: title.isEmpty ? 'Result ${results.length + 1}' : title,
          url: url,
          snippet: snippet,
        ));
      }
      if (results.isNotEmpty) {
        return WebSearchResponse(
          provider: WebSearchProvider.duckduckgo,
          query: query,
          results: results,
        );
      }
    } on DioException {
      // Fall through to the instant-answer endpoint.
    }

    final api = await _dio.get<dynamic>(
      'https://api.duckduckgo.com/',
      queryParameters: {'q': query, 'format': 'json', 'no_html': '1'},
    );
    final data = _asMap(api.data);
    final abstractText = data['AbstractText']?.toString() ?? '';
    final related = (data['RelatedTopics'] as List<dynamic>? ?? const []);
    final results = <WebSearchResult>[];
    if (abstractText.isNotEmpty) {
      results.add(WebSearchResult(
        title: data['Heading']?.toString() ?? query,
        url: data['AbstractURL']?.toString() ?? '',
        snippet: abstractText,
      ));
    }
    for (final item in related) {
      final map = _asMap(item);
      final text = map['Text']?.toString() ?? '';
      if (text.isEmpty) continue;
      results.add(WebSearchResult(
        title: text,
        url: map['FirstURL']?.toString() ?? '',
        snippet: text,
      ));
      if (results.length >= limit) break;
    }
    return WebSearchResponse(
      provider: WebSearchProvider.duckduckgo,
      query: query,
      results: results,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  static String _errorDetail(dynamic data) {
    if (data is Map) {
      final map = data.cast<String, dynamic>();
      return (map['detail'] ?? map['error'] ?? map['message'] ?? '').toString();
    }
    if (data is String) return data.length > 200 ? data.substring(0, 200) : data;
    return '';
  }

  static String _cleanHtml(String value) => value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _cleanDuckUrl(String value) {
    if (value.startsWith('//')) return 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.queryParameters.containsKey('uddg')) {
      return Uri.decodeComponent(uri.queryParameters['uddg']!);
    }
    return value;
  }
}
