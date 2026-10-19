import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/stt_service.dart';

class SttHistoryItem {
  final String id;
  final String transcribedText;
  final String audioPath;
  final DateTime createdAt;

  SttHistoryItem({
    required this.id,
    required this.transcribedText,
    required this.audioPath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'transcribedText': transcribedText,
    'audioPath': audioPath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SttHistoryItem.fromJson(Map<String, dynamic> json) => SttHistoryItem(
    id: json['id'],
    transcribedText: json['transcribedText'],
    audioPath: json['audioPath'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class SttScreen extends StatefulWidget {
  const SttScreen({super.key});

  @override
  State<SttScreen> createState() => _SttScreenState();
}

class _SttScreenState extends State<SttScreen> {
  final SttService _sttService = SttService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isRecording = false;
  bool _isProcessing = false;
  String _currentText = "";

  List<SttHistoryItem> _history = [];
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('stt_history');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      setState(() {
        _history = jsonList.map((e) => SttHistoryItem.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_history.map((e) => e.toJson()).toList());
    await prefs.setString('stt_history', data);
  }

  // Bật/Tắt thu âm
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      final audioFile = await _sttService.stopRecording();

      if (audioFile != null) {
        final text = await _sttService.transcribe(audioFile);
        final resultText = (text != null && text.isNotEmpty) ? text : "Không nhận diện được giọng nói";

        setState(() {
          _currentText = resultText;
        });

        final newItem = SttHistoryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          transcribedText: resultText,
          audioPath: audioFile.path,
          createdAt: DateTime.now(),
        );

        setState(() {
          _history.insert(0, newItem);
          _isProcessing = false;
        });
        await _saveHistory();
      } else {
        setState(() => _isProcessing = false);
      }
    } else {
      setState(() {
        _isRecording = true;
        _currentText = "Đang lắng nghe giọng nói của bạn...";
      });
      await _sttService.startRecording();
    }
  }

  // Tải file ghi âm về máy
  Future<void> _downloadAudio(SttHistoryItem item) async {
    try {
      final sourceFile = File(item.audioPath);
      if (!await sourceFile.exists()) {
        throw "File thu âm không tồn tại";
      }

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      final fileName = "STT_Recording_${item.id}.wav";
      final savedFile = await sourceFile.copy("${downloadsDir.path}/$fileName");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Đã lưu bản thu âm vào Download: ${savedFile.path}"),
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

  Future<void> _playAudio(SttHistoryItem item) async {
    try {
      if (_currentlyPlayingId == item.id && _audioPlayer.playing) {
        await _audioPlayer.pause();
        setState(() => _currentlyPlayingId = null);
        return;
      }

      await _audioPlayer.setFilePath(item.audioPath);
      setState(() => _currentlyPlayingId = item.id);
      await _audioPlayer.play();

      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _currentlyPlayingId = null);
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File thu âm không còn tồn tại")),
      );
    }
  }

  Future<void> _deleteItem(String id) async {
    setState(() {
      _history.removeWhere((item) => item.id == id);
    });
    await _saveHistory();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _sttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Khung hiển thị văn bản vừa nói
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints(minHeight: 120),
                child: Center(
                  child: Text(
                    _currentText.isEmpty ? "Nhấn nút bên dưới và bắt đầu nói..." : _currentText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: _currentText.isEmpty ? Colors.grey : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Nút Thu âm lớn
            GestureDetector(
              onTap: _isProcessing ? null : _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : theme.primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : theme.primaryColor).withValues(alpha: 0.4),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRecording ? "Đang thu âm (Nhấn để dừng)" : "Nhấn để bắt đầu nói",
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Tiêu đề Lịch sử STT
            const Row(
              children: [
                Text(
                  "Lịch sử ghi âm & Nhận diện",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Danh sách lịch sử thu âm
            Expanded(
              child: _history.isEmpty
                  ? const Center(child: Text("Chưa có lịch sử thu âm nào", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final item = _history[index];
                  final isPlaying = _currentlyPlayingId == item.id;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.withValues(alpha: 0.1),
                        child: IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.orange.shade800,
                          ),
                          onPressed: () => _playAudio(item),
                        ),
                      ),
                      title: Text(
                        item.transcribedText,
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
                            tooltip: "Tải bản ghi âm về máy",
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