import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/glass_tokens.dart';
import '../../providers/application/providers_controller.dart';
import '../application/agents_controller.dart';
import '../domain/agent_profile.dart';

/// CRUD for the specialist sub-agents used by `delegate_task`.
class AgentsSettingsScreen extends ConsumerWidget {
  const AgentsSettingsScreen({super.key});

  static const _knownTools = [
    'web_search',
    'read_file',
    'write_file',
    'list_files',
    'search_files',
    'code_sandbox',
    'generate_image',
    'extract_text_from_file',
    'create_artifact',
    'update_artifact',
    'list_artifacts',
    'list_skills',
    'load_skill',
    'read_skill_resource',
    'create_skill',
    'search_skill_marketplace',
    'install_marketplace_skill',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(agentProfilesProvider);
    final tokens = context.glass;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Sub-agents',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Reset to defaults',
            icon: const Icon(Icons.restart_alt),
            onPressed: () async {
              await ref.read(agentProfileStoreProvider).resetToDefaults();
              ref.invalidate(agentProfilesProvider);
            },
          ),
          IconButton(
            tooltip: 'Add agent',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(context, ref, null),
          ),
        ],
      ),
      body: profiles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'The main agent can hand a self-contained task to one of these '
                'specialists with delegate_task. Sub-agents cannot delegate '
                'further and only receive the tools you allow here.',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
            for (final profile in items)
              _ProfileCard(
                profile: profile,
                onToggle: (value) async {
                  await ref
                      .read(agentProfileStoreProvider)
                      .save(profile.copyWith(enabled: value));
                  ref.invalidate(agentProfilesProvider);
                },
                onTap: () => _edit(context, ref, profile),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AgentProfile? profile,
  ) async {
    final name = TextEditingController(text: profile?.name ?? '');
    final emoji = TextEditingController(text: profile?.emoji ?? '🤖');
    final purpose = TextEditingController(text: profile?.purpose ?? '');
    final persona = TextEditingController(text: profile?.persona ?? '');
    final model = TextEditingController(text: profile?.model ?? '');
    final skills = TextEditingController(text: profile?.skills.join(', ') ?? '');
    final selectedTools = <String>{...?profile?.tools};
    var providerId = profile?.providerConfigId ?? '';
    var maxSteps = profile?.maxSteps ?? 10;
    var enabled = profile?.enabled ?? true;
    var saving = false;
    String? error;

    final configs =
        ref.watch(providerConfigsProvider).valueOrNull ?? const [];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(profile == null ? 'New sub-agent' : 'Edit sub-agent'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: emoji,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(labelText: 'Emoji'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: name,
                          decoration:
                              const InputDecoration(labelText: 'Name'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: purpose,
                    decoration: const InputDecoration(
                      labelText: 'Purpose',
                      hintText: 'One line: what this specialist is for',
                    ),
                  ),
                  TextField(
                    controller: persona,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Persona / instructions',
                      hintText:
                          'How it should think, what to prioritize, tone, '
                          'constraints…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: providerId,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      helperText: 'Default uses the active provider',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Default provider'),
                      ),
                      for (final config in configs)
                        DropdownMenuItem(
                          value: config.id,
                          child: Text(config.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => providerId = value ?? ''),
                  ),
                  TextField(
                    controller: model,
                    decoration: const InputDecoration(
                      labelText: 'Model override',
                      hintText: 'Leave empty for the provider default',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Max steps: $maxSteps',
                      style: Theme.of(dialogContext).textTheme.bodySmall),
                  Slider(
                    value: maxSteps.toDouble(),
                    min: 2,
                    max: 20,
                    divisions: 18,
                    label: '$maxSteps',
                    onChanged: (value) =>
                        setState(() => maxSteps = value.round()),
                  ),
                  const SizedBox(height: 4),
                  Text('Allowed tools',
                      style: Theme.of(dialogContext).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tool in _knownTools)
                        FilterChip(
                          label: Text(tool, style: const TextStyle(fontSize: 11)),
                          selected: selectedTools.contains(tool),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                selectedTools.add(tool);
                              } else {
                                selectedTools.remove(tool);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  TextField(
                    controller: skills,
                    decoration: const InputDecoration(
                      labelText: 'Preferred skills',
                      hintText: 'Comma-separated skill names (optional)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled'),
                    value: enabled,
                    onChanged: (value) => setState(() => enabled = value),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (profile != null)
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        await ref
                            .read(agentProfileStoreProvider)
                            .delete(profile.id);
                        ref.invalidate(agentProfilesProvider);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final trimmed = name.text.trim();
                      if (trimmed.isEmpty) {
                        setState(() => error = 'A name is required.');
                        return;
                      }
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final updated = AgentProfile(
                          id: profile?.id ?? 'agent-${const Uuid().v4()}',
                          name: trimmed,
                          emoji: emoji.text.trim().isEmpty
                              ? '🤖'
                              : emoji.text.trim(),
                          purpose: purpose.text.trim(),
                          persona: persona.text.trim(),
                          tools: selectedTools.toList(),
                          skills: skills.text
                              .split(',')
                              .map((item) => item.trim())
                              .where((item) => item.isNotEmpty)
                              .toList(),
                          maxSteps: maxSteps,
                          providerConfigId: providerId,
                          model: model.text.trim(),
                          enabled: enabled,
                        );
                        await ref
                            .read(agentProfileStoreProvider)
                            .save(updated);
                        ref.invalidate(agentProfilesProvider);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (e) {
                        setState(() {
                          saving = false;
                          error = '$e';
                        });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    emoji.dispose();
    purpose.dispose();
    persona.dispose();
    model.dispose();
    skills.dispose();
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onToggle,
    required this.onTap,
  });

  final AgentProfile profile;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.glassBorder),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        leading: Text(profile.emoji, style: const TextStyle(fontSize: 22)),
        title: Text(profile.name),
        subtitle: Text(
          profile.purpose.isEmpty ? 'No purpose set' : profile.purpose,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: tokens.textSecondary, fontSize: 11.5),
        ),
        trailing: Switch(value: profile.enabled, onChanged: onToggle),
        onTap: onTap,
      ),
    );
  }
}
