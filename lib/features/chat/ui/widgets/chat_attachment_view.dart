import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../app/theme/glass_tokens.dart';
import '../../../core/models/chat_models.dart';

/// Display file attachments in chat messages.
class ChatAttachmentView extends StatelessWidget {
  const ChatAttachmentView({
    super.key,
    required this.attachment,
    required this.onDelete,
  });

  final AttachmentMeta attachment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final isHtml = attachment.mimeType.contains('html');
    final isMarkdown = attachment.mimeType.contains('markdown') ||
        attachment.name.endsWith('.md');
    final isJson = attachment.mimeType.contains('json');
    final isImage =
        attachment.mimeType.startsWith('image/');

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
            child: Row(
              children: [
                Icon(_iconFor(attachment.mimeType), size: 18, color: tokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        _sizeDisplay(attachment.sizeBytes ?? 0),
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          if (isImage) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                child: Image.file(
                  File(attachment.path),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
          if (isMarkdown || isHtml || isJson) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.maxFinite,
                child: _ContentPreview(
                  path: attachment.path,
                  mimeType: attachment.mimeType,
                  isMarkdown: isMarkdown,
                  isHtml: isHtml,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static IconData _iconFor(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mimeType.contains('video')) return Icons.video_library_outlined;
    if (mimeType.contains('audio')) return Icons.audio_file_outlined;
    if (mimeType.contains('markdown') || mimeType.contains('text')) {
      return Icons.description_outlined;
    }
    if (mimeType.contains('json') || mimeType.contains('xml')) {
      return Icons.data_object;
    }
    return Icons.attachment_outlined;
  }

  static String _sizeDisplay(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ContentPreview extends StatefulWidget {
  const _ContentPreview({
    required this.path,
    required this.mimeType,
    required this.isMarkdown,
    required this.isHtml,
  });

  final String path;
  final String mimeType;
  final bool isMarkdown;
  final bool isHtml;

  @override
  State<_ContentPreview> createState() => _ContentPreviewState();
}

class _ContentPreviewState extends State<_ContentPreview> {
  late Future<String> _content;

  @override
  void initState() {
    super.initState();
    _content = File(widget.path).readAsString();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;

    return FutureBuilder<String>(
      future: _content,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          return Text(
            'Error reading file: ${snapshot.error}',
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
          );
        }

        final content = snapshot.data ?? '';
        final preview = content.length > 500
            ? '${content.substring(0, 500)}...'
            : content;

        if (widget.isMarkdown) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.secondary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              child: Markdown(
                data: preview,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ),
          );
        }

        if (widget.isHtml) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.secondary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: SelectableText(
                preview,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tokens.secondary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            child: SelectableText(
              preview,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        );
      },
    );
  }
}
