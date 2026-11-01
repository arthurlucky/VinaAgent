import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/storage/app_sandbox.dart';
import '../../agent/domain/agent_tool.dart';
import 'process_manager_service.dart';

class ProcessAgentTools {
  const ProcessAgentTools._();

  static List<AgentTool> all({
    required ProcessManagerService processManager,
    required List<String> allowedRoots,
    String activeWorkdir = '',
  }) =>
      [
        runBashScript(
          allowedRoots: allowedRoots,
          activeWorkdir: activeWorkdir,
        ),
        startBackgroundProcess(
          processManager: processManager,
          allowedRoots: allowedRoots,
          activeWorkdir: activeWorkdir,
        ),
        listBackgroundProcesses(processManager: processManager),
        getProcessLogs(processManager: processManager),
        stopBackgroundProcess(processManager: processManager),
      ];

  static String _resolvePath(
    String rawPath,
    List<String> allowedRoots, [
    String activeWorkdir = '',
  ]) {
    if (allowedRoots.isEmpty) return rawPath.trim();
    final root = allowedRoots.first;
    final trimmed = rawPath.trim().replaceAll('\\', '/');

    if (trimmed.startsWith('/') || trimmed.startsWith(root)) {
      final stripped = trimmed.replaceFirst(RegExp(r'^/+'), '');
      return AppSandbox.resolveWithRoot(stripped, root) ??
          p.join(root, stripped);
    }

    final effectiveWorkdir = (activeWorkdir.isEmpty ||
            activeWorkdir == 'default' ||
            activeWorkdir == 'root' ||
            activeWorkdir == '/')
        ? root
        : (activeWorkdir.startsWith(root)
            ? activeWorkdir
            : p.join(root, activeWorkdir));

    return p.normalize(p.join(effectiveWorkdir, trimmed));
  }

  static String _resolveWorkdir(
    List<String> allowedRoots,
    String activeWorkdir,
  ) {
    if (allowedRoots.isEmpty) return Directory.current.path;
    final root = allowedRoots.first;
    String dir;
    if (activeWorkdir.isEmpty ||
        activeWorkdir == 'default' ||
        activeWorkdir == 'root' ||
        activeWorkdir == '/') {
      dir = root;
    } else if (activeWorkdir.startsWith(root)) {
      dir = activeWorkdir;
    } else {
      dir = p.normalize(p.join(root, activeWorkdir));
    }
    try {
      final d = Directory(dir);
      if (!d.existsSync()) d.createSync(recursive: true);
    } catch (_) {}
    return dir;
  }

