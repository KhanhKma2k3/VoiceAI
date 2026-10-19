library shell_commands;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../pc_control_models.dart';

class ShellCommands {
  ShellCommands({
    required this.allowUnsafeShell,
    required this.workingDir,
    required this.logFilePath,
  });

  final bool allowUnsafeShell;
  final String workingDir;
  final String logFilePath;

  Future<void> _log(String command, AgentCommandResult result) async {
    final line = '[${DateTime.now().toIso8601String()}] SHELL: $command => '
        '${result.success ? 'OK' : 'FAIL'} ${result.message}\n';
    try {
      await File(logFilePath).writeAsString(line, mode: FileMode.append);
    } catch (_) {
      // không để lỗi log làm crash agent
    }
  }

  Future<AgentCommandResult> runShell(Map<String, dynamic> params) async {
    if (!allowUnsafeShell) {
      return AgentCommandResult.fail(
        'Chạy shell command tùy ý đang bị TẮT trong cấu hình (allowUnsafeShell=false).',
      );
    }
    if (params['confirm'] != true) {
      return AgentCommandResult.fail('Cần xác nhận (confirm: true) trước khi chạy shell command.');
    }
    final command = params['command'];
    if (command is! String || command.isEmpty) {
      return AgentCommandResult.fail('Thiếu params.command');
    }

    try {
      final result = await Process.run(
        'cmd',
        ['/c', command],
        workingDirectory: p.absolute(workingDir),
      ).timeout(const Duration(seconds: 15));

      final agentResult = result.exitCode == 0
          ? AgentCommandResult.ok('Đã chạy lệnh', data: {'stdout': result.stdout, 'stderr': result.stderr})
          : AgentCommandResult.fail('Lỗi: exit code ${result.exitCode}', data: {'stderr': result.stderr});

      await _log(command, agentResult);
      return agentResult;
    } catch (e) {
      final fail = AgentCommandResult.fail('Lỗi: $e');
      await _log(command, fail);
      return fail;
    }
  }
}
