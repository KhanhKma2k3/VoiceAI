import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nơi DUY NHẤT giữ chế độ sáng/tối và màu chủ đạo của toàn app.
///
/// Trước đây state này nằm trong `_MyAppState`, nhưng sau khi đăng nhập,
/// `LoginScreen` lại tự tạo `RootScreen` kèm các hàm đổi theme gọi `setState`
/// của CHÍNH nó (màn hình đã bị đóng) -> công tắc Dark Mode / chọn màu không
/// tác dụng và báo lỗi "setState() called after dispose()".
///
/// Giờ mọi màn hình đọc/ghi qua đối tượng này, `MaterialApp` lắng nghe nó,
/// và lựa chọn được lưu lại để lần mở app sau vẫn giữ nguyên.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _kDark = 'theme_is_dark';
  static const _kColor = 'theme_primary_color';
  static const Color defaultColor = Color(0xFF2563EB);

  bool _isDark = false;
  Color _primaryColor = defaultColor;

  bool get isDark => _isDark;
  Color get primaryColor => _primaryColor;

  /// Gọi 1 lần trong main() trước runApp().
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDark = prefs.getBool(_kDark) ?? false;
      final saved = prefs.getInt(_kColor);
      if (saved != null) _primaryColor = Color(saved);
    } catch (_) {
      // Đọc cài đặt lỗi thì dùng mặc định, không làm app sập.
    }
  }

  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    notifyListeners();
    await _save((p) => p.setBool(_kDark, value));
  }

  Future<void> setPrimaryColor(Color color) async {
    if (_primaryColor == color) return;
    _primaryColor = color;
    notifyListeners();
    // ignore: deprecated_member_use
    await _save((p) => p.setInt(_kColor, color.value));
  }

  Future<void> _save(Future<bool> Function(SharedPreferences) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {}
  }
}
