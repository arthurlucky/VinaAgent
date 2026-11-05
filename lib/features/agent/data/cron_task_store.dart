import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/core/db/app_database.dart';
import 'package:pocketstrike/core/services/notification_service.dart';
import 'package:pocketstrike/core/storage/prefs_provider.dart';
import 'package:pocketstrike/features/agent/domain/agent_tool.dart';
import 'package:pocketstrike/features/chat/application/chat_controller.dart';
import 'package:pocketstrike/features/chat/application/run_registry.dart';
import 'package:pocketstrike/features/conversations/application/conversations_controller.dart';
import 'package:pocketstrike/features/telegram/telegram_service.dart';

enum CronTaskType { oneShot, recurring }

/// How a scheduled task behaves when it fires.
///
/// [reminder] keeps the original behaviour: show a notification and inject a
/// reminder into the active chat. [agent] runs the configured AI provider with
/// the agent loop and tools (for example `web_search`) in a dedicated
/// conversation, then posts the result.
enum CronTaskMode { reminder, agent }

class CronTask {
  const CronTask({
    required this.id,
    required this.title,
    required this.prompt,
    required this.type,
    required this.nextRunAt,
    this.recurringSchedule,
    this.isActive = true,
    this.mode = CronTaskMode.reminder,
    required this.createdAt,
    this.lastRunAt,
  });

  final String id;
  final String title;
  final String prompt;
  final CronTaskType type;
  final DateTime nextRunAt;
  final String? recurringSchedule;
  final bool isActive;
  final CronTaskMode mode;
  final DateTime createdAt;
  final DateTime? lastRunAt;

  CronTask copyWith({
    String? id,
    String? title,
    String? prompt,
    CronTaskType? type,
    DateTime? nextRunAt,
    String? recurringSchedule,
    bool? isActive,
    CronTaskMode? mode,
    DateTime? createdAt,
    DateTime? lastRunAt,
  }) {
    return CronTask(
      id: id ?? this.id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
      type: type ?? this.type,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      recurringSchedule: recurringSchedule ?? this.recurringSchedule,
      isActive: isActive ?? this.isActive,
      mode: mode ?? this.mode,
      createdAt: createdAt ?? this.createdAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'prompt': prompt,
        'type': type.name,
        'nextRunAt': nextRunAt.toIso8601String(),
        'recurringSchedule': recurringSchedule,
        'isActive': isActive,
        'mode': mode.name,
        'createdAt': createdAt.toIso8601String(),
        'lastRunAt': lastRunAt?.toIso8601String(),
      };

  factory CronTask.fromJson(Map<String, dynamic> json) => CronTask(
        id: json['id'] as String,
        title: json['title'] as String,
        prompt: json['prompt'] as String,
        type: CronTaskType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => CronTaskType.oneShot,
        ),
        nextRunAt: DateTime.parse(json['nextRunAt'] as String),
        recurringSchedule: json['recurringSchedule'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        mode: CronTaskMode.values.firstWhere(
          (e) => e.name == json['mode'],
          orElse: () => CronTaskMode.reminder,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastRunAt: json['lastRunAt'] != null
            ? DateTime.parse(json['lastRunAt'] as String)
            : null,
      );
}

/// Computes the next fire time for a recurring schedule.
///
/// Supported values:
/// * `hourly`
/// * `every_30m`
/// * `daily@HH:mm` (local time)
/// * `daily_7am` (legacy label, treated as `daily@07:00`)
///
/// Unknown schedules keep the historical 24-hour cadence.
DateTime nextCronRunAt(String? schedule, DateTime from) {
  final value = (schedule ?? '').trim().toLowerCase();
  if (value == 'hourly') return from.add(const Duration(hours: 1));
  if (value == 'every_30m') return from.add(const Duration(minutes: 30));

  var daily = value;
  if (daily == 'daily_7am') daily = 'daily@07:00';
  if (daily.startsWith('daily@')) {
    final raw = daily.substring('daily@'.length);
    final parts = raw.split(':');
    final hour = (int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 7)
        .clamp(0, 23)
        .toInt();
    final minute = (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0)
        .clamp(0, 59)
        .toInt();
    var next = DateTime(from.year, from.month, from.day, hour, minute);
    if (!next.isAfter(from)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  return from.add(const Duration(hours: 24));
}

/// Human-readable schedule label used by the UI and agent tools.
String describeCronSchedule(CronTask task) {
  final schedule = task.recurringSchedule?.trim();
  if (schedule == null || schedule.isEmpty) return 'One-shot';
  final lower = schedule.toLowerCase();
  if (lower == 'hourly') return 'Every hour';
  if (lower == 'every_30m') return 'Every 30 minutes';
  if (lower == 'daily_7am') return 'Daily at 07:00';
  if (lower.startsWith('daily@')) {
    return 'Daily at ${schedule.substring('daily@'.length)}';
  }
  return 'Every 24 hours';
}

final cronTaskProvider =
    NotifierProvider<CronTaskNotifier, List<CronTask>>(CronTaskNotifier.new);

class CronTaskNotifier extends Notifier<List<CronTask>> {
  static const _kStorageKey = 'pocketstrike_cron_tasks';
  Timer? _ticker;
  bool _checking = false;
  final Set<String> _runningTaskIds = {};

  @override
  List<CronTask> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final raw = prefs.getString(_kStorageKey);
    List<CronTask> loaded = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        loaded = list.map((e) => CronTask.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    _startBackgroundTicker();

    ref.onDispose(() {
      _ticker?.cancel();
    });

    return loaded;
  }

  void _startBackgroundTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) => _checkPendingTasks());
  }

  Future<void> _save(List<CronTask> tasks) async {
    state = tasks;
    final prefs = ref.read(sharedPreferencesProvider);
    final jsonStr = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_kStorageKey, jsonStr);
  }

