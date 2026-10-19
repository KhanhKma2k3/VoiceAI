import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

/// Bọc google_sign_in (bản ^6.x) để LoginScreen chỉ cần gọi 1 hàm lấy
/// `id_token`, rồi gửi lên backend qua ApiService.loginWithGoogle().
class GoogleAuthService {
  GoogleAuthService._();

  /// "Web client ID" (OAuth 2.0) của Google Cloud — CÙNG giá trị với
  /// GOOGLE_CLIENT_ID trong .env của backend. Truyền khi build:
  ///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '397099624436-ft12fkdsfafo4jsu0llf91ddkhj0fhdb.apps.googleusercontent.com',
  );

  /// google_sign_in chỉ hỗ trợ Android / iOS / Web (không có Windows, Linux).
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: serverClientId.isEmpty ? null : serverClientId,
  );

  /// Mở màn chọn tài khoản Google. Trả về `id_token`, hoặc null nếu người
  /// dùng tự hủy. Ném Exception nếu có lỗi thật sự.
  static Future<String?> signInAndGetIdToken() async {
    if (serverClientId.isEmpty) {
      throw Exception(
        "Chưa cấu hình GOOGLE_SERVER_CLIENT_ID khi build app "
            "(--dart-define=GOOGLE_SERVER_CLIENT_ID=...).",
      );
    }
    // Đăng xuất phiên Google cũ để luôn hiện màn chọn tài khoản.
    await _googleSignIn.signOut();
    final account = await _googleSignIn.signIn();
    if (account == null) return null;

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw Exception("Không lấy được thông tin xác thực từ Google.");
    }
    return idToken;
  }

  static Future<void> signOut() async {
    if (!isSupported) return;
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}
