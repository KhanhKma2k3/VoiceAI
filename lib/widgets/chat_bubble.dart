import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ChatBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final bool isLatestBotMessage;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isUser,
    this.isLatestBotMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    // Lấy màu từ theme hiện tại để bong bóng chat đổi theo dark mode và
    // theo màu chủ đạo người dùng chọn (trước đây là màu sáng cố định).
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final textColor = isUser ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03), // 👈 Đã đổi để hết cảnh báo Deprecated
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: isLatestBotMessage && !isUser
            ? AnimatedTextKit(
          animatedTexts: [
            TypewriterAnimatedText(
              message,
              textStyle: TextStyle( // 👈 ĐÃ XÓA 'const' TẠI ĐÂY (Sửa lỗi Invalid constant value)
                fontSize: 15,
                color: textColor,
                height: 1.4,
              ),
              speed: const Duration(milliseconds: 30),
            ),
          ],
          totalRepeatCount: 1,
          displayFullTextOnTap: true,
        )
            : Text(
          message,
          style: TextStyle( // 👈 ĐÃ XÓA 'const' TẠI ĐÂY (Sửa lỗi Invalid constant value)
            fontSize: 15,
            color: textColor,
            height: 1.4,
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
  }
}