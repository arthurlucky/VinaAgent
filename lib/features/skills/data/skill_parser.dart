import 'package:yaml/yaml.dart';

import '../domain/agent_skill.dart';

/// Parsed representation of a single `SKILL.md` file.
class ParsedSkill {
  const ParsedSkill({
    required this.name,
    required this.description,
    required this.body,
  });

  final String name;
  final String description;
  final String body;
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
  static final RegExp _validName = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');
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

    final name = _text(frontmatter['name']) ?? fallbackName?.trim() ?? '';
    if (!_validName.hasMatch(name)) {
      throw SkillFormatException(
        'Invalid skill name "$name": use lowercase letters, numbers and '
        'hyphens (max 64 characters)',
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
    );
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().replaceAll(_xmlTag, '').trim();
    return text.isEmpty ? null : text;
  }
}
