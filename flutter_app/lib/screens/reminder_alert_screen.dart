/// reminder_alert_screen.dart — หน้าเตือนเต็มจอ + ฟ้าพูดอัตโนมัติ
/// เปิดขึ้นเมื่อ: กด notification / full-screen intent (เหมือนนาฬิกาปลุก)
import 'package:flutter/material.dart';
import '../services/tts_service.dart';

class ReminderAlertScreen extends StatefulWidget {
  final String message;

  const ReminderAlertScreen({super.key, required this.message});

  @override
  State<ReminderAlertScreen> createState() => _ReminderAlertScreenState();
}

class _ReminderAlertScreenState extends State<ReminderAlertScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-speak after short delay
    Future.delayed(const Duration(milliseconds: 500), _speakReminder);
  }

  Future<void> _speakReminder() async {
    if (!mounted) return;
    setState(() => _isSpeaking = true);

    final speakText = 'แจ้งเตือนจากฟ้า ${widget.message}';
    await TtsService.speak(speakText);

    if (mounted) setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    TtsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6C9BCF), Color(0xFF3A6FA0)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated bell icon
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications_active,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  const Text(
                    'ฟ้าเตือน~',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Reminder message
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        height: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Speaking indicator
                  if (_isSpeaking)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'ฟ้ากำลังพูด...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Speak again button
                  OutlinedButton.icon(
                    onPressed: _isSpeaking ? null : _speakReminder,
                    icon: const Icon(Icons.volume_up, color: Colors.white),
                    label: const Text(
                      'ฟังอีกครั้ง',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Dismiss button
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF3A6FA0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'รับทราบ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