  Future<void> addTask(CronTask task) async {
    final updated = [...state, task];
    await _save(updated);
  }

  Future<void> deleteTask(String id) async {
    final updated = state.where((t) => t.id != id).toList();
    await _save(updated);
    await _deleteConversationForTask(id);
  }

  Future<void> cancelTaskByKeyword(String keyword) async {
    final lower = keyword.toLowerCase();
    final removedIds = <String>{};
    final updated = state.where((t) {
      final match = t.title.toLowerCase().contains(lower) ||
          t.prompt.toLowerCase().contains(lower);
      if (match) removedIds.add(t.id);
      return !match;
    }).toList();
    await _save(updated);
    for (final id in removedIds) {
      await _deleteConversationForTask(id);
    }
  }

  Future<void> toggleTaskActive(String id, bool active) async {
    final updated = state.map((t) {
      if (t.id == id) return t.copyWith(isActive: active);
      return t;
    }).toList();
    await _save(updated);
  }

  /// Runs a task immediately without changing its schedule.
  Future<void> runTaskNow(CronTask task) async {
    if (_runningTaskIds.contains(task.id)) return;
    _runningTaskIds.add(task.id);
    try {
      await _executeTaskTrigger(task);
    } finally {
      _runningTaskIds.remove(task.id);
    }
  }

