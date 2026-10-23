library apps_commands;

import 'dart:convert';
import 'dart:io';

import '../pc_control_models.dart';
import 'text_match.dart';

class _AppEntry {
  _AppEntry(this.name, this.appId);
  final String name;
  final String appId;
}

class AppsCommands {
  AppsCommands({required this.appMap});

  /// Lối tắt quen thuộc: tên gọi -> tên file thực thi. Không còn là danh
  /// sách giới hạn: ứng dụng đã cài đều được tìm qua chỉ mục Start Menu.
  final Map<String, String> appMap;

  /// Điểm khớp tối thiểu để chấp nhận một ứng dụng.
  static const double _minScore = 0.72;

  /// Tên tiếng Việt -> các từ khoá để tìm trong chỉ mục (nhiều khả năng
  /// Windows đặt tên tiếng Anh hoặc tiếng Việt tuỳ ngôn ngữ cài đặt).
  static const Map<String, List<String>> _aliases = {
    'cài đặt': ['settings', 'cài đặt'],
    'cài đặt windows': ['settings'],
    'máy tính': ['calculator', 'máy tính'],
    'máy tính bỏ túi': ['calculator'],
    'ghi chú': ['notepad', 'sticky notes', 'ghi chú'],
    'sổ tay': ['notepad'],
    'trình duyệt': ['chrome', 'edge', 'firefox', 'brave'],
    'trình duyệt web': ['chrome', 'edge', 'firefox'],
    'lịch': ['calendar', 'lịch'],
    'thư': ['mail', 'outlook'],
    'ảnh': ['photos', 'ảnh'],
    'bản đồ': ['maps'],
    'đồng hồ': ['clock', 'alarms'],
    'thời tiết': ['weather'],
    'cửa hàng': ['microsoft store', 'store'],
    'ghi âm': ['sound recorder', 'voice recorder'],
    'máy ảnh': ['camera'],
    'camera': ['camera'],
    'trình phát nhạc': ['media player', 'spotify', 'groove'],
    'bảng điều khiển': ['control panel'],
    'vẽ': ['paint'],
    'công cụ cắt': ['snipping tool'],
    'chụp màn hình': ['snipping tool'],
  };

  /// Công cụ hệ thống có thể không nằm trong Start Menu -> lệnh chạy trực tiếp.
  static const Map<String, String> _systemTools = {
    'quản lý tác vụ': 'taskmgr.exe',
    'task manager': 'taskmgr.exe',
    'bảng điều khiển': 'control.exe',
    'dòng lệnh': 'cmd.exe',
    'command prompt': 'cmd.exe',
    'cmd': 'cmd.exe',
    'powershell': 'powershell.exe',
    'trình quản lý tệp': 'explorer.exe',
    'quản lý tệp': 'explorer.exe',
    'file explorer': 'explorer.exe',
    'thư mục': 'explorer.exe',
    'paint': 'mspaint.exe',
    'notepad': 'notepad.exe',
    'máy tính bỏ túi': 'calc.exe',
    'calculator': 'calc.exe',
  };

  List<_AppEntry>? _index;
  DateTime? _indexAt;

  // ---------------------------------------------------------------------
  // MỞ ỨNG DỤNG
  // ---------------------------------------------------------------------
  /// Thứ tự: appMap -> .exe/đường dẫn -> công cụ hệ thống -> chỉ mục toàn bộ
  /// ứng dụng đã cài (Win32 + UWP + Store, khớp mờ, bỏ dấu, từ đồng nghĩa
  /// Việt-Anh) -> `where` -> quét shortcut Start Menu.
  Future<AgentCommandResult> openApp(Map<String, dynamic> params) async {
    final rawName = (params['name'] as String? ?? '').trim();
    if (rawName.isEmpty) {
      return AgentCommandResult.fail("Thiếu tên ứng dụng cần mở.");
    }
    final lower = rawName.toLowerCase();

    // 1. Lối tắt trong appMap.
    final mapped = appMap[lower];
    if (mapped != null) return _launch(mapped, displayName: rawName);

    // 2. Tên file .exe hoặc đường dẫn đầy đủ.
    if (lower.endsWith('.exe') || rawName.contains('\\') || rawName.contains('/')) {
      return _launch(rawName, displayName: rawName);
    }

    // 3. Công cụ hệ thống quen thuộc.
    final tool = _systemTools[lower];
    if (tool != null) return _launch(tool, displayName: rawName);

    // 4. Chỉ mục ứng dụng đã cài (mở được cả Cài đặt, Máy tính, Store...).
    final terms = <String>{rawName, ...?_aliases[lower]}.toList();
    final index = await _loadIndex();
    final match = _bestApp(index, terms);
    if (match != null) {
      final ok = await _launchAppId(match.appId);
      if (ok) return AgentCommandResult.ok("Đã mở ${match.name}");
    }

    // 5. PATH / App Paths.
    final foundInPath = await _resolveViaWhere(rawName);
    if (foundInPath != null) return _launch(foundInPath, displayName: rawName);

    // 6. Shortcut Start Menu (dự phòng cho app vừa cài, chỉ mục chưa kịp cập nhật).
    final fresh = await _loadIndex(force: true);
    final retry = _bestApp(fresh, terms);
    if (retry != null && retry.appId != match?.appId) {
      if (await _launchAppId(retry.appId)) {
        return AgentCommandResult.ok("Đã mở ${retry.name}");
      }
    }
    final shortcut = await _findStartMenuShortcut(rawName);
    if (shortcut != null) return _launch(shortcut, displayName: rawName);

    final hints = _topSuggestions(fresh, terms);
    return AgentCommandResult.fail(
      "Không tìm thấy ứng dụng '$rawName' trên máy."
          "${hints.isEmpty ? '' : ' Ý bạn là: ${hints.join(', ')}?'}",
      data: {'suggestions': hints},
    );
  }

