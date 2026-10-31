import 'package:yaml/yaml.dart';

import '../domain/agent_skill.dart';

/// Parsed representation of a single `SKILL.md` file.
class ParsedSkill {
  const ParsedSkill({
    required this.name,
    required this.description,
    required this.body,
    this.triggers = const [],
  });

  final String name;
  final String description;
  final String body;

  /// Optional keywords (any language) that auto-activate the skill.
  final List<String> triggers;
}

/// Parses the YAML frontmatter and markdown body of a `SKILL.md` file.
///
/// The expected format is:
///
/// ```markdown
/// ---
/// name: pdf-processing
/// description: Extract text from PDFs. Use when the user mentions PDFs.
/// ---
///
/// # PDF Processing
/// ...
/// ```
class SkillParser {
  SkillParser._();

  static final RegExp _frontmatter =
      RegExp(r'^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)');
  static final RegExp _xmlTag = RegExp(r'<[^>]*>');

  static ParsedSkill parse(String raw, {String? fallbackName}) {
    final match = _frontmatter.firstMatch(raw);
    if (match == null) {
      throw SkillFormatException(
        'SKILL.md must start with a YAML frontmatter block delimited by ---',
      );
    }

    dynamic frontmatter;
    try {
      frontmatter = loadYaml(match.group(1) ?? '');
    } on YamlException catch (error) {
      throw SkillFormatException('Invalid YAML frontmatter: ${error.message}');
    }

    if (frontmatter is! Map) {
      throw SkillFormatException('Frontmatter must be a YAML mapping');
    }

    // Third-party skills often use human-readable names ("PDF Processing").
    // Normalise them instead of rejecting the whole skill.
    final name = _slugify(_text(frontmatter['name']) ?? fallbackName ?? '');
    if (name.isEmpty) {
      throw SkillFormatException(
        'Invalid skill name: use letters, numbers and hyphens.',
      );
    }

    final description = _text(frontmatter['description']) ?? '';
    if (description.isEmpty) {
      throw SkillFormatException('Skill "$name" is missing a description');
    }
    if (description.length > 1024) {
      throw SkillFormatException(
        'Skill "$name" description exceeds 1024 characters',
      );
    }

    final body = raw.substring(match.end).trim();
    if (body.isEmpty) {
      throw SkillFormatException('Skill "$name" has no instructions');
    }

    return ParsedSkill(
      name: name,
      description: description,
      body: body,
      triggers: _triggers(frontmatter['triggers']),
    );
  }

  static List<String> _triggers(dynamic value) {
    final raw = <String>[];
    if (value is Iterable) {
      for (final item in value) {
        final text = _text(item);
        if (text != null) raw.add(text);
      }
    } else {
      final text = _text(value);
      if (text != null) raw.addAll(text.split(','));
    }

    return raw
        .map((item) => _slugify(item).replaceAll('-', ' '))
        .where((item) => item.isNotEmpty)
        .toSet()
        .take(20)
        .toList();
  }

  static String _slugify(String raw) {
    var name = raw.trim().toLowerCase();
    name = name.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    name = name.replaceAll(RegExp(r'-+'), '-');
    name = name.replaceAll(RegExp(r'^-+|-+$'), '');
    if (name.length > 64) {
      name = name.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
    }
    return name;
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().replaceAll(_xmlTag, '').trim();
    return text.isEmpty ? null : text;
  }
}
