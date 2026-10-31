/// A reusable AI-agent skill loaded from a `SKILL.md` package.
///
/// Skills follow the progressive-disclosure model:
///
/// * **Level 1** — [name] and [description] are injected into the system prompt
///   so the model knows the skill exists (about 100 tokens per skill).
/// * **Level 2** — [body] (the instructions in `SKILL.md`) is only loaded when
///   the model calls the `load_skill` tool.
/// * **Level 3** — files listed in [resources] are read on demand through
///   `read_skill_resource`.
class AgentSkill {
  const AgentSkill({
    required this.name,
    required this.description,
    required this.body,
    required this.directory,
    required this.resources,
    required this.bundled,
    required this.enabled,
  });

  final String name;
  final String description;
  final String body;

  /// Absolute path of the skill directory on the device.
  final String directory;

  /// Relative paths of reference files (everything except `SKILL.md`).
  final List<String> resources;

  /// True when the skill shipped with the app.
  final bool bundled;

  /// False when the user disabled the skill in settings.
  final bool enabled;

  AgentSkill copyWith({bool? enabled}) => AgentSkill(
        name: name,
        description: description,
        body: body,
        directory: directory,
        resources: resources,
        bundled: bundled,
        enabled: enabled ?? this.enabled,
      );

  /// Single line used in the Level-1 system-prompt catalog.
  String get catalogLine => '- $name: $description';

  /// Human-readable summary used by tools and the settings UI.
  String get summary {
    final visibility = bundled ? 'bundled' : 'custom';
    final state = enabled ? 'enabled' : 'disabled';
    return '$name ($visibility, $state) — $description';
  }
}

/// Thrown when a `SKILL.md` file cannot be parsed.
class SkillFormatException implements Exception {
  SkillFormatException(this.message);

  final String message;

  @override
  String toString() => 'SkillFormatException: $message';
}
