import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/features/artifacts/application/artifacts_controller.dart';
import 'package:pocketstrike/features/artifacts/domain/artifact.dart';

/// Browse versioned artifacts created by the agent.
class ArtifactsScreen extends ConsumerWidget {
  const ArtifactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artifacts = ref.watch(artifactsProvider);
    final tokens = context.glass;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Artifacts',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(artifactsProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(artifactsProvider);
          await ref.read(artifactsProvider.future);
        },
        child: artifacts.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(24),
            children: const [
              SizedBox(height: 80),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 60),
              Text('Could not load artifacts: $error'),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 60),
                  Icon(Icons.inventory_2_outlined,
                      size: 42, color: tokens.textSecondary),
                  const SizedBox(height: 12),
                  Text(
                    'No artifacts yet.\n\nAsk the agent to produce a document, '
                    'code file or HTML page with create_artifact, or let it '
                    'save substantial deliverables here instead of chat.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.textSecondary, height: 1.5),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final artifact = items[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: tokens.glassColor,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.glassBorder),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    leading: Icon(
                      _iconFor(artifact.type),
                      color: tokens.accent,
                    ),
                    title: Text(
                      artifact.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${artifact.type} · v${artifact.latest.number} · '
                      '${_date(artifact.updatedAt)}',
                      style: TextStyle(color: tokens.textSecondary, fontSize: 11.5),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtifactViewerScreen(artifact: artifact),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'markdown' => Icons.article_outlined,
        'html' => Icons.language,
        'code' => Icons.code,
        'json' => Icons.data_object,
        'csv' => Icons.table_chart_outlined,
        _ => Icons.description_outlined,
      };

  static String _date(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class ArtifactViewerScreen extends ConsumerStatefulWidget {
  const ArtifactViewerScreen({super.key, required this.artifact});

  final Artifact artifact;

  @override
  ConsumerState<ArtifactViewerScreen> createState() =>
      _ArtifactViewerScreenState();
}

class _ArtifactViewerScreenState extends ConsumerState<ArtifactViewerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _version;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _version = widget.artifact.latest.number;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _copy(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard.')),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${widget.artifact.title}"?'),
        content: const Text(
          'This removes every version of the artifact from the app sandbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(artifactStoreProvider).delete(widget.artifact.id);
    ref.invalidate(artifactsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final content = ref.watch(
      artifactVersionProvider(
        (id: widget.artifact.id, number: _version),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.artifact.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Copy version',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              final value = await content.whenData((v) => v).valueOrNull;
              if (value != null) await _copy(value);
            },
          ),
          IconButton(
            tooltip: 'Delete artifact',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Preview'),
            Tab(text: 'Code'),
            Tab(text: 'Versions'),
          ],
        ),
      ),
      body: content.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (text) => TabBarView(
          controller: _tabs,
          children: [
            _PreviewTab(artifact: widget.artifact, content: text),
            _CodeTab(
              artifact: widget.artifact,
              content: text,
              onCopy: () => _copy(text),
              tokens: tokens,
            ),
            _VersionsTab(
              artifact: widget.artifact,
              selected: _version,
              onSelect: (number) {
                setState(() => _version = number);
                _tabs.index = 0;
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTab extends StatelessWidget {
  const _PreviewTab({required this.artifact, required this.content});

  final Artifact artifact;
  final String content;

  @override
  Widget build(BuildContext context) {
    if (artifact.type == 'markdown') {
      return Markdown(
        data: content,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
        ),
      );
    }
    if (artifact.type == 'html') {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'HTML artifacts are stored as source. Use the Code tab to copy '
              'or edit the markup; previewing HTML in-app is disabled to avoid '
              'running untrusted scripts.',
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SelectableText(
          content,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
        ),
      ],
    );
  }
}

class _CodeTab extends StatelessWidget {
  const _CodeTab({
    required this.artifact,
    required this.content,
    required this.onCopy,
    required this.tokens,
  });

  final Artifact artifact;
  final String content;
  final VoidCallback onCopy;
  final GlassTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(
            children: [
              Text(
                artifact.type == 'code' && artifact.language.isNotEmpty
                    ? artifact.language
                    : artifact.type,
                style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            child: SelectableText(
              content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _VersionsTab extends StatelessWidget {
  const _VersionsTab({
    required this.artifact,
    required this.selected,
    required this.onSelect,
  });

  final Artifact artifact;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final version in artifact.versions.reversed)
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            selected: version.number == selected,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: version.number == selected
                  ? tokens.accent.withValues(alpha: 0.2)
                  : tokens.glassColor,
              child: Text(
                '${version.number}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            title: Text('Version ${version.number}'),
            subtitle: Text(
              version.note.isEmpty
                  ? _date(version.createdAt)
                  : '${_date(version.createdAt)} · ${version.note}',
              style: TextStyle(color: tokens.textSecondary, fontSize: 11.5),
            ),
            onTap: () => onSelect(version.number),
          ),
      ],
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
