import '../domain/agent_skill.dart';

/// Structured input for the quality gate and renderer.
class SkillDraft {
  const SkillDraft({
    required this.name,
    required this.description,
    required this.body,
    this.triggers = const [],
    this.reason = '',
  });

  final String name;
  final String description;
  final String body;
  final List<String> triggers;
  final String reason;
}

class SkillQualityReport {
  const SkillQualityReport({
    required this.score,
    required this.errors,
    required this.warnings,
  });

  final int score;
  final List<String> errors;
  final List<String> warnings;

  bool get passed => errors.isEmpty && score >= 70;
  bool get autoApprovable => errors.isEmpty && score >= 85;

  String get summary {
    if (errors.isEmpty && warnings.isEmpty) {
      return 'Quality score $score/100 — ready.';
    }
    final parts = <String>[];
    if (errors.isNotEmpty) parts.add('Errors: ${errors.join('; ')}');
    if (warnings.isNotEmpty) parts.add('Warnings: ${warnings.join('; ')}');
    return 'Quality score $score/100 — ${parts.join(' ')}';
  }
}

/// Enforces the "no trash skills" contract before anything reaches disk.
class SkillQualityGate {
  const SkillQualityGate._();

  static final RegExp _validName = RegExp(r'^[a-z0-9][a-z0-9-]{2,47}$');
  static final RegExp _numberedStep = RegExp(r'^\s*\d+\.\s+\S', multiLine: true);
  static final RegExp _placeholder = RegExp(
    r'\b(TODO|TBD|FIXME|placeholder|insert here|lorem ipsum|your-api-key|example\.com/your)\b',
    caseSensitive: false,
  );
  static final RegExp _secret = RegExp(
    r'(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AIza[0-9A-Za-z\-_]{20,})',
  );
  static const List<String> _requiredSections = [
    '## When to use',
    '## Steps',
    '## Verification',
    '## Failure modes',
  ];
  static const List<String> _knownTools = [
    'load_skill',
    'list_skills',
    'read_skill_resource',
    'create_skill',
    'read_file',
    'write_file',
    'list_files',
    'search_files',
    'web_search',
    'code_sandbox',
    'generate_image',
    'extract_text_from_file',
    'create_artifact',
    'delegate_task',
  ];

  static SkillQualityReport evaluate(
    SkillDraft draft, {
    List<AgentSkill> existing = const [],
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final name = draft.name.trim().toLowerCase();
    final description = draft.description.trim();
    final body = draft.body.trim();

    if (!_validName.hasMatch(name)) {
      errors.add('Name must be kebab-case, 3-48 characters');
    }
    if (description.length < 40) {
      errors.add('Description must be at least 40 characters');
    }
    if (description.length > 1024) {
      errors.add('Description must be 1024 characters or less');
    }
    if (!RegExp(r'use when|gunakan saat|when to use', caseSensitive: false)
        .hasMatch(description)) {
      warnings.add('Description should say when to use the skill');
    }
    if (body.length < 300) {
      errors.add('Instructions are too short (minimum 300 characters)');
    }
    for (final section in _requiredSections) {
      if (!body.toLowerCase().contains(section.toLowerCase())) {
        errors.add('Missing section "$section"');
      }
    }
    if (_numberedStep.allMatches(body).length < 3) {
      errors.add('Steps must contain at least 3 numbered actions');
    }
    if (!_knownTools.any(body.contains) && !body.contains('`')) {
      warnings.add('Add at least one concrete tool or command in backticks');
    }
    if (_placeholder.hasMatch(body) || _placeholder.hasMatch(description)) {
      errors.add('Remove TODO/TBD/placeholder text');
    }
    if (_secret.hasMatch(body) || _secret.hasMatch(description)) {
      errors.add('Remove API keys or secrets from the skill');
    }
    for (final skill in existing) {
      final similarity = _jaccard(
        '$name $description',
        '${skill.name} ${skill.description}',
      );
      if (similarity > 0.75) {
        errors.add('Too similar to existing skill "${skill.name}"');
        break;
      }
    }

    var score = 100 - errors.length * 12 - warnings.length * 4;
    if (score < 0) score = 0;
    return SkillQualityReport(
      score: score,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Renders a deterministic, professional SKILL.md body from model output.
  static String render({
    required String whenToUse,
    required List<String> prerequisites,
    required List<String> steps,
    required List<String> verification,
    required List<String> failureModes,
    String example = '',
  }) {
    final buffer = StringBuffer()
      ..writeln('## When to use')
      ..writeln(whenToUse.trim())
      ..writeln()
      ..writeln('## Prerequisites');
    if (prerequisites.isEmpty) {
      buffer.writeln('- None beyond the tools already available to the agent.');
    } else {
      for (final item in prerequisites) {
        buffer.writeln('- ${item.trim()}');
      }
    }
    buffer
      ..writeln()
      ..writeln('## Steps');
    for (var i = 0; i < steps.length; i++) {
      buffer.writeln('${i + 1}. ${steps[i].trim()}');
    }
    buffer
      ..writeln()
      ..writeln('## Verification');
    for (final item in verification) {
      buffer.writeln('- ${item.trim()}');
    }
    buffer
      ..writeln()
      ..writeln('## Failure modes');
    for (final item in failureModes) {
      buffer.writeln('- ${item.trim()}');
    }
    if (example.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Example')
        ..writeln(example.trim());
    }
    return buffer.toString().trim();
  }

  /// Builds a [SkillDraft] from the JSON shape requested from the model.
  static SkillDraft? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final description = json['description']?.toString().trim() ?? '';
    if (name.isEmpty || description.isEmpty) return null;

    final body = json['body']?.toString().trim() ?? '';
    final rendered = body.isNotEmpty
        ? body
        : render(
            whenToUse: json['when_to_use']?.toString() ?? description,
            prerequisites: _list(json['prerequisites']),
            steps: _list(json['steps']),
            verification: _list(json['verification']),
            failureModes: _list(json['failure_modes']),
            example: json['example']?.toString() ?? '',
          );

    return SkillDraft(
      name: name,
      description: description,
      body: rendered,
      triggers: _list(json['triggers'])
          .map((t) => t.toLowerCase().trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .take(20)
          .toList(),
      reason: json['reason']?.toString() ?? '',
    );
  }

  static List<String> _list(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^\s*[-*\d.]+\s*'), '').trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static double _jaccard(String a, String b) {
    Set<String> tokens(String value) => value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length > 2)
        .toSet();
    final left = tokens(a);
    final right = tokens(b);
    if (left.isEmpty || right.isEmpty) return 0;
    final intersection = left.intersection(right).length;
    final union = left.union(right).length;
    return union == 0 ? 0 : intersection / union;
  }
}
