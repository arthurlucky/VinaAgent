import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/core/storage/prefs_provider.dart';
import 'package:pocketstrike/features/skills/data/skill_store.dart';
import 'package:pocketstrike/features/skills/domain/agent_skill.dart';

/// Shared, filesystem-backed skill store.
final skillStoreProvider = Provider<SkillStore>((ref) {
  return SkillStore(ref.watch(sharedPreferencesProvider));
});

/// Every installed skill (bundled + custom), seeded on first read.
final skillsProvider = FutureProvider<List<AgentSkill>>((ref) async {
  final store = ref.watch(skillStoreProvider);
  await store.ensureSeeded();
  return store.listSkills();
});

/// Level-1 catalog injected into the agent system prompt.
final skillCatalogProvider = FutureProvider<String>((ref) async {
  final store = ref.watch(skillStoreProvider);
  await store.ensureSeeded();
  return store.buildCatalogPrompt();
});

/// Whether the skill system is enabled globally.
final skillsEnabledProvider = Provider<bool>((ref) {
  ref.watch(skillsProvider);
  return ref.watch(skillStoreProvider).globallyEnabled;
});
