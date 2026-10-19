import 'package:flutter/material.dart';

import '../services/api_service.dart';

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

  // Thông tin tài khoản thật (lấy từ bản lưu cục bộ, sau đó làm mới từ server).
  String? _displayName;
  String? _email;

  // Slider tốc độ dùng chung 1 khoảng -50% -> +50% cho MỌI giọng đọc.
  // Backend (routes/tts.py: _rate_percent_to_zalo_speed) tự map tuyến tính
  // khoảng này sang speed 0.8-1.2 khi gọi Zalo AI, và dùng thẳng chuỗi
  // "+x%" cho Edge-TTS -> KHÔNG được giới hạn range ở client, nếu không
  // giọng Zalo sẽ chỉ dùng được một phần nhỏ của dải speed mà nó hỗ trợ.
  static const double _rateRangeLimit = 50;

  // Danh sách mặc định/dự phòng: dùng ngay khi mở màn hình và khi không
  // gọi được GET /voices (offline, server sập...). Sau khi _loadVoices()
  // gọi thành công, danh sách này sẽ được thay bằng dữ liệu thật từ server
  // -> không còn cảnh 2 nơi (client/server) định nghĩa lệch nhau nữa.
  bool _loadingVoices = true;
  List<Map<String, String>> _voices = [
    {'name': '🇻🇳 Bắc - Nữ Truyền Cảm (Zalo)', 'code': 'zalo_female_north'},
    {'name': '🇻🇳 Bắc - Nam Ấm Áp (Zalo)', 'code': 'zalo_male_north'},
    {'name': '🇻🇳 Nam - Nữ Trong Trẻo (Zalo)', 'code': 'zalo_female_south'},
    {'name': '🇻🇳 Nam - Nam Trầm (Zalo)', 'code': 'zalo_male_south'},
    {'name': 'Hoài My (Nữ - Miền Nam, Edge)', 'code': 'vi-VN-HoaiMyNeural'},
    {'name': 'Nam Minh (Nam - Miền Bắc, Edge)', 'code': 'vi-VN-NamMinhNeural'},
    {'name': 'Phương Anh (Nữ - Đa ngôn ngữ, Edge)', 'code': 'vi-VN-PhuongAnhNeural'},
    {'name': 'Jenny (Nữ - Tiếng Anh Mỹ)', 'code': 'en-US-JennyNeural'},
    {'name': 'Guy (Nam - Tiếng Anh Mỹ)', 'code': 'en-US-GuyNeural'},
    {'name': 'Sonia (Nữ - Tiếng Anh Anh)', 'code': 'en-GB-SoniaNeural'},
  ];

  final List<Color> _themeColors = [
    const Color(0xFF2563EB),
    const Color(0xFF7C3AED),
    const Color(0xFF10B981),
    const Color(0xFFEF4444),
    const Color(0xFFF59E0B),
  ];

  bool get _isZaloVoice => _voice.startsWith('zalo_');

  @override
  void initState() {
    super.initState();
    _voice = widget.currentVoice;
    _rate = widget.currentRate;
    _pitch = widget.currentPitch;
    _isDark = widget.isDarkMode;
    _selectedColor = widget.primaryColor;

    // An toàn phòng trường hợp _rate truyền vào từ ngoài lỡ vượt khoảng cho
    // phép (tránh assertion lỗi "value phải nằm trong [min, max]" của Slider).
    _rate = _rate.clamp(-_rateRangeLimit, _rateRangeLimit);

    _loadProfile();
    _loadVoices();
  }

  /// Hiện ngay thông tin đã lưu lúc đăng nhập, rồi hỏi server (GET /me) để
  /// cập nhật bản mới nhất. Không còn hiển thị thông tin mẫu cố định.
  Future<void> _loadProfile() async {
    final cached = await ApiService.getCachedProfile();
    if (!mounted) return;
    setState(() => _applyProfile(cached));

    final fresh = await ApiService.fetchProfile();
    if (!mounted || fresh == null) return;
    setState(() => _applyProfile(fresh));
  }

  void _applyProfile(Map<String, String?> profile) {
    final name = profile['display_name'];
    _displayName = (name != null && name.isNotEmpty) ? name : profile['username'];
    _email = profile['email'];
  }

  // Lấy danh sách giọng đọc THỰC TẾ từ server, để không bao giờ lệch với
  // những gì routes/tts.py đang hỗ trợ (kể cả khi sau này thêm/bớt giọng
  // ở backend mà quên sửa client).
  Future<void> _loadVoices() async {
    final voices = await ApiService.getVoices();
    if (!mounted) return;

    if (voices != null && voices.isNotEmpty) {
      setState(() {
        _voices = voices;
        // Nếu giọng đang chọn không còn nằm trong danh sách mới từ server,
        // rơi về giọng đầu tiên để tránh lỗi DropdownButtonFormField
        // (value phải khớp với 1 trong các items).
        if (!_voices.any((v) => v['code'] == _voice)) {
          _voice = _voices.first['code']!;
        }
        _loadingVoices = false;
      });
    } else {
      // Không lấy được từ server (offline...) -> giữ nguyên danh sách dự
      // phòng đã có sẵn, chỉ tắt trạng thái loading.
      setState(() => _loadingVoices = false);
    }
  }

  void _onVoiceChanged(String val) {
    setState(() => _voice = val);
    widget.onSaveTts(_voice, _rate, _pitch);
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
    // Zalo AI KHÔNG có tham số cao độ -> vô hiệu hóa thanh trượt pitch khi
    // đang chọn giọng Zalo, để không gây hiểu lầm "chỉnh mà không có tác
    // dụng". Thanh trượt tốc độ dùng chung 1 khoảng cho mọi giọng vì backend
    // tự quy đổi phù hợp cho từng loại (xem _rateRangeLimit ở trên).
    final bool isZaloVoice = _isZaloVoice;

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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    child: (_displayName != null && _displayName!.isNotEmpty)
                        ? Text(
                      _displayName!.characters.first.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    )
                        : const Icon(Icons.person),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName ?? "Đang tải...",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (_email != null && _email!.isNotEmpty) ? _email! : "Chưa liên kết email",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Màu chủ đạo App", style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 12),
                      // Wrap tự xuống dòng khi màn hình hẹp -> hết lỗi tràn ngang.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _themeColors.map((color) {
                          bool isSelected = _selectedColor.value == color.value;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedColor = color);
                              widget.onChangeColor(color);
                            },
                            child: Container(
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
                    isExpanded: true, // cho phép tên giọng dài tự cắt "..." thay vì tràn
                    value: _voice,
                    decoration: InputDecoration(
                      labelText: "Giọng đọc AI",
                      prefixIcon: const Icon(Icons.record_voice_over),
                      suffixIcon: _loadingVoices
                          ? const Padding(
                        padding: EdgeInsets.all(14.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                          : null,
                    ),
                    items: _voices
                        .map((v) => DropdownMenuItem(
                      value: v['code'],
                      child: Text(v['name']!, overflow: TextOverflow.ellipsis),
                    ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) _onVoiceChanged(val);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text("Tốc độ đọc: ${_rate.toInt()}%"),
                  Slider(
                    value: _rate,
                    min: -_rateRangeLimit,
                    max: _rateRangeLimit,
                    onChanged: (val) => setState(() => _rate = val),
                    onChangeEnd: (val) => widget.onSaveTts(_voice, _rate, _pitch),
                  ),
                  Text(
                    isZaloVoice
                        ? "Cao độ giọng: không hỗ trợ với giọng Zalo"
                        : "Cao độ giọng: ${_pitch.toInt()} Hz",
                    style: TextStyle(color: isZaloVoice ? Colors.grey : null),
                  ),
                  Slider(
                    value: _pitch,
                    min: -20,
                    max: 20,
                    // Zalo AI không có tham số pitch -> khóa thanh trượt lại
                    // (onChanged: null làm Slider tự chuyển sang trạng thái
                    // disabled, mờ đi) thay vì để chỉnh vô ích.
                    onChanged: isZaloVoice
                        ? null
                        : (val) => setState(() => _pitch = val),
                    onChangeEnd: isZaloVoice
                        ? null
                        : (val) => widget.onSaveTts(_voice, _rate, _pitch),
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