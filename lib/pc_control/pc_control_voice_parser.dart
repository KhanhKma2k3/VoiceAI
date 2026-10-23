/// Bộ phân tích văn bản (đã được STT chuyển từ giọng nói) thành 1 lệnh
/// điều khiển PC cụ thể (action + params), dùng bởi [PcControlScreen].
///
/// Đây là bộ nhận dạng theo từ khoá đơn giản (không cần gọi thêm AI) — đủ
/// dùng cho các câu lệnh ngắn kiểu "mở Chrome", "đóng Zalo", "tăng âm
/// lượng"... Vì [AppsCommands.openApp] phía agent đã có khả năng tự tìm
/// và mở BẤT KỲ ứng dụng nào đã cài trên máy, phần "tên ứng dụng" ở đây
/// chỉ cần trích ra đúng đoạn văn bản người dùng nói, không cần biết trước
/// danh sách app.
library pc_control_voice_parser;

class VoicePcCommand {
  VoicePcCommand({required this.action, required this.params, required this.label});

  /// Tên action gửi cho agent (vd: 'open_app', 'media_control'...).
  final String action;
  final Map<String, dynamic> params;

  /// Mô tả ngắn để hiển thị lại cho người dùng biết app đã "hiểu" lệnh gì
  /// trước khi thực thi (vd: 'Mở "chrome"').
  final String label;
}

class PcVoiceCommandParser {
  PcVoiceCommandParser._();

  // Các tiền tố "mở ứng dụng" / "đóng ứng dụng", xếp theo thứ tự DÀI -> NGẮN
  // để ưu tiên khớp cụm cụ thể hơn trước khi rơi về tiền tố ngắn chung chung.
  static const _openPrefixes = [
    'mở ứng dụng ',
    'mở app ',
    'khởi động ứng dụng ',
    'khởi động ',
    'chạy ứng dụng ',
    'chạy ',
    'mở ',
  ];

  static const _closePrefixes = [
    'đóng ứng dụng ',
    'đóng app ',
    'thoát ứng dụng ',
    'tắt ứng dụng ',
    'thoát ',
    'đóng ',
    'tắt ',
  ];

  // Lỗi STT nghe nhầm thường gặp -> cụm đúng (bổ sung dần theo thực tế).
  static const _phraseFixes = {
    'cái đặt': 'cài đặt',
    'cải đặt': 'cài đặt',
    'cài đạt': 'cài đặt',
    'cài đật': 'cài đặt',
    'mỡ ': 'mở ',
    'mơ ': 'mở ',
    'mợ ': 'mở ',
    'mờ ': 'mở ',
    'má ': 'mở ',
    'mà ': 'mở ',
  };

  // Từ đệm cuối câu, bỏ đi để lấy đúng tên ứng dụng ("mở zalo lên đi").
  static const _fillerTail = [
    ' lên đi', ' lên', ' đi', ' giúp tôi', ' giùm tôi', ' cho tôi', ' nhé', ' nha', ' với', ' ra',
  ];

  /// Trả về `null` nếu không nhận diện được câu lệnh nào phù hợp.
  static VoicePcCommand? parse(String rawText) {
    final text = _normalize(rawText);
    if (text.isEmpty) return null;

    // 1. Điều khiển media — kiểm tra TRƯỚC vì các cụm như "tắt tiếng" dùng
    //    chung từ "tắt" với lệnh đóng ứng dụng, dễ bị nhận nhầm nếu để sau.
    if (_containsAny(text, ['tắt tiếng', 'im lặng', 'câm luôn', 'mute'])) {
      return VoicePcCommand(
        action: 'media_control',
        params: {'action': 'mute'},
        label: 'Tắt tiếng',
      );
    }
    if (_containsAny(text, [
      'tăng âm lượng',
      'to lên',
      'to hơn',
      'âm lượng lên',
      'volume up',
    ])) {
      return VoicePcCommand(
        action: 'media_control',
        params: {'action': 'volume_up'},
        label: 'Tăng âm lượng',
      );
    }
    if (_containsAny(text, [
      'giảm âm lượng',
      'nhỏ lại',
      'nhỏ hơn',
      'âm lượng xuống',
      'volume down',
    ])) {
      return VoicePcCommand(
        action: 'media_control',
        params: {'action': 'volume_down'},
        label: 'Giảm âm lượng',
      );
    }
    if (_containsAny(text, [
      'phát nhạc',
      'phát tiếp',
      'tạm dừng',
      'tiếp tục phát',
      'play',
      'pause',
    ])) {
      return VoicePcCommand(
        action: 'media_control',
        params: {'action': 'play_pause'},
        label: 'Phát / Tạm dừng',
      );
    }
    if (_containsAny(text, ['bài tiếp theo', 'next track', 'nhạc tiếp'])) {
      return VoicePcCommand(
        action: 'media_control',
        params: {'action': 'next'},
        label: 'Bài tiếp theo',
      );
    }
    if (_containsAny(text, ['bài trước', 'previous track', 'nhạc trước'])) {
      return VoicePcCommand(
        action: 'media_control',
        params: {'action': 'prev'},
        label: 'Bài trước',
      );
    }

    // 2. Mở ứng dụng (bất kỳ) — trích tên app ngay sau các cụm mở đầu.
    final openName = _extractAfterAny(text, _openPrefixes);
    if (openName != null && openName.isNotEmpty) {
      return VoicePcCommand(
        action: 'open_app',
        params: {'name': openName},
        label: 'Mở "$openName"',
      );
    }

    // 3. Đóng / thoát ứng dụng.
    final closeName = _extractAfterAny(text, _closePrefixes);
    if (closeName != null && closeName.isNotEmpty) {
      return VoicePcCommand(
        action: 'close_app',
        params: {'name': closeName},
        label: 'Đóng "$closeName"',
      );
    }

    return null;
  }

  static String _normalize(String text) {
    var t = text.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'[.!?,]+$'), '').trim();
    _phraseFixes.forEach((wrong, right) {
      if (wrong.endsWith(' ')) {
        // Tiền tố: chỉ sửa khi đứng ĐẦU câu.
        if (t.startsWith(wrong)) t = right + t.substring(wrong.length);
      } else {
        t = t.replaceAll(wrong, right);
      }
    });
    return t;
  }

  static bool _containsAny(String text, List<String> keywords) =>
      keywords.any(text.contains);

  /// Thử từng tiền tố trong [prefixes] (đã sắp DÀI -> NGẮN); trả về phần
  /// còn lại sau tiền tố khớp ĐẦU TIÊN, hoặc `null` nếu không có tiền tố
  /// nào khớp phần đầu câu.
  static String? _extractAfterAny(String text, List<String> prefixes) {
    for (final prefix in prefixes) {
      if (text.startsWith(prefix)) {
        final rest = text.substring(prefix.length).trim();
        // Bỏ thêm chữ "ứng dụng"/"app" lỡ còn sót lại (vd: "mở cho tôi ứng dụng chrome").
        var name = rest.replaceFirst(RegExp(r'^(cho tôi\s+)?(ứng dụng\s+|app\s+)?'), '').trim();
        // Bỏ từ đệm cuối câu ("zalo lên đi" -> "zalo"). Chỉ làm ở đây để
        // không làm hỏng cụm media như "to lên", "âm lượng lên".
        var changed = true;
        while (changed) {
          changed = false;
          for (final f in _fillerTail) {
            if (name.endsWith(f)) {
              name = name.substring(0, name.length - f.length).trim();
              changed = true;
            }
          }
        }
        return name;
      }
    }
    return null;
  }
}