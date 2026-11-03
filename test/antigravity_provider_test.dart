import 'package:flutter_test/flutter_test.dart';
import 'package:pocketstrike/core/models/chat_models.dart';
import 'package:pocketstrike/features/providers/data/antigravity_helper.dart';
import 'package:pocketstrike/features/providers/data/antigravity_provider.dart';
import 'package:pocketstrike/features/providers/domain/provider_types.dart';

void main() {
  group('AntigravityCredentials Tests', () {
    test('parses plain Bearer access token string', () {
      const raw = 'ya29.a0AfH6SM...';
      final creds = AntigravityCredentials.parse(raw);
      expect(creds.accessToken, raw);
      expect(creds.refreshToken, isNull);
      expect(creds.projectId, isNull);
      expect(creds.isExpired, isFalse);
    });

    test('parses JSON format credentials from gcloud / OAuth output', () {
      const jsonStr = '''
{
  "access_token": "ya29.json_token",
  "refresh_token": "1//refresh_token_example",
  "client_id": "test-client-id.apps.googleusercontent.com",
  "client_secret": "test-client-secret",
  "project_id": "cloudaicompanion-12345",
  "expires_at": 1800000000
}
''';
      final creds = AntigravityCredentials.parse(jsonStr);
      expect(creds.accessToken, 'ya29.json_token');
      expect(creds.refreshToken, '1//refresh_token_example');
      expect(creds.clientId, 'test-client-id.apps.googleusercontent.com');
      expect(creds.clientSecret, 'test-client-secret');
      expect(creds.projectId, 'cloudaicompanion-12345');
      expect(creds.isExpired, isFalse);
    });
  });

  group('AntigravityHelper Schema Sanitization Tests', () {
    test('recursively removes "optional" and "\$schema" keywords', () {
      final rawSchema = {
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'shell command',
            'optional': false,
          },
          'nested': {
            'type': 'object',
            'optional': true,
            'properties': {
              'flag': {
                'type': 'boolean',
                'optional': true,
              },
            },
          },
        },
        'required': ['command'],
      };

      final sanitized = AntigravityHelper.sanitizeSchema(rawSchema);

      expect(sanitized.containsKey(r'$schema'), isFalse);
      expect(sanitized['type'], 'object');
      expect(sanitized['required'], ['command']);

      final properties = sanitized['properties'] as Map<String, dynamic>;
      final commandProp = properties['command'] as Map<String, dynamic>;
      expect(commandProp.containsKey('optional'), isFalse);
      expect(commandProp['type'], 'string');

      final nestedProp = properties['nested'] as Map<String, dynamic>;
      expect(nestedProp.containsKey('optional'), isFalse);
      final nestedProps = nestedProp['properties'] as Map<String, dynamic>;
      final flagProp = nestedProps['flag'] as Map<String, dynamic>;
      expect(flagProp.containsKey('optional'), isFalse);
    });

    test('convertTools returns function_declarations with sanitized parameters', () {
      final tools = [
        const ProviderToolSpec(
          name: 'shell',
          description: 'Execute command',
          parameters: {
            'type': 'object',
            'optional': false,
            'properties': {
              'cmd': {
                'type': 'string',
                'optional': false,
              },
            },
          },
        ),
      ];

      final converted = AntigravityHelper.convertTools(tools);
      expect(converted.length, 1);
      expect(converted.first['name'], 'shell');
      expect(converted.first['description'], 'Execute command');
      final params = converted.first['parameters'] as Map<String, dynamic>;
      expect(params.containsKey('optional'), isFalse);
      final props = params['properties'] as Map<String, dynamic>;
      expect(props['cmd'].containsKey('optional'), isFalse);
    });
  });

  group('AntigravityHelper Message Conversion Tests', () {
    test('injects skip_thought_signature_validator into assistant functionCall parts', () {
      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: MessageRole.user,
          content: 'Run ls',
          createdAt: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          content: 'Running command...',
          toolCalls: const [
            ToolCallInfo(
              id: 'call_1',
              name: 'shell',
              argumentsJson: '{"cmd":"ls -la"}',
            ),
          ],
          createdAt: DateTime.now(),
        ),
        ChatMessage(
          id: '3',
          conversationId: 'c1',
          role: MessageRole.tool,
          content: 'total 0',
          toolName: 'shell',
          createdAt: DateTime.now(),
        ),
      ];

      final (system, contents) = AntigravityHelper.convertMessages(
        messages,
        'System prompt here',
      );

      expect(system, 'System prompt here');
      expect(contents.length, 3);

      // Turn 1: user
      expect(contents[0]['role'], 'user');
      expect(contents[0]['parts'][0]['text'], 'Run ls');

      // Turn 2: assistant / model with thought signature sentinel
      expect(contents[1]['role'], 'model');
      final modelParts = contents[1]['parts'] as List;
      expect(modelParts[0]['text'], 'Running command...');
      final fnPart = modelParts[1] as Map<String, dynamic>;
      expect(fnPart['functionCall']['name'], 'shell');
      expect(fnPart['functionCall']['args'], {'cmd': 'ls -la'});
      expect(
        fnPart['thoughtSignature'],
        AntigravityHelper.thoughtSignatureSentinel,
      );

      // Turn 3: tool result
      expect(contents[2]['role'], 'user');
      final toolPart = contents[2]['parts'][0] as Map<String, dynamic>;
      expect(toolPart['functionResponse']['name'], 'shell');
      expect(toolPart['functionResponse']['response'], {'result': 'total 0'});
    });
  });

  group('AntigravityProvider Basic Tests', () {
    test('properties reflect Google Antigravity config', () {
      final provider = AntigravityProvider(
        configId: 'cfg-ag',
        baseUrl: ProviderType.antigravity.defaultBaseUrl,
        apiKey: 'ya29.dummy',
      );

      expect(provider.displayName, 'Google Antigravity');
      expect(provider.supportsTools, isTrue);
      expect(provider.supportsVision, isTrue);
      expect(provider.configId, 'cfg-ag');
    });

    test('listModels falls back to suggested models on network error or offline', () async {
      final provider = AntigravityProvider(
        configId: 'cfg-ag',
        baseUrl: 'http://127.0.0.1:1', // deliberately unreachable
        apiKey: 'ya29.dummy',
      );

      final models = await provider.listModels();
      expect(models, contains('gemini-3.8-flash-high'));
      expect(models, contains('claude-sonnet-4-6'));
    });
  });
}
