import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tts_service.dart';

class TtsHistoryItem {
  final String id;
  final String text;
  final String filePath;
  final DateTime createdAt;

  TtsHistoryItem({
    required this.id,
    required this.text,
    required this.filePath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory TtsHistoryItem.fromJson(Map<String, dynamic> json) => TtsHistoryItem(
    id: json['id'],
    text: json['text'],
    filePath: json['filePath'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class TtsScreen extends StatefulWidget {
  final String selectedVoice;
  final double selectedRate;
  final double selectedPitch;

  const TtsScreen({
    super.key,
    required this.selectedVoice,
    required this.selectedRate,
    required this.selectedPitch,
  });

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final TextEditingController _textController = TextEditingController();
  final TtsService _ttsService = TtsService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isLoading = false;
  List<TtsHistoryItem> _history = [];
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // Load lịch sử từ SharedPreferences
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('tts_history');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      setState(() {
        _history = jsonList.map((e) => TtsHistoryItem.fromJson(e)).toList();
      });
    }
  }

  // Lưu lịch sử
  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_history.map((e) => e.toJson()).toList());
    await prefs.setString('tts_history', data);
  }

  // Tạo giọng nói & Thêm vào lịch sử
  Future<void> _generateSpeech() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      File? audioFile = await _ttsService.generateSpeech(
        text,
        voiceCode: widget.selectedVoice,
        ratePercent: widget.selectedRate.toInt(),
        pitchHz: widget.selectedPitch.toInt(),
      );

      if (audioFile != null && mounted) {
        final newItem = TtsHistoryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: text,
          filePath: audioFile.path,
          createdAt: DateTime.now(),
        );

        setState(() {
          _history.insert(0, newItem);
        });
        await _saveHistory();

        // Tự động phát âm thanh vừa tạo
        _playAudio(newItem);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi tạo âm thanh: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Phát lại file âm thanh
  Future<void> _playAudio(TtsHistoryItem item) async {
    try {
      if (_currentlyPlayingId == item.id && _audioPlayer.playing) {
        await _audioPlayer.pause();
        setState(() => _currentlyPlayingId = null);
        return;
      }

      await _audioPlayer.setFilePath(item.filePath);
      setState(() => _currentlyPlayingId = item.id);
      await _audioPlayer.play();

      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _currentlyPlayingId = null);
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File âm thanh không còn tồn tại")),
      );
    }
  }

  // Tải file về thư mục Downloads của thiết bị
  Future<void> _downloadAudio(TtsHistoryItem item) async {
    try {
      final sourceFile = File(item.filePath);
      if (!await sourceFile.exists()) {
        throw "File nguồn không tồn tại";
      }

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      final fileName = "TTS_${item.id}.mp3";
      final savedFile = await sourceFile.copy("${downloadsDir.path}/$fileName");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Đã tải file về: ${savedFile.path}"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Không thể tải file: $e")),
        );
      }
    }
  }

  // Xóa item lịch sử
  Future<void> _deleteItem(String id) async {
    setState(() {
      _history.removeWhere((item) => item.id == id);
    });
    await _saveHistory();
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Khung nhập văn bản
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _textController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: "Nhập văn bản cần chuyển thành giọng nói...",
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isLoading ? null : _generateSpeech,
                        icon: _isLoading
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                            : const Icon(Icons.volume_up_rounded),
                        label: Text(_isLoading ? "Đang tạo..." : "Chuyển Thành Giọng Nói"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Tiêu đề Lịch sử
            const Text(
              "Lịch sử TTS & Tải file",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),

            // Danh sách Lịch sử
            Expanded(
              child: _history.isEmpty
                  ? const Center(child: Text("Chưa có lịch sử chuyển đổi nào", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final item = _history[index];
                  final isPlaying = _currentlyPlayingId == item.id;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: theme.primaryColor,
                          ),
                          onPressed: () => _playAudio(item),
                        ),
                      ),
                      title: Text(
                        item.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        "${item.createdAt.hour}:${item.createdAt.minute.toString().padLeft(2, '0')} - ${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year}",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.blue),
                            tooltip: "Tải file về máy",
                            onPressed: () => _downloadAudio(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            tooltip: "Xóa",
                            onPressed: () => _deleteItem(item.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}