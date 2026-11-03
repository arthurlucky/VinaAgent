import 'dart:convert';

/// Declarative manifest for a Vina Agent plugin.
///
/// A plugin is a folder that bundles one or more agent capabilities:
///
/// ```
/// MyPlugin/
///   plugin.json          # this manifest
///   skills/<name>/SKILL.md
///   agents/<name>.json   # AgentProfile JSON
///   mcp.json             # optional: { "servers": [...] }
///   hooks.json           # optional: { "before_send": "...", "after_run": "..." }
/// ```
///
/// Plugins are inspired by Claude Code plugins: skills, sub-agents, hooks, MCP
/// servers and slash commands are installed and enabled as one unit.
class PluginManifest {
  const PluginManifest({
    required this.name,
    this.version = '1.0.0',
    this.description = '',
    this.author = '',
    this.skillDirectories = const ['skills'],
    this.agentDirectories = const ['agents'],
    this.commands = const [],
    this.mcpServers = const [],
    this.hooks = const {},
    this.permissions = const [],
  });

  final String name;
  final String version;
  final String description;
  final String author;

  /// Relative folders that contain `SKILL.md` packages.
  final List<String> skillDirectories;

  /// Relative folders that contain `*.json` agent profiles.
  final List<String> agentDirectories;

  final List<PluginCommand> commands;
  final List<PluginMcpServer> mcpServers;

  /// Lifecycle hook name -> shell command. Supported: `before_send`,
  /// `after_run`, `on_install`.
  final Map<String, String> hooks;

  /// Free-form capabilities the plugin declares (shown before enabling).
  final List<String> permissions;

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        'description': description,
        'author': author,
        'skills': skillDirectories,
        'agents': agentDirectories,
        'commands': commands.map((c) => c.toJson()).toList(),
        'mcpServers': mcpServers.map((s) => s.toJson()).toList(),
        'hooks': hooks,
        'permissions': permissions,
      };

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final rawName = (json['name'] as String? ?? '').trim();
    return PluginManifest(
      name: rawName,
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      skillDirectories: _stringList(json['skills'], fallback: const ['skills']),
      agentDirectories: _stringList(json['agents'], fallback: const ['agents']),
      commands: [
        for (final raw in (json['commands'] as List<dynamic>? ?? const []))
          if (raw is Map<String, dynamic>) PluginCommand.fromJson(raw),
      ],
      mcpServers: [
        for (final raw in (json['mcpServers'] as List<dynamic>? ?? const []))
          if (raw is Map<String, dynamic>) PluginMcpServer.fromJson(raw),
      ],
      hooks: {
        for (final entry in (json['hooks'] as Map<String, dynamic>? ?? const {})
            .entries)
          entry.key: entry.value.toString(),
      },
      permissions: _stringList(json['permissions'], fallback: const []),
    );
  }

  /// Parses a `plugin.json` string, returning null when it is malformed.
  static PluginManifest? tryParse(String raw, {String? fallbackName}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final manifest = PluginManifest.fromJson(decoded);
      if (manifest.name.isNotEmpty) return manifest;
      if (fallbackName == null) return null;
      return PluginManifest.fromJson({...decoded, 'name': fallbackName});
    } catch (_) {
      return null;
    }
  }

  static List<String> _stringList(dynamic value, {required List<String> fallback}) {
    if (value is! List) return fallback;
    final list = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return list.isEmpty ? fallback : list;
  }
}

/// A slash command contributed by a plugin.
class PluginCommand {
  const PluginCommand({
    required this.name,
    this.description = '',
    required this.prompt,
  });

  final String name;
  final String description;

  /// Prompt sent to the model. `$ARGUMENTS` is replaced with the typed text.
  final String prompt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'prompt': prompt,
      };

  factory PluginCommand.fromJson(Map<String, dynamic> json) => PluginCommand(
        name: (json['name'] as String? ?? '').trim(),
        description: json['description'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
      );
}

/// An MCP server bundled by a plugin.
class PluginMcpServer {
  const PluginMcpServer({
    required this.name,
    required this.url,
    this.transport = 'sse',
  });

  final String name;
  final String url;

  /// `sse` or `streamableHttp`.
  final String transport;

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'transport': transport,
      };

  factory PluginMcpServer.fromJson(Map<String, dynamic> json) => PluginMcpServer(
        name: (json['name'] as String? ?? 'MCP').trim(),
        url: (json['url'] as String? ?? '').trim(),
        transport: (json['transport'] as String? ?? 'sse').trim(),
      );
}

/// A plugin discovered on disk.
class InstalledPlugin {
  const InstalledPlugin({
    required this.manifest,
    required this.directory,
    required this.enabled,
    this.error,
  });

  final PluginManifest manifest;

  /// Absolute plugin folder path.
  final String directory;
  final bool enabled;

  /// Non-null when the manifest could not be parsed.
  final String? error;

  String get name => manifest.name;

  InstalledPlugin copyWith({bool? enabled, String? error}) => InstalledPlugin(
        manifest: manifest,
        directory: directory,
        enabled: enabled ?? this.enabled,
        error: error ?? this.error,
      );
}
