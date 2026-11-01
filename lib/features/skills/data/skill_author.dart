import 'dart:convert';

import '../../../core/models/chat_models.dart';
import '../../providers/domain/ai_provider.dart';
import '../domain/agent_skill.dart';
import 'skill_quality_gate.dart';

class SkillAuthorResult {
  const SkillAuthorResult({required this.draft, required this.report});

  final SkillDraft draft;
  final SkillQualityReport report;
}

/// Uses the active model to draft professional, reusable Agent Skills.
///
/// The model returns structured JSON; Vina renders the markdown itself and
/// runs the quality gate before anything is stored. This prevents the
/// "generic AI skill" problem: no free-form fluff can reach the library.
class SkillAuthor {
  const SkillAuthor();

  static const String _systemPrompt = '''
You are Vina Agent's senior skill librarian. You write reusable Agent Skills
that follow the Anthropic SKILL.md format. Output STRICT JSON only — no
markdown fences, no commentary.

JSON schema:
{
  "skip": false,
  "name": "kebab-case-name",
  "description": "What it does. Use when ...",
  "triggers": ["keyword", "keyword"],
  "when_to_use": "Concrete situations and user phrasings.",
  "prerequisites": ["required tool, file or context"],
  "steps": ["imperative step 1", "imperative step 2", "imperative step 3"],
  "verification": ["how to prove the task succeeded"],
  "failure_modes": ["what can go wrong and how to recover"],
  "example": "A short concrete example."
}

Hard rules:
- Name: lowercase kebab-case, 3-48 chars, unique.
- Description: 40-1024 chars, must contain "Use when".
- At least 3 numbered-style steps, each specific and actionable.
- Mention real Vina tools where relevant: load_skill, list_skills,
  read_skill_resource, create_skill, read_file, write_file, list_files,
  search_files, web_search, code_sandbox, generate_image,
  extract_text_from_file, create_artifact, delegate_task.
- No TODO/TBD/placeholders, no API keys, no generic advice, no invented tools.
- Prefer a narrow workflow over a broad "be helpful" essay.
- If the request is too vague to produce a genuinely reusable skill, return
  {"skip": true, "reason": "..."}.
''';

  Future<SkillAuthorResult?> draftFromPrompt({
    required AIProvider provider,
    required String model,
    required String request,
    List<AgentSkill> existing = const [],
    bool reflection = false,
  }) async {
    final trimmed = request.trim();
    if (trimmed.isEmpty) return null;

    final prompt = reflection
        ? 'Review this completed agent run. Create a skill ONLY if it contains '
            'a reusable, non-obvious procedure worth repeating. Otherwise '
            'return {"skip": true, "reason": "..."}.\n\n$trimmed'
        : 'Create the best possible Agent Skill for this request:\n\n$trimmed';

    final text = await _complete(
      provider: provider,
      model: model,
      system: _systemPrompt,
      user: prompt,
    );
    final json = _extractJson(text);
    if (json == null || json['skip'] == true) return null;

    final draft = SkillQualityGate.fromJson(json);
    if (draft == null) return null;

    return SkillAuthorResult(
      draft: draft,
      report: SkillQualityGate.evaluate(draft, existing: existing),
    );
  }

  Future<PendingSkill?> learnFromRun({
    required AIProvider provider,
    required String model,
    required String userRequest,
    required String transcript,
    List<AgentSkill> existing = const [],
    List<PendingSkill> pending = const [],
  }) async {
    if (transcript.trim().length < 120) return null;

    final result = await draftFromPrompt(
      provider: provider,
      model: model,
      request: 'User request:\n$userRequest\n\nAgent run:\n$transcript',
      existing: existing,
      reflection: true,
    );
    if (result == null || !result.report.passed) return null;
    if (pending.any((draft) => draft.name == result.draft.name)) return null;

    return PendingSkill(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      name: result.draft.name,
      description: result.draft.description,
      body: result.draft.body,
      triggers: result.draft.triggers,
      source: 'auto',
      score: result.report.score,
      createdAt: DateTime.now(),
      reason: result.draft.reason.isEmpty
          ? 'Learned from a completed agent run.'
          : result.draft.reason,
    );
  }

  Future<String> _complete({
    required AIProvider provider,
    required String model,
    required String system,
    required String user,
  }) async {
    final buffer = StringBuffer();
    await for (final event in provider.streamMessage(ChatRequest(
      messages: [
        ChatMessage(
          id: 'skill-system',
          role: MessageRole.system,
          content: system,
          createdAt: DateTime.now(),
        ),
        ChatMessage(
          id: 'skill-user',
          role: MessageRole.user,
          content: user,
          createdAt: DateTime.now(),
        ),
      ],
      model: model,
      params: const GenerationParams(temperature: 0.2, maxTokens: 2600),
    ))) {
      if (event is TextDeltaEvent) {
        buffer.write(event.text);
      } else if (event is StreamErrorEvent) {
        throw StateError(event.message);
      }
    }
    return buffer.toString().trim();
  }

  static Map<String, dynamic>? _extractJson(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
