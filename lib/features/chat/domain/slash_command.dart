/// A chat slash command such as `/skills` or `/skill code-review`.
class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    this.aliases = const [],
  });

  /// Command name without the leading slash.
  final String name;
  final String description;
  final List<String> aliases;

  String get usage => '/$name';

  bool matches(String prefix) =>
      name.startsWith(prefix) || aliases.any((alias) => alias.startsWith(prefix));
}

const List<SlashCommand> kSlashCommands = [
  SlashCommand(name: 'help', description: 'Show every slash command'),
  SlashCommand(name: 'skills', description: 'Browse installed skills'),
  SlashCommand(
    name: 'skill',
    description: 'Use a skill for the next message: /skill <name> [prompt]',
  ),
  SlashCommand(
    name: 'marketplace',
    description: 'Open the skill marketplace',
  ),
  SlashCommand(name: 'agent', description: 'Switch to Agent mode (tools + skills)'),
  SlashCommand(name: 'chat', description: 'Switch to plain Chat mode'),
  SlashCommand(name: 'local', description: 'Switch to an on-device local model'),
  SlashCommand(name: 'new', description: 'Start a new conversation'),
  SlashCommand(name: 'model', description: 'Open model settings'),
  SlashCommand(name: 'mcp', description: 'Open MCP server settings'),
  SlashCommand(
    name: 'image',
    description: 'Generate an image: /image <prompt>',
    aliases: ['img'],
  ),
];

/// Commands matching what the user has typed so far.
///
/// Returns an empty list once the command token is complete and a space has
/// been typed, so the popup does not cover the composer while writing args.
List<SlashCommand> slashCommandSuggestions(String input) {
  final text = input.trimLeft();
  if (!text.startsWith('/')) return const [];

  final token = text.substring(1);
  if (token.contains(RegExp(r'\s'))) return const [];

  final needle = token.toLowerCase();
  return kSlashCommands.where((command) => command.matches(needle)).toList();
}