  Future<void> _checkPendingTasks() async {
    if (_checking) return;
    _checking = true;
    try {
      await _checkPendingTasksInner();
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkPendingTasksInner() async {
    final now = DateTime.now();
    final updated = <CronTask>[];

    for (final task in state) {
      if (task.isActive && now.isAfter(task.nextRunAt)) {
        // Trigger Task Execution!
        unawaited(runTaskNow(task));

        if (task.type == CronTaskType.oneShot) {
          // Deactivate one-shot task after firing
          updated.add(task.copyWith(isActive: false, lastRunAt: now));
        } else {
          // Reschedule recurring task at its real next occurrence.
          final nextRun = nextCronRunAt(task.recurringSchedule, now);
          updated.add(task.copyWith(nextRunAt: nextRun, lastRunAt: now));
        }
      } else {
        updated.add(task);
      }
    }

    if (updated.length != state.length ||
        state.any((t) => t.lastRunAt != updated.firstWhere((u) => u.id == t.id).lastRunAt)) {
      await _save(updated);
    }
  }

  Future<void> _executeTaskTrigger(CronTask task) async {
    if (task.mode == CronTaskMode.agent) {
      await _runAgentTask(task);
    } else {
      await _sendReminder(task);
    }
  }

  Future<void> _sendReminder(CronTask task) async {
    final title = task.title;
    final prompt = task.prompt;

    // 1. Inject reminder into active Chat thread
    try {
      await ref
          .read(chatControllerProvider.notifier)
          .injectReminderMessage(title, prompt);
    } catch (_) {}

    // 2. Send Telegram notification if connected
    try {
      await ref
          .read(telegramServiceProvider.notifier)
          .postNotification('⏰ *Reminder Alert: $title*\n\n$prompt');
    } catch (_) {}

    // 3. Trigger Android System Notification Banner
    try {
      final notifService = ref.read(notificationServiceProvider);
      await notifService.showNotification(
        id: task.id.hashCode,
        title: '⏰ Reminder: $title',
        body: prompt,
      );
    } catch (_) {}
  }

  /// Runs an agent task in a dedicated conversation, then posts the result.
  Future<void> _runAgentTask(CronTask task) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final actions = ref.read(conversationActionsProvider);
      final source = 'cron_${task.id}';

      final conversations = await db.conversationsDao.getAll();
      final existing =
          conversations.where((c) => c.source == source).firstOrNull;
      final convId = existing?.id ??
          await actions.createConversation(source: source);

      await actions.rename(convId, '⏰ ${task.title}');

      final registry = ref.read(chatRunRegistryProvider);
      if (registry.isRunning(convId)) return;

      // Keep only the latest run in the task conversation.
      await db.messagesDao.deleteForConversation(convId);

      final prompt = '${task.prompt}\n\n'
          '[Automated scheduled task. Complete it without asking follow-up '
          'questions. Use available tools such as web_search when they help.]';

      await ref.read(chatControllerProvider.notifier).sendMessage(
            text: prompt,
            conversationId: convId,
            forceAgentMode: true,
            forceCloudMode: true,
            preApprovedTools: const {'web_search'},
            // Headless runs cannot show confirmation dialogs, so keep
            // destructive/external tools blocked unless explicitly approved.
            policyOverride: ConfirmationPolicy.destructiveOnly,
          );

      await db.conversationsDao.touch(convId);

      final runState = ref.read(chatRunRegistryProvider).stateFor(convId);
      final error = runState.error?.trim() ?? '';
      if (error.isNotEmpty) {
        await _postResult(task, '⚠️ ${task.title}', 'Agent run failed: $error');
        return;
      }

      final messages = await db.messagesDao.getForConversation(convId);
      final lastAssistant = messages
          .where((m) => m.role == 'assistant')
          .lastOrNull;
      final result = lastAssistant?.content.trim() ?? '';
      if (result.isEmpty) {
        await _postResult(
          task,
          '⚠️ ${task.title}',
          'Agent run finished without output.',
        );
        return;
      }

      await _postResult(task, '⏰ ${task.title}', result);
    } catch (error) {
      await _postResult(
        task,
        '⚠️ ${task.title}',
        'Agent run failed: $error',
      );
    }
  }

  Future<void> _postResult(
    CronTask task,
    String title,
    String body,
  ) async {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    try {
      await ref.read(notificationServiceProvider).showNotification(
            id: task.id.hashCode,
            title: title,
            body: _clip(compact, 240),
          );
    } catch (_) {}
    try {
      await ref.read(telegramServiceProvider.notifier).postNotification(
            '$title\n\n${_clip(body.trim(), 3800)}',
          );
    } catch (_) {}
  }

