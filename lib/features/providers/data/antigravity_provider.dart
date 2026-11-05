import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/models/chat_models.dart';
import '../domain/ai_provider.dart';
import '../domain/provider_types.dart';
import 'antigravity_helper.dart';
import 'sse_parser.dart';

/// Native Google Antigravity (Google Cloud Code Assist) provider.
///
/// Implements the exact request envelope, header fingerprints, schema sanitization,
/// and thought-signature bypass sentinel used by VansRouter / CLIProxyAPI to speak
/// directly with Google's backend without requiring an external proxy or router.
class AntigravityProvider implements AIProvider {
  AntigravityProvider({
    required this.configId,
    required this.baseUrl,
    this.apiKey,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 25),
              receiveTimeout: const Duration(minutes: 5),
            )) {
    if (apiKey != null && apiKey!.trim().isNotEmpty) {
      _credentials = AntigravityCredentials.parse(apiKey!);
    }
  }

  @override
  final String configId;
  final String baseUrl;
  final String? apiKey;
  final Dio _dio;

  AntigravityCredentials? _credentials;
  String? _resolvedProjectId;

  static const String _defaultUserAgent = AntigravityHelper.userAgent;
  static const String _defaultGoogApiClient = AntigravityHelper.googApiClient;

  @override
  String get displayName => ProviderType.antigravity.displayName;

  @override
  bool get supportsTools => true;

  @override
  bool get supportsVision => true;

  /// Resolves the effective base URL, defaulting to Google production if empty.
  String get _effectiveBaseUrl {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return ProviderType.antigravity.defaultBaseUrl;
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// Ensures a valid access token is ready, attempting refresh if expired.
  Future<String> _ensureAccessToken() async {
    final creds = _credentials;
    if (creds == null) {
      throw Exception('Missing Antigravity access token or credentials.');
    }

    final needsRefresh =
        creds.accessToken.isEmpty || creds.isExpired || creds.expiresAt == null;
    if (needsRefresh && creds.canRefresh) {
      try {
        final resp = await _dio.post<Map<String, dynamic>>(
          AntigravityOAuthConfig.tokenEndpoint,
          data: {
            'client_id': creds.effectiveClientId,
            'client_secret': creds.effectiveClientSecret,
            'refresh_token': creds.refreshToken,
            'grant_type': 'refresh_token',
          },
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
          ),
        );
        final newTok = resp.data?['access_token']?.toString();
        if (newTok != null && newTok.isNotEmpty) {
          final expiresIn = (resp.data?['expires_in'] as num?)?.toInt() ?? 3600;
          _credentials = creds.copyWith(
            accessToken: newTok,
            expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
          );
          return newTok;
        }
      } catch (_) {
        // Fall back to current access token if refresh fails
      }
    }

    if (creds.accessToken.isEmpty) {
      throw Exception(
        'Antigravity credentials have no access token and could not be '
        'refreshed. Sign in again from the provider settings.',
      );
    }
    return creds.accessToken;
  }

  Future<Map<String, String>> _buildHeaders() async {
    final token = await _ensureAccessToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'User-Agent': _defaultUserAgent,
      'X-Goog-Api-Client': _defaultGoogApiClient,
    };
  }

  /// Discovers and caches the internal Google project ID associated with this account.
  Future<String> _ensureProjectId() async {
    if (_resolvedProjectId != null && _resolvedProjectId!.isNotEmpty) {
      return _resolvedProjectId!;
    }
    if (_credentials?.projectId != null &&
        _credentials!.projectId!.isNotEmpty) {
      _resolvedProjectId = _credentials!.projectId;
      return _resolvedProjectId!;
    }

    try {
      final headers = await _buildHeaders();
      final resp = await _dio.post<Map<String, dynamic>>(
        '$_effectiveBaseUrl/v1internal:loadCodeAssist',
        data: jsonEncode({
          'metadata': {
            'ideType': 'ANTIGRAVITY',
            'platform': 'PLATFORM_UNSPECIFIED',
            'pluginType': 'GEMINI',
          },
        }),
        options: Options(headers: headers),
      );

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        final proj = AntigravityHelper.extractProjectId(data);
        if (proj != null && proj.isNotEmpty) {
          _resolvedProjectId = proj;
          return proj;
        }
      }
    } catch (_) {
      // If loadCodeAssist is unreachable or fails, return empty to let backend default
    }

    return _resolvedProjectId ?? '';
  }

  @override
  Stream<ChatStreamEvent> streamMessage(ChatRequest request) async* {
    final String projectId;
    final Map<String, String> headers;
    try {
      projectId = await _ensureProjectId();
      headers = await _buildHeaders();
    } catch (e) {
      yield StreamErrorEvent('Antigravity Auth Error: $e');
      return;
    }

    final (system, contents) = AntigravityHelper.convertMessages(
      request.messages,
      request.params.systemPrompt,
    );
    final convertedTools = AntigravityHelper.convertTools(request.tools);

    final innerRequest = <String, dynamic>{
      'contents': contents,
      if (system != null && system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'generationConfig': {
        'temperature': request.params.temperature,
        'topP': request.params.topP,
        'maxOutputTokens': request.params.maxTokens,
      },
      if (convertedTools.isNotEmpty)
        'tools': [
          {
            'function_declarations': convertedTools,
          },
        ],
    };

    final envelope = <String, dynamic>{
      if (projectId.isNotEmpty) 'project': projectId,
      'model': request.model,
      'request': innerRequest,
    };

    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '$_effectiveBaseUrl/v1internal:streamGenerateContent?alt=sse',
        data: jsonEncode(envelope),
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
        cancelToken: request.cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        yield const StreamDoneEvent();
        return;
      }
      yield StreamErrorEvent(dioErrorMessage(e));
      return;
    }

    final responseBody = response.data;
    if (responseBody == null) {
      yield const StreamErrorEvent('Empty response body from Antigravity');
      return;
    }

    final toolCalls = <ToolCallInfo>[];

    await for (final json in parseSseJsonStream(responseBody.stream)) {
      // Unpack potential outer 'response' envelope
      final root = json['response'] is Map<String, dynamic>
          ? json['response'] as Map<String, dynamic>
          : json;

      final usage = root['usageMetadata'] as Map<String, dynamic>?;
      if (usage != null) {
        yield UsageEvent(UsageInfo(
          promptTokens: (usage['promptTokenCount'] as num?)?.toInt(),
          completionTokens: (usage['candidatesTokenCount'] as num?)?.toInt(),
        ));
      }

      final candidates = root['candidates'];
      if (candidates is! List || candidates.isEmpty) continue;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) continue;
      final content = first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'];
      if (parts is! List) continue;

      for (final raw in parts) {
        if (raw is! Map<String, dynamic>) continue;
        final text = raw['text'];
        if (text is String && text.isNotEmpty) {
          yield TextDeltaEvent(text);
        }
        final fnCall = raw['functionCall'] as Map<String, dynamic>?;
        if (fnCall != null) {
          final fnName = fnCall['name']?.toString() ?? '';
          final fnArgs = fnCall['args'] ?? const {};
          toolCalls.add(ToolCallInfo(
            id: 'antigravity_${toolCalls.length}_$fnName',
            name: fnName,
            argumentsJson: jsonEncode(fnArgs),
          ));
        }
      }
    }

    if (toolCalls.isNotEmpty) {
      yield ToolCallsEvent(toolCalls);
    }
    yield const StreamDoneEvent();
  }

  @override
  Future<List<String>> listModels() async {
    try {
      final projectId = await _ensureProjectId();
      final headers = await _buildHeaders();

      final resp = await _dio.post<Map<String, dynamic>>(
        '$_effectiveBaseUrl/v1internal:fetchAvailableModels',
        data: jsonEncode({
          if (projectId.isNotEmpty) 'project': projectId,
        }),
        options: Options(headers: headers),
      );

      final data = resp.data;
      if (data is Map<String, dynamic>) {
        final modelsMap = data['models'];
        if (modelsMap is Map) {
          final list = modelsMap.keys
              .map((k) => k.toString())
              .where((k) => k.isNotEmpty)
              .toList();
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {
      // Fall back to suggested models on failure
    }

    return ProviderType.antigravity.suggestedModels;
  }
}
