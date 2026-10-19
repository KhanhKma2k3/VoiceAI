import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Quên mật khẩu, 2 bước:
///   1. Nhập email -> server gửi mã xác nhận 6 số.
///   2. Nhập mã + mật khẩu mới -> đặt lại xong quay về màn đăng nhập.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.initialEmail.contains('@') ? widget.initialEmail : '',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _clean(Object e) => e.toString().replaceAll('Exception: ', '');

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      _toast("Vui lòng nhập email hợp lệ");
      return;
    }
    setState(() => _loading = true);
    try {
      final msg = await ApiService.forgotPassword(email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      _toast(msg.isNotEmpty ? msg : "Đã gửi mã xác nhận về email của bạn");
    } catch (e) {
      _toast(_clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    if (code.isEmpty || newPassword.isEmpty) {
      _toast("Vui lòng nhập mã xác nhận và mật khẩu mới");
      return;
    }
    if (newPassword.length < 6) {
      _toast("Mật khẩu phải có ít nhất 6 ký tự");
      return;
    }
    if (newPassword != _confirmController.text) {
      _toast("Mật khẩu nhập lại không khớp");
      return;
    }
    setState(() => _loading = true);
    try {
      final msg = await ApiService.resetPassword(
        email: _emailController.text.trim(),
        code: code,
        newPassword: newPassword,
      );
      if (!mounted) return;
      _toast(msg.isNotEmpty ? msg : "Đặt lại mật khẩu thành công");
      Navigator.of(context).pop();
    } catch (e) {
      _toast(_clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
    );
  }

  Widget _visibilityToggle() {
    return IconButton(
      tooltip: _showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu",
      icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
      onPressed: () => setState(() => _showPassword = !_showPassword),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quên mật khẩu")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _codeSent
                    ? "Nhập mã 6 số vừa được gửi tới ${_emailController.text.trim()} và đặt mật khẩu mới."
                    : "Nhập email đã đăng ký, chúng tôi sẽ gửi mã xác nhận để bạn đặt lại mật khẩu.",
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                enabled: !_codeSent && !_loading,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _decoration("Email", Icons.email_outlined),
              ),
              if (_codeSent) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: _decoration("Mã xác nhận", Icons.pin_outlined).copyWith(counterText: ""),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _newPasswordController,
                  obscureText: !_showPassword,
                  decoration: _decoration("Mật khẩu mới", Icons.lock_outline, suffix: _visibilityToggle()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmController,
                  obscureText: !_showPassword,
                  decoration: _decoration("Nhập lại mật khẩu mới", Icons.lock_outline),
                ),
              ],
              const SizedBox(height: 24),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                onPressed: _codeSent ? _resetPassword : _sendCode,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  _codeSent ? "Đặt lại mật khẩu" : "Gửi mã xác nhận",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              if (_codeSent && !_loading)
                TextButton(
                  onPressed: _sendCode,
                  child: const Text("Gửi lại mã"),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
