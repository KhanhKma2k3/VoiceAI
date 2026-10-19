import 'package:flutter/material.dart';

import '../pc_control/controller_service.dart';
import '../pc_control/pc_control_bootstrap.dart';
import '../pc_control/pc_control_models.dart';
import '../pc_control/pc_control_voice_parser.dart';
import '../services/stt_service.dart';

class PcControlScreen extends StatefulWidget {
  const PcControlScreen({super.key});

  @override
  State<PcControlScreen> createState() => _PcControlScreenState();
}

class _PcControlScreenState extends State<PcControlScreen> {
  ControllerService? get _controller => PcControlBootstrap.controller;

  final SttService _sttService = SttService();
  final TextEditingController _appNameController = TextEditingController();

  List<PcAgentInfo> _agents = [];
  String? _selectedAgentId;
  bool _busy = false;
  bool _connected = false;

  // Trạng thái cho tính năng điều khiển bằng giọng nói.
  bool _isRecording = false;
  bool _isVoiceBusy = false;

  @override
  void initState() {
    super.initState();
    _controller?.agentsOnline.listen((agents) {
      if (!mounted) return;
      setState(() {
        _agents = agents;
        if (_selectedAgentId == null && agents.isNotEmpty) {
          _selectedAgentId = agents.first.id;
        } else if (agents.every((a) => a.id != _selectedAgentId)) {
          _selectedAgentId = agents.isNotEmpty ? agents.first.id : null;
        }
      });
    });
    _controller?.connectionState.listen((connected) {
      if (!mounted) return;
      setState(() => _connected = connected);
    });
  }

  @override
  void dispose() {
    if (_isRecording) {
      _sttService.stopRecording();
    }
    _sttService.dispose();
    _appNameController.dispose();
    super.dispose();
  }

  Future<void> _run(String action, Map<String, dynamic> params, {String? confirmMessage}) async {
    if (confirmMessage != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Xác nhận"),
          content: Text(confirmMessage),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Đồng ý")),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    final result = await _controller!.sendCommand(
      action: action,
      params: params,
      targetAgentId: _selectedAgentId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red.shade400,
      ),
    );
  }

  // -----------------------------------------------------------------
  // Điều khiển bằng giọng nói
  // -----------------------------------------------------------------

  /// Nhấn 1 lần để bắt đầu ghi âm, nhấn lần nữa để dừng & xử lý câu lệnh.
  Future<void> _toggleVoiceRecording() async {
    if (_busy || _isVoiceBusy || _agents.isEmpty) return;

    if (!_isRecording) {
      try {
        await _sttService.startRecording();
        if (!mounted) return;
        setState(() => _isRecording = true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }

    setState(() {
      _isRecording = false;
      _isVoiceBusy = true;
    });

    try {
      final file = await _sttService.stopRecording();
      if (file == null) {
        if (!mounted) return;
        setState(() => _isVoiceBusy = false);
        return;
      }

      final text = await _sttService.transcribe(file);
      if (!mounted) return;

      if (text == null || text.trim().isEmpty) {
        setState(() => _isVoiceBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không nghe rõ, bạn thử nói lại nhé.')),
        );
        return;
      }

      final command = PcVoiceCommandParser.parse(text);
      setState(() => _isVoiceBusy = false);

      if (command == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Không hiểu lệnh: "$text". Thử nói ví dụ "mở Chrome" hoặc "đóng Zalo".',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã nghe: "$text" → ${command.label}')),
      );
      await _run(command.action, command.params);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVoiceBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi xử lý giọng nói: $e')),
      );
    }
  }

  /// Cho phép mở bất kỳ ứng dụng nào bằng cách gõ tên (bổ sung cho các nút
  /// nhanh có sẵn) — dùng chung logic tìm-và-mở ở phía agent (appMap ->
  /// PATH -> Start Menu).
  Future<void> _openAppByTypedName() async {
    final name = _appNameController.text.trim();
    if (name.isEmpty) return;
    await _run('open_app', {'name': name});
    _appNameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_controller == null) {
      // Trường hợp build Windows (Desktop đóng vai trò agent, không phải controller)
      return Scaffold(
        body: Center(
          child: Text(
            "Bản Windows không dùng màn hình này — máy tính này đang được chia sẻ\nđể điều khiển từ điện thoại.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    final voiceDisabled = _agents.isEmpty || _busy || _isVoiceBusy;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trạng thái kết nối + chọn máy tính
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _connected ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _connected ? "Đã kết nối máy chủ" : "Đang kết nối...",
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_agents.isEmpty)
                        const Text(
                          "Chưa có máy tính nào online.\nHãy mở app này trên Windows và đăng nhập cùng tài khoản.",
                          style: TextStyle(color: Colors.grey),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _selectedAgentId,
                          decoration: const InputDecoration(
                            labelText: "Máy tính",
                            prefixIcon: Icon(Icons.computer_outlined),
                          ),
                          items: _agents
                              .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedAgentId = v),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---------------- Điều khiển bằng giọng nói ----------------
              const Text(
                "Điều khiển bằng giọng nói",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: voiceDisabled ? null : _toggleVoiceRecording,
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: _isRecording
                              ? Colors.red
                              : theme.primaryColor.withValues(alpha: voiceDisabled ? 0.3 : 1),
                          child: _isVoiceBusy
                              ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                              : Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _isRecording
                              ? "Đang nghe... nhấn lại để dừng."
                              : _isVoiceBusy
                              ? "Đang xử lý giọng nói..."
                              : "Nhấn micro rồi nói, ví dụ: \"mở Chrome\", \"đóng Zalo\", \"tăng âm lượng\".",
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text("Ứng dụng", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pillButton(theme, Icons.language, "Mở Chrome", () => _run('open_app', {'name': 'chrome'})),
                  _pillButton(theme, Icons.close, "Đóng Chrome", () => _run('close_app', {'name': 'chrome'})),
                  _pillButton(theme, Icons.calculate_outlined, "Máy tính", () => _run('open_app', {'name': 'calculator'})),
                ],
              ),
              const SizedBox(height: 12),

              // Mở BẤT KỲ ứng dụng nào bằng cách gõ tên — agent sẽ tự tìm
              // trong appMap, PATH, rồi Start Menu.
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _appNameController,
                      enabled: _agents.isNotEmpty && !_busy,
                      decoration: const InputDecoration(
                        labelText: "Tên ứng dụng bất kỳ",
                        hintText: "VD: Spotify, Zalo, Visual Studio Code...",
                        prefixIcon: Icon(Icons.apps_rounded),
                      ),
                      onSubmitted: (_) => _openAppByTypedName(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _agents.isEmpty || _busy ? null : _openAppByTypedName,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("Mở"),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const Text("Media", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pillButton(theme, Icons.play_arrow, "Play/Pause", () => _run('media_control', {'action': 'play_pause'})),
                  _pillButton(theme, Icons.volume_up, "Vol +", () => _run('media_control', {'action': 'volume_up'})),
                  _pillButton(theme, Icons.volume_down, "Vol -", () => _run('media_control', {'action': 'volume_down'})),
                  _pillButton(theme, Icons.volume_off, "Mute", () => _run('media_control', {'action': 'mute'})),
                ],
              ),

              const SizedBox(height: 20),
              if (_busy) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillButton(ThemeData theme, IconData icon, String label, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: _agents.isEmpty || _busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
        foregroundColor: theme.primaryColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
