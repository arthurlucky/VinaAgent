import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/app_sandbox.dart';
import '../../agents/domain/agent_profile.dart';
import '../domain/plugin_manifest.dart';

/// Filesystem-backed plugin library.
///
/// Layout on device:
///
/// ```
/// <app documents>/VinaAgent/Plugins/<plugin>/plugin.json
/// <app documents>/VinaAgent/Plugins/<plugin>/skills/<skill>/SKILL.md
/// <app documents>/VinaAgent/Plugins/<plugin>/agents/<agent>.json
/// ```
class PluginStore {
  PluginStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _enabledPrefix = 'plugin_enabled_';
  static const String _seededKey = 'plugins_seeded_v1';
  static final RegExp _validName = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  Future<Directory> root() async {
    final sandbox = await AppSandbox.root();
    final dir = Directory(p.join(sandbox.path, 'Plugins'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  bool isEnabled(String name) =>
      _prefs.getBool('$_enabledPrefix$name') ?? true;

  Future<void> setEnabled(String name, bool enabled) async {
    await _prefs.setBool('$_enabledPrefix$name', enabled);
  }

  /// Creates the example plugin and a short README on first launch.
  Future<void> ensureSeeded() async {
    try {
      final pluginsDir = await root();
      final readme = File(p.join(pluginsDir.path, 'README.md'));
      if (!await readme.exists()) {
        await readme.writeAsString(_pluginReadme, flush: true);
      }
      if (_prefs.getBool(_seededKey) == true) return;

      final exampleDir = Directory(p.join(pluginsDir.path, 'getting-started'));
      if (!await exampleDir.exists()) {
        await createPlugin(
          name: 'getting-started',
          description:
              'Example plugin that bundles a skill and a slash command. '
              'Edit or delete it freely.',
          instructions:
              'When the user asks about plugins, explain that a plugin is a '
              'folder with plugin.json, skills/, agents/ and optional '
              'hooks.json or mcp.json. Offer to create one for the task.',
        );
      }
      await _prefs.setBool(_seededKey, true);
    } catch (_) {
      // Plugins are optional; the app still works without them.
    }
  }

  Future<List<InstalledPlugin>> list() async {
    final pluginsDir = await root();
    final plugins = <InstalledPlugin>[];
    await for (final entity in pluginsDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final plugin = await _readPlugin(entity);
      if (plugin != null) plugins.add(plugin);
    }
    plugins.sort((a, b) => a.name.compareTo(b.name));
    return plugins;
  }

  Future<InstalledPlugin?> _readPlugin(Directory dir) async {
    final fallbackName = p.basename(dir.path);
    final candidates = [
      File(p.join(dir.path, 'plugin.json')),
      File(p.join(dir.path, '.vina-plugin', 'plugin.json')),
    ];

    File? manifestFile;
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        manifestFile = candidate;
        break;
      }
    }

    PluginManifest? parsed;
    String? error;
    if (manifestFile != null) {
      try {
        parsed = PluginManifest.tryParse(
          await manifestFile.readAsString(),
          fallbackName: fallbackName,
        );
      } catch (e) {
        error = 'Could not read plugin.json: $e';
      }
    }

    var manifest = parsed ??
        PluginManifest(
          name: fallbackName,
          description: 'Plugin folder without a plugin.json manifest.',
        );

    if (manifest.name.isEmpty) return null;

    // Optional hooks.json is merged into the manifest.
    final hooksFile = File(p.join(dir.path, 'hooks.json'));
    if (await hooksFile.exists()) {
      try {
        final decoded = jsonDecode(await hooksFile.readAsString());
        if (decoded is Map<String, dynamic>) {
          manifest = PluginManifest.fromJson({
            ...manifest.toJson(),
            'hooks': {
              ...manifest.hooks,
              for (final entry in decoded.entries)
                entry.key: entry.value.toString(),
            },
          });
        }
      } catch (_) {}
    }

    return InstalledPlugin(
      manifest: manifest,
      directory: dir.path,
      enabled: isEnabled(manifest.name),
      error: error,
    );
  }

  /// Skill folders contributed by enabled plugins.
  Future<List<Directory>> enabledSkillRoots([
    List<InstalledPlugin>? plugins,
  ]) async {
    final all = plugins ?? await list();
    final roots = <Directory>[];
    for (final plugin in all.where((plugin) => plugin.enabled)) {
      for (final relative in plugin.manifest.skillDirectories) {
        final dir = Directory(p.join(plugin.directory, relative));
        if (await dir.exists()) roots.add(dir);
      }
    }
    return roots;
  }

  /// Agent profiles contributed by enabled plugins.
  Future<List<AgentProfile>> enabledAgentProfiles([
    List<InstalledPlugin>? plugins,
  ]) async {
    final all = plugins ?? await list();
    final profiles = <AgentProfile>[];
    for (final plugin in all.where((plugin) => plugin.enabled)) {
      for (final relative in plugin.manifest.agentDirectories) {
        final dir = Directory(p.join(plugin.directory, relative));
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File || !entity.path.endsWith('.json')) continue;
          try {
            final decoded = jsonDecode(await entity.readAsString());
            if (decoded is! Map<String, dynamic>) continue;
            final profile = AgentProfile.fromJson(decoded);
            final fallbackId =
                'plugin-${plugin.name}-${p.basenameWithoutExtension(entity.path)}';
            profiles.add(
              profile.id.isEmpty
                  ? AgentProfile.fromJson({...decoded, 'id': fallbackId})
                  : profile,
            );
          } catch (_) {}
        }
      }
    }
    return profiles;
  }

  /// Slash commands contributed by enabled plugins.
  List<PluginCommand> enabledCommands(List<InstalledPlugin> plugins) => [
        for (final plugin in plugins.where((plugin) => plugin.enabled))
          for (final command in plugin.manifest.commands)
            if (command.name.trim().isNotEmpty && command.prompt.trim().isNotEmpty)
              command,
      ];

  /// Runs every enabled plugin hook named [hook].
  ///
  /// Hooks are ordinary shell commands with a 20 second timeout. Output is
  /// returned for logging; a failing hook never breaks the chat.
  Future<List<String>> runHooks(
    String hook, {
    Map<String, String> environment = const {},
  }) async {
    final results = <String>[];
    final plugins = await list();
    for (final plugin in plugins.where((plugin) => plugin.enabled)) {
      final command = plugin.manifest.hooks[hook]?.trim() ?? '';
      if (command.isEmpty) continue;
      try {
        final shell = Platform.isWindows
            ? 'cmd'
            : (Platform.isAndroid ? '/system/bin/sh' : '/bin/sh');
        final args = Platform.isWindows ? ['/c', command] : ['-c', command];
        final result = await Process.run(
          shell,
          args,
          workingDirectory: plugin.directory,
          environment: {...Platform.environment, ...environment},
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        ).timeout(const Duration(seconds: 20));
        final output = '${result.stdout}${result.stderr}'.trim();
        results.add(
          '${plugin.name} [$hook] exit=${result.exitCode}'
          '${output.isEmpty ? '' : ': $output'}',
        );
      } catch (error) {
        results.add('${plugin.name} [$hook] failed: $error');
      }
    }
    return results;
  }

  /// Creates a plugin folder from plain instructions.
  Future<InstalledPlugin> createPlugin({
    required String name,
    required String description,
    required String instructions,
    String author = 'Vina Agent',
  }) async {
    final slug = _slugify(name);
    if (!_validName.hasMatch(slug)) {
      throw const FormatException(
        'Invalid plugin name. Use lowercase letters, numbers, - and _.',
      );
    }
    final pluginsDir = await root();
    final dir = Directory(p.join(pluginsDir.path, slug));
    if (await dir.exists()) {
      throw FormatException('A plugin named "$slug" already exists.');
    }
    await dir.create(recursive: true);

    final manifest = PluginManifest(
      name: slug,
      version: '1.0.0',
      description: description.trim(),
      author: author,
      commands: [
        PluginCommand(
          name: slug,
          description: description.trim().isEmpty
              ? 'Run the $slug plugin'
              : description.trim(),
          prompt: '\$ARGUMENTS',
        ),
      ],
      permissions: const ['skills', 'slash-command'],
    );

    await File(p.join(dir.path, 'plugin.json')).writeAsString(
      JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      flush: true,
    );

    final skillDir = Directory(p.join(dir.path, 'skills', slug));
    await skillDir.create(recursive: true);
    final title = slug
        .split(RegExp(r'[-_]'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
    await File(p.join(skillDir.path, 'SKILL.md')).writeAsString(
      '---\n'
      'name: $slug\n'
      'description: ${jsonEncode(description.trim().isEmpty ? 'Instructions for $slug' : description.trim())}\n'
      '---\n\n'
      '# $title\n\n'
      '${instructions.trim().isEmpty ? 'Describe how the agent should handle $slug tasks.' : instructions.trim()}\n',
      flush: true,
    );

    await File(p.join(dir.path, 'README.md')).writeAsString(
      '# $slug\n\n'
      '${description.trim()}\n\n'
      '## Contents\n'
      '- `skills/$slug/SKILL.md` — progressive-disclosure instructions\n'
      '- `plugin.json` — manifest and `/$slug` slash command\n\n'
      'Add `agents/*.json`, `hooks.json` or `mcpServers` in `plugin.json` to '
      'extend this plugin.\n',
      flush: true,
    );

    await setEnabled(slug, true);
    final plugin = await _readPlugin(dir);
    if (plugin == null) {
      throw const FormatException('Could not read the new plugin back.');
    }
    return plugin;
  }

  /// Copies an existing folder into the plugin library.
  Future<InstalledPlugin> installFromFolder(String sourcePath) async {
    final source = Directory(sourcePath.trim());
    if (!await source.exists()) {
      throw FormatException('Folder not found: $sourcePath');
    }
    final pluginsDir = await root();
    final name = p.basename(source.path);
    final target = Directory(p.join(pluginsDir.path, name));
    if (await target.exists()) {
      throw FormatException('A plugin named "$name" already exists.');
    }
    await _copyDirectory(source, target);
    await setEnabled(name, true);
    final plugin = await _readPlugin(target);
    if (plugin == null) {
      throw const FormatException('Could not read the installed plugin.');
    }
    return plugin;
  }

  /// Removes a plugin folder and its enabled preference.
  Future<void> deletePlugin(String name) async {
    final safeName = p.basename(name.trim());
    if (safeName.isEmpty || safeName == '.' || safeName == '..') return;
    final pluginsDir = await root();
    final dir = Directory(p.join(pluginsDir.path, safeName));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await _prefs.remove('$_enabledPrefix$safeName');
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: source.path);
      final destination = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        await File(destination).parent.create(recursive: true);
        await entity.copy(destination);
      }
    }
  }

  String _slugify(String raw) {
    var name = raw.trim().toLowerCase();
    name = name.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    name = name.replaceAll(RegExp(r'-+'), '-');
    name = name.replaceAll(RegExp(r'^-+|-+$'), '');
    if (name.length > 64) {
      name = name.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
    }
    return name;
  }

  static const String _pluginReadme = r'''# Vina Agent Plugins

Drop a folder in here to install a plugin. Every plugin bundles agent
capabilities as one unit, similar to Claude Code plugins.

```
MyPlugin/
  plugin.json
  skills/<skill>/SKILL.md
  agents/<agent>.json        (optional)
  hooks.json                 (optional)
```

`plugin.json` example:

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What this plugin does",
  "author": "you",
  "skills": ["skills"],
  "agents": ["agents"],
  "commands": [
    { "name": "my-command", "description": "Short help", "prompt": "Do the thing. $ARGUMENTS" }
  ],
  "mcpServers": [
    { "name": "terminal", "url": "http://127.0.0.1:3847/sse", "transport": "sse" }
  ],
  "hooks": {
    "before_send": "echo preparing >&2",
    "after_run": "echo finished >&2"
  },
  "permissions": ["skills", "mcp"]
}
```

Enable or disable plugins in Settings > Plugins. Plugin skills appear in the
normal skill catalog and plugin agents appear in Settings > Sub-agents.
''';
}
