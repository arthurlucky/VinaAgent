import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/process_task.dart';

class ProcessManagerService extends ChangeNotifier {
  ProcessManagerService();

  final Map<String, ProcessTask> _tasks = {};
  static const _uuid = Uuid();

  List<ProcessTask> get tasks => _tasks.values.toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  List<ProcessTask> get runningTasks =>
      tasks.where((t) => t.status == ProcessTaskStatus.running).toList();

  ProcessTask? getTask(String id) => _tasks[id];

  /// Starts a long-running process asynchronously in the background.
  Future<ProcessTask> startProcess({
    required String command,
    String? name,
    String? scriptPath,
    String? workingDirectory,
  }) async {
    final id = 'proc_${_uuid.v4().substring(0, 8)}';
    final task = ProcessTask(
      id: id,
      command: command,
      name: name,
      scriptPath: scriptPath,
      workingDirectory: workingDirectory,
      startedAt: DateTime.now(),
      status: ProcessTaskStatus.running,
    );

    _tasks[id] = task;
    notifyListeners();

    try {
      final shell = Platform.isAndroid ? '/system/bin/sh' : 'sh';
      final proc = await Process.start(
        shell,
        ['-c', command],
        workingDirectory: workingDirectory,
        runInShell: false,
      );

      task.process = proc;
      task.pid = proc.pid;
      notifyListeners();

      // Listen to stdout
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          task.appendLog(line);
          notifyListeners();
        },
        onError: (err) {
          task.appendLog('[STDOUT ERR] $err');
          notifyListeners();
        },
      );

      // Listen to stderr
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          task.appendLog('[STDERR] $line');
          notifyListeners();
        },
        onError: (err) {
          task.appendLog('[STDERR ERR] $err');
          notifyListeners();
        },
      );

      // Listen to exit
      unawaited(proc.exitCode.then((code) {
        task.exitCode = code;
        task.status =
            code == 0 ? ProcessTaskStatus.stopped : ProcessTaskStatus.failed;
        task.appendLog('[PROCESS EXITED with code $code]');
        notifyListeners();
      }));

      // Wait brief 400ms to capture any immediate startup errors/output
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return task;
    } catch (e) {
      task.status = ProcessTaskStatus.failed;
      task.appendLog('[FAILED TO START] $e');
      notifyListeners();
      return task;
    }
  }

  /// Stops a running process.
  Future<bool> stopProcess(String id) async {
    final task = _tasks[id];
    if (task == null || task.status != ProcessTaskStatus.running) return false;

    try {
      final proc = task.process;
      if (proc != null) {
        proc.kill(ProcessSignal.sigterm);
        // Force kill if still running after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (task.status == ProcessTaskStatus.running) {
            proc.kill(ProcessSignal.sigkill);
          }
        });
      }
      task.status = ProcessTaskStatus.stopped;
      task.appendLog('[PROCESS STOPPED BY USER/AGENT]');
      notifyListeners();
      return true;
    } catch (e) {
      task.appendLog('[STOP ERROR] $e');
      notifyListeners();
      return false;
    }
  }

  /// Restarts a process.
  Future<ProcessTask?> restartProcess(String id) async {
    final task = _tasks[id];
    if (task == null) return null;
    await stopProcess(id);
    return startProcess(
      command: task.command,
      name: task.name,
      scriptPath: task.scriptPath,
      workingDirectory: task.workingDirectory,
    );
  }

  /// Removes a stopped or failed task from history.
  void removeTask(String id) {
    final task = _tasks[id];
    if (task != null && task.status != ProcessTaskStatus.running) {
      _tasks.remove(id);
      notifyListeners();
    }
  }

  /// Clears all non-running tasks.
  void clearInactiveTasks() {
    _tasks.removeWhere((_, t) => t.status != ProcessTaskStatus.running);
    notifyListeners();
  }

  /// Returns recent logs.
  List<String> getLogs(String id, {int maxLines = 50}) {
    final task = _tasks[id];
    if (task == null) return [];
    if (task.logLines.length <= maxLines) {
      return List.unmodifiable(task.logLines);
    }
    return List.unmodifiable(
      task.logLines.sublist(task.logLines.length - maxLines),
    );
  }

  @override
  void dispose() {
    for (final task in runningTasks) {
      task.process?.kill(ProcessSignal.sigterm);
    }
    super.dispose();
  }
}

final processManagerProvider =
    ChangeNotifierProvider<ProcessManagerService>((ref) {
  final service = ProcessManagerService();
  ref.onDispose(service.dispose);
  return service;
});
