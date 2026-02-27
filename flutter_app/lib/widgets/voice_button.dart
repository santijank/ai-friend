/// voice_button.dart — ปุ่มไมค์ (ใช้ Android Native Speech Recognition)
/// กดสั้น = พูดครั้งเดียว, กดค้าง = J.A.R.V.I.S. mode
import 'package:flutter/material.dart';
import '../services/stt_service.dart';

class VoiceButton extends StatefulWidget {
  final Function(String text) onResult;
  final VoidCallback? onLongPress;

  const VoiceButton({super.key, required this.onResult, this.onLongPress});

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> {
  bool _isListening = false;

  Future<void> _startListening() async {
    if (!SttService.isAvailable || _isListening) return;

    setState(() => _isListening = true);

    // เรียก native Android speech recognition (Google popup)
    // บังคับ language = th-TH → ได้ข้อความไทยแน่นอน
    final result = await SttService.recognizeSpeech();

    if (!mounted) return;
    setState(() => _isListening = false);

    if (result.isNotEmpty) {
      widget.onResult(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _startListening,
      onLongPress: widget.onLongPress,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _isListening
              ? Colors.red.shade50
              : const Color(0xFF6C9BCF).withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: _isListening ? Colors.red : const Color(0xFF6C9BCF),
          size: 24,
        ),
      ),
    );
  }
}
