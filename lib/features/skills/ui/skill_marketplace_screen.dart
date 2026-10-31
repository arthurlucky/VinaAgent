import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/features/skills/application/marketplace_controller.dart';
import 'package:pocketstrike/features/skills/application/skills_controller.dart';
import 'package:pocketstrike/features/skills/domain/marketplace_models.dart';

/// Browse popular public skill repositories and install skills on device.
class SkillMarketplaceScreen extends ConsumerStatefulWidget {
  const SkillMarketplaceScreen({super.key});

  @override
  ConsumerState<SkillMarketplaceScreen> createState() =>
      _SkillMarketplaceScreenState();
}

class _SkillMarketplaceScreenState
    extends ConsumerState<SkillMarketplaceScreen> {
  MarketplaceSource? _source;
  String _query = '';
  final Set<String> _installing = {};

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(marketplaceSourcesProvider);
    final selected = _source != null && sources.contains(_source)
        ? _source!
        : (sources.isNotEmpty ? sources.first : null);
    final installed = ref.watch(skillsProvider).valueOrNull
            ?.map((skill) => skill.name)
            .toSet() ??
        <String>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Skill Marketplace',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Add repository',
            icon: const Icon(Icons.add_link),
            onPressed: _addRepository,
          ),
        ],
      ),
      body: selected == null
          ? const Center(child: Text('No marketplace sources configured.'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search skills in this source',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: DropdownButtonFormField<MarketplaceSource>(
                    key: ValueKey(selected.id),
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Source',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final source in sources)
                        DropdownMenuItem(
                          value: source,
                          child: Text(
                            source.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _source = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${selected.id} — ${selected.description}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.glass.textSecondary,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(child: _buildList(selected, installed)),
              ],
            ),
    );
  }

  Widget _buildList(MarketplaceSource source, Set<String> installed) {
    final skillsAsync = ref.watch(marketplaceSkillsProvider(source));

    return skillsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 40),
          Text('$error'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.invalidate(marketplaceSkillsProvider(source)),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (skills) {
        final query = _query.trim().toLowerCase();
        final filtered = query.isEmpty
            ? skills
            : skills
                .where((skill) =>
                    skill.name.toLowerCase().contains(query) ||
                    skill.description.toLowerCase().contains(query))
                .toList();

        if (filtered.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                skills.isEmpty
                    ? 'No skills found in this repository.'
                    : 'No skills match "$_query".',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final skill = filtered[index];
            return _MarketplaceTile(
              skill: skill,
              installed: installed.contains(skill.name),
              busy: _installing.contains(skill.id),
              onInstall: () => _install(skill),
            );
          },
        );
      },
    );
  }

  Future<void> _install(MarketplaceSkill skill) async {
    setState(() => _installing.add(skill.id));
    try {
      final installed = await ref
          .read(marketplaceClientProvider)
          .install(skill, ref.read(skillStoreProvider));
      ref.invalidate(skillsProvider);
      ref.invalidate(skillCatalogProvider);
      ref.invalidate(marketplaceSkillsProvider(skill.source));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Installed "${installed.name}".')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _installing.remove(skill.id));
      }
    }
  }

  Future<void> _addRepository() async {
    final controller = TextEditingController();
    String? error;

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Add repository'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'owner/repo',
              hintText: 'anthropics/skills',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  MarketplaceSource.parse(controller.text);
                  Navigator.of(dialogContext).pop(controller.text);
                } catch (e) {
                  setState(() => error = e.toString());
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null) return;

    try {
      final source = MarketplaceSource.parse(value);
      await ref.read(marketplaceSourcesProvider.notifier).add(value);
      if (mounted) setState(() => _source = source);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}

class _MarketplaceTile extends StatelessWidget {
  const _MarketplaceTile({
    required this.skill,
    required this.installed,
    required this.busy,
    required this.onInstall,
  });

  final MarketplaceSkill skill;
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: tokens.glassColor,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.glassBorder, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(Icons.extension_outlined, size: 18, color: tokens.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
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
            if (installed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.check_circle, size: 20, color: tokens.accent),
              )
            else if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: 'Install',
                icon: const Icon(Icons.download_rounded, size: 20),
                onPressed: onInstall,
              ),
          ],
        ),
      ),
    );
  }
}
