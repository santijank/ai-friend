/// voice_button.dart — ปุ่มไมค์ขนาดใหญ่ + Full-screen Listening Overlay
import 'package:flutter/material.dart';
import '../services/stt_service.dart';
import 'thai_stt_dialog.dart';

class VoiceButton extends StatefulWidget {
  final Function(String text) onResult;
  final VoidCallback? onLongPress;

  const VoiceButton({super.key, required this.onResult, this.onLongPress});

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  bool _isListening = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!SttService.isAvailable) return;

    // ถ้าไม่มี Thai locale → แสดง dialog แนะนำ
    if (!SttService.hasThaiLocale && mounted) {
      final proceed = await showThaiSttDialog(context);
      if (proceed != true) {
        // กลับมาจากตั้งค่า → refresh locale list
        await SttService.refreshLocales();
        if (!mounted) return;
        if (!SttService.hasThaiLocale) return; // ยังไม่มี → ไม่เปิดฟัง
      }
    }

    setState(() => _isListening = true);
    _pulseController.repeat(reverse: true);

    // แสดง overlay เต็มจอ
    if (!mounted) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (ctx) => _ListeningOverlay(
        pulseController: _pulseController,
        onStop: (text) => Navigator.of(ctx).pop(text),
      ),
    );

    _pulseController.stop();
    _pulseController.reset();
    setState(() => _isListening = false);

    if (result != null && result.isNotEmpty) {
      widget.onResult(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SttService.isAvailable) {
      return const SizedBox.shrink();
    }

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

/// Full-screen listening overlay
class _ListeningOverlay extends StatefulWidget {
  final AnimationController pulseController;
  final Function(String text) onStop;

  const _ListeningOverlay({
    required this.pulseController,
    required this.onStop,
  });

  @override
  State<_ListeningOverlay> createState() => _ListeningOverlayState();
}

class _ListeningOverlayState extends State<_ListeningOverlay> {
  String _text = '';
  bool _finalResult = false;

  @override
  void initState() {
    super.initState();
    _startStt();
  }

  Future<void> _startStt() async {
    await SttService.startListening(
      onResult: (text) {
        if (!mounted) return;
        setState(() => _text = text);
      },
      onDone: () {
        if (!mounted) return;
        _finalResult = true;
        // Auto-send หลังจากพูดเสร็จ (delay เล็กน้อยให้เห็นข้อความ)
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) widget.onStop(_text);
        });
      },
    );
  }

  Future<void> _cancel() async {
    await SttService.stopListening();
    widget.onStop('');
  }

  Future<void> _send() async {
    await SttService.stopListening();
    // delay เล็กน้อยให้ STT flush ข้อมูลสุดท้าย
    await Future.delayed(const Duration(milliseconds: 200));
    widget.onStop(_text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            _finalResult ? 'พูดเสร็จแล้ว' : 'กำลังฟัง...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _finalResult ? Colors.green.shade700 : const Color(0xFF6C9BCF),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'พูดภาษาไทยได้เลย',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),

          // Transcription text
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _text.isEmpty ? '...' : _text,
                  style: TextStyle(
                    fontSize: _text.isEmpty ? 24 : 20,
                    color: _text.isEmpty ? Colors.grey.shade300 : Colors.black87,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // Mic animation + buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Cancel
                _CircleButton(
                  icon: Icons.close_rounded,
                  color: Colors.grey.shade400,
                  size: 52,
                  onTap: _cancel,
                  label: 'ยกเลิก',
                ),

                // Big mic button with pulse
                AnimatedBuilder(
                  animation: widget.pulseController,
                  builder: (context, _) {
                    final scale = 1.0 + widget.pulseController.value * 0.15;
                    return Transform.scale(
                      scale: _finalResult ? 1.0 : scale,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _finalResult
                              ? Colors.green
                              : Colors.red.shade400,
                          boxShadow: [
                            if (!_finalResult)
                              BoxShadow(
                                color: Colors.red.withValues(
                                    alpha: 0.3 + widget.pulseController.value * 0.2),
                                blurRadius: 20 + widget.pulseController.value * 10,
                                spreadRadius: widget.pulseController.value * 5,
                              ),
                          ],
                        ),
                        child: Icon(
                          _finalResult
                              ? Icons.check_rounded
                              : Icons.mic_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    );
                  },
                ),

                // Send
                _CircleButton(
                  icon: Icons.send_rounded,
                  color: _text.isNotEmpty
                      ? const Color(0xFF6C9BCF)
                      : Colors.grey.shade300,
                  size: 52,
                  onTap: _text.isNotEmpty ? _send : null,
                  label: 'ส่ง',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;
  final String label;

  const _CircleButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }
}
