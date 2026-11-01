import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/glass_tokens.dart';
import '../data/process_manager_service.dart';
import '../domain/process_task.dart';

/// Shows the Task Manager bottom sheet.
Future<void> showTaskManagerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const TaskManagerSheet(),
  );
}

class TaskManagerSheet extends ConsumerStatefulWidget {
  const TaskManagerSheet({super.key});

  @override
  ConsumerState<TaskManagerSheet> createState() => _TaskManagerSheetState();
}

class _TaskManagerSheetState extends ConsumerState<TaskManagerSheet> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final processManager = ref.watch(processManagerProvider);
    final tasks = processManager.tasks;
    final runningCount = processManager.runningTasks.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.memory_rounded, color: tokens.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Task Manager',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: runningCount > 0
                                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                  : tokens.glassBorder,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$runningCount running',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: runningCount > 0
                                    ? const Color(0xFF10B981)
                                    : tokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Background processes & servers',
                        style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (tasks.any((t) => t.status != ProcessTaskStatus.running))
                  IconButton(
                    icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                    tooltip: 'Clear finished tasks',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      processManager.clearInactiveTasks();
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptyState(context, tokens)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: tasks.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _ProcessTaskCard(
                        task: task,
                        onViewLogs: () => _openLogsModal(task),
                        onStop: () async {
                          HapticFeedback.mediumImpact();
                          await processManager.stopProcess(task.id);
                        },
                        onRestart: () async {
                          HapticFeedback.mediumImpact();
                          await processManager.restartProcess(task.id);
                        },
                        onEditScript: () => _openScriptEditor(task),
                        onRemove: () {
                          HapticFeedback.lightImpact();
                          processManager.removeTask(task.id);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, GlassTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal_rounded, size: 48, color: tokens.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              'No Background Processes',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Servers (like Express `node server.js` or `python -m http.server`) started by you or Vina Agent will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Open File Manager'),
              onPressed: () {
                Navigator.pop(context);
                context.push(AppRoutes.settingsFiles);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openLogsModal(ProcessTask task) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProcessLogsSheet(taskId: task.id),
    );
  }

  void _openScriptEditor(ProcessTask task) {
    if (task.scriptPath == null || !File(task.scriptPath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Script file not found: ${task.scriptPath ?? "None specified"}'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => _ScriptEditorDialog(
        filePath: task.scriptPath!,
        onSaved: () async {
          final manager = ref.read(processManagerProvider);
          if (task.status == ProcessTaskStatus.running) {
            await manager.restartProcess(task.id);
          }
        },
      ),
    );
  }
}

class _ProcessTaskCard extends StatelessWidget {
  const _ProcessTaskCard({
    required this.task,
    required this.onViewLogs,
    required this.onStop,
    required this.onRestart,
    required this.onEditScript,
    required this.onRemove,
  });

  final ProcessTask task;
  final VoidCallback onViewLogs;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onEditScript;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.glass;
    final isRunning = task.status == ProcessTaskStatus.running;
    final isFailed = task.status == ProcessTaskStatus.failed;

    final statusColor = isRunning
        ? const Color(0xFF10B981)
        : isFailed
            ? Colors.redAccent
            : tokens.textSecondary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.glassColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: isRunning
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : tokens.glassBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: isRunning
                      ? [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.status.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            task.command,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: tokens.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (task.pid != null) ...[
                Text(
                  'PID: ${task.pid}',
                  style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                'Uptime: ${_formatUptime(task.uptime)}',
                style: TextStyle(fontSize: 11, color: tokens.textSecondary),
              ),
              const Spacer(),
              Text(
                '${task.logLines.length} logs',
                style: TextStyle(fontSize: 11, color: tokens.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('Logs', style: TextStyle(fontSize: 12)),
                onPressed: onViewLogs,
              ),
              if (task.scriptPath != null) ...[
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  onPressed: onEditScript,
                ),
              ],
              if (isRunning) ...[
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: const Icon(Icons.stop_circle_rounded, size: 16, color: Colors.redAccent),
                  label: const Text('Stop', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                  onPressed: onStop,
                ),
              ] else ...[
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Color(0xFF10B981)),
                  label: const Text('Restart', style: TextStyle(fontSize: 12, color: Color(0xFF10B981))),
                  onPressed: onRestart,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatUptime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    if (minutes > 59) {
      final hours = d.inHours;
      final m = minutes % 60;
      return '${hours}h ${m}m';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ProcessLogsSheet extends ConsumerStatefulWidget {
  const _ProcessLogsSheet({required this.taskId});
  final String taskId;

  @override
  ConsumerState<_ProcessLogsSheet> createState() => _ProcessLogsSheetState();
}

class _ProcessLogsSheetState extends ConsumerState<_ProcessLogsSheet> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final processManager = ref.watch(processManagerProvider);
    final task = processManager.getTask(widget.taskId);

    if (task == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: const Text('Process task no longer exists.'),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final logs = task.logLines;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded, color: Color(0xFF10B981), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                  tooltip: 'Copy all logs',
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(ClipboardData(text: logs.join('\n')));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Logs copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Icon(
                    _autoScroll ? Icons.vertical_align_bottom_rounded : Icons.pause_circle_outline_rounded,
                    color: _autoScroll ? const Color(0xFF10B981) : Colors.white38,
                    size: 20,
                  ),
                  tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
                  onPressed: () {
                    setState(() => _autoScroll = !_autoScroll);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          // Log terminal
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'No console output captured yet.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final line = logs[index];
                      Color lineCol = Colors.white70;
                      if (line.startsWith('[STDERR') || line.startsWith('[FAILED') || line.contains('Error:')) {
                        lineCol = Colors.redAccent;
                      } else if (line.startsWith('[PROCESS')) {
                        lineCol = const Color(0xFF10B981);
                      }
                      return Text(
                        line,
                        style: TextStyle(
                          color: lineCol,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScriptEditorDialog extends StatefulWidget {
  const _ScriptEditorDialog({
    required this.filePath,
    required this.onSaved,
  });

  final String filePath;
  final VoidCallback onSaved;

  @override
  State<_ScriptEditorDialog> createState() => _ScriptEditorDialogState();
}

class _ScriptEditorDialogState extends State<_ScriptEditorDialog> {
  late TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    String content = '';
    try {
      final file = File(widget.filePath);
      if (file.existsSync()) {
        content = file.readAsStringSync();
      }
    } catch (_) {}
    _controller = TextEditingController(text: content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final file = File(widget.filePath);
      await file.writeAsString(_controller.text, flush: true);
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Script saved successfully! Restarting process...'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving script: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.code_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.filePath.split('/').last,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F1117)
                      : const Color(0xFFF1F3F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: _isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save & Restart'),
                  onPressed: _isSaving ? null : _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
