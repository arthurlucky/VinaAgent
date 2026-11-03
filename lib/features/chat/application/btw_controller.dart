import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/core/db/app_database.dart';
import 'package:pocketstrike/core/models/chat_models.dart';
import 'package:pocketstrike/features/conversations/application/conversations_controller.dart';
import 'package:pocketstrike/features/providers/application/providers_controller.dart';
import 'package:pocketstrike/features/providers/domain/ai_provider.dart';
import 'package:pocketstrike/features/providers/domain/provider_types.dart';

/// State of a `/btw` side question.
///
/// The answer is intentionally ephemeral: it is streamed to the overlay and
/// never persisted to the conversation or sent back to the main model.
class BtwState {
  const BtwState({
    this.question = '',
    this.answer = '',
    this.loading = false,
    this.error,
    this.model,
  });

  final String question;
  final String answer;
  final bool loading;
  final String? error;
  final String? model;

  bool get hasContent => answer.isNotEmpty || loading || error != null;

  BtwState copyWith({
    String? question,
    String? answer,
    bool? loading,
    String? error,
    bool clearError = false,
    String? model,
  }) {
    return BtwState(
      question: question ?? this.question,
      answer: answer ?? this.answer,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      model: model ?? this.model,
    );
  }
}

/// Answers "by the way" questions in an isolated stream.
///
/// This runs completely independently from [ChatController], so it works even
/// while the main agent is busy and never interrupts the current run.
class BtwController extends StateNotifier<BtwState> {
  BtwController(this.ref) : super(const BtwState());

  final Ref ref;
  CancelToken? _cancelToken;

  Future<void> ask(String question, {String? conversationId}) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    _cancelToken?.cancel('New side question');
    final token = CancelToken();
    _cancelToken = token;
    state = BtwState(question: trimmed, loading: true);

    try {
      final resolved = await _resolveProvider();
      if (resolved == null) return;
      final (provider, model, params) = resolved;

      final history = await _buildHistory(conversationId, trimmed);
      final buffer = StringBuffer();

      await for (final event in provider.streamMessage(ChatRequest(
        messages: history,
        model: model,
        params: params,
        cancelToken: token,
      ))) {
        if (event is TextDeltaEvent) {
          buffer.write(event.text);
          state = state.copyWith(answer: buffer.toString(), loading: true);
        } else if (event is StreamErrorEvent) {
          state = state.copyWith(error: event.message, loading: false);
          return;
        }
        if (token.isCancelled) break;
      }

      if (!token.isCancelled) {
        state = state.copyWith(answer: buffer.toString(), loading: false);
      }
    } catch (error) {
      state = state.copyWith(error: error.toString(), loading: false);
    }
  }

  void cancel() {
    _cancelToken?.cancel('Side question dismissed');
    state = state.copyWith(loading: false);
  }

  void reset() {
    _cancelToken?.cancel('Side question dismissed');
    state = const BtwState();
  }

  Future<(AIProvider, String, GenerationParams)?> _resolveProvider() async {
    final config = await ref.read(activeProviderConfigProvider.future);
    if (config == null) {
      state = state.copyWith(
        error: 'No AI provider configured. Add one in Settings first.',
        loading: false,
      );
      return null;
    }
    final provider = await ref
        .read(providerResolverProvider)
        .resolve(configId: config.id);
    if (provider == null) {
      state = state.copyWith(
        error: 'Failed to initialize the AI provider.',
        loading: false,
      );
      return null;
    }
    var model = config.defaultModel.trim();
    if (model.isEmpty) {
      model = ProviderTypeX.fromId(config.type).suggestedModels.first;
    }
    final params =
        await ref.read(providerResolverProvider).paramsFor(provider.configId);
    state = state.copyWith(model: model);
    return (provider, model, params);
  }

  Future<List<ChatMessage>> _buildHistory(
    String? conversationId,
    String question,
  ) async {
    final id = conversationId ?? ref.read(currentConversationIdProvider);
    final history = <ChatMessage>[];

    if (id != null) {
      final rows = await ref
          .read(appDatabaseProvider)
          .messagesDao
          .getForConversation(id);
      final recent = rows.where((m) => m.role != 'tool').toList();
      final start = recent.length > 12 ? recent.length - 12 : 0;
      for (final row in recent.sublist(start)) {
        final role = MessageRole.values
                .where((r) => r.name == row.role)
                .firstOrNull ??
            MessageRole.user;
        if (role == MessageRole.system) continue;
        history.add(
          ChatMessage(
            id: row.id,
            role: role,
            content: row.content,
            createdAt: row.createdAt,
          ),
        );
      }
    }

    const instruction = 'You are Vina Agent answering a quick "by the way" '
        'side question. Answer directly and concisely. The recent conversation '
        'is background context only: do not continue the main task, do not call '
        'tools, and do not pretend to change any files.';

    return [
      ChatMessage(
        id: 'btw-system',
        role: MessageRole.system,
        content: instruction,
        createdAt: DateTime.now(),
      ),
      ...history,
      ChatMessage(
        id: 'btw-question',
        role: MessageRole.user,
        content: question,
        createdAt: DateTime.now(),
      ),
    ];
  }
}

final btwControllerProvider =
    StateNotifierProvider<BtwController, BtwState>((ref) {
  return BtwController(ref);
});
