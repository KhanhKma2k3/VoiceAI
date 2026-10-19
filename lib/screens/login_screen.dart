import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/google_auth_service.dart';
import '../pc_control/pc_control_bootstrap.dart';
import '../main.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Đăng nhập: _usernameController nhận tên tài khoản HOẶC email.
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController(); // chỉ dùng khi đăng ký
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController(); // chỉ dùng khi đăng ký
  bool _isLogin = true; // Switch giữa Login và Register
  bool _loading = false;
  bool _showPassword = false; // Hiện / ẩn mật khẩu

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _toast("Vui lòng nhập đầy đủ thông tin");
      return;
    }

    String? email;
    if (!_isLogin) {
      email = _emailController.text.trim();
      if (email.isEmpty || !email.contains('@')) {
        _toast("Vui lòng nhập email hợp lệ (dùng để khôi phục mật khẩu)");
        return;
      }
      if (password.length < 6) {
        _toast("Mật khẩu phải có ít nhất 6 ký tự");
        return;
      }
      if (password != _confirmController.text.trim()) {
        _toast("Mật khẩu nhập lại không khớp");
        return;
      }
    }

    await _runAuth(() async {
      if (_isLogin) {
        await ApiService.login(username, password);
      } else {
        await ApiService.register(username, password, email: email);
      }
    });
  }

  Future<void> _signInWithGoogle() async {
    await _runAuth(() async {
      final idToken = await GoogleAuthService.signInAndGetIdToken();
      if (idToken == null) throw _Cancelled(); // người dùng tự đóng hộp thoại
      await ApiService.loginWithGoogle(idToken);
    });
  }

  /// Chạy 1 luồng đăng nhập/đăng ký; nếu thành công thì vào màn hình chính.
  Future<void> _runAuth(Future<void> Function() action) async {
    setState(() => _loading = true);

    try {
      await action();

      // Đăng nhập/đăng ký xong -> có JWT mới -> khởi động ngay tính năng
      // Điều khiển PC (bản Windows tự thành agent, bản khác tự thành controller).
      await PcControlBootstrap.start();

      if (mounted) {
        // Theme do ThemeController giữ chung toàn app nên không cần truyền gì.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RootScreen()),
        );
      }
    } on _Cancelled {
      // Người dùng hủy chọn tài khoản Google -> không báo lỗi.
    } catch (e) {
      _toast(e.toString().replaceAll("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialEmail: _usernameController.text.trim()),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.smart_toy_rounded,
                  size: 80,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  _isLogin ? "ĐĂNG NHẬP" : "ĐĂNG KÝ TÀI KHOẢN",
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _usernameController,
                  keyboardType: _isLogin ? TextInputType.emailAddress : TextInputType.text,
                  decoration: _decoration(
                    _isLogin ? "Email hoặc tên tài khoản" : "Tên tài khoản",
                    Icons.person_outline,
                  ),
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _decoration("Email (Gmail)", Icons.email_outlined),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: _decoration(
                    "Mật khẩu",
                    Icons.lock_outline,
                    suffix: IconButton(
                      tooltip: _showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu",
                      icon: Icon(
                        _showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmController,
                    obscureText: !_showPassword,
                    decoration: _decoration("Nhập lại mật khẩu", Icons.lock_outline),
                  ),
                ],
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _loading ? null : _openForgotPassword,
                      child: const Text("Quên mật khẩu?"),
                    ),
                  )
                else
                  const SizedBox(height: 8),
                const SizedBox(height: 8),
                _loading
                    ? const CircularProgressIndicator()
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _isLogin ? "Đăng Nhập" : "Đăng Ký",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Google Sign-In chỉ có trên Android / iOS.
                    if (GoogleAuthService.isSupported) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text("hoặc", style: TextStyle(color: Colors.grey.shade600)),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
                        label: Text(
                          _isLogin ? "Đăng nhập bằng Google" : "Đăng ký bằng Google",
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? "Chưa có tài khoản? Đăng ký ngay"
                        : "Đã có tài khoản? Đăng nhập",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dùng nội bộ để thoát luồng khi người dùng tự hủy chọn tài khoản Google.
class _Cancelled implements Exception {}
