import 'dart:io';
import 'package:pocketstrike/core/storage/app_sandbox.dart';
import 'package:pocketstrike/features/agent/domain/agent_tool.dart';

/// Document Converter & Text Extraction Tools.
class DocumentAgentTools {
  const DocumentAgentTools._();

  static List<AgentTool> all({required List<String> allowedRoots}) => [
        extractTextFromFile(allowedRoots),
        formatMarkdownDocument(),
      ];

  static AgentTool extractTextFromFile(List<String> allowedRoots) => AgentTool(
        name: 'extract_text_from_file',
        description: 'Parses text, markdown, JSON, or code files and extracts clean structured content.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'filePath': {
              'type': 'string',
              'description': 'Sandbox path of the file to parse (e.g. "Downloads/report.txt").',
            },
          },
          'required': ['filePath'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final pathStr = args['filePath'] as String? ?? '';
          if (pathStr.isEmpty) return 'Error: File path is empty.';
          final resolved = AppSandbox.resolveWithRoot(
            pathStr,
            allowedRoots.isEmpty ? '' : allowedRoots.first,
          );
          if (resolved == null ||
              !AppSandbox.isAllowed(resolved, allowedRoots)) {
            return 'Error: Access denied. Files must be inside the app sandbox.';
          }
          final file = File(resolved);
          if (!await file.exists()) {
            return 'Error: Document "$resolved" not found.';
          }
          final content = await file.readAsString();
          return 'Extracted Document (${content.length} characters):\n---\n$content';
        },
      );

  static AgentTool formatMarkdownDocument() => AgentTool(
        name: 'format_markdown_document',
        description: 'Formats raw text or structured notes into GitHub Flavored Markdown.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Document title header.',
            },
            'body': {
              'type': 'string',
              'description': 'Main document content.',
            },
          },
          'required': ['title', 'body'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final title = args['title'] as String? ?? 'Document';
          final body = args['body'] as String? ?? '';
          return '# $title\n\n$body\n\n---\n*Formatted by Vina Agent*';
        },
      );
}
