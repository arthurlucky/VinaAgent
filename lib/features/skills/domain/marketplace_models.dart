/// A GitHub repository that publishes Agent Skills.
class MarketplaceSource {
  const MarketplaceSource({
    required this.owner,
    required this.repo,
    required this.title,
    required this.description,
  });

  final String owner;
  final String repo;
  final String title;
  final String description;

  String get id => '$owner/$repo';
  String get url => 'https://github.com/$owner/$repo';

  @override
  bool operator ==(Object other) =>
      other is MarketplaceSource && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Parses `owner/repo` typed by the user.
  factory MarketplaceSource.parse(String value) {
    final parts = value.trim().split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw const FormatException('Use the owner/repo format, e.g. anthropics/skills');
    }
    return MarketplaceSource(
      owner: parts[0].trim(),
      repo: parts[1].trim(),
      title: parts[1].trim(),
      description: 'Custom GitHub repository',
    );
  }
}

/// A single skill discovered inside a marketplace source.
class MarketplaceSkill {
  const MarketplaceSkill({
    required this.source,
    required this.directory,
    required this.name,
    required this.description,
  });

  final MarketplaceSource source;

  /// Folder that contains `SKILL.md`, relative to the repository root.
  final String directory;

  final String name;
  final String description;

  String get slug =>
      directory.isEmpty ? source.repo : directory.split('/').last;

  String get id => '${source.id}/$slug';

  MarketplaceSkill withDescription(String value) => MarketplaceSkill(
        source: source,
        directory: directory,
        name: name,
        description: value,
      );

  @override
  bool operator ==(Object other) => other is MarketplaceSkill && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Popular, public skill repositories. These are the upstreams that
/// marketplaces such as skills.sh and ClawHub index.
const List<MarketplaceSource> kFeaturedSkillSources = [
  MarketplaceSource(
    owner: 'anthropics',
    repo: 'skills',
    title: 'Anthropic Skills',
    description:
        'Official Agent Skills: documents, design, MCP and enterprise workflows.',
  ),
  MarketplaceSource(
    owner: 'vercel-labs',
    repo: 'skills',
    title: 'Vercel Labs',
    description: 'find-skills and web development workflows from Vercel.',
  ),
  MarketplaceSource(
    owner: 'obra',
    repo: 'superpowers',
    title: 'Superpowers',
    description: 'Brainstorming, TDD, debugging and planning workflows.',
  ),
  MarketplaceSource(
    owner: 'mattpocock',
    repo: 'skills',
    title: 'Matt Pocock',
    description: 'TypeScript, code review, TDD and refactoring skills.',
  ),
  MarketplaceSource(
    owner: 'microsoft',
    repo: 'azure-skills',
    title: 'Microsoft Azure',
    description: 'Azure diagnostics, cost, RBAC and deployment skills.',
  ),
  MarketplaceSource(
    owner: 'supabase',
    repo: 'agent-skills',
    title: 'Supabase',
    description: 'Postgres and Supabase best practices.',
  ),
  MarketplaceSource(
    owner: 'prisma',
    repo: 'skills',
    title: 'Prisma',
    description: 'Prisma ORM, migrations and database setup.',
  ),
  MarketplaceSource(
    owner: 'remotion-dev',
    repo: 'skills',
    title: 'Remotion',
    description: 'Programmatic video creation with React.',
  ),
  MarketplaceSource(
    owner: 'emilkowalski',
    repo: 'skills',
    title: 'Emil Kowalski',
    description: 'Animation and interface design craft.',
  ),
];
