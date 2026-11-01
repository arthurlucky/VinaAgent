import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/features/skills/application/marketplace_controller.dart';
import 'package:pocketstrike/features/skills/application/skills_controller.dart';
import 'package:pocketstrike/features/skills/data/skillsmp_client.dart';
import 'package:pocketstrike/features/skills/domain/marketplace_models.dart';

/// Search and install skills from SkillsMP (skillsmp.com).
class SkillMarketplaceScreen extends ConsumerStatefulWidget {
  const SkillMarketplaceScreen({super.key});

  @override
  ConsumerState<SkillMarketplaceScreen> createState() =>
      _SkillMarketplaceScreenState();
}

class _SkillMarketplaceScreenState
    extends ConsumerState<SkillMarketplaceScreen> {
  final _searchController = TextEditingController(text: 'agent');
  final Set<String> _installing = {};
  final List<MarketplaceSkill> _skills = [];

  Timer? _debounce;
  String _query = 'agent';
  String _sortBy = 'stars';
  String _language = '';
  int _page = 1;
  bool _loading = false;
  bool _hasNext = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  SkillsMpClient get _client => ref.read(skillsMpClientProvider);

  Future<void> _search({required bool reset}) async {
    if (_loading && !reset) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _page = 1;
        _skills.clear();
        _hasNext = false;
      }
    });

    try {
      final page = await _client.search(
        _query,
        page: reset ? 1 : _page,
        limit: 20,
        sortBy: _sortBy,
        language: _language.isEmpty ? null : _language,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _skills
            ..clear()
            ..addAll(page.skills);
        } else {
          for (final skill in page.skills) {
            if (!_skills.any((existing) => existing.id == skill.id)) {
              _skills.add(skill);
            }
          }
        }
        _page = page.page;
        _hasNext = page.hasNext;
      });
    } on SkillsMpException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _query = value.trim().isEmpty ? 'agent' : value.trim();
      _search(reset: true);
    });
  }

  Future<void> _install(MarketplaceSkill skill) async {
    setState(() => _installing.add(skill.id));
    try {
      final installed = await ref
          .read(marketplaceClientProvider)
          .install(skill, ref.read(skillStoreProvider));
      ref.invalidate(skillsProvider);
      ref.invalidate(skillCatalogProvider);
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
      if (mounted) setState(() => _installing.remove(skill.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final installed = ref.watch(skillsProvider).valueOrNull
            ?.map((skill) => skill.name)
            .toSet() ??
        <String>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SkillsMP Marketplace',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'skillsmp.com',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: () => _showAbout(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              onSubmitted: (value) {
                _query = value.trim().isEmpty ? 'agent' : value.trim();
                _search(reset: true);
              },
              decoration: InputDecoration(
                hintText: 'Search 3M+ skills on SkillsMP',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('★ Popular'),
                  selected: _sortBy == 'stars',
                  onSelected: (_) {
                    if (_sortBy == 'stars') return;
                    setState(() => _sortBy = 'stars');
                    _search(reset: true);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Recent'),
                  selected: _sortBy == 'recent',
                  onSelected: (_) {
                    if (_sortBy == 'recent') return;
                    setState(() => _sortBy = 'recent');
                    _search(reset: true);
                  },
                ),
                const Spacer(),
                DropdownButton<String>(
                  value: _language,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Any language')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'id', child: Text('Indonesia')),
                    DropdownMenuItem(value: 'ja', child: Text('日本語')),
                    DropdownMenuItem(value: 'zh', child: Text('中文')),
                  ],
                  onChanged: (value) {
                    setState(() => _language = value ?? '');
                    _search(reset: true);
                  },
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.secondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(
                    color: tokens.secondary.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!, style: TextStyle(color: tokens.textSecondary)),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => _search(reset: true),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(child: _buildList(installed, tokens)),
        ],
      ),
    );
  }

  Widget _buildList(Set<String> installed, GlassTokens tokens) {
    if (_loading && _skills.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_loading && _skills.isEmpty && _error == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No skills found for "$_query".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: _skills.length + (_hasNext ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _skills.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: OutlinedButton(
              onPressed: _loading
                  ? null
                  : () {
                      _page += 1;
                      _search(reset: false);
                    },
              child: Text(_loading ? 'Loading…' : 'Load more'),
            ),
          );
        }
        final skill = _skills[index];
        return _MarketplaceTile(
          skill: skill,
          installed: installed.contains(skill.name),
          busy: _installing.contains(skill.id),
          onInstall: () => _install(skill),
        );
      },
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SkillsMP'),
        content: const Text(
          'Search results come from skillsmp.com, a community catalog of '
          '3M+ open-source Agent Skills. Installing downloads the skill '
          'directly from its public GitHub repository into the app sandbox.\n\n'
          'Anonymous search is rate-limited; if the quota is exhausted, try '
          'again later or install a skill from a known repository.',
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  skill.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (skill.stars > 0) ...[
                Icon(Icons.star, size: 13, color: tokens.secondary),
                const SizedBox(width: 3),
                Text(
                  _compact(skill.stars),
                  style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${skill.author.isEmpty ? skill.source.owner : skill.author} · '
            '${skill.source.id}/${skill.directory}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
          ),
          if (skill.description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              skill.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textSecondary, height: 1.35),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: installed
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: tokens.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Installed',
                        style: TextStyle(color: tokens.accent, fontSize: 12),
                      ),
                    ],
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : onInstall,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download, size: 16),
                    label: Text(busy ? 'Installing…' : 'Install'),
                  ),
          ),
        ],
      ),
    );
  }

  static String _compact(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }
}
