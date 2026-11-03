import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/chat_run.dart';

/// Tracks every in-flight conversation run independently.
///
/// The old single global `isGenerating` flag blocked the whole app while one
/// conversation was streaming. The registry keys state by conversation id so
/// multiple runs can coexist and the UI can render the run that belongs to the
/// currently open conversation.
class ChatRunRegistry extends ChangeNotifier {
  final Map<String, ChatRunState> _runs = {};

  ChatRunState stateFor(String? conversationId) {
    if (conversationId == null) return const ChatRunState();
    return _runs[conversationId] ?? ChatRunState(conversationId: conversationId);
  }

  bool isRunning(String conversationId) =>
      _runs[conversationId]?.isGenerating ?? false;

  bool get hasActiveRuns => _runs.values.any((run) => run.isGenerating);

  List<ChatRunState> get activeRuns =>
      _runs.values.where((run) => run.isGenerating).toList(growable: false);

  void update(String conversationId, ChatRunState state) {
    _runs[conversationId] = state.copyWith(conversationId: conversationId);
    notifyListeners();
  }

  void enqueue(String conversationId, QueuedChatMessage message) {
    final current = stateFor(conversationId);
    update(
      conversationId,
      current.copyWith(queued: [...current.queued, message]),
    );
  }

  QueuedChatMessage? dequeue(String conversationId) {
    final current = stateFor(conversationId);
    if (current.queued.isEmpty) return null;
    final next = current.queued.first;
    update(
      conversationId,
      current.copyWith(queued: current.queued.sublist(1)),
    );
    return next;
  }

  void clear(String conversationId) {
    if (_runs.remove(conversationId) != null) notifyListeners();
  }
}

final chatRunRegistryProvider =
    ChangeNotifierProvider<ChatRunRegistry>((ref) => ChatRunRegistry());
