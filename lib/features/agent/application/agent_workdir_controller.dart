import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/app_sandbox.dart';
import '../../../core/storage/prefs_provider.dart';

final agentWorkdirProvider =
    StateNotifierProvider<AgentWorkdirNotifier, String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AgentWorkdirNotifier(prefs);
});

class AgentWorkdirNotifier extends StateNotifier<String> {
  AgentWorkdirNotifier(this._prefs)
      : super(_prefs.getString(_prefKey) ?? '');

  static const _prefKey = 'agent_active_workdir';
  final SharedPreferences _prefs;

  /// Returns friendly display name (e.g. "root/" or "root/MyProject").
  String get displayWorkdir {
    final cur = state.trim();
    if (cur.isEmpty || cur == '/' || cur == 'root' || cur == 'default') {
      return 'root/';
    }
    final clean = cur.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    return 'root/$clean';
  }

  /// Relative path inside sandbox (e.g. "" for root, or "MyProject").
  String get relativeWorkdir {
    final cur = state.trim();
    if (cur.isEmpty || cur == '/' || cur == 'root' || cur == 'default') {
      return '';
    }
    return cur.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  }

  /// Sets the active working directory. Passing '' or '/' or 'default' resets to root.
  Future<void> setWorkdir(String target) async {
    final trimmed = target.trim();
    final cleaned = (trimmed.isEmpty ||
            trimmed == 'default' ||
            trimmed == '/' ||
            trimmed == 'root')
        ? ''
        : trimmed.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');

    if (cleaned.isNotEmpty) {
      final rootDir = await AppSandbox.root();
      final targetDir = Directory(p.join(rootDir.path, cleaned));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
    }

    state = cleaned;
    await _prefs.setString(_prefKey, cleaned);
  }

  /// Resolves an agent path relative to the active workdir.
  Future<String> resolveAgentPath(String rawPath) async {
    final rootDir = await AppSandbox.root();
    final rootPath = rootDir.path;
    final trimmed = rawPath.trim().replaceAll('\\', '/');

    // Leading slash or absolute inside root -> resolve directly against root
    if (trimmed.startsWith('/') || trimmed.startsWith(rootPath)) {
      final stripped = trimmed.replaceFirst(RegExp(r'^/+'), '');
      return AppSandbox.resolveWithRoot(stripped, rootPath) ??
          p.join(rootPath, stripped);
    }

    // Relative path with an active workdir
    final wd = relativeWorkdir;
    if (wd.isNotEmpty) {
      final combined = p.join(wd, trimmed);
      return AppSandbox.resolveWithRoot(combined, rootPath) ??
          p.join(rootPath, combined);
    }

    // Default: relative to sandbox root
    return AppSandbox.resolveWithRoot(trimmed, rootPath) ??
        p.join(rootPath, trimmed);
  }

  /// Lists all top-level directories available in sandbox root.
  Future<List<String>> listAvailableFolders() async {
    final rootDir = await AppSandbox.root();
    final folders = <String>[];
    await for (final entity in rootDir.list(followLinks: false)) {
      if (entity is Directory) {
        folders.add(p.basename(entity.path));
      }
    }
    folders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return folders;
  }
}
