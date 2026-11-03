import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/core/db/app_database.dart';
import 'package:pocketstrike/core/storage/prefs_provider.dart';
import 'package:pocketstrike/features/agents/data/agent_profile_store.dart';
import 'package:pocketstrike/features/chat/domain/slash_command.dart';
import 'package:pocketstrike/features/mcp/application/mcp_controller.dart';
import 'package:pocketstrike/features/skills/data/skill_store.dart';

import '../data/plugin_store.dart';
import '../domain/plugin_manifest.dart';

class PluginState {
  const PluginState({
    this.loading = false,
    this.plugins = const [],
    this.error,
    this.message,
  });

  final bool loading;
  final List<InstalledPlugin> plugins;
  final String? error;
  final String? message;

  List<InstalledPlugin> get enabled =>
      plugins.where((plugin) => plugin.enabled).toList(growable: false);

  PluginState copyWith({
    bool? loading,
    List<InstalledPlugin>? plugins,
    String? error,
    bool clearError = false,
    String? message,
    bool clearMessage = false,
  }) {
    return PluginState(
      loading: loading ?? this.loading,
      plugins: plugins ?? this.plugins,
      error: clearError ? null : (error ?? this.error),
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// Loads plugins and wires their skills, sub-agents, MCP servers and commands
/// into the rest of the app.
class PluginController extends StateNotifier<PluginState> {
  PluginController(this.ref) : super(const PluginState(loading: true)) {
    _initializing = refresh();
  }

  final Ref ref;

  Future<void>? _initializing;

  PluginStore get _store => ref.read(pluginStoreProvider);

  /// Waits for the first plugin scan to finish (cheap after startup).
  Future<void> ensureReady() async {
    await (_initializing ??= refresh());
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _store.ensureSeeded();
      final plugins = await _store.list();

      // Publish read-only contributions to the skill and sub-agent stores.
      SkillStore.extraRoots
        ..clear()
        ..addAll(await _store.enabledSkillRoots(plugins));
      AgentProfileStore.extraProfiles
        ..clear()
        ..addAll(await _store.enabledAgentProfiles(plugins));

      await _syncMcpServers(plugins);
      state = PluginState(plugins: plugins, loading: false);
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: 'Could not load plugins: $error',
      );
    }
  }

  Future<void> setEnabled(String name, bool enabled) async {
    await _store.setEnabled(name, enabled);
    await refresh();
    state = state.copyWith(
      message: enabled ? 'Plugin "$name" enabled.' : 'Plugin "$name" disabled.',
    );
  }

  Future<InstalledPlugin> createPlugin({
    required String name,
    required String description,
    required String instructions,
  }) async {
    final plugin = await _store.createPlugin(
      name: name,
      description: description,
      instructions: instructions,
    );
    await refresh();
    state = state.copyWith(message: 'Plugin "${plugin.name}" created.');
    return plugin;
  }

  Future<void> installFromFolder(String path) async {
    final plugin = await _store.installFromFolder(path);
    await refresh();
    state = state.copyWith(message: 'Plugin "${plugin.name}" installed.');
  }

  Future<void> deletePlugin(String name) async {
    await _store.deletePlugin(name);
    await refresh();
    state = state.copyWith(message: 'Plugin "$name" removed.');
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  PluginCommand? findCommand(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final plugin in state.plugins.where((plugin) => plugin.enabled)) {
      for (final command in plugin.manifest.commands) {
        if (command.name.toLowerCase() == needle) return command;
      }
    }
    return null;
  }

  String renderCommand(PluginCommand command, String arguments) {
    final args = arguments.trim();
    const token = r'$ARGUMENTS';
    if (command.prompt.contains(token)) {
      return command.prompt.replaceAll(token, args);
    }
    return args.isEmpty ? command.prompt : '${command.prompt}\n\n$args';
  }

  /// Runs a lifecycle hook for every enabled plugin. Never throws.
  Future<void> runLifecycleHook(
    String hook, {
    Map<String, String> environment = const {},
  }) async {
    try {
      final output = await _store.runHooks(hook, environment: environment);
      for (final line in output) {
        debugPrint('[Plugin hook] $line');
      }
    } catch (_) {}
  }

  Future<void> _syncMcpServers(List<InstalledPlugin> plugins) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final existing = await db.select(db.mcpServers).get();

      final desired = <String, ({String name, String url, String transport})>{};
      for (final plugin in plugins.where((plugin) => plugin.enabled)) {
        for (final server in plugin.manifest.mcpServers) {
          if (server.url.trim().isEmpty) continue;
          final id = 'plugin-${plugin.name}-${_slug(server.name)}';
          desired[id] = (
            name: '${plugin.name}: ${server.name}',
            url: server.url.trim(),
            transport: server.transport.trim().isEmpty
                ? 'sse'
                : server.transport.trim(),
          );
        }
      }

      for (final entry in desired.entries) {
        final match = existing.where((row) => row.id == entry.key).firstOrNull;
        if (match == null) {
          await db.mcpServersDao.upsert(
            McpServersCompanion.insert(
              id: entry.key,
              name: entry.value.name,
              transport: Value(entry.value.transport),
              url: entry.value.url,
              createdAt: DateTime.now(),
            ),
          );
        } else if (match.url != entry.value.url ||
            match.transport != entry.value.transport) {
          await db.mcpServersDao.upsert(
            McpServersCompanion(
              id: Value(entry.key),
              name: Value(entry.value.name),
              transport: Value(entry.value.transport),
              url: Value(entry.value.url),
              createdAt: Value(match.createdAt),
            ),
          );
        }
      }

      // Remove servers that belonged to disabled or deleted plugins.
      for (final row in existing) {
        if (!row.id.startsWith('plugin-')) continue;
        if (desired.containsKey(row.id)) continue;
        await ref.read(mcpActionsProvider).deleteServer(row.id);
      }
    } catch (_) {
      // MCP sync is best-effort; plugins still load without it.
    }
  }

  String _slug(String raw) {
    final slug = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'server' : slug;
  }
}

final pluginStoreProvider = Provider<PluginStore>((ref) {
  return PluginStore(ref.watch(sharedPreferencesProvider));
});

final pluginControllerProvider =
    StateNotifierProvider<PluginController, PluginState>((ref) {
  return PluginController(ref);
});

/// Slash commands contributed by enabled plugins.
final pluginCommandsProvider = Provider<List<SlashCommand>>((ref) {
  final plugins = ref.watch(pluginControllerProvider).plugins;
  return [
    for (final plugin in plugins.where((plugin) => plugin.enabled))
      for (final command in plugin.manifest.commands)
        if (command.name.trim().isNotEmpty)
          SlashCommand(
            name: command.name.trim(),
            description: command.description.trim().isEmpty
                ? 'Plugin: ${plugin.name}'
                : command.description.trim(),
          ),
  ];
});
