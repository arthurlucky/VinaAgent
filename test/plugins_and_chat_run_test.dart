import 'package:flutter_test/flutter_test.dart';
import 'package:pocketstrike/features/chat/domain/chat_run.dart';
import 'package:pocketstrike/features/chat/application/run_registry.dart';
import 'package:pocketstrike/features/chat/domain/slash_command.dart';
import 'package:pocketstrike/features/chat/application/btw_controller.dart';
import 'package:pocketstrike/features/plugins/domain/plugin_manifest.dart';

void main() {
  group('ChatRun & Queue Domain Tests', () {
    test('QueuedChatMessage serialization round-trip', () {
      final now = DateTime(2026, 11, 3, 14, 0);
      final msg = QueuedChatMessage(
        id: 'q-1',
        text: 'Hello from delayed task',
        activeSkillName: 'research',
        queuedAt: now,
      );

      final json = msg.toJson();
      expect(json['id'], 'q-1');
      expect(json['text'], 'Hello from delayed task');
      expect(json['activeSkillName'], 'research');

      final deserialized = QueuedChatMessage.fromJson(json);
      expect(deserialized.id, 'q-1');
      expect(deserialized.text, 'Hello from delayed task');
      expect(deserialized.activeSkillName, 'research');
    });

    test('ChatRunRegistry manages independent per-conversation state', () {
      final registry = ChatRunRegistry();

      expect(registry.isRunning('conv-A'), isFalse);
      expect(registry.isRunning('conv-B'), isFalse);

      registry.update(
        'conv-A',
        const ChatRunState(
          conversationId: 'conv-A',
          isGenerating: true,
          streamingText: 'streaming in A...',
        ),
      );

      expect(registry.isRunning('conv-A'), isTrue);
      expect(registry.isRunning('conv-B'), isFalse);
      expect(registry.stateFor('conv-A').streamingText, 'streaming in A...');
      expect(registry.stateFor('conv-B').isGenerating, isFalse);
    });

    test('ChatRunRegistry queues and dequeues delayed messages in FIFO order', () {
      final registry = ChatRunRegistry();
      const convId = 'conv-fifo';

      registry.enqueue(
        convId,
        QueuedChatMessage(
          id: '1',
          text: 'First queued',
          queuedAt: DateTime.now(),
        ),
      );
      registry.enqueue(
        convId,
        QueuedChatMessage(
          id: '2',
          text: 'Second queued',
          queuedAt: DateTime.now(),
        ),
      );

      expect(registry.stateFor(convId).queued.length, 2);

      final first = registry.dequeue(convId);
      expect(first?.text, 'First queued');
      expect(registry.stateFor(convId).queued.length, 1);

      final second = registry.dequeue(convId);
      expect(second?.text, 'Second queued');
      expect(registry.stateFor(convId).queued.isEmpty, isTrue);

      final empty = registry.dequeue(convId);
      expect(empty, isNull);
    });
  });

  group('BtwState Model Tests', () {
    test('default state has no content', () {
      const state = BtwState();
      expect(state.hasContent, isFalse);
      expect(state.loading, isFalse);
    });

    test('copyWith updates fields correctly', () {
      const initial = BtwState();
      final updated = initial.copyWith(
        question: 'What is this file?',
        answer: 'It is a manifest.',
        loading: false,
      );
      expect(updated.hasContent, isTrue);
      expect(updated.question, 'What is this file?');
      expect(updated.answer, 'It is a manifest.');
    });
  });

  group('Slash Command Tests', () {
    test('kSlashCommands contains btw command', () {
      final btw = kSlashCommands.where((c) => c.name == 'btw').firstOrNull;
      expect(btw, isNotNull);
      expect(btw!.usage, '/btw');
    });

    test('slashCommandSuggestions includes both built-ins and plugin commands', () {
      final extra = [
        const SlashCommand(name: 'my-plugin-cmd', description: 'Plugin cmd'),
      ];

      final suggestions = slashCommandSuggestions('/my', extra: extra);
      expect(suggestions.any((c) => c.name == 'my-plugin-cmd'), isTrue);

      final btwSuggestions = slashCommandSuggestions('/bt', extra: extra);
      expect(btwSuggestions.any((c) => c.name == 'btw'), isTrue);
    });
  });

  group('PluginManifest Domain Tests', () {
    test('parses complete plugin.json', () {
      const raw = '''
{
  "name": "data-analysis",
  "version": "1.2.0",
  "description": "Analyze spreadsheets and tabular data",
  "author": "tester",
  "skills": ["skills"],
  "agents": ["agents"],
  "commands": [
    { "name": "analyze", "description": "Run analysis", "prompt": "Analyze: \$ARGUMENTS" }
  ],
  "mcpServers": [
    { "name": "data-mcp", "url": "http://127.0.0.1:3847/sse", "transport": "sse" }
  ],
  "hooks": {
    "before_send": "echo checking data",
    "after_run": "echo done"
  },
  "permissions": ["skills", "mcp"]
}
''';

      final manifest = PluginManifest.tryParse(raw);
      expect(manifest, isNotNull);
      expect(manifest!.name, 'data-analysis');
      expect(manifest.version, '1.2.0');
      expect(manifest.commands.length, 1);
      expect(manifest.commands.first.name, 'analyze');
      expect(manifest.commands.first.prompt, 'Analyze: \$ARGUMENTS');
      expect(manifest.mcpServers.length, 1);
      expect(manifest.mcpServers.first.name, 'data-mcp');
      expect(manifest.hooks['before_send'], 'echo checking data');
      expect(manifest.hooks['after_run'], 'echo done');
    });

    test('fallback name applied when plugin.json has no name', () {
      const raw = '{"description": "No name given"}';
      final manifest = PluginManifest.tryParse(raw, fallbackName: 'fallback-dir');
      expect(manifest, isNotNull);
      expect(manifest!.name, 'fallback-dir');
    });

    test('returns null for invalid JSON', () {
      expect(PluginManifest.tryParse('{ invalid json }'), isNull);
    });
  });
}
