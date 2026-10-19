import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

/// Trước đây class này tự gọi http.post trực tiếp tới /tts mà KHÔNG gắn
/// token đăng nhập -> luôn bị 401 sau khi backend bật xác thực JWT bắt buộc.
/// Giờ chuyển sang gọi qua ApiService (nơi duy nhất biết cách đính kèm
/// header Authorization), tránh viết trùng logic gọi API ở 2 nơi.
class TtsService {
  Future<File?> generateSpeech(
      String text, {
        String voiceCode = 'vi-VN-HoaiMyNeural',
        int ratePercent = 0,
        int pitchHz = 0,
      }) async {
    final bytes = await ApiService.getSpeechAudio(
      text,
      voice: voiceCode,
      rate: '${ratePercent >= 0 ? "+" : ""}$ratePercent%',
      pitch: '${pitchHz >= 0 ? "+" : ""}${pitchHz}Hz',
    );

    if (bytes == null) return null;

    final tempDir = await getTemporaryDirectory();
    // Mỗi lần tạo 1 tên file RIÊNG BIỆT (thay vì "response.mp3" cố định)
    // để tránh lỗi PathAccessException trên Windows khi just_audio vẫn
    // đang giữ khóa (lock) file cũ trong lúc phát.
    final fileName = 'tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }
}