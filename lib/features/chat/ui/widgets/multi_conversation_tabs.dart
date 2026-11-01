import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/glass_tokens.dart';
import '../../../core/db/app_database.dart';
import '../../conversations/application/conversations_controller.dart';

/// Horizontal tab bar untuk multi-conversation switching.
/// Menampilkan conversation list sebagai tabs dengan New button.
class MultiConversationTabs extends ConsumerWidget {
  const MultiConversationTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final currentId = ref.watch(currentConversationIdProvider);
    final tokens = context.glass;

    return conversations.when(
      loading: () => SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => const SizedBox.shrink(),
      data: (convs) {
        if (convs.length <= 1) return const SizedBox.shrink();

        return Container(
          height: 50,
          decoration: BoxDecoration(
            color: tokens.glassColor,
            border: Border(
              bottom: BorderSide(color: tokens.glassBorder, width: 0.5),
            ),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemCount: convs.length + 1,
            itemBuilder: (context, index) {
              if (index == convs.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(conversationActionsProvider)
                          .ensureActiveConversation();
                      ref.invalidate(conversationsProvider);
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                );
              }

              final conv = convs[index];
              final isActive = currentId == conv.id;

              return _ConversationTab(
                conversation: conv,
                isActive: isActive,
                onTap: () {
                  ref.read(currentConversationIdProvider.notifier).state =
                      conv.id;
                },
                onMenuTap: () => _showMenu(context, ref, conv),
                tokens: tokens,
              );
            },
          ),
        );
      },
    );
  }

  void _showMenu(
    BuildContext context,
    WidgetRef ref,
    Conversation conv,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(context);
                final name = await _showRenameDialog(context, conv.title);
                if (name != null && name.isNotEmpty) {
                  await ref
                      .read(conversationActionsProvider)
                      .updateTitle(conv.id, name);
                  ref.invalidate(conversationsProvider);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, size: 20),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
              textColor: Colors.red,
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete conversation?'),
                    content: Text(
                      'Conversation "${conv.title}" will be permanently deleted.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await ref
                      .read(conversationActionsProvider)
                      .deleteConversation(conv.id);
                  ref.invalidate(conversationsProvider);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showRenameDialog(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Conversation name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ConversationTab extends StatelessWidget {
  const _ConversationTab({
    required this.conversation,
    required this.isActive,
    required this.onTap,
    required this.onMenuTap,
    required this.tokens,
  });

  final Conversation conversation;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onMenuTap;
  final GlassTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMenuTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? tokens.secondary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isActive
                ? Border.all(color: tokens.secondary.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  conversation.title.isEmpty
                      ? 'Untitled'
                      : conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive ? tokens.textPrimary : tokens.textSecondary,
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: Icon(
                    Icons.check_circle,
                    size: 12,
                    color: tokens.secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
