import '../../agent/domain/agent_tool.dart';
import 'skill_store.dart';

/// Agent tools that expose the skill library.
///
/// These tools implement Levels 2 and 3 of progressive disclosure: the system
/// prompt only carries skill metadata, the model pulls instructions and
/// reference files through these tools when a task actually needs them.
class SkillTools {
  const SkillTools._();

  static List<AgentTool> all({required SkillStore store}) => [
        listSkills(store),
        loadSkill(store),
        readSkillResource(store),
        createSkill(store),
      ];

  static AgentTool listSkills(SkillStore store) => AgentTool(
        name: 'list_skills',
        description:
            'Lists the AI skills installed on this device with their name, '
            'description and enabled state. Skills are reusable instruction '
            'packages (SKILL.md). Call this when the user asks what the agent '
            'can do or which skills are available.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description':
                  'Optional filter matched against skill name and description.',
            },
          },
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final query = (args['query'] as String? ?? '').trim().toLowerCase();
          final skills = await store.listSkills();
          final filtered = query.isEmpty
              ? skills
              : skills
                  .where((skill) =>
                      skill.name.contains(query) ||
                      skill.description.toLowerCase().contains(query))
                  .toList();

          if (filtered.isEmpty) {
            return query.isEmpty
                ? 'No skills installed yet. Use create_skill to add one.'
                : 'No skills match "$query".';
          }

          final buffer = StringBuffer('Installed skills (${filtered.length}):\n');
          for (final skill in filtered) {
            buffer.writeln('- ${skill.summary}');
          }
          return buffer.toString().trim();
        },
      );

  static AgentTool loadSkill(SkillStore store) => AgentTool(
        name: 'load_skill',
        description:
            'Loads the full instructions (Level 2) of an installed skill by '
            'name. Always call this before following a skill. Returns the '
            'SKILL.md body plus the reference files that can be read with '
            'read_skill_resource.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description': 'Skill name, for example "research-report".',
            },
          },
          'required': ['name'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final name = (args['name'] as String? ?? '').trim();
          if (name.isEmpty) return 'Error: "name" is required.';

          final skill = await store.findSkill(name);
          if (skill == null) {
            return 'Error: no skill named "$name". Call list_skills first.';
          }
          if (!skill.enabled) {
            return 'Skill "$name" is disabled by the user. Do not follow it; '
                'ask the user to enable it in Settings > Agent Skills.';
          }

          final buffer = StringBuffer()
            ..writeln('# Skill: ${skill.name}')
            ..writeln()
            ..writeln(skill.body);

          if (skill.resources.isNotEmpty) {
            buffer
              ..writeln()
              ..writeln('Reference files (use read_skill_resource):');
            for (final resource in skill.resources) {
              buffer.writeln('- $resource');
            }
          }
          return buffer.toString().trim();
        },
      );

  static AgentTool readSkillResource(SkillStore store) => AgentTool(
        name: 'read_skill_resource',
        description:
            'Reads a reference file bundled with a skill (Level 3), for example '
            '"references/template.md". Only read files listed by load_skill.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description': 'Skill name that owns the file.',
            },
            'path': {
              'type': 'string',
              'description': 'Relative path inside the skill directory.',
            },
          },
          'required': ['name', 'path'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final name = (args['name'] as String? ?? '').trim();
          final path = (args['path'] as String? ?? '').trim();
          if (name.isEmpty || path.isEmpty) {
            return 'Error: both "name" and "path" are required.';
          }

          final content = await store.readResource(name, path);
          if (content == null) {
            return 'Error: could not read "$path" from skill "$name".';
          }
          return content;
        },
      );

  static AgentTool createSkill(SkillStore store) => AgentTool(
        name: 'create_skill',
        description:
            'Creates a new reusable skill (SKILL.md) on the device. Use when the '
            'user asks to remember a workflow, or when you discover a repeatable '
            'procedure worth reusing. Provide a kebab-case name, a description '
            'that says what it does AND when to use it, and step-by-step '
            'markdown instructions.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description': 'Kebab-case skill name, e.g. "meeting-notes".',
            },
            'description': {
              'type': 'string',
              'description':
                  'What the skill does and when to use it (max 1024 chars).',
            },
            'instructions': {
              'type': 'string',
              'description': 'Markdown body with numbered workflow steps.',
            },
          },
          'required': ['name', 'description', 'instructions'],
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          try {
            final skill = await store.createSkill(
              name: args['name'] as String? ?? '',
              description: args['description'] as String? ?? '',
              instructions: args['instructions'] as String? ?? '',
            );
            return 'Created skill "${skill.name}" at ${skill.directory}. '
                'It is now listed in list_skills and will be offered to the '
                'model on future runs.';
          } catch (error) {
            return 'Error creating skill: $error';
          }
        },
      );
}
