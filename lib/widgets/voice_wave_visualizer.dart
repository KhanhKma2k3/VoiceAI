import 'package:flutter/material.dart';

class VoiceWaveVisualizer extends StatefulWidget {
  final bool isRecording;
  final bool isThinking;

  const VoiceWaveVisualizer({
    super.key,
    required this.isRecording,
    required this.isThinking,
  });

  @override
  State<VoiceWaveVisualizer> createState() => _VoiceWaveVisualizerState();
}

class _VoiceWaveVisualizerState extends State<VoiceWaveVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🟢 LẤY MÀU CHỦ ĐẠO DỰA VÀO THEME CỦA CONTEXT
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.isThinking
                ? Icons.psychology_rounded
                : (widget.isRecording ? Icons.mic_rounded : Icons.graphic_eq),
            color: primaryColor, // 👈 Đã thay thế AppTheme.primaryColor
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            widget.isThinking
                ? "AI đang suy nghĩ..."
                : (widget.isRecording ? "Đang lắng nghe..." : "Sẵn sàng"),
            style: TextStyle(
              color: primaryColor, // 👈 Đã thay thế AppTheme.primaryColor
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          // Hiệu ứng sóng âm động
          if (widget.isRecording || widget.isThinking)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Row(
                  children: List.generate(4, (index) {
                    double height = 8 + (index % 2 == 0 ? 12 : 18) * _controller.value;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 3,
                      height: height,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                );
              },
            ),
        ],
      ),
    );
  }
}