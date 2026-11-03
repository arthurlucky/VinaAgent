import 'package:pocketstrike/features/agent/domain/agent_tool.dart';

import '../data/plugin_store.dart';

/// Agent-facing tools for discovering and creating plugins.
class PluginTools {
  const PluginTools._();

  static List<AgentTool> all({
    required PluginStore store,
    Future<void> Function()? onChanged,
  }) =>
      [
        listPlugins(store),
        createPlugin(store, onChanged),
      ];

  static AgentTool listPlugins(PluginStore store) => AgentTool(
        name: 'list_plugins',
        description:
            'Lists installed Vina Agent plugins with their skills, sub-agents, '
            'slash commands, MCP servers and hooks.',
        inputSchema: const {
          'type': 'object',
          'properties': <String, dynamic>{},
        },
        risk: ToolRisk.safe,
        run: (_) async {
          final plugins = await store.list();
          if (plugins.isEmpty) {
            return 'No plugins installed. Create one with create_plugin.';
          }
          final buffer = StringBuffer('Installed plugins (${plugins.length}):\n');
          for (final plugin in plugins) {
            final manifest = plugin.manifest;
            buffer.writeln(
              '- ${manifest.name} v${manifest.version} '
              '(${plugin.enabled ? 'enabled' : 'disabled'}) — '
              '${manifest.description}',
            );
            if (manifest.commands.isNotEmpty) {
              buffer.writeln(
                '  commands: ${manifest.commands.map((c) => '/${c.name}').join(', ')}',
              );
            }
            if (manifest.mcpServers.isNotEmpty) {
              buffer.writeln(
                '  mcp: ${manifest.mcpServers.map((s) => s.name).join(', ')}',
              );
            }
            if (manifest.hooks.isNotEmpty) {
              buffer.writeln(
                '  hooks: ${manifest.hooks.keys.join(', ')}',
              );
            }
          }
          return buffer.toString().trim();
        },
      );

  static AgentTool createPlugin(
    PluginStore store,
    Future<void> Function()? onChanged,
  ) =>
      AgentTool(
        name: 'create_plugin',
        description:
            'Creates a new plugin folder that bundles a reusable skill and a '
            'slash command. Use this when the user asks to package a workflow '
            'as a plugin.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description': 'Plugin name (lowercase, hyphens allowed).',
            },
            'description': {
              'type': 'string',
              'description': 'One-line description of the plugin.',
            },
            'instructions': {
              'type': 'string',
              'description':
                  'SKILL.md instructions the agent should follow for this plugin.',
            },
          },
          'required': ['name', 'description', 'instructions'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          try {
            final plugin = await store.createPlugin(
              name: args['name'] as String? ?? '',
              description: args['description'] as String? ?? '',
              instructions: args['instructions'] as String? ?? '',
            );
            await onChanged?.call();
            return 'Created plugin "${plugin.name}" at ${plugin.directory}. '
                'It contributes /${plugin.name} and a skill.';
          } catch (error) {
            return 'Failed to create plugin: $error';
          }
        },
      );
}
