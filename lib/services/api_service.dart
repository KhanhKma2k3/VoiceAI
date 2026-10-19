import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // IP IPv4 của máy chạy backend trong mạng LAN khi phát triển.
  // ⚠️ Cần đổi theo IP thật của máy bạn (ipconfig / ifconfig).
  // Với bản build thật (release), nên trỏ về domain/HTTPS thay vì IP LAN.
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.trolyamthanh.online',
  );

  // ---------- Token helpers ----------

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  /// Trả về JWT hiện tại (null nếu chưa đăng nhập). Dùng cho module
  /// pc_control để xác thực với Relay Server bằng CHÍNH token đăng nhập
  /// này — không cần token/deviceId cấu hình tay riêng nữa.
  static Future<String?> getToken() => _getToken();

  /// Tên tài khoản hiện tại (đã lưu lúc login), dùng làm tên hiển thị cho
  /// thiết bị (deviceName) khi ghép nối Điều khiển PC.
  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  /// Địa chỉ WebSocket của Relay Server (tính năng Điều khiển PC).
  /// Mặc định dùng CHUNG HOST với [baseUrl] (tiện khi dev qua LAN, vì
  /// backend và relay-server-v2 thường chạy cùng máy lúc test). Đổi
  /// `relayPort`/domain khi deploy thật (nên dùng wss:// qua HTTPS).
  static const String relayUrl = String.fromEnvironment(
    'RELAY_URL',
    defaultValue: 'wss://relay.trolyamthanh.online',
  );

  /// Header dùng chung cho các API cần đăng nhập.
  /// Trước đây token được lưu lúc login nhưng KHÔNG BAO GIỜ được gửi kèm
  /// request nào khác -> backend cũ cũng không kiểm tra nên "có vẻ chạy",
  /// nhưng thực chất mọi endpoint đều mở public. Giờ backend đã bắt buộc
  /// JWT hợp lệ, nên mọi request phải đính kèm header Authorization.
  static Future<Map<String, String>> _authHeaders({String? contentType}) async {
    final token = await _getToken();
    return {
      if (contentType != null) 'Content-Type': contentType,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ---------- Auth ----------

  /// Đọc thông báo lỗi từ response của backend (trường `detail`).
  static String _errorDetail(http.Response response, String fallback) {
    try {
      final err = jsonDecode(utf8.decode(response.bodyBytes));
      final detail = err['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      // FastAPI trả list khi lỗi validate dữ liệu đầu vào.
      if (detail is List && detail.isNotEmpty && detail.first is Map) {
        return (detail.first['msg'] ?? fallback).toString();
      }
    } catch (_) {}
    return fallback;
  }

  static Future<Map<String, dynamic>> _postAuth(
      String path,
      Map<String, dynamic> body,
      String failMessage,
      ) async {
    final http.Response response;
    try {
      response = await http
          .post(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      // Gửi mail qua SMTP có thể mất vài giây nên cho timeout rộng hơn.
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw Exception("Máy chủ phản hồi quá lâu, vui lòng thử lại.");
    } on SocketException {
      throw Exception("Không kết nối được máy chủ. Kiểm tra mạng và thử lại.");
    } on http.ClientException {
      throw Exception("Không kết nối được máy chủ. Kiểm tra mạng và thử lại.");
    }
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception(_errorDetail(response, failMessage));
  }

  static Future<Map<String, dynamic>?> register(
      String username,
      String password, {
        String? email,
      }) async {
    final data = await _postAuth(
      '/register',
      {
        'username': username,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
      },
      "Đăng ký thất bại",
    );
    await _saveSession(data);
    return data;
  }

  /// [identifier] có thể là tên tài khoản hoặc email.
  static Future<Map<String, dynamic>?> login(String identifier, String password) async {
    final data = await _postAuth(
      '/login',
      {'username': identifier, 'password': password},
      "Đăng nhập thất bại",
    );
    await _saveSession(data);
    return data;
  }

  /// Đăng nhập bằng Google: gửi `id_token` lấy từ google_sign_in lên server để
  /// server xác minh và cấp JWT của app.
  static Future<Map<String, dynamic>?> loginWithGoogle(String idToken) async {
    final data = await _postAuth(
      '/auth/google',
      {'id_token': idToken},
      "Đăng nhập Google thất bại",
    );
    await _saveSession(data);
    return data;
  }

  /// Yêu cầu gửi mã xác nhận (6 số) về email để đặt lại mật khẩu.
  static Future<String> forgotPassword(String email) async {
    final data = await _postAuth(
      '/forgot-password',
      {'email': email},
      "Không gửi được mã xác nhận",
    );
    return (data['message'] ?? '').toString();
  }

  static Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final data = await _postAuth(
      '/reset-password',
      {'email': email, 'code': code, 'new_password': newPassword},
      "Đặt lại mật khẩu thất bại",
    );
    return (data['message'] ?? '').toString();
  }

  /// Thông tin tài khoản đã lưu cục bộ (hiện ngay, không cần chờ mạng).
  static Future<Map<String, String?>> getCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'username': prefs.getString('username'),
      'email': prefs.getString('email'),
      'display_name': prefs.getString('display_name'),
    };
  }

  /// Lấy hồ sơ mới nhất từ server (GET /me) và cập nhật bản lưu cục bộ.
  /// Trả về null nếu lỗi mạng/phiên hết hạn (khi đó dùng bản lưu cục bộ).
  static Future<Map<String, String?>?> fetchProfile() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/me'),
        headers: await _authHeaders(),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await _putOrRemove(prefs, 'username', data['username']);
      await _putOrRemove(prefs, 'email', data['email']);
      await _putOrRemove(prefs, 'display_name', data['display_name']);
      return {
        'username': data['username'] as String?,
        'email': data['email'] as String?,
        'display_name': data['display_name'] as String?,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> _putOrRemove(SharedPreferences prefs, String key, dynamic value) async {
    if (value is String && value.isNotEmpty) {
      await prefs.setString(key, value);
    } else {
      await prefs.remove(key);
    }
  }

  static Future<void> _saveSession(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', data['access_token']);
    await prefs.setString('username', data['username']);
    await _putOrRemove(prefs, 'email', data['email']);
    await _putOrRemove(prefs, 'display_name', data['display_name']);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('jwt_token');
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ---------- Chat ----------

  // 1. Gửi tin nhắn đến API /chat (yêu cầu đăng nhập)
  static Future<String?> sendMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: await _authHeaders(contentType: 'application/json'),
        body: jsonEncode({
          'user_id': null,
          'message': text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['bot_reply'];
      }
      if (response.statusCode == 401) {
        print("Phiên đăng nhập đã hết hạn, cần đăng nhập lại.");
        return null;
      }
      print("Lỗi Server Chat (${response.statusCode}): ${response.body}");
      return null;
    } catch (e) {
      print("Lỗi kết nối /chat: $e");
      return null;
    }
  }

  // 2. Gọi API /tts để sinh âm thanh (yêu cầu đăng nhập)
  static Future<List<int>?> getSpeechAudio(
      String text, {
        String? voice,
        String rate = '+0%',
        String pitch = '+0Hz',
      }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/tts'),
        headers: await _authHeaders(contentType: 'application/json'),
        body: jsonEncode({
          'text': text,
          'voice': voice ?? 'zalo_female_north', // Mặc định Zalo Bắc
          'rate': rate,
          'pitch': pitch,
        }),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      print("Lỗi Server TTS (${response.statusCode}): ${response.body}");
      return null;
    } catch (e) {
      print("Lỗi kết nối /tts: $e");
      return null;
    }
  }

  // 3. API Speech-to-Text /stt (yêu cầu đăng nhập)
  static Future<String?> transcribeAudio(File file) async {
    try {
      if (!await file.exists() || await file.length() == 0) {
        print("Lỗi: File âm thanh rỗng hoặc không tồn tại!");
        return null;
      }

      var uri = Uri.parse('$baseUrl/stt');
      var request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authHeaders());

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
      }
      print("Lỗi STT từ Server (${response.statusCode}): ${response.body}");
      return null;
    } catch (e) {
      print("Lỗi kết nối /stt: $e");
      return null;
    }
  }

  // 4. Lấy danh sách lịch sử trò chuyện của CHÍNH user đang đăng nhập
  static Future<List<dynamic>> getHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/history'),
        headers: await _authHeaders(contentType: 'application/json'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return data;
      }
      print("Lỗi lấy lịch sử (${response.statusCode}): ${response.body}");
      return [];
    } catch (e) {
      print("Lỗi kết nối /history: $e");
      return [];
    }
  }

  // 5. Voice assistant tổng hợp (yêu cầu đăng nhập)
  static Future<Map<String, dynamic>?> sendVoiceCommand(File file) async {
    try {
      var uri = Uri.parse('$baseUrl/voice-assistant');
      var request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _authHeaders());

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
        String userText = response.headers['x-user-text'] != null
            ? utf8.decode(response.headers['x-user-text']!.codeUnits)
            : "";
        String botReply = response.headers['x-bot-reply'] != null
            ? utf8.decode(response.headers['x-bot-reply']!.codeUnits)
            : "";

        return {
          'user_text': userText,
          'bot_reply': botReply,
          'audio_bytes': response.bodyBytes,
        };
      }
      print("Lỗi Voice Assistant: ${response.statusCode}");
      return null;
    } catch (e) {
      print("Lỗi kết nối Voice Assistant: $e");
      return null;
    }
  }

  // 6. Lấy danh sách giọng đọc khả dụng từ server (public, không cần token)
  // -> để Settings luôn khớp với danh sách backend thực sự hỗ trợ
  // (routes/tts.py: GET /voices), tránh 2 nơi định nghĩa lệch nhau.
  static Future<List<Map<String, String>>?> getVoices() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/voices'));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return data
            .map<Map<String, String>>((v) => {
          'name': v['name'].toString(),
          'code': v['code'].toString(),
        })
            .toList();
      }
      print("Lỗi lấy danh sách giọng đọc (${response.statusCode}): ${response.body}");
      return null;
    } catch (e) {
      print("Lỗi kết nối /voices: $e");
      return null;
    }
  }
}