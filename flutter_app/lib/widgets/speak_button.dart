// speak_button.dart — ปุ่มฟังเสียงข้อความ AI (มี animation)
import 'package:flutter/material.dart';
import '../services/tts_service.dart';

class SpeakButton extends StatefulWidget {
  final String text;

  const SpeakButton({super.key, required this.text});

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton>
    with SingleTickerProviderStateMixin {
  bool _isSpeaking = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    TtsService.addListener(_onTtsStateChanged);
  }

  void _onTtsStateChanged() {
    if (!mounted) return;
    final speaking = TtsService.isPlaying;
    if (speaking != _isSpeaking) {
      setState(() => _isSpeaking = speaking);
      if (speaking) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  Future<void> _toggleSpeak() async {
    if (_isSpeaking) {
      await TtsService.stop();
    } else {
      await TtsService.speak(widget.text);
    }
  }

  @override
  void dispose() {
    TtsService.removeListener(_onTtsStateChanged);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!TtsService.isAvailable) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _toggleSpeak,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isSpeaking
                  ? const Color(0xFF6C9BCF).withValues(alpha: 0.1 + _pulseController.value * 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                  size: 18,
                  color: _isSpeaking
                      ? Color.lerp(
                          const Color(0xFF6C9BCF),
                          const Color(0xFF4A7FB5),
                          _pulseController.value,
                        )
                      : const Color(0xFF6C9BCF),
                ),
                const SizedBox(width: 4),
                Text(
                  _isSpeaking ? 'หยุด' : 'ฟัง',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _isSpeaking ? FontWeight.bold : FontWeight.normal,
                    color: const Color(0xFF6C9BCF),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
