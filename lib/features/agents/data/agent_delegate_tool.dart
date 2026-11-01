import 'package:uuid/uuid.dart';

import '../../../core/models/chat_models.dart';
import '../../../shared/widgets/confirm_action_sheet.dart';
import '../../agent/data/agent_engine.dart';
import '../../agent/domain/agent_event.dart';
import '../../agent/domain/agent_tool.dart';
import '../../providers/domain/ai_provider.dart';
import '../domain/agent_profile.dart';

/// A resolved provider/model pair for a delegated sub-agent.
typedef DelegateTarget = ({
  AIProvider provider,
  String configId,
  String model,
});

/// Builds the `delegate_task` tool from user-configured agent profiles.
class AgentDelegation {
  const AgentDelegation._();

  static const _uuid = Uuid();

  static AgentTool build({
    required List<AgentProfile> profiles,
    required Future<DelegateTarget?> Function(AgentProfile profile) resolveTarget,
    required Future<GenerationParams> Function(String configId) paramsFor,
    required Future<List<AgentTool>> Function() loadTools,
  }) {
    final enabled = profiles.where((profile) => profile.enabled).toList();
    final catalog = enabled.isEmpty
        ? 'No agents are configured.'
        : enabled
            .map((profile) =>
                '- ${profile.name} ${profile.emoji}: ${profile.purpose}')
            .join('\n');

    return AgentTool(
      name: 'delegate_task',
      description:
          'Delegates a self-contained task to a specialized sub-agent and '
          'returns its result. Use when a task benefits from a focused '
          'researcher, coder or reviewer. The sub-agent cannot delegate '
          'further. Available agents:\n$catalog',
      inputSchema: {
        'type': 'object',
        'properties': {
          'agent': {
            'type': 'string',
            'description':
                'Agent name or id. One of: ${enabled.map((p) => p.name).join(', ')}.',
          },
          'task': {
            'type': 'string',
            'description':
                'Clear, self-contained task with the expected output.',
          },
          'context': {
            'type': 'string',
            'description':
                'Optional context, file paths or findings the sub-agent needs.',
          },
        },
        'required': ['agent', 'task'],
      },
      risk: ToolRisk.external,
      run: (args) async {
        final requested = (args['agent'] as String? ?? '').trim().toLowerCase();
        final task = (args['task'] as String? ?? '').trim();
        final context = (args['context'] as String? ?? '').trim();
        if (requested.isEmpty || task.isEmpty) {
          return 'Error: "agent" and "task" are required.';
        }

        final profile = enabled.where((profile) {
          return profile.id.toLowerCase() == requested ||
              profile.name.toLowerCase() == requested;
        }).firstOrNull;
        if (profile == null) {
          return 'Error: no enabled agent named "$requested". '
              'Available: ${enabled.map((p) => p.name).join(', ')}.';
        }

        final target = await resolveTarget(profile);
        if (target == null) {
          return 'Error: no AI provider is configured for ${profile.name}.';
        }

        var tools = await loadTools();
        tools = tools.where((tool) => tool.name != 'delegate_task').toList();
        if (profile.tools.isNotEmpty) {
          final allow = profile.tools.toSet();
          tools = tools
              .where((tool) =>
                  allow.contains(tool.name) ||
                  allow.any((name) => tool.name.endsWith('__$name')))
              .toList();
        }
        if (tools.isEmpty) {
          return 'Error: ${profile.name} has no allowed tools available.';
        }

        final history = [
          ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.system,
            content: profile.systemPrompt,
            createdAt: DateTime.now(),
          ),
          ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.user,
            content: context.isEmpty
                ? 'Delegated task:\n$task'
                : 'Delegated task:\n$task\n\nContext:\n$context',
            createdAt: DateTime.now(),
          ),
        ];

        final buffer = StringBuffer();
        String? finalAnswer;
        String? error;
        var toolCalls = 0;

        final engine = AgentEngine(maxSteps: profile.maxSteps.clamp(1, 20));
        await for (final event in engine.run(
          provider: target.provider,
          history: history,
          model: target.model,
          params: await paramsFor(target.configId),
          tools: tools,
          policy: ConfirmationPolicy.autonomous,
          requestConfirmation: (_, __) async => ConfirmResult.allow,
        )) {
          if (event is AgentTextDeltaEvent) {
            buffer.write(event.text);
          } else if (event is AgentToolCallCompletedEvent) {
            toolCalls += 1;
          } else if (event is AgentAssistantMessageEvent) {
            finalAnswer = event.message.content;
          } else if (event is AgentRunErrorEvent) {
            error = event.message;
          }
        }

        final answer = (finalAnswer ?? buffer.toString()).trim();
        final header = '${profile.emoji} ${profile.name} finished after '
            '$toolCalls tool call${toolCalls == 1 ? '' : 's'}.';
        if (error != null) {
          return '$header\n\nSub-agent error: $error\n\n'
              '${answer.length > 6000 ? answer.substring(0, 6000) : answer}';
        }
        if (answer.isEmpty) {
          return '$header\n\nThe sub-agent returned no text.';
        }
        return '$header\n\n'
            '${answer.length > 7000 ? '${answer.substring(0, 7000)}…' : answer}';
      },
    );
  }
}
