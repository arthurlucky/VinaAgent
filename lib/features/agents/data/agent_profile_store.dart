import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/agent_profile.dart';

/// Persists user-configured sub-agent profiles.
class AgentProfileStore {
  AgentProfileStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'agent_profiles_v1';

  Future<List<AgentProfile>> list() async {
    final raw = _prefs.getString(_key);
    if (raw == null) {
      final defaults = AgentProfile.defaults();
      await _write(defaults);
      return defaults;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return AgentProfile.defaults();
      final profiles = decoded
          .whereType<Map<String, dynamic>>()
          .map(AgentProfile.fromJson)
          .where((profile) => profile.id.isNotEmpty)
          .toList();
      return profiles.isEmpty ? AgentProfile.defaults() : profiles;
    } catch (_) {
      return AgentProfile.defaults();
    }
  }

  Future<void> save(AgentProfile profile) async {
    final profiles = await list();
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _write(profiles);
  }

  Future<void> delete(String id) async {
    final profiles = await list();
    profiles.removeWhere((profile) => profile.id == id);
    await _write(profiles);
  }

  Future<void> resetToDefaults() async {
    await _write(AgentProfile.defaults());
  }

  Future<void> _write(List<AgentProfile> profiles) async {
    await _prefs.setString(
      _key,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );
  }
}
