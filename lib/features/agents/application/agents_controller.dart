import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/core/storage/prefs_provider.dart';
import 'package:pocketstrike/features/agents/data/agent_profile_store.dart';
import 'package:pocketstrike/features/agents/domain/agent_profile.dart';

final agentProfileStoreProvider = Provider<AgentProfileStore>((ref) {
  return AgentProfileStore(ref.watch(sharedPreferencesProvider));
});

final agentProfilesProvider = FutureProvider<List<AgentProfile>>((ref) async {
  return ref.watch(agentProfileStoreProvider).list();
});
