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
    this.triggers = const [],
  });

  final String name;
  final String description;
  final String body;

  /// Optional keywords (any language) that auto-activate the skill.
  final List<String> triggers;

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
        triggers: triggers,
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

/// A manually authored skill draft waiting for the user's approval.
///
/// Skills learned automatically from a completed run, and skills created by
/// the agent's `create_skill` tool, are installed immediately after passing the
/// quality gate. This queue is for drafts generated manually from the skills
/// screen, where the user still reviews before activation.
class PendingSkill {
  const PendingSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
    required this.source,
    required this.score,
    required this.createdAt,
    this.triggers = const [],
    this.reason = '',
  });

  final String id;
  final String name;
  final String description;

  /// Rendered markdown body (without YAML frontmatter).
  final String body;
  final List<String> triggers;

  /// `auto`, `ai` or `agent`.
  final String source;
  final int score;
  final DateTime createdAt;
  final String reason;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'body': body,
        'triggers': triggers,
        'source': source,
        'score': score,
        'createdAt': createdAt.toIso8601String(),
        'reason': reason,
      };

  factory PendingSkill.fromJson(Map<String, dynamic> json) => PendingSkill(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        body: json['body'] as String? ?? '',
        triggers: (json['triggers'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        source: json['source'] as String? ?? 'ai',
        score: (json['score'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        reason: json['reason'] as String? ?? '',
      );
}
