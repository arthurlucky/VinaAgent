import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/core/storage/prefs_provider.dart';
import 'package:pocketstrike/features/skills/data/github_marketplace_client.dart';
import 'package:pocketstrike/features/skills/domain/marketplace_models.dart';

/// GitHub-backed marketplace client.
final marketplaceClientProvider = Provider<GithubMarketplaceClient>((ref) {
  return GithubMarketplaceClient();
});

/// Sources shown in the marketplace: curated defaults + user added repos.
final marketplaceSourcesProvider =
    NotifierProvider<MarketplaceSourcesNotifier, List<MarketplaceSource>>(
        MarketplaceSourcesNotifier.new);

class MarketplaceSourcesNotifier extends Notifier<List<MarketplaceSource>> {
  static const String _key = 'marketplace_custom_sources';

  @override
  List<MarketplaceSource> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final custom = prefs.getStringList(_key) ?? const [];
    final sources = [...kFeaturedSkillSources];
    for (final id in custom) {
      try {
        final source = MarketplaceSource.parse(id);
        if (!sources.any((existing) => existing.id == source.id)) {
          sources.add(source);
        }
      } catch (_) {
        // Ignore malformed entries from older versions.
      }
    }
    return sources;
  }

  Future<void> add(String value) async {
    final source = MarketplaceSource.parse(value);
    if (state.any((existing) => existing.id == source.id)) return;
    state = [...state, source];
    await _persist();
  }

  Future<void> remove(MarketplaceSource source) async {
    if (kFeaturedSkillSources.contains(source)) return;
    state = state.where((existing) => existing.id != source.id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final custom = state
        .where((source) => !kFeaturedSkillSources.contains(source))
        .map((source) => source.id)
        .toList();
    await prefs.setStringList(_key, custom);
  }
}

/// Skills discovered in a marketplace source.
final marketplaceSkillsProvider =
    FutureProvider.family<List<MarketplaceSkill>, MarketplaceSource>(
        (ref, source) async {
  return ref.watch(marketplaceClientProvider).listSkills(source);
});