  // ---------------------------------------------------------------------
  // ĐÓNG ỨNG DỤNG
  // ---------------------------------------------------------------------
  /// Thứ tự: appMap -> khớp mờ với các cửa sổ đang mở (tên tiến trình +
  /// tiêu đề cửa sổ) -> đoán tên tiến trình `<tên>.exe`.
  Future<AgentCommandResult> closeApp(Map<String, dynamic> params) async {
    final rawName = (params['name'] as String? ?? '').trim();
    if (rawName.isEmpty) {
      return AgentCommandResult.fail("Thiếu tên ứng dụng cần đóng.");
    }
    final lower = rawName.toLowerCase();

    final mapped = appMap[lower];
    if (mapped != null) return _taskkillImage(mapped, rawName);

    // Khớp với cửa sổ đang mở.
    final windows = await _openWindows();
    final terms = <String>{rawName, ...?_aliases[lower]}.toList();
    Map<String, dynamic>? best;
    var bestScore = 0.0;
    for (final w in windows) {
      final proc = (w['ProcessName'] ?? '').toString();
      final title = (w['MainWindowTitle'] ?? '').toString();
      for (final t in terms) {
        final s = [TextMatch.score(t, proc), TextMatch.score(t, title)]
            .reduce((a, b) => a > b ? a : b);
        if (s > bestScore) {
          bestScore = s;
          best = w;
        }
      }
    }
    if (best != null && bestScore >= _minScore) {
      return _closeWindowOf(best, rawName);
    }

    // Dự phòng: coi tên là tên tiến trình.
    return _taskkillImage(rawName, rawName);
  }

