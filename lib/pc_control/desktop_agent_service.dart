library desktop_agent_service;

import 'agent_commands/apps_commands.dart';
import 'agent_commands/file_commands.dart';
import 'agent_commands/media_commands.dart';
import 'agent_commands/shell_commands.dart';
import 'pc_control_models.dart';
import 'pc_control_socket.dart';

class DesktopAgentConfig {
  DesktopAgentConfig({
    required this.relayUrl,
    required this.deviceName,
    required this.appMap,
    required this.fileSandboxDir,
    required this.logFilePath,
    this.allowDeleteFiles = false,
    this.allowUnsafeShell = false,
  });

  final String relayUrl;
  final String deviceName;
  final Map<String, String> appMap;
  final String fileSandboxDir;
  final String logFilePath;
  final bool allowDeleteFiles;
  final bool allowUnsafeShell;
}

class DesktopAgentService {
  DesktopAgentService({
    required this.config,
    required Future<String?> Function() getAuthToken,
  }) {
    _socket = PcControlSocket(
      relayUrl: config.relayUrl,
      role: 'agent',
      deviceName: config.deviceName,
      getAuthToken: getAuthToken,
    );
    _apps = AppsCommands(appMap: config.appMap);
    _media = MediaCommands();
    _files = FileCommands(sandboxDir: config.fileSandboxDir, allowDeleteFiles: config.allowDeleteFiles);
    _shell = ShellCommands(
      allowUnsafeShell: config.allowUnsafeShell,
      workingDir: config.fileSandboxDir,
      logFilePath: config.logFilePath,
    );
  }

  final DesktopAgentConfig config;
  late final PcControlSocket _socket;
  late final AppsCommands _apps;
  late final MediaCommands _media;
  late final FileCommands _files;
  late final ShellCommands _shell;

  Stream<bool> get connectionState => _socket.connectionState;

  Future<void> start() async {
    _socket.messages.listen(_handleMessage);
    await _socket.connect();
  }

  void stop() => _socket.dispose();

  Future<void> _handleMessage(Map<String, dynamic> msg) async {
    if (msg['type'] != 'command') return;

    final action = msg['action'] as String? ?? '';
    final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? {};
    final requestId = msg['requestId'] as String? ?? '';
    final sourceConnId = msg['sourceConnId'] as String? ?? '';

    late AgentCommandResult result;
    try {
      switch (action) {
        case 'open_app':
          result = await _apps.openApp(params);
          break;
        case 'close_app':
          result = await _apps.closeApp(params);
          break;
        case 'media_control':
          result = await _media.mediaControl(params);
          break;
        case 'list_files':
          result = await _files.listFiles(params);
          break;
        case 'create_file':
          result = await _files.createFile(params);
          break;
        case 'rename_file':
          result = await _files.renameFile(params);
          break;
        case 'delete_file':
          result = await _files.deleteFile(params);
          break;
        case 'run_shell':
          result = await _shell.runShell(params);
          break;
        default:
          result = AgentCommandResult.fail("Action '$action' không được hỗ trợ.");
      }
    } catch (e) {
      result = AgentCommandResult.fail('Lỗi xử lý lệnh: $e');
    }

    _socket.sendResult(
      sourceConnId: sourceConnId,
      requestId: requestId,
      success: result.success,
      message: result.message,
      data: result.data,
    );
  }
}
