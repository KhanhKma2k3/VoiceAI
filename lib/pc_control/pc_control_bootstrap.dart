/// Điểm khởi động/dừng duy nhất cho tính năng "Điều khiển máy tính".
///
/// - Trên Windows: tự chạy nền làm AGENT (thay thế hoàn toàn windows-agent/
///   Node.js cũ) — mở app + đăng nhập là xong, không cần cài gì thêm.
/// - Trên các nền tảng khác (Android/iOS...): chạy làm CONTROLLER, cung cấp
///   [controller] cho PcControlScreen dùng để gửi lệnh.
///
/// Gọi [PcControlBootstrap.start] ở 2 chỗ:
///   1. main.dart, ngay sau khi xác nhận `ApiService.isLoggedIn() == true`.
///   2. login_screen.dart, ngay sau khi `ApiService.login()` thành công.
/// Gọi [PcControlBootstrap.stop] mỗi khi logout (main.dart và
/// chat_screen.dart đều có nút đăng xuất riêng, gọi ở cả 2 chỗ).
library pc_control_bootstrap;

import 'dart:io';

import '../services/api_service.dart';
import 'controller_service.dart';
import 'desktop_agent_service.dart';

class PcControlBootstrap {
  PcControlBootstrap._();

  static ControllerService? _controller;
  static DesktopAgentService? _agent;

  /// Chỉ có giá trị trên nền tảng KHÔNG PHẢI Windows — dùng cho
  /// PcControlScreen. Null trên Windows (vì Windows đóng vai trò agent).
  static ControllerService? get controller => _controller;

  static Future<void> start() async {
    final username = await ApiService.getUsername();
    final deviceName = Platform.isWindows
        ? 'PC - ${Platform.localHostname}'
        : (username != null ? 'Điện thoại của $username' : 'Điện thoại');

    if (Platform.isWindows) {
      if (_agent != null) return; // đã chạy rồi, không khởi động lại
      final userHome = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
      final sandboxDir = '$userHome\\VoiceAgentFiles';
      _agent = DesktopAgentService(
        config: DesktopAgentConfig(
          relayUrl: ApiService.relayUrl,
          deviceName: deviceName,
          appMap: const {
            'chrome': 'chrome.exe',
            'notepad': 'notepad.exe',
            'word': 'winword.exe',
            'excel': 'excel.exe',
            'calculator': 'calc.exe',
          },
          fileSandboxDir: sandboxDir,
          logFilePath: '$sandboxDir\\agent.log',
          allowDeleteFiles: false, // giữ nguyên khuyến nghị an toàn từ bản Node.js cũ
          allowUnsafeShell: false,
        ),
        getAuthToken: ApiService.getToken,
      );
      await _agent!.start();
    } else {
      if (_controller != null) return;
      _controller = ControllerService(
        relayUrl: ApiService.relayUrl,
        deviceName: deviceName,
        getAuthToken: ApiService.getToken,
      );
      await _controller!.start();
    }
  }

  static void stop() {
    _agent?.stop();
    _agent = null;
    _controller?.stop();
    _controller = null;
  }
}
