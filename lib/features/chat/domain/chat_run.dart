import 'package:pocketstrike/core/models/chat_models.dart';
import 'package:pocketstrike/features/agent/domain/agent_event.dart';

/// A user message waiting for the current agent run to finish.
///
/// Vina Agent never blocks the composer while a run is active. New messages
/// are appended to this queue ("delay message task") and dispatched one by one
/// when the active run completes.
class QueuedChatMessage {
  const QueuedChatMessage({
    required this.id,
    required this.text,
    this.attachments = const [],
    this.activeSkillName,
    required this.queuedAt,
  });

  final String id;
  final String text;
  final List<AttachmentMeta> attachments;
  final String? activeSkillName;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        if (activeSkillName != null) 'activeSkillName': activeSkillName,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory QueuedChatMessage.fromJson(Map<String, dynamic> json) =>
      QueuedChatMessage(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        attachments: [
          for (final raw in (json['attachments'] as List<dynamic>? ?? const []))
            AttachmentMeta.fromJson(raw as Map<String, dynamic>),
        ],
        activeSkillName: json['activeSkillName'] as String?,
        queuedAt: DateTime.tryParse(json['queuedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Live state of one conversation run.
///
/// Each conversation owns an independent run, so the user can keep chatting in
/// conversation B while conversation A is still streaming.
class ChatRunState {
  const ChatRunState({
    this.conversationId,
    this.isGenerating = false,
    this.isGeneratingImage = false,
    this.imageGenerationPrompt,
    this.streamingText = '',
    this.tokensPerSecond,
    this.tokenCount,
    this.status,
    this.error,
    this.runId,
    this.steps = const [],
    this.queued = const [],
  });

  final String? conversationId;
  final bool isGenerating;
  final bool isGeneratingImage;
  final String? imageGenerationPrompt;
  final String streamingText;
  final double? tokensPerSecond;
  final int? tokenCount;
  final String? status;
  final String? error;
  final String? runId;
  final List<AgentStep> steps;
  final List<QueuedChatMessage> queued;

  /// True when this conversation has something the UI should render.
  bool get hasActivity =>
      isGenerating ||
      isGeneratingImage ||
      streamingText.isNotEmpty ||
      steps.isNotEmpty ||
      status != null ||
      error != null ||
      runId != null;

  ChatRunState copyWith({
    String? conversationId,
    bool? isGenerating,
    bool? isGeneratingImage,
    String? imageGenerationPrompt,
    bool clearImagePrompt = false,
    String? streamingText,
    double? tokensPerSecond,
    bool clearTokensPerSecond = false,
    int? tokenCount,
    String? status,
    bool clearStatus = false,
    String? error,
    bool clearError = false,
    String? runId,
    bool clearRunId = false,
    List<AgentStep>? steps,
    List<QueuedChatMessage>? queued,
  }) {
    return ChatRunState(
      conversationId: conversationId ?? this.conversationId,
      isGenerating: isGenerating ?? this.isGenerating,
      isGeneratingImage: isGeneratingImage ?? this.isGeneratingImage,
      imageGenerationPrompt: clearImagePrompt
          ? null
          : (imageGenerationPrompt ?? this.imageGenerationPrompt),
      streamingText: streamingText ?? this.streamingText,
      tokensPerSecond: clearTokensPerSecond
          ? null
          : (tokensPerSecond ?? this.tokensPerSecond),
      tokenCount: tokenCount ?? this.tokenCount,
      status: clearStatus ? null : (status ?? this.status),
      error: clearError ? null : (error ?? this.error),
      runId: clearRunId ? null : (runId ?? this.runId),
      steps: steps ?? this.steps,
      queued: queued ?? this.queued,
    );
  }

  /// Resets everything except the queue (used between chained runs).
  ChatRunState idle() => ChatRunState(
        conversationId: conversationId,
        queued: queued,
      );
}