  Future<AgentCommandResult> _closeWindowOf(Map<String, dynamic> w, String display) async {
    final pid = w['Id'];
    final proc = (w['ProcessName'] ?? '').toString();
    final title = (w['MainWindowTitle'] ?? '').toString();
    try {
      // Đóng nhẹ nhàng trước (cho phép app hỏi lưu file).
      await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-Process -Id $pid -ErrorAction SilentlyContinue).CloseMainWindow() | Out-Null',
      ]);
      await Future.delayed(const Duration(milliseconds: 1500));
      // ApplicationFrameHost chứa nhiều app UWP -> không được kill cưỡng bức.
      if (proc.toLowerCase() != 'applicationframehost') {
        final still = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'if (Get-Process -Id $pid -ErrorAction SilentlyContinue) { "yes" }',
        ]);
        if ((still.stdout as String).contains('yes')) {
          await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
        }
      }
      return AgentCommandResult.ok(
        "Đã đóng ${title.isNotEmpty ? title : display}",
        data: {'process': proc, 'title': title},
      );
    } catch (e) {
      return AgentCommandResult.fail('Lỗi khi đóng $display: $e');
    }
  }

  Future<AgentCommandResult> _taskkillImage(String name, String display) async {
    var exe = name;
    if (!exe.toLowerCase().endsWith('.exe')) exe = '$exe.exe';
    try {
      final result = await Process.run('taskkill', ['/IM', exe, '/F']);
      if (result.exitCode != 0) {
        return AgentCommandResult.fail(
          "Không thể đóng '$display' (có thể chưa mở hoặc sai tên).",
        );
      }
      return AgentCommandResult.ok("Đã đóng $display", data: {'stdout': result.stdout});
    } catch (e) {
      return AgentCommandResult.fail('Lỗi khi đóng $exe: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Chỉ mục ứng dụng đã cài
  // ---------------------------------------------------------------------
  /// `Get-StartApps` liệt kê MỌI mục trong Start (Win32, UWP, Store, Cài đặt...).
  /// Cache 10 phút; `force` để làm mới khi không tìm thấy.
  Future<List<_AppEntry>> _loadIndex({bool force = false}) async {
    final fresh = _index != null &&
        _indexAt != null &&
        DateTime.now().difference(_indexAt!) < const Duration(minutes: 10);
    if (!force && fresh) return _index!;

    final entries = <_AppEntry>[];
    try {
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '[Console]::OutputEncoding=[Text.Encoding]::UTF8; '
              'Get-StartApps | Select-Object Name,AppID | ConvertTo-Json -Compress',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final out = (r.stdout as String).trim();
      if (r.exitCode == 0 && out.isNotEmpty) {
        final decoded = jsonDecode(out);
        final list = decoded is List ? decoded : [decoded]; // 1 mục -> object
        for (final e in list) {
          if (e is Map && e['Name'] != null && e['AppID'] != null) {
            entries.add(_AppEntry(e['Name'].toString(), e['AppID'].toString()));
          }
        }
      }
    } catch (_) {
      // PowerShell lỗi -> chỉ mục rỗng, các bước dự phòng phía sau vẫn chạy.
    }
    _index = entries;
    _indexAt = DateTime.now();
    return entries;
  }

  _AppEntry? _bestApp(List<_AppEntry> index, List<String> terms) {
    _AppEntry? best;
    var bestScore = 0.0;
    for (final app in index) {
      for (final t in terms) {
        var s = TextMatch.score(t, app.name);
        // Bằng điểm: ưu tiên tên ngắn hơn ("Word" thắng "Word Viewer").
        if (s > bestScore ||
            (s == bestScore && best != null && app.name.length < best.name.length)) {
          if (s >= _minScore) {
            bestScore = s;
            best = app;
          }
        }
      }
    }
    return best;
  }

  List<String> _topSuggestions(List<_AppEntry> index, List<String> terms) {
    final scored = <MapEntry<String, double>>[];
    for (final app in index) {
      var s = 0.0;
      for (final t in terms) {
        final v = TextMatch.score(t, app.name);
        if (v > s) s = v;
      }
      if (s >= 0.5) scored.add(MapEntry(app.name, s));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(3).map((e) => e.key).toList();
  }

  /// Mở bằng AppID: hoạt động cho cả Win32 lẫn UWP.
  Future<bool> _launchAppId(String appId) async {
    try {
      // explorer.exe thường trả exit code 1 dù mở thành công -> không dựa vào exitCode.
      await Process.start(
        'explorer.exe',
        ['shell:AppsFolder\\$appId'],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Các cửa sổ đang mở (có tiêu đề) để khớp lệnh đóng.
  Future<List<Map<String, dynamic>>> _openWindows() async {
    try {
      final r = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '[Console]::OutputEncoding=[Text.Encoding]::UTF8; '
              'Get-Process | Where-Object { \$_.MainWindowTitle -ne "" } | '
              'Select-Object Id,ProcessName,MainWindowTitle | ConvertTo-Json -Compress',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      final out = (r.stdout as String).trim();
      if (r.exitCode != 0 || out.isEmpty) return [];
      final decoded = jsonDecode(out);
      final list = decoded is List ? decoded : [decoded];
      return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------
  // Helpers cũ (giữ nguyên)
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
    } catch (_) {}
    return null;
  }

  Future<String?> _findStartMenuShortcut(String query) async {
    final programData = Platform.environment['ProgramData'];
    final appData = Platform.environment['AppData'];
    final dirs = <Directory>[
      if (programData != null)
        Directory('$programData\\Microsoft\\Windows\\Start Menu\\Programs'),
      if (appData != null)
        Directory('$appData\\Microsoft\\Windows\\Start Menu\\Programs'),
    ];

    String? best;
    var bestScore = 0.0;
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File || !entity.path.toLowerCase().endsWith('.lnk')) continue;
          final fileName = entity.uri.pathSegments.last;
          final nameNoExt = fileName.substring(0, fileName.length - 4);
          final s = TextMatch.score(query, nameNoExt);
          if (s > bestScore) {
            bestScore = s;
            best = entity.path;
          }
        }
      } catch (_) {}
    }
    return bestScore >= _minScore ? best : null;
  }
}