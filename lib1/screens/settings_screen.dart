import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final String currentVoice;
  final double currentRate;
  final double currentPitch;
  final bool isDarkMode;
  final Color primaryColor;
  final Function(String voice, double rate, double pitch) onSaveTts;
  final Function(bool isDark) onToggleTheme;
  final Function(Color color) onChangeColor;
  final VoidCallback onLogout; // Callback thực hiện đăng xuất từ main / chat_screen

  const SettingsScreen({
    super.key,
    required this.currentVoice,
    required this.currentRate,
    required this.currentPitch,
    required this.isDarkMode,
    required this.primaryColor,
    required this.onSaveTts,
    required this.onToggleTheme,
    required this.onChangeColor,
    required this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _voice;
  late double _rate;
  late double _pitch;
  late bool _isDark;
  late Color _selectedColor;

  final List<Map<String, String>> _voices = [
    {'name': 'Hoài My (Nữ - Miền Nam)', 'code': 'vi-VN-HoaiMyNeural'},
    {'name': 'Nam Minh (Nam - Miền Bắc)', 'code': 'vi-VN-NamMinhNeural'},
  ];

  final List<Color> _themeColors = [
    const Color(0xFF2563EB),
    const Color(0xFF7C3AED),
    const Color(0xFF10B981),
    const Color(0xFFEF4444),
    const Color(0xFFF59E0B),
  ];

  @override
  void initState() {
    super.initState();
    _voice = widget.currentVoice;
    _rate = widget.currentRate;
    _pitch = widget.currentPitch;
    _isDark = widget.isDarkMode;
    _selectedColor = widget.primaryColor;
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận đăng xuất"),
        content: const Text("Bạn có chắc chắn muốn đăng xuất khỏi tài khoản này?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx); // Đóng hộp thoại
              widget.onLogout();   // 🟢 ĐÃ SỬA: Thực thi hàm Đăng xuất thật để thoát ra LoginScreen
            },
            child: const Text("Đăng xuất", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cài đặt hệ thống"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 👤 1. THÔNG TIN TÀI KHOẢN
          const Text("Tài khoản", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                radius: 24,
                child: Icon(Icons.person),
              ),
              title: const Text("Nguyễn Văn A", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("user.demo@gmail.com"),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)),
                child: const Text("Gói VIP", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 🎨 2. GIAO DIỆN & MÀU SẮC
          const Text("Giao diện & Chủ đề", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Chế độ tối (Dark Mode)"),
                  secondary: const Icon(Icons.dark_mode_outlined),
                  value: _isDark,
                  onChanged: (val) {
                    setState(() => _isDark = val);
                    widget.onToggleTheme(val);
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Màu chủ đạo App", style: TextStyle(fontSize: 16)),
                      Row(
                        children: _themeColors.map((color) {
                          bool isSelected = _selectedColor.value == color.value;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedColor = color);
                              widget.onChangeColor(color);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                                boxShadow: isSelected ? [const BoxShadow(color: Colors.black26, blurRadius: 4)] : null,
                              ),
                              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 🔊 3. CÀI ĐẶT TEXT-TO-SPEECH (TTS)
          const Text("Cấu hình Giọng nói (TTS)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _voice,
                    decoration: const InputDecoration(labelText: "Giọng đọc AI", prefixIcon: Icon(Icons.record_voice_over)),
                    items: _voices.map((v) => DropdownMenuItem(value: v['code'], child: Text(v['name']!))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _voice = val);
                        widget.onSaveTts(_voice, _rate, _pitch);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text("Tốc độ đọc: ${_rate.toInt()}%"),
                  Slider(
                    value: _rate,
                    min: -50,
                    max: 50,
                    onChanged: (val) {
                      setState(() => _rate = val);
                      widget.onSaveTts(_voice, _rate, _pitch);
                    },
                  ),
                  Text("Cao độ giọng: ${_pitch.toInt()} Hz"),
                  Slider(
                    value: _pitch,
                    min: -20,
                    max: 20,
                    onChanged: (val) {
                      setState(() => _pitch = val);
                      widget.onSaveTts(_voice, _rate, _pitch);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 🎙️ 4. CÀI ĐẶT SPEECH-TO-TEXT (STT)
          const Text("Thu âm & Nhận diện (STT)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          Card(
            child: const ListTile(
              leading: Icon(Icons.graphic_eq),
              title: Text("Mô hình nhận diện giọng nói"),
              subtitle: Text("Faster-Whisper (Tiếng Việt)"),
              trailing: Icon(Icons.check_circle, color: Colors.green),
            ),
          ),
          const SizedBox(height: 28),

          // 🚪 5. NÚT ĐĂNG XUẤT
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red,
              elevation: 0,
              side: const BorderSide(color: Colors.red),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text("Đăng xuất tài khoản", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
    );
  }
}