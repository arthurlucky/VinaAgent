import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketstrike/app/theme/glass_tokens.dart';
import 'package:pocketstrike/shared/widgets/app_icons.dart';
import 'package:pocketstrike/shared/widgets/glass_button.dart';
import 'package:pocketstrike/features/agent/data/cron_task_store.dart';

class CronTasksScreen extends ConsumerWidget {
  const CronTasksScreen({super.key});

  void _showAddTaskSheet(BuildContext context, WidgetRef ref) {
    final tokens = context.glass;
    final titleController = TextEditingController();
    final promptController = TextEditingController();
    double delayMinutes = 30;
    bool isRecurring = false;
    bool runAgent = false;
    TimeOfDay runAt = const TimeOfDay(hour: 7, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(tokens.radiusLg)),
            border: Border.all(color: tokens.glassBorder),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.sparkles, color: tokens.accent, size: 20),
                    const SizedBox(width: 8),
                    Text('New Task / Cron Job',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Task Title (e.g. Daily Tech News)',
                    filled: true,
                    fillColor: tokens.glassColor,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: promptController,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: runAgent
                        ? 'Prompt (e.g. Search today\'s technology news)'
                        : 'Prompt / Instruction (e.g. Remind me to drink water)',
                    filled: true,
                    fillColor: tokens.glassColor,
                  ),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Run Agent automatically'),
                  subtitle: Text(
                    'Uses the active AI provider and tools such as web_search.',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                  value: runAgent,
                  activeThumbColor: tokens.accent,
                  onChanged: (val) => setSheetState(() => runAgent = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Recurring Daily Cron Job'),
                  value: isRecurring,
                  activeThumbColor: tokens.accent,
                  onChanged: (val) => setSheetState(() => isRecurring = val),
                ),
                if (isRecurring)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.schedule, color: tokens.accent),
                    title: Text('Run daily at ${runAt.format(context)}'),
                    subtitle: const Text('Local time'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: runAt,
                      );
                      if (picked != null && context.mounted) {
                        setSheetState(() => runAt = picked);
                      }
                    },
                  )
                else
                  Row(
                    children: [
                      Text('Delay (${delayMinutes.toInt()} mins): '),
                      Expanded(
                        child: Slider(
                          value: delayMinutes,
                          min: 5,
                          max: 240,
                          divisions: 47,
                          activeColor: tokens.accent,
                          onChanged: (val) =>
                              setSheetState(() => delayMinutes = val),
                        ),
                      ),
                    ],
                  ),
                if (runAgent)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'Agent jobs use the active cloud provider and run while '
                      'Vina Agent is active. Keep the app or the 24/7 Telegram '
                      'relay service running for reliable schedules.',
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Create Scheduled Task',
                  icon: AppIcons.plus,
                  expanded: true,
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) return;
                    final now = DateTime.now();
                    final schedule = isRecurring
                        ? 'daily@${runAt.hour.toString().padLeft(2, '0')}:${runAt.minute.toString().padLeft(2, '0')}'
                        : null;
                    final nextRun = isRecurring
                        ? nextCronRunAt(schedule, now)
                        : now.add(Duration(minutes: delayMinutes.toInt()));
                    final newTask = CronTask(
                      id: 'task_${now.millisecondsSinceEpoch}',
                      title: titleController.text.trim(),
                      prompt: promptController.text.trim().isEmpty
                          ? titleController.text.trim()
                          : promptController.text.trim(),
                      type: isRecurring
                          ? CronTaskType.recurring
                          : CronTaskType.oneShot,
                      nextRunAt: nextRun,
                      recurringSchedule: schedule,
                      mode: runAgent
                          ? CronTaskMode.agent
                          : CronTaskMode.reminder,
                      createdAt: now,
                    );
                    await ref.read(cronTaskProvider.notifier).addTask(newTask);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.glass;
    final tasks = ref.watch(cronTaskProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Scheduled Tasks & Cron Jobs',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTaskSheet(context, ref),
        backgroundColor: tokens.accent,
        icon: Icon(Icons.add, color: tokens.onAccent),
        label: Text('Add Task', style: TextStyle(color: tokens.onAccent, fontWeight: FontWeight.bold)),
      ),
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alarm_off, size: 56, color: tokens.textSecondary),
                  const SizedBox(height: 14),
                  Text('No Active Tasks or Reminders',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Say "remind me to drink water in 1 hour"\nor tap + Add Task to create a schedule.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                final isAgent = task.mode == CronTaskMode.agent;
                final now = DateTime.now();
                final next = task.nextRunAt;
                final isToday = next.year == now.year &&
                    next.month == now.month &&
                    next.day == now.day;
                final tomorrow = now.add(const Duration(days: 1));
                final isTomorrow = next.year == tomorrow.year &&
                    next.month == tomorrow.month &&
                    next.day == tomorrow.day;
                final dayLabel = isToday
                    ? 'today'
                    : (isTomorrow ? 'tomorrow' : '${next.day}/${next.month}');
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.glassColor,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isAgent
                              ? Icons.smart_toy_outlined
                              : (task.type == CronTaskType.recurring
                                  ? Icons.loop
                                  : Icons.notifications_active),
                          color: tokens.accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    task.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (!task.isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: tokens.glassBorder,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'PAUSED',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: tokens.textSecondary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.prompt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: tokens.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${isAgent ? "🤖 Agent" : "🔔 Reminder"} • ${describeCronSchedule(task)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: tokens.accent,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Next run: ${next.hour.toString().padLeft(2, "0")}:${next.minute.toString().padLeft(2, "0")} $dayLabel',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: tokens.textSecondary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Run now',
                        icon: Icon(Icons.play_circle_outline, color: tokens.accent),
                        onPressed: () {
                          unawaited(
                            ref.read(cronTaskProvider.notifier).runTaskNow(task),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isAgent
                                    ? 'Running "${task.title}" with the agent…'
                                    : 'Reminder "${task.title}" triggered.',
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () =>
                            ref.read(cronTaskProvider.notifier).deleteTask(task.id),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
