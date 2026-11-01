import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/features/providers/application/providers_controller.dart';
import 'package:pocketstrike/features/providers/domain/provider_types.dart';
import 'package:pocketstrike/features/skills/application/skills_controller.dart';
import 'package:pocketstrike/features/skills/data/skill_author.dart';
import 'package:pocketstrike/features/skills/domain/agent_skill.dart';
import 'package:pocketstrike/features/skills/ui/skill_marketplace_screen.dart';

/// Manage the progressive-disclosure skill library installed on the device.
class SkillsScreen extends ConsumerWidget {
  const SkillsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(skillsProvider);
    ref.invalidate(skillCatalogProvider);
    ref.invalidate(pendingSkillsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(skillsProvider);
    final pendingAsync = ref.watch(pendingSkillsProvider);
    final store = ref.watch(skillStoreProvider);
    final globallyEnabled = ref.watch(skillsEnabledProvider);
    final autoLearn = ref.watch(autoLearnSkillsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Agent Skills',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Create skill with AI',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => _showAiDraftDialog(context, ref),
          ),
          IconButton(
            tooltip: 'SkillsMP marketplace',
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
              _GlobalToggle(
                enabled: autoLearn,
                title: 'Learn from experience',
                subtitle:
                    'After complex runs, draft a skill and queue it for review',
                onChanged: (value) async {
                  await store.setAutoLearnEnabled(value);
                  _refresh(ref);
                },
              ),
              pendingAsync.maybeWhen(
                data: (pending) => pending.isEmpty
                    ? const SizedBox.shrink()
                    : _PendingSection(
                        drafts: pending,
                        onApprove: (draft) => _approve(context, ref, draft),
                        onReject: (draft) => _reject(ref, draft),
                        onTap: (draft) => _showPending(context, draft),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              if (skills.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No skills yet. Tap "New skill", use the AI button, or ask '
                    'the agent to draft one with create_skill.',
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

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    PendingSkill draft,
  ) async {
    try {
      await ref.read(skillStoreProvider).approvePending(draft.id);
      _refresh(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Activated "${draft.name}".')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _reject(WidgetRef ref, PendingSkill draft) async {
    await ref.read(skillStoreProvider).rejectPending(draft.id);
    _refresh(ref);
  }

  void _showPending(BuildContext context, PendingSkill draft) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(draft.name),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(draft.description),
                const SizedBox(height: 8),
                Text(
                  'Source: ${draft.source} · quality ${draft.score}/100',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (draft.reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(draft.reason),
                ],
                const Divider(height: 20),
                SelectableText(
                  draft.body,
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

  Future<void> _showAiDraftDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final promptController = TextEditingController();
    var busy = false;
    String? error;
    SkillAuthorResult? result;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Create skill with AI'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: promptController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'What should this skill do?',
                      hintText:
                          'e.g. Review a Flutter widget for accessibility and '
                          'report concrete fixes',
                    ),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      result!.draft.name,
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                    Text(result!.draft.description),
                    const SizedBox(height: 6),
                    Text(
                      result!.report.summary,
                      style: TextStyle(
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    if (result!.report.errors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Rejected by the quality gate. Refine the prompt.',
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const Divider(height: 18),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          result!.draft.body,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            if (result == null)
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          final config = await ref
                              .read(activeProviderConfigProvider.future);
                          if (config == null) {
                            throw StateError(
                              'No AI provider configured. Add one in Settings.',
                            );
                          }
                          final provider = await ref
                              .read(providerResolverProvider)
                              .resolve(configId: config.id);
                          if (provider == null) {
                            throw StateError('Could not initialize provider.');
                          }
                          var model = config.defaultModel;
                          if (model.isEmpty) {
                            model = ProviderTypeX.fromId(config.type)
                                .suggestedModels
                                .first;
                          }
                          final existing =
                              await ref.read(skillStoreProvider).listSkills();
                          final generated =
                              await const SkillAuthor().draftFromPrompt(
                            provider: provider,
                            model: model,
                            request: promptController.text,
                            existing: existing,
                          );
                          setState(() {
                            busy = false;
                            result = generated;
                            if (generated == null) {
                              error =
                                  'The model skipped this request. Add more '
                                  'detail about the workflow and tools.';
                            }
                          });
                        } catch (e) {
                          setState(() {
                            busy = false;
                            error = '$e';
                          });
                        }
                      },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Generate'),
              ),
            if (result != null && result!.report.errors.isEmpty)
              FilledButton(
                onPressed: () async {
                  final draft = result!.draft;
                  await ref.read(skillStoreProvider).addPending(PendingSkill(
                        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
                        name: draft.name,
                        description: draft.description,
                        body: draft.body,
                        triggers: draft.triggers,
                        source: 'ai',
                        score: result!.report.score,
                        createdAt: DateTime.now(),
                        reason: 'Drafted with AI from the user prompt.',
                      ));
                  _refresh(ref);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Save for review'),
              ),
          ],
        ),
      ),
    );
    promptController.dispose();
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

class _PendingSection extends StatelessWidget {
  const _PendingSection({
    required this.drafts,
    required this.onApprove,
    required this.onReject,
    required this.onTap,
  });

  final List<PendingSkill> drafts;
  final ValueChanged<PendingSkill> onApprove;
  final ValueChanged<PendingSkill> onReject;
  final ValueChanged<PendingSkill> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
          child: Row(
            children: [
              Icon(Icons.pending_actions, size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Text(
                'PENDING REVIEW (${drafts.length})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                      color: tokens.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        for (final draft in drafts)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: tokens.secondary.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => onTap(draft),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        draft.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${draft.source} · score ${draft.score}/100',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => onReject(draft),
                      child: const Text('Reject'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () => onApprove(draft),
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GlobalToggle extends StatelessWidget {
  const _GlobalToggle({
    required this.enabled,
    required this.onChanged,
    this.title = 'Enable skills',
    this.subtitle = 'Inject skill metadata into the agent prompt',
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;

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
        title: Text(title),
        subtitle: Text(subtitle),
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
