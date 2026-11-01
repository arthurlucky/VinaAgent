/// A user-configurable specialist the main agent can delegate work to.
class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.name,
    required this.emoji,
    required this.purpose,
    required this.persona,
    required this.tools,
    required this.skills,
    required this.maxSteps,
    this.providerConfigId = '',
    this.model = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String emoji;

  /// One-line description shown in settings and to the main agent.
  final String purpose;

  /// Detailed behaviour/persona instructions.
  final String persona;

  /// Tool-name allowlist. Empty means "all tools except delegate_task".
  final List<String> tools;

  /// Preferred skill names (advisory, injected into the system prompt).
  final List<String> skills;

  final int maxSteps;
  final String providerConfigId;
  final String model;
  final bool enabled;

  String get systemPrompt {
    final buffer = StringBuffer()
      ..writeln('You are $emoji $name, a specialized sub-agent inside Vina Agent.')
      ..writeln('Purpose: $purpose')
      ..writeln()
      ..writeln(persona.trim().isEmpty
          ? 'Work carefully and report concrete results.'
          : persona.trim());
    if (skills.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Preferred skills: ${skills.join(', ')}. Load them with '
            'load_skill when relevant.');
    }
    buffer
      ..writeln()
      ..writeln('Rules:')
      ..writeln('- You are handling ONE delegated task. Stay focused on it.')
      ..writeln('- You cannot delegate further; do the work yourself.')
      ..writeln('- Use only the tools provided.')
      ..writeln('- Return a concise result the parent agent can use directly.');
    return buffer.toString().trim();
  }

  AgentProfile copyWith({
    String? name,
    String? emoji,
    String? purpose,
    String? persona,
    List<String>? tools,
    List<String>? skills,
    int? maxSteps,
    String? providerConfigId,
    String? model,
    bool? enabled,
  }) =>
      AgentProfile(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        purpose: purpose ?? this.purpose,
        persona: persona ?? this.persona,
        tools: tools ?? this.tools,
        skills: skills ?? this.skills,
        maxSteps: maxSteps ?? this.maxSteps,
        providerConfigId: providerConfigId ?? this.providerConfigId,
        model: model ?? this.model,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'purpose': purpose,
        'persona': persona,
        'tools': tools,
        'skills': skills,
        'maxSteps': maxSteps,
        'providerConfigId': providerConfigId,
        'model': model,
        'enabled': enabled,
      };

  factory AgentProfile.fromJson(Map<String, dynamic> json) => AgentProfile(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Agent',
        emoji: json['emoji'] as String? ?? '🤖',
        purpose: json['purpose'] as String? ?? '',
        persona: json['persona'] as String? ?? '',
        tools: (json['tools'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        skills: (json['skills'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        maxSteps: (json['maxSteps'] as num?)?.toInt() ?? 10,
        providerConfigId: json['providerConfigId'] as String? ?? '',
        model: json['model'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
      );

  static List<AgentProfile> defaults() => const [
        AgentProfile(
          id: 'researcher',
          name: 'Researcher',
          emoji: '🔎',
          purpose:
              'Find, verify and summarize information from the web and files.',
          persona:
              'You are a meticulous research assistant. Cross-check claims, '
              'prefer primary sources, note dates and uncertainty, and return '
              'a compact summary with links or file paths. Never fabricate '
              'sources.',
          tools: [
            'web_search',
            'read_file',
            'list_files',
            'search_files',
            'list_skills',
            'load_skill',
            'read_skill_resource',
          ],
          skills: [],
          maxSteps: 8,
        ),
        AgentProfile(
          id: 'coder',
          name: 'Coder',
          emoji: '🛠️',
          purpose: 'Implement, debug and package code and technical artifacts.',
          persona:
              'You are a pragmatic senior engineer. Read before writing, make '
              'the smallest correct change, run a verification step, and '
              'explain trade-offs briefly. Save substantial deliverables with '
              'create_artifact.',
          tools: [
            'read_file',
            'write_file',
            'list_files',
            'search_files',
            'code_sandbox',
            'create_artifact',
            'update_artifact',
            'list_artifacts',
            'list_skills',
            'load_skill',
            'read_skill_resource',
          ],
          skills: [],
          maxSteps: 14,
        ),
        AgentProfile(
          id: 'reviewer',
          name: 'Reviewer',
          emoji: '🧐',
          purpose:
              'Review code, documents or plans and report concrete issues.',
          persona:
              'You are a rigorous reviewer. Prioritize correctness, security '
              'and user impact. Report findings with severity, evidence and a '
              'specific fix. Do not rewrite everything; review what was asked.',
          tools: [
            'read_file',
            'list_files',
            'search_files',
            'code_sandbox',
            'list_artifacts',
            'list_skills',
            'load_skill',
            'read_skill_resource',
          ],
          skills: [],
          maxSteps: 8,
        ),
      ];
}
