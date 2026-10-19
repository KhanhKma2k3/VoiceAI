import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // IP IPv4 mới cập nhật chuẩn từ ipconfig của bạn
  static const String baseUrl = "http://10.112.78.39:8000";


  static Future<Map<String, dynamic>?> register(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        await _saveToken(data['access_token'], data['username']);
        return data;
      } else {
        final err = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(err['detail'] ?? "Đăng ký thất bại");
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        await _saveToken(data['access_token'], data['username']);
        return data;
      } else {
        final err = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(err['detail'] ?? "Đăng nhập thất bại");
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> _saveToken(String token, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    await prefs.setString('username', username);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('jwt_token');
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
  // 1. Gửi tin nhắn đến API /chat
  static Future<String?> sendMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': null,
          'message': text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['bot_reply'];
      } else {
        print("Lỗi Server Chat (${response.statusCode}): ${response.body}");
        return null;
      }
    } catch (e) {
      print("Lỗi kết nối /chat: $e");
      return null;
    }
  }

  // 2. Gọi API /tts để sinh âm thanh
  static Future<List<int>?> getSpeechAudio(String text, {String? voice}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'voice': voice ?? 'zalo_female_north', // Mặc định Zalo Bắc
          'rate': '+0%',
        }),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print("Lỗi Server TTS (${response.statusCode}): ${response.body}");
        return null;
      }
    } catch (e) {
      print("Lỗi kết nối /tts: $e");
      return null;
    }
  }

  // 3. API Speech-to-Text /stt (ĐÃ BỔ SUNG THÊM VÀO ĐÂY)
  static Future<String?> transcribeAudio(File file) async {
    try {
      if (!await file.exists() || await file.length() == 0) {
        print("Lỗi: File âm thanh rỗng hoặc không tồn tại!");
        return null;
      }

      var uri = Uri.parse('$baseUrl/stt');
      var request = http.MultipartRequest('POST', uri);

      var multipartFile = await http.MultipartFile.fromPath(
        'file', // Field name trùng khớp UploadFile trong FastAPI
        file.path,
        filename: file.path.split('/').last,
        contentType: MediaType('audio', 'm4a'),
      );

      request.files.add(multipartFile);

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['text'];
      } else {
        print("Lỗi STT từ Server (${response.statusCode}): ${response.body}");
        return null;
      }
    } catch (e) {
      print("Lỗi kết nối /stt: $e");
      return null;
    }
  }

  // 4. Lấy danh sách lịch sử trò chuyện
  static Future<List<dynamic>> getHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/history'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return data;
      } else {
        print("Lỗi lấy lịch sử (${response.statusCode}): ${response.body}");
        return [];
      }
    } catch (e) {
      print("Lỗi kết nối /history: $e");
      return [];
    }
  }

  // Bổ sung vào class ApiService:
  static Future<Map<String, dynamic>?> sendVoiceCommand(File file) async {
    try {
      var uri = Uri.parse('$baseUrl/voice-assistant');
      var request = http.MultipartRequest('POST', uri);

      var multipartFile = await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: file.path.split('/').last,
        contentType: MediaType('audio', 'm4a'),
      );

      request.files.add(multipartFile);

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // Đọc header trả về văn bản
        String userText = response.headers['x-user-text'] != null
            ? utf8.decode(response.headers['x-user-text']!.codeUnits)
            : "";
        String botReply = response.headers['x-bot-reply'] != null
            ? utf8.decode(response.headers['x-bot-reply']!.codeUnits)
            : "";

        return {
          'user_text': userText,
          'bot_reply': botReply,
          'audio_bytes': response.bodyBytes, // Byte mp3 để phát loa ngay
        };
      } else {
        print("Lỗi Voice Assistant: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Lỗi kết nối Voice Assistant: $e");
      return null;
    }
  }
}