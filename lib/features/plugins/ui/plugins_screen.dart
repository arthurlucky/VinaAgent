import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/features/plugins/application/plugins_controller.dart';
import 'package:pocketstrike/features/plugins/domain/plugin_manifest.dart';

/// Settings screen for installing, creating and toggling plugins.
class PluginsScreen extends ConsumerWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.glass;
    final state = ref.watch(pluginControllerProvider);

    ref.listen(pluginControllerProvider, (previous, next) {
      if (next.message != null && next.message != previous?.message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message!)),
        );
        ref.read(pluginControllerProvider.notifier).clearMessage();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugins'),
        actions: [
          IconButton(
            tooltip: 'Reload plugins',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.read(pluginControllerProvider.notifier).refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Create plugin'),
      ),
      body: state.loading && state.plugins.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
              children: [
                _IntroCard(tokens: tokens),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                if (state.plugins.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No plugins yet.\nCreate one or drop a folder into '
                        'VinaAgent/Plugins.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                for (final plugin in state.plugins)
                  _PluginCard(plugin: plugin),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showInstallDialog(context, ref),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Install plugin from folder path'),
                ),
              ],
            ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_PluginDraft>(
      context: context,
      builder: (_) => const _CreatePluginDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(pluginControllerProvider.notifier).createPlugin(
            name: result.name,
            description: result.description,
            instructions: result.instructions,
          );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create plugin: $error')),
      );
    }
  }

  Future<void> _showInstallDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Install plugin from folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Absolute folder path',
            hintText: '/storage/emulated/0/Download/MyPlugin',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return;
    try {
      await ref.read(pluginControllerProvider.notifier).installFromFolder(path);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not install plugin: $error')),
      );
    }
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({super.key, required this.tokens});

  final GlassTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.glassBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.extension_outlined, size: 17, color: tokens.accent),
              const SizedBox(width: 7),
              const Text(
                'Bundle skills, sub-agents, hooks, MCP servers & commands',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A plugin is a folder with plugin.json. Enabled plugins contribute '
            'their SKILL.md packages, agent profiles, slash commands and MCP '
            'servers to the whole app. Hooks run as shell commands on '
            'before_send and after_run.',
            style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PluginCard extends ConsumerWidget {
  const _PluginCard({super.key, required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.glass;
    final manifest = plugin.manifest;
    final chips = <String>[
      if (manifest.skillDirectories.isNotEmpty) 'skills',
      if (manifest.agentDirectories.isNotEmpty) 'agents',
      if (manifest.commands.isNotEmpty)
        '${manifest.commands.length} command(s)',
      if (manifest.mcpServers.isNotEmpty)
        '${manifest.mcpServers.length} MCP',
      if (manifest.hooks.isNotEmpty) '${manifest.hooks.length} hook(s)',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: plugin.enabled
              ? tokens.accent.withValues(alpha: 0.35)
              : tokens.glassBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${manifest.name}  v${manifest.version}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (manifest.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          manifest.description,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                value: plugin.enabled,
                onChanged: (value) => ref
                    .read(pluginControllerProvider.notifier)
                    .setEnabled(manifest.name, value),
              ),
              IconButton(
                tooltip: 'Remove plugin',
                icon: const Icon(Icons.delete_outline, size: 19),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text('Remove ${manifest.name}?'),
                      content: const Text(
                        'The plugin folder and its contributed skills/agents '
                        'will be removed.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await ref
                      .read(pluginControllerProvider.notifier)
                      .deletePlugin(manifest.name);
                },
              ),
            ],
          ),
          if (plugin.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                plugin.error!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final chip in chips)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    chip,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: tokens.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plugin.directory,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PluginDraft {
  const _PluginDraft(this.name, this.description, this.instructions);

  final String name;
  final String description;
  final String instructions;
}

class _CreatePluginDialog extends StatefulWidget {
  const _CreatePluginDialog();

  @override
  State<_CreatePluginDialog> createState() => _CreatePluginDialogState();
}

class _CreatePluginDialogState extends State<_CreatePluginDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _instructions = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create plugin'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'my-workflow',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What this plugin helps with',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _instructions,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Skill instructions',
                hintText: 'Step-by-step behaviour the agent should follow…',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(
              context,
              _PluginDraft(
                _name.text.trim(),
                _description.text.trim(),
                _instructions.text.trim(),
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
