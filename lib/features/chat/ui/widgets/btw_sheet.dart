import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/features/chat/application/btw_controller.dart';
import 'package:pocketstrike/features/chat/ui/widgets/markdown_message.dart';

/// Opens the ephemeral `/btw` side-question overlay.
Future<void> showBtwSheet(
  BuildContext context, {
  String? initialQuestion,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BtwSheet(initialQuestion: initialQuestion),
  );
}

class _BtwSheet extends ConsumerStatefulWidget {
  const _BtwSheet({this.initialQuestion});

  final String? initialQuestion;

  @override
  ConsumerState<_BtwSheet> createState() => _BtwSheetState();
}

class _BtwSheetState extends ConsumerState<_BtwSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuestion ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final question = widget.initialQuestion?.trim() ?? '';
      final notifier = ref.read(btwControllerProvider.notifier);
      notifier.reset();
      if (question.isNotEmpty) notifier.ask(question);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    HapticFeedback.lightImpact();
    ref.read(btwControllerProvider.notifier).ask(question);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final state = ref.watch(btwControllerProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.62,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: tokens.glassBorder, width: 0.8),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 15,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '/btw — side question',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Temporary answer. Not saved to this conversation.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.loading)
                  IconButton(
                    tooltip: 'Stop',
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    onPressed: () =>
                        ref.read(btwControllerProvider.notifier).cancel(),
                  ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (state.question.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: tokens.glassColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.glassBorder, width: 0.7),
                ),
                child: Text(
                  state.question,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                child: state.error != null
                    ? Text(
                        state.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      )
                    : state.answer.isEmpty
                        ? Center(
                            child: state.loading
                                ? const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  )
                                : Text(
                                    'Ask anything. The main agent keeps running '
                                    'and the conversation is untouched.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: tokens.textSecondary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                          )
                        : MarkdownMessage(text: state.answer),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ask a quick side question…',
                      hintStyle: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12.5,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: tokens.glassBorder, width: 0.8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: tokens.glassBorder, width: 0.8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _submit,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      size: 18,
                      color: tokens.onAccent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
