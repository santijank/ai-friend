/// chat_bubble.dart — กล่องข้อความ + ปุ่มฟังเสียง + สถานะกำลังพูด
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/tts_service.dart';
import 'speak_button.dart';

class ChatBubble extends StatefulWidget {
  final Message message;

  const ChatBubble({super.key, required this.message});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    TtsService.addListener(_onTtsChanged);
  }

  void _onTtsChanged() {
    if (!mounted) return;
    // แสดงสถานะเฉพาะ bubble ของ AI
    final speaking = TtsService.isPlaying && widget.message.role == 'ai';
    if (speaking != _isSpeaking) {
      setState(() => _isSpeaking = speaking);
    }
  }

  @override
  void dispose() {
    TtsService.removeListener(_onTtsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: _isSpeaking
                  ? const Color(0xFF4A7FB5)
                  : const Color(0xFF6C9BCF),
              child: _isSpeaking
                  ? const Icon(Icons.graphic_eq_rounded,
                      size: 16, color: Colors.white)
                  : const Text('🤖', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF6C9BCF)
                    : _isSpeaking
                        ? const Color(0xFFE3EDF7)
                        : const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: _isSpeaking && !isUser
                    ? Border.all(
                        color: const Color(0xFF6C9BCF).withValues(alpha: 0.4),
                        width: 1.5)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (!isUser) ...[
                    const SizedBox(height: 4),
                    SpeakButton(text: widget.message.content),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
