import 'dart:convert';
import 'package:http/http.dart' as http;

class AiChatService {
  final String baseUrl = "http://10.112.78.39:8000"; // Đảm bảo đúng IP máy tính của bạn

  Future<String?> sendMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': null,
          'message': text, // BẮT BUỘC KHỚP VỚI FASTAPI ('message')
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['bot_reply'];
      } else {
        print("Lỗi /chat (${response.statusCode}): ${response.body}");
        return null;
      }
    } catch (e) {
      print("Lỗi kết nối /chat: $e");
      return null;
    }
  }
}