import '../../agent/domain/agent_tool.dart';
import '../domain/agent_skill.dart';
import '../domain/marketplace_models.dart';
import 'github_marketplace_client.dart';
import 'skill_quality_gate.dart';
import 'skill_store.dart';
import 'skillsmp_client.dart';

/// Agent tools that expose the skill library.
///
/// These tools implement Levels 2 and 3 of progressive disclosure: the system
/// prompt only carries skill metadata, the model pulls instructions and
/// reference files through these tools when a task actually needs them.
class SkillTools {
  const SkillTools._();

  static List<AgentTool> all({
    required SkillStore store,
    GithubMarketplaceClient? marketplace,
    SkillsMpClient? skillsMp,
  }) =>
      [
        listSkills(store),
        loadSkill(store),
        readSkillResource(store),
        createSkill(store),
        if (skillsMp != null) searchMarketplace(skillsMp),
        if (marketplace != null) installMarketplaceSkill(marketplace, store),
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
            'Drafts a new reusable skill (SKILL.md) and submits it to the '
            'quality gate. Passing drafts are stored as PENDING and require '
            'user approval in Settings → Agent Skills before activation. '
            'Provide a kebab-case name, a description that says what it does '
            'AND when to use it, and instructions with ## When to use, '
            '## Steps (3+), ## Verification and ## Failure modes.',
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
            'triggers': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Optional activation keywords (any language).',
            },
          },
          'required': ['name', 'description', 'instructions'],
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          final triggers = (args['triggers'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList();
          final draft = SkillDraft(
            name: args['name'] as String? ?? '',
            description: args['description'] as String? ?? '',
            body: args['instructions'] as String? ?? '',
            triggers: triggers,
          );
          final existing = await store.listSkills();
          final report = SkillQualityGate.evaluate(draft, existing: existing);
          if (report.errors.isNotEmpty) {
            return 'Rejected by the skill quality gate '
                '(score ${report.score}/100):\n'
                '- ${report.errors.join('\n- ')}\n'
                'Improve the draft and call create_skill again.';
          }

          await store.addPending(PendingSkill(
            id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
            name: draft.name,
            description: draft.description,
            body: draft.body,
            triggers: draft.triggers,
            source: 'agent',
            score: report.score,
            createdAt: DateTime.now(),
            reason: 'Drafted by the agent during a run.',
          ));
          return 'Draft "${draft.name}" passed the quality gate '
              '(score ${report.score}/100) and is waiting for approval in '
              'Settings → Agent Skills. It is not active yet.';
        },
      );

  static AgentTool searchMarketplace(SkillsMpClient client) => AgentTool(
        name: 'search_skill_marketplace',
        description:
            'Searches SkillsMP (skillsmp.com), the public catalog of 3M+ Agent '
            'Skills. Returns skill name, GitHub repository, folder, stars and '
            'the exact github_url needed by install_marketplace_skill.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Search words, e.g. "pdf" or "code review".',
            },
            'limit': {
              'type': 'integer',
              'description': 'Optional result count (1-20).',
            },
          },
          'required': ['query'],
        },
        risk: ToolRisk.external,
        run: (args) async {
          final query = (args['query'] as String? ?? '').trim();
          if (query.isEmpty) return 'Error: "query" is required.';
          final rawLimit = args['limit'];
          final limit = rawLimit is num ? rawLimit.toInt().clamp(1, 20) : 12;

          try {
            final page = await client.search(query, limit: limit);
            if (page.skills.isEmpty) {
              return 'No SkillsMP skills match "$query".';
            }

            final buffer = StringBuffer('SkillsMP results for "$query":\n');
            for (final skill in page.skills) {
              buffer.writeln(
                '- ${skill.name} by ${skill.author} '
                '[${skill.source.id}/${skill.directory}] '
                '★${skill.stars} — ${skill.description}',
              );
              buffer.writeln('  github_url: ${skill.githubUrl}');
            }
            buffer.writeln(
              '\nInstall one with install_marketplace_skill '
              '(github_url + name + description).',
            );
            return buffer.toString().trim();
          } on SkillsMpException catch (error) {
            return 'SkillsMP search failed: ${error.message}';
          } catch (error) {
            return 'SkillsMP search failed: $error';
          }
        },
      );

  static AgentTool installMarketplaceSkill(
    GithubMarketplaceClient client,
    SkillStore store,
  ) =>
      AgentTool(
        name: 'install_marketplace_skill',
        description:
            'Downloads a skill from SkillsMP/GitHub and installs it on this '
            'device. Prefer the exact github_url returned by '
            'search_skill_marketplace. Installed skills become available to '
            'load_skill.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'github_url': {
              'type': 'string',
              'description':
                  'Exact GitHub tree URL from SkillsMP, e.g. '
                  '"https://github.com/owner/repo/tree/main/skills/pdf".',
            },
            'name': {
              'type': 'string',
              'description': 'Skill name from the search result.',
            },
            'description': {
              'type': 'string',
              'description': 'Short description from the search result.',
            },
            'source': {
              'type': 'string',
              'description':
                  'Fallback repository "owner/repo" when github_url is absent.',
            },
            'slug': {
              'type': 'string',
              'description': 'Fallback skill slug inside the repository.',
            },
          },
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          final githubUrl = (args['github_url'] as String? ?? '').trim();
          final sourceId = (args['source'] as String? ?? '').trim();
          final slug = (args['slug'] as String? ?? '').trim();

          try {
            if (githubUrl.isNotEmpty) {
              final parsed = SkillsMpClient.parseGithubUrl(githubUrl);
              if (parsed == null) {
                return 'Error: github_url is not a valid GitHub URL.';
              }
              final name = (args['name'] as String? ?? '').trim();
              final skill = MarketplaceSkill(
                source: parsed.source,
                directory: parsed.directory,
                branch: parsed.branch,
                name: name.isEmpty ? parsed.directory.split('/').last : name,
                description: (args['description'] as String? ?? '').trim(),
                githubUrl: githubUrl,
              );
              final installed = await client.install(skill, store);
              return 'Installed "${installed.name}" from ${skill.source.id}. '
                  'It is now available to load_skill.';
            }

            if (sourceId.isEmpty || slug.isEmpty) {
              return 'Error: provide github_url, or source + slug.';
            }
            final installed = await client.installBySlug(sourceId, slug, store);
            return 'Installed "${installed.name}" from $sourceId. '
                'It is now available to load_skill.';
          } catch (error) {
            return 'Install failed: $error';
          }
        },
      );
}
