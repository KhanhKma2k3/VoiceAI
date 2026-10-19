import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../services/ai_chat_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/voice_wave_visualizer.dart';
import 'history_screen.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatScreen extends StatefulWidget {
  final bool isDarkMode;
  final Color primaryColor;
  final Function(bool) onToggleTheme;
  final Function(Color) onChangeColor;
  final String selectedVoice;
  final double selectedRate;
  final double selectedPitch;

  const ChatScreen({
    super.key,
    required this.isDarkMode,
    required this.primaryColor,
    required this.onToggleTheme,
    required this.onChangeColor,
    required this.selectedVoice,
    required this.selectedRate,
    required this.selectedPitch,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  final SttService _sttService = SttService();
  final TtsService _ttsService = TtsService();
  final AiChatService _aiChatService = AiChatService();

  bool _isSessionActive = false; // Trạng thái phiên thoại liên tục
  bool _isRecording = false;     // Đang thu âm
  bool _isAiResponding = false;  // AI đang trả lời / khóa mic

  Timer? _loopTimer;

  @override
  void initState() {
    super.initState();
    // Lắng nghe sự kiện audio kết thúc -> Bật lại Mic nếu đang trong phiên thoại
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && _isSessionActive) {
        if (mounted) {
          setState(() => _isAiResponding = false);
          _startListeningChunk();
        }
      }
    });

    // Tin nhắn chào mừng ban đầu
    _messages.add(
      ChatMessage(
        text: "Xin chào! Tôi là Trợ lý AI Voice. Bạn có thể nhấn biểu tượng Micro bên dưới để bắt đầu trò chuyện rảnh tay nhé!",
        isUser: false,
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Bật / Tắt phiên trò chuyện liên tục
  void _toggleContinuousSession() {
    if (_isSessionActive) {
      _stopSession("Đã tắt phiên trò chuyện giọng nói.");
    } else {
      setState(() {
        _isSessionActive = true;
        _isAiResponding = false;
      });
      _startListeningChunk();
    }
  }

  // Thu âm từng đoạn 4 giây
  Future<void> _startListeningChunk() async {
    if (!_isSessionActive || _isAiResponding || !mounted) return;

    try {
      await _sttService.startRecording();
      setState(() => _isRecording = true);

      _loopTimer?.cancel();
      _loopTimer = Timer(const Duration(seconds: 4), () async {
        if (!_isRecording || !_isSessionActive || _isAiResponding) return;

        final file = await _sttService.stopRecording();
        setState(() => _isRecording = false);

        if (file != null) {
          final transcribedText = await _sttService.transcribe(file);
          if (transcribedText != null && transcribedText.trim().isNotEmpty) {
            _checkKeywordAndProcess(transcribedText.trim());
          } else {
            _startListeningChunk();
          }
        } else {
          _startListeningChunk();
        }
      });
    } catch (e) {
      debugPrint("Lỗi ghi âm: $e");
    }
  }

  // Kiểm tra từ khóa kích hoạt
  Future<void> _checkKeywordAndProcess(String text) async {
    final cleanText = text.toLowerCase();

    // 1. Từ khóa kết thúc
    if (cleanText.contains("kết thúc") ||
        cleanText.contains("tạm biệt") ||
        cleanText.contains("dừng lại") ||
        cleanText.contains("tắt đi")) {
      _stopSession("Tạm biệt bạn! Rất vui được hỗ trợ bạn.");
      return;
    }

    // 2. Từ khóa gửi
    List<String> sendKeywords = ["xong", "hỏi", "gửi", "trả lời", "nhé", "ơi"];
    bool hasKeyword = sendKeywords.any((kw) => cleanText.endsWith(kw) || cleanText.contains(kw));

    if (hasKeyword) {
      setState(() => _isAiResponding = true);
      await _processMessageAndSpeak(text);
    } else {
      _startListeningChunk();
    }
  }

  // Dừng phiên thoại
  Future<void> _stopSession(String exitMessage) async {
    _loopTimer?.cancel();
    if (_isRecording) {
      await _sttService.stopRecording();
    }
    setState(() {
      _isSessionActive = false;
      _isRecording = false;
      _isAiResponding = false;
      _messages.add(ChatMessage(text: exitMessage, isUser: false));
    });
    _scrollToBottom();

    File? audioFile = await _ttsService.generateSpeech(
      exitMessage,
      voiceCode: widget.selectedVoice,
    );
    if (audioFile != null) {
      await _audioPlayer.setFilePath(audioFile.path);
      await _audioPlayer.play();
    }
  }

  // Xử lý gửi tin nhắn tới Backend & đọc ra loa
  Future<void> _processMessageAndSpeak(String text) async {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
    });
    _scrollToBottom();

    final botReply = await _aiChatService.sendMessage(text);
    final replyText = botReply ?? "Không nhận được phản hồi từ AI.";

    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(text: replyText, isUser: false));
    });
    _scrollToBottom();

    File? audioFile = await _ttsService.generateSpeech(
      replyText,
      voiceCode: widget.selectedVoice,
      ratePercent: widget.selectedRate.toInt(),
      pitchHz: widget.selectedPitch.toInt(),
    );

    if (audioFile != null && mounted) {
      await _audioPlayer.setFilePath(audioFile.path);
      await _audioPlayer.play();
    } else if (_isSessionActive) {
      setState(() => _isAiResponding = false);
      _startListeningChunk();
    }
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _sttService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.smart_toy_rounded, color: widget.primaryColor, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Trợ lý AI Voice",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isSessionActive ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isSessionActive ? "Đang lắng nghe" : "Sẵn sàng",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: "Lịch sử",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 🌊 Visualizer sóng âm khi bật thoại rảnh tay
            if (_isSessionActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: VoiceWaveVisualizer(
                  isRecording: _isRecording,
                  isThinking: _isAiResponding,
                ),
              ),

            // 💬 Danh sách tin nhắn dạng ChatBubbles
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isLatestBot = (!msg.isUser && index == _messages.length - 1);

                  return ChatBubble(
                    message: msg.text,
                    isUser: msg.isUser,
                    isLatestBotMessage: isLatestBot,
                  );
                },
              ),
            ),

            // 🎙️ Floating Input Bar (Thanh nhập liệu bo cong dạng nổi)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: theme.cardTheme.color ?? Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Nút bật/tắt thoại rảnh tay có hiệu ứng màu sắc nổi bật
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _toggleContinuousSession,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isSessionActive
                              ? Colors.red.shade500
                              : widget.primaryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isSessionActive ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: _isSessionActive ? Colors.white : widget.primaryColor,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Khung gõ tin nhắn text
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: "Nhập tin nhắn hoặc mở Mic...",
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (text) {
                        if (text.trim().isNotEmpty) {
                          _textController.clear();
                          _processMessageAndSpeak(text);
                        }
                      },
                    ),
                  ),

                  // Nút Gửi
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        final text = _textController.text.trim();
                        if (text.isNotEmpty) {
                          _textController.clear();
                          _processMessageAndSpeak(text);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: widget.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}