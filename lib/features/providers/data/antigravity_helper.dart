import 'dart:convert';

import '../../../core/models/chat_models.dart';
import '../domain/provider_types.dart';
import 'multimodal_helper.dart';

/// Credentials container for Google Antigravity.
class AntigravityCredentials {
  const AntigravityCredentials({
    required this.accessToken,
    this.refreshToken,
    this.clientId,
    this.clientSecret,
    this.expiresAt,
    this.projectId,
  });

  final String accessToken;
  final String? refreshToken;
  final String? clientId;
  final String? clientSecret;
  final DateTime? expiresAt;
  final String? projectId;

  bool get isExpired {
    if (expiresAt == null) return false;
    // Consider expired 60 seconds early to avoid mid-request expiration
    return DateTime.now().isAfter(
      expiresAt!.subtract(const Duration(seconds: 60)),
    );
  }

  AntigravityCredentials copyWith({
    String? accessToken,
    String? refreshToken,
    String? clientId,
    String? clientSecret,
    DateTime? expiresAt,
    String? projectId,
  }) {
    return AntigravityCredentials(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      expiresAt: expiresAt ?? this.expiresAt,
      projectId: projectId ?? this.projectId,
    );
  }

  /// Parses raw input which may be:
  /// - A plain access token string (`ya29...`)
  /// - A JSON string with credentials (from gcloud / CLIProxyAPI / Antigravity OAuth)
  static AntigravityCredentials parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed);
        if (map is Map<String, dynamic>) {
          final token = map['access_token']?.toString() ??
              map['token']?.toString() ??
              map['accessToken']?.toString() ??
              trimmed;
          final refresh = map['refresh_token']?.toString() ??
              map['refreshToken']?.toString();
          final client =
              map['client_id']?.toString() ?? map['clientId']?.toString();
          final secret = map['client_secret']?.toString() ??
              map['clientSecret']?.toString();
          final proj = map['project_id']?.toString() ??
              map['projectId']?.toString() ??
              map['project']?.toString();

          DateTime? expiry;
          final expRaw = map['expiry'] ??
              map['expires_at'] ??
              map['token_expiry'] ??
              map['expiresIn'];
          if (expRaw is num) {
            expiry = DateTime.fromMillisecondsSinceEpoch(
              expRaw > 10000000000 ? expRaw.toInt() : (expRaw * 1000).toInt(),
            );
          } else if (expRaw is String) {
            expiry = DateTime.tryParse(expRaw);
          }

          return AntigravityCredentials(
            accessToken: token,
            refreshToken: refresh,
            clientId: client,
            clientSecret: secret,
            expiresAt: expiry,
            projectId: proj,
          );
        }
      } catch (_) {}
    }

    return AntigravityCredentials(accessToken: trimmed);
  }
}

/// Helpers for formatting messages, tools, and schemas for Google Antigravity.
class AntigravityHelper {
  const AntigravityHelper._();

  /// Sentinel bypass value used by VansRouter / CLIProxyAPI to prevent
  /// Google Antigravity from failing on synthetic multi-turn tool history.
  static const String thoughtSignatureSentinel =
      'skip_thought_signature_validator';

  /// Sanitizes tool JSON Schema by recursively stripping keywords rejected
  /// by Gemini / Antigravity backend (such as `optional`, `$schema`).
  static Map<String, dynamic> sanitizeSchema(Map<String, dynamic> raw) {
    final sanitized = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      // Google Gemini rejects 'optional' keyword under parameters/properties
      if (key == 'optional' || key == r'$schema') {
        continue;
      }

      final value = entry.value;
      if (value is Map<String, dynamic>) {
        sanitized[key] = sanitizeSchema(value);
      } else if (value is Map) {
        sanitized[key] = sanitizeSchema(Map<String, dynamic>.from(value));
      } else if (value is List) {
        sanitized[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return sanitizeSchema(item);
          } else if (item is Map) {
            return sanitizeSchema(Map<String, dynamic>.from(item));
          }
          return item;
        }).toList();
      } else {
        sanitized[key] = value;
      }
    }
    return sanitized;
  }

  /// Converts normalized tool specs into Google Antigravity `function_declarations`.
  static List<Map<String, dynamic>> convertTools(List<ProviderToolSpec> tools) {
    return [
      for (final tool in tools)
        {
          'name': tool.name,
          'description': tool.description,
          'parameters': sanitizeSchema(tool.parameters),
        },
    ];
  }

  /// Converts chat messages to Google Antigravity Gemini-envelope format.
  ///
  /// Assistant functionCalls include [thoughtSignatureSentinel] to bypass
  /// the upstream thought signature validator on synthetic history.
  static (String?, List<Map<String, dynamic>>) convertMessages(
    List<ChatMessage> messages,
    String? extraSystemPrompt,
  ) {
    final systemParts = <String>[
      if (extraSystemPrompt != null && extraSystemPrompt.trim().isNotEmpty)
        extraSystemPrompt.trim(),
      for (final m in messages)
        if (m.role == MessageRole.system && m.content.trim().isNotEmpty)
          m.content.trim(),
    ];

    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case MessageRole.system:
          break;

        case MessageRole.user:
          final imageAttachments =
              MultimodalHelper.extractImageAttachments(m.attachments);
          final parts = <Map<String, dynamic>>[];
          if (m.content.isNotEmpty) {
            parts.add({'text': m.content});
          }
          for (final img in imageAttachments) {
            parts.add({
              'inlineData': {
                'mimeType': img.mimeType,
                'data': img.base64Data,
              },
            });
          }
          if (parts.isEmpty) {
            parts.add({'text': 'Describe this image.'});
          }
          out.add({
            'role': 'user',
            'parts': parts,
          });

        case MessageRole.assistant:
          final parts = <Map<String, dynamic>>[];
          if (m.content.isNotEmpty) {
            parts.add({'text': m.content});
          }
          for (final call in m.toolCalls) {
            parts.add({
              'functionCall': {
                'name': call.name,
                'args': _tryDecodeJson(call.argumentsJson),
              },
              'thoughtSignature': thoughtSignatureSentinel,
            });
          }
          if (parts.isNotEmpty) {
            out.add({
              'role': 'model',
              'parts': parts,
            });
          }

        case MessageRole.tool:
          out.add({
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'name': m.toolName ?? 'tool',
                  'response': {'result': m.content},
                },
              },
            ],
          });
      }
    }

    return (systemParts.isEmpty ? null : systemParts.join('\n\n'), out);
  }

  static Object _tryDecodeJson(String json) {
    try {
      return jsonDecode(json);
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
