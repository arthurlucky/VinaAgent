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
      throw const FormatException(
        'Use the owner/repo format, e.g. anthropics/skills',
      );
    }
    return MarketplaceSource(
      owner: parts[0].trim(),
      repo: parts[1].trim(),
      title: parts[1].trim(),
      description: 'Custom GitHub repository',
    );
  }
}

/// A single skill discovered in the SkillsMP catalog.
class MarketplaceSkill {
  const MarketplaceSkill({
    required this.source,
    required this.directory,
    required this.name,
    required this.description,
    this.branch = 'main',
    this.author = '',
    this.stars = 0,
    this.detailUrl = '',
    this.githubUrl = '',
  });

  final MarketplaceSource source;

  /// Folder that contains `SKILL.md`, relative to the repository root.
  final String directory;

  final String name;
  final String description;

  /// Branch named in the SkillsMP `githubUrl` (usually `main`/`master`).
  final String branch;

  final String author;
  final int stars;

  /// SkillsMP detail page.
  final String detailUrl;

  /// Exact GitHub tree/blob URL for this skill.
  final String githubUrl;

  String get slug =>
      directory.isEmpty ? source.repo : directory.split('/').last;

  String get id =>
      '${source.id}/${directory.isEmpty ? source.repo : directory}';

  MarketplaceSkill withDescription(String value) => MarketplaceSkill(
        source: source,
        directory: directory,
        name: name,
        description: value,
        branch: branch,
        author: author,
        stars: stars,
        detailUrl: detailUrl,
        githubUrl: githubUrl,
      );

  @override
  bool operator ==(Object other) => other is MarketplaceSkill && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Popular, public skill repositories kept as an offline fallback when the
/// SkillsMP API is unavailable.
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
    owner: 'microsoft',
    repo: 'azure-skills',
    title: 'Microsoft Azure',
    description: 'Azure diagnostics, cost, RBAC and deployment skills.',
  ),
];
