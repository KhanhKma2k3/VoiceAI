import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

class TtsService {
  Future<File?> generateSpeech(
      String text, {
        String voiceCode = 'vi-VN-HoaiMyNeural',
        int ratePercent = 0,
        int pitchHz = 0,
      }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'voice': voiceCode,
          'rate': '${ratePercent >= 0 ? "+" : ""}$ratePercent%',
          'pitch': '${pitchHz >= 0 ? "+" : ""}${pitchHz}Hz',
        }),
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/response.mp3');
        await file.writeAsBytes(bytes);
        return file;
      } else {
        print("Lỗi TTS (${response.statusCode}): ${response.body}");
        return null;
      }
    } catch (e) {
      print("Lỗi kết nối /tts: $e");
      return null;
    }
  }
}