  /// Tool to run bash/sh scripts or shell commands synchronously.
  static AgentTool runBashScript({
    required List<String> allowedRoots,
    String activeWorkdir = '',
  }) =>
      AgentTool(
        name: 'run_bash_script',
        description:
            'Executes a shell command, script, or script file in the active agent workspace. '
            'Supports bash/sh commands, Node.js (if installed), Python, and file scripts. '
            'Returns stdout, stderr, and exit code.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description':
                  'Shell command or inline script to execute (e.g. "ls -la", "node index.js", "python3 test.py").',
            },
            'script_file': {
              'type': 'string',
              'description':
                  'Optional path of a script file in the sandbox to execute (e.g. "build.sh", "server.js").',
            },
            'timeout_seconds': {
              'type': 'integer',
              'description':
                  'Maximum execution time in seconds before timeout (default: 30).',
            },
          },
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          var cmd = args['command'] as String? ?? '';
          final scriptFile = args['script_file'] as String?;
          final timeoutSec = (args['timeout_seconds'] as num?)?.toInt() ?? 30;

          final cwd = _resolveWorkdir(allowedRoots, activeWorkdir);

          if (scriptFile != null && scriptFile.trim().isNotEmpty) {
            final fullPath = _resolvePath(scriptFile, allowedRoots, activeWorkdir);
            final file = File(fullPath);
            if (!await file.exists()) {
              return 'Error: Script file "$scriptFile" does not exist at "$fullPath".';
            }
            final ext = p.extension(fullPath).toLowerCase();
            if (ext == '.js') {
              cmd = 'node "$fullPath"';
            } else if (ext == '.py') {
              cmd = 'python3 "$fullPath"';
            } else {
              cmd = 'sh "$fullPath"';
            }
          }

          if (cmd.trim().isEmpty) {
            return 'Error: Either "command" or "script_file" must be provided.';
          }

          try {
            final shell = Platform.isAndroid ? '/system/bin/sh' : 'sh';
            final result = await Process.run(
              shell,
              ['-c', cmd],
              workingDirectory: cwd,
              runInShell: false,
            ).timeout(Duration(seconds: timeoutSec));

            final stdoutText = (result.stdout as String? ?? '').trim();
            final stderrText = (result.stderr as String? ?? '').trim();

            final sb = StringBuffer();
            sb.writeln('Exit Code: ${result.exitCode}');
            sb.writeln('Working Dir: $cwd');
            if (stdoutText.isNotEmpty) {
              sb.writeln('\n--- STDOUT ---');
              if (stdoutText.length > 3000) {
                sb.writeln(stdoutText.substring(0, 3000));
                sb.writeln('\n[... Output truncated due to length ...]');
              } else {
                sb.writeln(stdoutText);
              }
            }
            if (stderrText.isNotEmpty) {
              sb.writeln('\n--- STDERR ---');
              if (stderrText.length > 2000) {
                sb.writeln(stderrText.substring(0, 2000));
                sb.writeln('\n[... Stderr truncated ...]');
              } else {
                sb.writeln(stderrText);
              }
            }
            if (stdoutText.isEmpty && stderrText.isEmpty) {
              sb.writeln('(No output produced)');
            }
            return sb.toString();
          } on TimeoutException {
            return 'Error: Execution timed out after $timeoutSec seconds. If this is a long-running server (like Express or a web server), use "start_background_process" instead.';
          } catch (e) {
            return 'Execution error: $e';
          }
        },
      );

  /// Tool to start a background daemon/server process.
  static AgentTool startBackgroundProcess({
    required ProcessManagerService processManager,
    required List<String> allowedRoots,
    String activeWorkdir = '',
  }) =>
      AgentTool(
        name: 'start_background_process',
        description:
            'Starts a long-running process, server (e.g. Express `node server.js`, `python -m http.server`), or background worker. '
            'Runs asynchronously without blocking. Returns a task ID and PID to monitor or stop later.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description':
                  'The command to execute (e.g. "node server.js", "python3 app.py").',
            },
            'name': {
              'type': 'string',
              'description':
                  'A human-readable label for this background process (e.g. "Express API Server").',
            },
            'script_file': {
              'type': 'string',
              'description':
                  'Optional path of the primary script file for easy editing/restarts.',
            },
          },
          'required': ['command'],
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          final command = args['command'] as String? ?? '';
          final name = args['name'] as String?;
          final scriptFile = args['script_file'] as String?;

          if (command.trim().isEmpty) {
            return 'Error: Command cannot be empty.';
          }

          final cwd = _resolveWorkdir(allowedRoots, activeWorkdir);
          String? resolvedScriptPath;
          if (scriptFile != null && scriptFile.isNotEmpty) {
            resolvedScriptPath = _resolvePath(scriptFile, allowedRoots, activeWorkdir);
          }

          final task = await processManager.startProcess(
            command: command,
            name: name,
            scriptPath: resolvedScriptPath ?? scriptFile,
            workingDirectory: cwd,
          );

          final initialLogs = processManager.getLogs(task.id, maxLines: 15);
          return 'Background process started successfully!\n'
              '• Task ID: ${task.id}\n'
              '• PID: ${task.pid ?? "pending"}\n'
              '• Name: ${task.displayName}\n'
              '• Status: ${task.status.name}\n'
              '• Working Dir: $cwd\n'
              '• Command: ${task.command}\n\n'
              'Initial Output:\n${initialLogs.isEmpty ? "(Waiting for initial output...)" : initialLogs.join("\n")}';
        },
      );

  /// Tool to list all background processes.
  static AgentTool listBackgroundProcesses({
    required ProcessManagerService processManager,
  }) =>
      AgentTool(
        name: 'list_background_processes',
        description:
            'Lists all active and recent background server and script processes managed by the Task Manager.',
        inputSchema: const {
          'type': 'object',
          'properties': {},
        },
        risk: ToolRisk.safe,
        run: (_) async {
          final tasks = processManager.tasks;
          if (tasks.isEmpty) {
            return 'No background processes are currently registered.';
          }

          final sb = StringBuffer();
          sb.writeln('Active & Recent Background Processes (${tasks.length}):\n');
          for (final t in tasks) {
            final uptimeMin = (t.uptime.inSeconds / 60).toStringAsFixed(1);
            sb.writeln('• [${t.id}] ${t.displayName}');
            sb.writeln('  Status: ${t.status.name.toUpperCase()} | PID: ${t.pid ?? "-"} | Uptime: ${uptimeMin}m');
            sb.writeln('  Command: ${t.command}');
            if (t.scriptPath != null) {
              sb.writeln('  Script: ${t.scriptPath}');
            }
            sb.writeln();
          }
          return sb.toString();
        },
      );

  /// Tool to retrieve logs of a background process.
  static AgentTool getProcessLogs({
    required ProcessManagerService processManager,
  }) =>
      AgentTool(
        name: 'get_process_logs',
        description:
            'Retrieves the recent console logs (stdout/stderr) from a background server or process.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'task_id': {
              'type': 'string',
              'description': 'The Task ID returned when the process was started (e.g. "proc_1234abcd").',
            },
            'lines': {
              'type': 'integer',
              'description': 'Number of recent log lines to retrieve (default: 40).',
            },
          },
          'required': ['task_id'],
        },
        risk: ToolRisk.safe,
        run: (args) async {
          final taskId = (args['task_id'] as String? ?? '').trim();
          final lines = (args['lines'] as num?)?.toInt() ?? 40;

          final task = processManager.getTask(taskId);
          if (task == null) {
            return 'Error: Task "$taskId" was not found in the Task Manager.';
          }

          final logs = processManager.getLogs(taskId, maxLines: lines);
          if (logs.isEmpty) {
            return 'No logs captured yet for task "${task.displayName}" [${task.id}].';
          }

          return 'Logs for "${task.displayName}" [${task.id}] (Status: ${task.status.name}):\n\n'
              '${logs.join("\n")}';
        },
      );

  /// Tool to stop a background process.
  static AgentTool stopBackgroundProcess({
    required ProcessManagerService processManager,
  }) =>
      AgentTool(
        name: 'stop_background_process',
        description:
            'Terminates and stops a running background process or server.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'task_id': {
              'type': 'string',
              'description': 'The Task ID to terminate (e.g. "proc_1234abcd").',
            },
          },
          'required': ['task_id'],
        },
        risk: ToolRisk.destructive,
        run: (args) async {
          final taskId = (args['task_id'] as String? ?? '').trim();
          final task = processManager.getTask(taskId);
          if (task == null) {
            return 'Error: Task "$taskId" does not exist.';
          }

          final ok = await processManager.stopProcess(taskId);
          if (ok) {
            return 'Successfully stopped process "${task.displayName}" [${task.id}].';
          } else {
            return 'Process "${task.displayName}" [${task.id}] was already stopped or could not be terminated.';
          }
        },
      );
}
