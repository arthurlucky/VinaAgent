import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/features/skills/application/skills_controller.dart';
import 'package:pocketstrike/features/skills/domain/agent_skill.dart';
import 'package:pocketstrike/features/skills/ui/skill_marketplace_screen.dart';

/// Manage the progressive-disclosure skill library installed on the device.
class SkillsScreen extends ConsumerWidget {
  const SkillsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(skillsProvider);
    ref.invalidate(skillCatalogProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(skillsProvider);
    final store = ref.watch(skillStoreProvider);
    final globallyEnabled = ref.watch(skillsEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agent Skills',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Skill marketplace',
            icon: const Icon(Icons.storefront_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SkillMarketplaceScreen(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New skill'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh(ref);
          await ref.read(skillsProvider.future);
        },
        child: skillsAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(24),
            children: const [
              SizedBox(height: 80),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 60),
              Text('Could not load skills: $error'),
            ],
          ),
          data: (skills) => ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
            children: [
              _GlobalToggle(
                enabled: globallyEnabled,
                onChanged: (value) async {
                  await store.setGloballyEnabled(value);
                  _refresh(ref);
                },
              ),
              const SizedBox(height: 8),
              if (skills.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No skills yet. Tap "New skill" or ask the agent to '
                    'create one with the create_skill tool.',
                  ),
                ),
              for (final skill in skills)
                _SkillCard(
                  skill: skill,
                  onToggle: (value) async {
                    await store.setEnabled(skill.name, value);
                    _refresh(ref);
                  },
                  onTap: () => _showSkill(context, skill),
                  onDelete: skill.bundled
                      ? null
                      : () async {
                          await store.deleteSkill(skill.name);
                          _refresh(ref);
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSkill(BuildContext context, AgentSkill skill) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(skill.name),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.description),
                const SizedBox(height: 12),
                if (skill.resources.isNotEmpty) ...[
                  Text(
                    'Resources: ${skill.resources.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                SelectableText(
                  skill.body,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final instructionsController = TextEditingController();
    String? error;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('New skill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'meeting-notes',
                  ),
                ),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'What it does and when to use it',
                  ),
                ),
                TextField(
                  controller: instructionsController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Instructions (markdown)',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
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
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await ref.read(skillStoreProvider).createSkill(
                              name: nameController.text,
                              description: descriptionController.text,
                              instructions: instructionsController.text,
                            );
                        _refresh(ref);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (e) {
                        setState(() {
                          saving = false;
                          error = e.toString();
                        });
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Create'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    descriptionController.dispose();
    instructionsController.dispose();
  }
}

class _GlobalToggle extends StatelessWidget {
  const _GlobalToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.glassBorder, width: 0.8),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enable skills'),
        subtitle: const Text('Inject skill metadata into the agent prompt'),
        value: enabled,
        onChanged: onChanged,
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.onToggle,
    required this.onTap,
    this.onDelete,
  });

  final AgentSkill skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${skill.name}?'),
        content: const Text(
          'This removes the skill directory from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.glassBorder, width: 0.8),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: tokens.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              skill.name,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          if (skill.bundled) ...[
                            const SizedBox(width: 6),
                            Text(
                              'bundled',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        skill.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: tokens.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                Switch(value: skill.enabled, onChanged: onToggle),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _confirmDelete(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