  Future<void> _deleteConversationForTask(String taskId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final conversations = await db.conversationsDao.getAll();
      final existing = conversations
          .where((c) => c.source == 'cron_$taskId')
          .firstOrNull;
      if (existing != null &&
          !ref.read(chatRunRegistryProvider).isRunning(existing.id)) {
        await ref.read(conversationActionsProvider).delete(existing.id);
      }
    } catch (_) {}
  }

  /// Agent tools for Task & Cron Job Automation.
  List<AgentTool> buildTools() {
    return [
      AgentTool(
        name: 'schedule_task',
        description:
            'Schedules a one-shot reminder, a recurring reminder, or a recurring agent job. '
            'Use mode "agent" when the task should run the AI agent with tools (for example '
            'a daily news search using web_search). Recurring schedules accept "hourly", '
            '"every_30m", or "daily@HH:mm" (24-hour local time).',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'title': {
              'type': 'string',
              'description': 'Short title of the task or reminder (e.g. "Daily Tech News").',
            },
            'prompt': {
              'type': 'string',
              'description': 'What the agent should remind or do when triggered.',
            },
            'delayMinutes': {
              'type': 'number',
              'description': 'Minutes from now until task fires (for one-shot reminders).',
            },
            'recurringSchedule': {
              'type': 'string',
              'description': 'Optional recurring schedule: "hourly", "every_30m", or "daily@HH:mm".',
            },
            'mode': {
              'type': 'string',
              'description':
                  'Task mode: "reminder" only notifies, "agent" runs the AI agent with tools and posts the result.',
              'enum': ['reminder', 'agent'],
            },
          },
          'required': ['title', 'prompt'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final rawTitle = (args['title'] as String?)?.trim();
          final title = (rawTitle == null || rawTitle.isEmpty)
              ? 'Scheduled Task'
              : rawTitle;
          final promptText = (args['prompt'] as String?)?.trim() ?? '';
          final delayVal = (args['delayMinutes'] as num?)?.toDouble() ?? 1.0;
          final delayMinutes = delayVal <= 0 ? 1.0 : delayVal;
          final recurringRaw =
              (args['recurringSchedule'] as String?)?.trim();
          final recurring = (recurringRaw == null || recurringRaw.isEmpty)
              ? null
              : recurringRaw;
          final modeRaw = (args['mode'] as String?)?.trim().toLowerCase();
          final mode = modeRaw == 'agent'
              ? CronTaskMode.agent
              : CronTaskMode.reminder;
          final now = DateTime.now();
          final fireTime = recurring != null
              ? nextCronRunAt(recurring, now)
              : now.add(Duration(seconds: (delayMinutes * 60).round()));

          final newTask = CronTask(
            id: 'task_${now.millisecondsSinceEpoch}',
            title: title,
            prompt: promptText,
            type: recurring != null
                ? CronTaskType.recurring
                : CronTaskType.oneShot,
            nextRunAt: fireTime,
            recurringSchedule: recurring,
            mode: mode,
            createdAt: now,
          );

          await addTask(newTask);
          final timeStr =
              '${fireTime.hour.toString().padLeft(2, "0")}:${fireTime.minute.toString().padLeft(2, "0")}';
          final modeStr =
              mode == CronTaskMode.agent ? 'agent job' : 'reminder';
          return 'Scheduled $modeStr "$title" (${describeCronSchedule(newTask)}) to fire at $timeStr.';
        },
      ),
      AgentTool(
        name: 'list_scheduled_tasks',
        description: 'Lists all currently active scheduled tasks, reminders, and recurring cron jobs.',
        inputSchema: const {
          'type': 'object',
          'properties': <String, dynamic>{},
        },
        risk: ToolRisk.safe,
        run: (args) async {
          if (state.isEmpty) return 'No scheduled tasks or active cron jobs currently set.';
          final buffer = StringBuffer('Active Scheduled Tasks & Cron Jobs:\n');
          for (final t in state) {
            final activeStr = t.isActive ? '🟢 Active' : '⚪ Paused';
            final modeStr = t.mode == CronTaskMode.agent ? '🤖 Agent' : '🔔 Reminder';
            buffer.writeln('• [${t.id}] ${t.title} ($activeStr, $modeStr)');
            buffer.writeln('   - Schedule: ${describeCronSchedule(t)}');
            buffer.writeln('   - Prompt: "${t.prompt}"');
            buffer.writeln('   - Next Run: ${t.nextRunAt.toLocal()}');
          }
          return buffer.toString().trim();
        },
      ),
      AgentTool(
        name: 'cancel_scheduled_task',
        description: 'Cancels/deletes a scheduled task or reminder by keyword or description (e.g. "water", "news").',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'keyword': {
              'type': 'string',
              'description': 'Keyword or title of the task to cancel (e.g. "water", "drink", "news").',
            },
          },
          'required': ['keyword'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final kw = args['keyword'] as String? ?? '';
          if (kw.trim().isEmpty) return 'Error: Keyword is empty.';
          await cancelTaskByKeyword(kw.trim());
          return 'Successfully cancelled matching tasks for "$kw".';
        },
      ),
    ];
  }
}

String _clip(String text, int max) {
  if (text.length <= max) return text;
  return '${text.substring(0, max)}…';
}
