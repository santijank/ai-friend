/// onboarding_screen.dart — หน้าแนะนำตัวแบบสนทนา (ไม่ใช่ฟอร์ม)
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_storage.dart';
import '../services/notification_service.dart';
import '../models/message.dart';
import '../widgets/chat_bubble.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];

  int _step = 0;
  String _userName = '';
  String _personality = 'friendly';
  String _wakeTime = '07:00';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // เริ่มด้วยข้อความต้อนรับ
    Future.delayed(const Duration(milliseconds: 500), () {
      _addAIMessage('สวัสดี! 🎉 ฟ้าดีใจที่ได้รู้จักเพื่อนใหม่!\n\nเรียกชื่ออะไรดีเอ่ย?');
    });
  }

  void _addAIMessage(String text) {
    setState(() {
      _messages.add(Message(role: 'ai', content: text));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(Message(role: 'user', content: text));
    });
    _controller.clear();
    _scrollToBottom();

    // ประมวลผลตาม step
    switch (_step) {
      case 0: // ถามชื่อ
        _userName = text;
        _step = 1;
        Future.delayed(const Duration(milliseconds: 800), () {
          _addAIMessage(
            '$_userName! ชื่อน่ารักดี 😊\n\n'
            'อยากให้ฟ้าเป็นเพื่อนแบบไหน?\n\n'
            '1. 😎 เพื่อนสนิท (สนุก ตลก จริงใจ)\n'
            '2. 🌸 พี่สาวอบอุ่น (ห่วงใย ดูแล)\n'
            '3. 🧸 น้องร่าเริง (สดใส พลังบวก)\n'
            '4. 🎩 พี่เลี้ยงมือโปร (เป็นระเบียบ)\n\n'
            'พิมพ์ตัวเลข 1-4 ได้เลย~',
          );
        });
        break;

      case 1: // เลือกบุคลิก
        final personalities = {'1': 'friendly', '2': 'caring', '3': 'cheerful', '4': 'professional'};
        _personality = personalities[text] ?? 'friendly';

        final names = {
          'friendly': 'เพื่อนสนิท',
          'caring': 'พี่สาวอบอุ่น',
          'cheerful': 'น้องร่าเริง',
          'professional': 'พี่เลี้ยงมือโปร',
        };

        _step = 2;
        Future.delayed(const Duration(milliseconds: 800), () {
          _addAIMessage(
            'โอเค~ ฟ้าจะเป็น${names[_personality]}ให้ $_userName นะ!\n\n'
            'ปกติตื่นกี่โมง? จะได้ทักทายตอนเช้า ☀️\n'
            '(พิมพ์เวลาเช่น 7 หรือ 6:30)',
          );
        });
        break;

      case 2: // ถามเวลาตื่น
        _wakeTime = _parseWakeTime(text);
        debugPrint('Parsed wake time: "$text" → "$_wakeTime"');
        _step = 3;
        _registerUser();
        break;
    }
  }

  /// แปลงเวลาจากหลายรูปแบบ → "HH:MM"
  /// รองรับ: "6.30", "6:30", "6", "06:30", "14.30", "7"
  String _parseWakeTime(String input) {
    input = input.trim();

    // รองรับทั้ง ":" และ "." เป็นตัวคั่น
    if (input.contains(':') || input.contains('.')) {
      final separator = input.contains(':') ? ':' : '.';
      final parts = input.split(separator);
      final h = (int.tryParse(parts[0]) ?? 7).clamp(0, 23);
      final m = (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0).clamp(0, 59);
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }

    // ตัวเลขเดี่ยว เช่น "7" → "07:00"
    final h = (int.tryParse(input) ?? 7).clamp(0, 23);
    return '${h.toString().padLeft(2, '0')}:00';
  }

  Future<void> _registerUser() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('Registering: name=$_userName, personality=$_personality, wake=$_wakeTime');

      final result = await ApiService.register(
        name: _userName,
        personality: _personality,
        wakeTime: _wakeTime,
      );

      debugPrint('Registration OK: ${result['user_id']}');

      // บันทึกในเครื่อง
      await LocalStorage.saveUser(
        userId: result['user_id'],
        name: _userName,
        personality: _personality,
      );

      // ตั้ง notification เช้า
      final parts = _wakeTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      await NotificationService.requestPermission();
      await NotificationService.scheduleDailyReminder(
        id: 1,
        title: '☀️ ฟ้าทักมา~',
        body: 'อรุณสวัสดิ์ $_userName! วันนี้จะเป็นวันที่ดีนะ!',
        hour: hour,
        minute: minute,
      );

      _addAIMessage(
        'เย้! พร้อมแล้ว! 🎉\n\n'
        'ฟ้าจะทักทายตอน $_wakeTime ทุกเช้าเลยนะ\n\n'
        'ถ้ามีอะไรอยากเล่า อยากถาม หรืออยากให้เตือนอะไร '
        'ทักมาได้เลยนะ $_userName~ 💕',
      );

      // รอ 2 วิ แล้วไปหน้าแชท
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      });
    } catch (e) {
      debugPrint('Registration error: $e');
      _step = 2; // ย้อนกลับให้พิมพ์เวลาใหม่ได้
      _addAIMessage(
        'อุ๊ปส์ เชื่อมต่อไม่ได้ชั่วคราว 😅\n\n'
        'ลองพิมพ์เวลาตื่นอีกครั้งนะ (เช่น 7 หรือ 6:30)',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '🤖 ฟ้า AI Friend',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF6C9BCF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ChatBubble(message: _messages[index]);
              },
            ),
          ),

          // Input bar
          if (_step < 3)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _onSend(),
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ข้อความ...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF5F7FA),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed: _isLoading ? null : _onSend,
                    backgroundColor: const Color(0xFF6C9BCF),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
