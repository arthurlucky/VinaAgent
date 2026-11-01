import '../../agent/domain/agent_tool.dart';
import 'artifact_store.dart';

/// Agent tools for versioned artifacts (documents, code, HTML, data).
class ArtifactTools {
  const ArtifactTools._();

  static List<AgentTool> all({required ArtifactStore store}) => [
        createArtifact(store),
        updateArtifact(store),
        listArtifacts(store),
      ];

  static AgentTool createArtifact(ArtifactStore store) => AgentTool(
        name: 'create_artifact',
        description:
            'Creates a versioned artifact (markdown document, code file, HTML '
            'page, JSON or CSV) that the user can open in Settings → Artifacts. '
            'Use this for substantial deliverables instead of pasting a long '
            'document into chat. Returns the artifact id.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Human-readable artifact title.',
            },
            'type': {
              'type': 'string',
              'enum': ['markdown', 'html', 'code', 'text', 'json', 'csv'],
            },
            'content': {
              'type': 'string',
              'description': 'Full artifact content.',
            },
            'language': {
              'type': 'string',
              'description': 'Language for type=code, e.g. dart or python.',
            },
            'note': {
              'type': 'string',
              'description': 'Optional version note.',
            },
          },
          'required': ['title', 'type', 'content'],
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          try {
            final artifact = await store.create(
              title: args['title'] as String? ?? '',
              type: args['type'] as String? ?? 'markdown',
              content: args['content'] as String? ?? '',
              language: args['language'] as String? ?? '',
              note: args['note'] as String? ?? '',
            );
            return 'Artifact created: "${artifact.title}" '
                '(id: ${artifact.id}, v${artifact.latest.number}). '
                'Open it in Settings → Artifacts.';
          } catch (error) {
            return 'Could not create artifact: $error';
          }
        },
      );

  static AgentTool updateArtifact(ArtifactStore store) => AgentTool(
        name: 'update_artifact',
        description:
            'Adds a new version to an existing artifact. Use after create_artifact '
            'when the user asks for changes; previous versions are preserved.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'id': {
              'type': 'string',
              'description': 'Artifact id returned by create_artifact.',
            },
            'content': {
              'type': 'string',
              'description': 'Full new content for this version.',
            },
            'note': {
              'type': 'string',
              'description': 'What changed in this version.',
            },
          },
          'required': ['id', 'content'],
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          try {
            final artifact = await store.update(
              id: args['id'] as String? ?? '',
              content: args['content'] as String? ?? '',
              note: args['note'] as String? ?? '',
            );
            return 'Updated "${artifact.title}" to v${artifact.latest.number}.';
          } catch (error) {
            return 'Could not update artifact: $error';
          }
        },
      );

  static AgentTool listArtifacts(ArtifactStore store) => AgentTool(
        name: 'list_artifacts',
        description: 'Lists artifacts saved on this device with version counts.',
        inputSchema: const {
          'type': 'object',
          'properties': <String, dynamic>{},
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final artifacts = await store.list();
          if (artifacts.isEmpty) return 'No artifacts yet.';
          final buffer = StringBuffer('Artifacts (${artifacts.length}):\n');
          for (final artifact in artifacts) {
            buffer.writeln(
              '- ${artifact.title} (id: ${artifact.id}, '
              '${artifact.type}, v${artifact.latest.number})',
            );
          }
          return buffer.toString().trim();
        },
      );
}
