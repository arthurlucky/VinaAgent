import 'dart:io';

enum ProcessTaskStatus {
  running,
  stopped,
  failed,
}

class ProcessTask {
  ProcessTask({
    required this.id,
    required this.command,
    required this.startedAt,
    this.name,
    this.scriptPath,
    this.workingDirectory,
    this.pid,
    this.process,
    this.status = ProcessTaskStatus.running,
    this.exitCode,
    List<String>? initialLogs,
  }) : logLines = initialLogs ?? <String>[];

  final String id;
  final String command;
  final DateTime startedAt;
  final String? name;
  final String? scriptPath;
  final String? workingDirectory;
  int? pid;
  Process? process;
  ProcessTaskStatus status;
  int? exitCode;
  final List<String> logLines;

  Duration get uptime => DateTime.now().difference(startedAt);

  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    if (scriptPath != null && scriptPath!.trim().isNotEmpty) {
      return scriptPath!.split('/').last;
    }
    return command;
  }

  void appendLog(String line) {
    logLines.add(line);
    if (logLines.length > 1000) {
      logLines.removeRange(0, logLines.length - 1000);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': displayName,
        'command': command,
        'scriptPath': scriptPath,
        'workingDirectory': workingDirectory,
        'pid': pid,
        'status': status.name,
        'exitCode': exitCode,
        'uptimeSeconds': uptime.inSeconds,
        'startedAt': startedAt.toIso8601String(),
        'logCount': logLines.length,
      };
}
