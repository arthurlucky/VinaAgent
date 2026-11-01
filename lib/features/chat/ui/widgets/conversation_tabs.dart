import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/glass_tokens.dart';
import '../../conversations/application/conversations_controller.dart';

/// Multi-conversation tab bar - switch between active conversations.
class ConversationTabs extends ConsumerWidget {
  const ConversationTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final currentId = ref.watch(currentConversationIdProvider);
    final tokens = context.glass;

    return conversations.when(
      loading: () => const SizedBox(height: 48, child: SizedBox.shrink()),
      error: (error, _) => const SizedBox.shrink(),
      data: (convs) {
        if (convs.length <= 1) return const SizedBox.shrink();

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: tokens.glassColor,
            border: Border(bottom: BorderSide(color: tokens.glassBorder)),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: convs.length + 1,
            itemBuilder: (context, index) {
              if (index == convs.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                    ),
                  ),
                );
              }

              final conv = convs[index];
              final isActive = currentId == conv.id;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Material(
                  color: isActive
                      ? tokens.secondary.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: () {
                      ref.read(currentConversationIdProvider.notifier).state =
                          conv.id;
                    },
                    onLongPress: () => _showOptions(context, ref, conv),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                conv.title.isEmpty ? 'Untitled' : conv.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isActive
                                      ? tokens.textPrimary
                                      : tokens.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showOptions(
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
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(context);
                final name = await _showRenameDialog(context, conv.title);
                if (name != null && context.mounted) {
                  await ref
                      .read(conversationActionsProvider)
                      .updateTitle(conv.id, name);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await ref
                    .read(conversationActionsProvider)
                    .deleteConversation(conv.id);
                ref.invalidate(conversationsProvider);
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
          decoration: const InputDecoration(labelText: 'Name'),
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
