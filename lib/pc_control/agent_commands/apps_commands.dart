library apps_commands;

import 'dart:io';

import '../pc_control_models.dart';

class AppsCommands {
  AppsCommands({required this.appMap});

  /// Danh sách tên gọi thân thiện -> tên file thực thi.
  /// VD: {'chrome': 'chrome.exe', 'notepad': 'notepad.exe'}.
  /// Đây chỉ là "lối tắt" cho vài app quen thuộc — KHÔNG còn là danh sách
  /// giới hạn duy nhất: [openApp] có thể mở bất kỳ ứng dụng nào đã cài
  /// trên máy (xem các bước fallback bên dưới).
  final Map<String, String> appMap;

  /// Mở một ứng dụng theo tên do người dùng cung cấp (gõ tay hoặc đọc bằng
  /// giọng nói). Thử lần lượt các cách sau, dừng lại ở bước đầu tiên thành
  /// công:
  ///   1. Tên rút gọn có trong [appMap] (vd: "chrome" -> "chrome.exe").
  ///   2. Người dùng gõ thẳng tên file .exe hoặc đường dẫn đầy đủ.
  ///   3. Tên có sẵn trong PATH / "App Paths" của Windows (vd: "code",
  ///      "spotify", "calc") — dùng lệnh `where`.
  ///   4. Tìm shortcut (.lnk) khớp tên trong Start Menu (All Users + User)
  ///      — cho phép mở gần như MỌI app đã cài, kể cả app không có trong
  ///      PATH (Zalo, Word, các app UWP có shortcut, v.v.).
  Future<AgentCommandResult> openApp(Map<String, dynamic> params) async {
    final rawName = (params['name'] as String? ?? '').trim();
    if (rawName.isEmpty) {
      return AgentCommandResult.fail("Thiếu tên ứng dụng cần mở.");
    }
    final lower = rawName.toLowerCase();

    // 1. Tên rút gọn quen thuộc trong appMap.
    final mapped = appMap[lower];
    if (mapped != null) {
      return _launch(mapped, displayName: rawName);
    }

    // 2. Gõ thẳng tên file .exe hoặc đường dẫn đầy đủ tới ứng dụng.
    if (lower.endsWith('.exe') || rawName.contains('\\') || rawName.contains('/')) {
      return _launch(rawName, displayName: rawName);
    }

    // 3. Thử để Windows tự tìm theo PATH / "App Paths" (vd: "code", "spotify").
    final foundInPath = await _resolveViaWhere(rawName);
    if (foundInPath != null) {
      return _launch(foundInPath, displayName: rawName);
    }

    // 4. Tìm shortcut khớp tên trong Start Menu -> mở được hầu hết app đã cài.
    final shortcut = await _findStartMenuShortcut(rawName);
    if (shortcut != null) {
      return _launch(shortcut, displayName: rawName);
    }

    return AgentCommandResult.fail(
      "Không tìm thấy ứng dụng '$rawName' trên máy. Hãy thử đọc rõ hơn tên "
          "ứng dụng, hoặc kiểm tra đã cài đặt ứng dụng này chưa.",
    );
  }

  Future<AgentCommandResult> closeApp(Map<String, dynamic> params) async {
    final rawName = (params['name'] as String? ?? '').trim();
    if (rawName.isEmpty) {
      return AgentCommandResult.fail("Thiếu tên ứng dụng cần đóng.");
    }
    final lower = rawName.toLowerCase();

    // Ưu tiên tên rút gọn trong appMap; nếu không có thì thử coi luôn
    // rawName là tên tiến trình (thêm .exe nếu thiếu) để vẫn đóng được
    // những app không nằm trong danh sách rút gọn.
    var exeName = appMap[lower] ?? rawName;
    if (!exeName.toLowerCase().endsWith('.exe')) {
      exeName = '$exeName.exe';
    }

    try {
      final result = await Process.run('taskkill', ['/IM', exeName, '/F']);
      if (result.exitCode != 0) {
        return AgentCommandResult.fail(
          "Không thể đóng '$rawName' (có thể chưa mở hoặc sai tên tiến trình): ${result.stderr}",
        );
      }
      return AgentCommandResult.ok(
        "Đã đóng $rawName",
        data: {'stdout': result.stdout},
      );
    } catch (e) {
      return AgentCommandResult.fail('Lỗi khi đóng $exeName: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  Future<AgentCommandResult> _launch(String target, {required String displayName}) async {
    try {
      final result = await Process.run('cmd', ['/c', 'start', '""', target]);
      if (result.exitCode != 0) {
        return AgentCommandResult.fail('Lỗi khi mở $displayName: ${result.stderr}');
      }
      return AgentCommandResult.ok("Đã mở $displayName");
    } catch (e) {
      return AgentCommandResult.fail('Lỗi khi mở $displayName: $e');
    }
  }

  /// Nhờ Windows tra `where <name>` (tìm trong PATH và "App Paths" đăng ký
  /// trong registry) — trả về đường dẫn thực thi nếu tìm thấy, null nếu không.
  Future<String?> _resolveViaWhere(String name) async {
    try {
      final result = await Process.run('where', [name]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) return lines.first;
      }
    } catch (_) {
      // `where` không có sẵn hoặc lỗi khác -> bỏ qua, thử cách tiếp theo.
    }
    return null;
  }

  /// Quét shortcut (.lnk) trong Start Menu (dùng chung cho mọi user + của
  /// riêng user hiện tại) và trả về đường dẫn shortcut khớp tên gần đúng
  /// nhất với [query]. Ưu tiên khớp chính xác, sau đó khớp theo tiền tố,
  /// cuối cùng là khớp chứa từ khoá ở bất kỳ đâu trong tên.
  Future<String?> _findStartMenuShortcut(String query) async {
    final programData = Platform.environment['ProgramData'];
    final appData = Platform.environment['AppData'];
    final dirs = <Directory>[
      if (programData != null)
        Directory('$programData\\Microsoft\\Windows\\Start Menu\\Programs'),
      if (appData != null)
        Directory('$appData\\Microsoft\\Windows\\Start Menu\\Programs'),
    ];

    final q = query.toLowerCase();
    String? exactMatch;
    String? prefixMatch;
    String? containsMatch;

    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File || !entity.path.toLowerCase().endsWith('.lnk')) continue;
          final fileName = entity.uri.pathSegments.last;
          final nameNoExt = fileName.substring(0, fileName.length - 4).toLowerCase();

          if (nameNoExt == q) {
            exactMatch ??= entity.path;
          } else if (nameNoExt.startsWith(q)) {
            prefixMatch ??= entity.path;
          } else if (nameNoExt.contains(q)) {
            containsMatch ??= entity.path;
          }
        }
      } catch (_) {
        // Bỏ qua thư mục không đọc được (quyền truy cập, v.v.) và tiếp tục.
      }
    }

    return exactMatch ?? prefixMatch ?? containsMatch;
  }
}
