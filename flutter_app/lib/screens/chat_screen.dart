/// chat_screen.dart — หน้าแชทหลัก + Voice Input + Mood Picker + J.A.R.V.I.S. Mode
import 'dart:math' show min;
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/local_storage.dart';
import '../services/notification_service.dart';
import '../services/tts_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/voice_button.dart';
import '../widgets/voice_mode_overlay.dart';
import '../widgets/mood_picker.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isTyping = false;
  bool _showMoodPicker = false;
  bool _isSpeaking = false;
  List<Map<String, dynamic>> _criticalAlerts = [];
  bool _alertDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _checkMoodReminder();
    _fetchCriticalAlerts();
    _rescheduleLocalReminders();
    TtsService.addListener(_onTtsChanged);
  }

  void _onTtsChanged() {
    if (!mounted) return;
    setState(() => _isSpeaking = TtsService.isPlaying);
  }

  /// Reschedule pending reminders จาก local storage (กันหาย)
  Future<void> _rescheduleLocalReminders() async {
    try {
      final pending = LocalStorage.getPendingReminders();
      var count = 0;
      for (final r in pending) {
        // wrap แต่ละ reminder แยก — 1 fail ไม่กระทบตัวอื่น
        try {
          final dt = DateTime.parse(
            (r['remind_at'] as String).replaceAll(' ', 'T'),
          );
          await NotificationService.scheduleReminder(
            id: dt.millisecondsSinceEpoch ~/ 1000,
            title: '🤖 ฟ้าเตือน~',
            body: r['message'] as String,
            scheduledTime: dt,
          );
          count++;
        } catch (e) {
          debugPrint('Failed to reschedule one reminder: $e');
        }
      }
      // ลบ reminder หมดเวลา
      await LocalStorage.cleanExpiredReminders();
      if (count > 0) {
        debugPrint('Rescheduled $count/${pending.length} pending reminders');
      }
    } catch (e) {
      debugPrint('Failed to reschedule reminders: $e');
    }
  }

  void _checkMoodReminder() {
    // ถ้าตอนค่ำ (18:00+) และยังไม่ได้บันทึก mood → แสดง mood picker
    final hour = DateTime.now().hour;
    if (hour >= 18) {
      setState(() => _showMoodPicker = true);
    }
  }

  Future<void> _fetchCriticalAlerts() async {
    try {
      final data = await ApiService.getCriticalAlerts();
      final alerts = (data['alerts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (alerts.isEmpty || !mounted) return;

      // กรอง alerts ที่เคยเห็นแล้วออก (ไม่แสดงซ้ำ)
      final seenIds = LocalStorage.seenAlertIds;
      final newAlerts = alerts.where((a) {
        final key = '${a['id']}_${a['title']}';
        return !seenIds.contains(key);
      }).toList();

      if (newAlerts.isEmpty) return;

      setState(() {
        _criticalAlerts = newAlerts;
        _alertDismissed = false;
      });

      // บันทึกว่าเห็น alerts เหล่านี้แล้ว
      final newSeenIds = [...seenIds];
      for (final a in newAlerts) {
        newSeenIds.add('${a['id']}_${a['title']}');
      }
      // เก็บแค่ 50 ตัวล่าสุด
      if (newSeenIds.length > 50) {
        newSeenIds.removeRange(0, newSeenIds.length - 50);
      }
      await LocalStorage.saveSeenAlertIds(newSeenIds);

      // พูดแจ้งเตือนภัยอัตโนมัติ
      if (LocalStorage.autoSpeak) {
        final title = newAlerts.first['title'] ?? '';
        if (title.isNotEmpty) {
          await TtsService.speak('ข่าวด่วน $title');
        }
      }
    } catch (_) {}
  }

  Future<void> _speakWelcome() async {
    if (!LocalStorage.autoSpeak) return;
    final name = LocalStorage.userName;
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 12) {
      greeting = 'สวัสดีตอนเช้า $name วันนี้เป็นไงบ้าง';
    } else if (hour < 17) {
      greeting = 'สวัสดีตอนบ่าย $name มีอะไรเล่าให้ฟังมั้ย';
    } else {
      greeting = 'สวัสดีตอนค่ำ $name วันนี้เป็นไงบ้าง';
    }
    await TtsService.speak(greeting);
  }

  void _loadMessages() {
    _messages = LocalStorage.getMessages();
    final isFirstOpen = _messages.isEmpty;
    if (isFirstOpen) {
      final name = LocalStorage.userName;
      _messages.add(Message(
        role: 'ai',
        content: 'พร้อมคุยแล้ว $name~ มีอะไรเล่าให้ฟังมั้ย? 😊',
      ));
    }
    setState(() {});
    _scrollToBottom();

    // พูดทักทายตอนเปิดแอป (delay เล็กน้อยให้ UI โหลดก่อน)
    if (isFirstOpen) {
      Future.delayed(const Duration(milliseconds: 500), _speakWelcome);
    }
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

  /// ส่งข้อความ + รับคำตอบ AI
  /// [speakReply] = true → พูดอัตโนมัติ (ปกติ), false → voice mode จัดการเอง
  Future<String?> _sendText(String text, {bool speakReply = true}) async {
    if (text.isEmpty) return null;

    final userMessage = Message(role: 'user', content: text);
    setState(() {
      _messages.add(userMessage);
      _isTyping = true;
    });
    _controller.clear();
    _scrollToBottom();

    await LocalStorage.saveMessage(userMessage);

    try {
      final response = await ApiService.sendMessage(
        userId: LocalStorage.userId,
        message: text,
      );

      final reply = response['reply'] as String;
      final aiMessage = Message(role: 'ai', content: reply);
      setState(() {
        _messages.add(aiMessage);
        _isTyping = false;
      });
      _scrollToBottom();

      await LocalStorage.saveMessage(aiMessage);

      // พูดอัตโนมัติ (เฉพาะโหมดปกติ)
      if (speakReply && LocalStorage.autoSpeak) {
        await TtsService.speak(reply);
      }

      // จัดการ stock alert จาก API response
      final stockSymbol = response['stock_symbol'] as String?;
      final stockPrice = response['stock_price'];
      final stockCurrency = response['stock_currency'] as String? ?? '';
      if (stockSymbol != null && stockPrice != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📊 ติดตามหุ้น $stockSymbol เรียบร้อย! (ราคา $stockPrice $stockCurrency)'),
            backgroundColor: Colors.blueGrey,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // จัดการ reminder จาก API response
      final hasReminder = response['has_reminder'] == true;
      final reminderTime = response['reminder_time'] as String?;
      final reminderMessage = response['reminder_message'] as String?;

      if (hasReminder && reminderTime != null && reminderMessage != null) {
        try {
          final dt = DateTime.parse(reminderTime.replaceAll(' ', 'T'));
          if (dt.isAfter(DateTime.now())) {
            await LocalStorage.saveReminder(
              message: reminderMessage,
              remindAt: reminderTime,
            );
            await NotificationService.scheduleReminder(
              id: dt.millisecondsSinceEpoch ~/ 1000,
              title: '🤖 ฟ้าเตือน~',
              body: reminderMessage,
              scheduledTime: dt,
            );
            await LocalStorage.syncRemindersToSharedPrefs();
            debugPrint('Reminder saved + scheduled: $reminderMessage at $dt');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('ตั้งเตือน "$reminderMessage" เรียบร้อย!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('Failed to handle reminder: $e');
        }
      }

      return reply;
    } catch (e) {
      debugPrint('Chat error: $e');
      final errorMessage = Message(
        role: 'ai',
        content: 'อุ๊ปส์ ฟ้าตอบไม่ได้ชั่วคราว ลองใหม่นะ~ 😅',
      );
      setState(() {
        _messages.add(errorMessage);
        _isTyping = false;
      });
      _scrollToBottom();
      await LocalStorage.saveMessage(errorMessage);
      return null;
    }
  }

  // ==================== J.A.R.V.I.S. Voice Mode ====================

  Future<void> _enterVoiceMode() async {
    TtsService.stop();
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return VoiceModeOverlay(
            onSendMessage: (text) => _sendText(text, speakReply: false),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = LocalStorage.userName;
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 12) {
      greeting = '☀️ สวัสดีตอนเช้า';
    } else if (hour < 17) {
      greeting = '🌤️ สวัสดีตอนบ่าย';
    } else {
      greeting = '🌙 สวัสดีตอนค่ำ';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '🤖 ฟ้า',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                if (_isSpeaking) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.graphic_eq_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'กำลังพูด...',
                          style: TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            Text(
              '$greeting $name',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF6C9BCF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              LocalStorage.autoSpeak
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
            ),
            onPressed: () async {
              final newVal = !LocalStorage.autoSpeak;
              await LocalStorage.saveSetting('autoSpeak', newVal);
              if (!newVal) TtsService.stop();
              setState(() {});
            },
            tooltip: LocalStorage.autoSpeak
                ? 'ปิดเสียงอัตโนมัติ'
                : 'เปิดเสียงอัตโนมัติ',
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: _showReminders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Mood Picker (แสดงตอนค่ำ)
          if (_showMoodPicker)
            MoodPicker(
              onSaved: () {
                setState(() => _showMoodPicker = false);
              },
            ),

          // Alert Banner
          if (_criticalAlerts.isNotEmpty && !_alertDismissed)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD32F2F), Color(0xFFE53935)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ข่าวด่วน',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _criticalAlerts.first['title'] ?? '',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () =>
                        setState(() => _alertDismissed = true),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isTyping) {
                  return const TypingIndicator();
                }
                return ChatBubble(message: _messages[index]);
              },
            ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Text field
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _sendText(_controller.text.trim()),
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'พิมพ์หรือกดไมค์เพื่อพูด...',
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
                    maxLines: 4,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                // Voice button: กดสั้น = one-shot, กดค้าง = J.A.R.V.I.S. mode
                VoiceButton(
                  onResult: (text) {
                    _controller.text = text;
                    _sendText(text);
                  },
                  onLongPress: _enterVoiceMode,
                ),
                const SizedBox(width: 6),
                // Send button
                FloatingActionButton.small(
                  onPressed: _isTyping
                      ? null
                      : () => _sendText(_controller.text.trim()),
                  backgroundColor: const Color(0xFF6C9BCF),
                  child: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showReminders() async {
    // ลองดึงจาก backend ก่อน ถ้า fail ใช้ local
    List<Map<String, dynamic>> reminders;
    bool isLocal = false;
    try {
      reminders = await ApiService.getReminders(LocalStorage.userId);
    } catch (_) {
      // Backend fail → ใช้ local reminders
      reminders = LocalStorage.getPendingReminders();
      isLocal = true;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📋 รายการเตือน',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        _runNotificationDiagnostic();
                      },
                      icon: const Icon(Icons.build, size: 20),
                      tooltip: 'ทดสอบระบบ',
                    ),
                    IconButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        _scheduleTestNotification();
                      },
                      icon: const Icon(Icons.timer, size: 20),
                      tooltip: 'ทดสอบ 30 วินาที',
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showAddReminder();
                      },
                      icon: const Icon(Icons.add_alarm, size: 20),
                      label: const Text('ตั้งเตือน'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (reminders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'ยังไม่มีรายการเตือน 📝\nกดปุ่ม "ตั้งเตือน" หรือบอกฟ้าว่ามีนัดอะไร~',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                ),
              ),
            ...reminders.map((r) => ListTile(
                  leading:
                      const Icon(Icons.alarm, color: Color(0xFF6C9BCF)),
                  title: Text(r['message'] ?? ''),
                  subtitle: Text(r['remind_at'] ?? ''),
                  trailing: isLocal
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: () async {
                            await ApiService.completeReminder(r['id']);
                            if (mounted) Navigator.pop(context);
                          },
                        ),
                )),
          ],
        );
      },
    );
  }

  Future<void> _scheduleTestNotification() async {
    if (!mounted) return;
    String result;
    try {
      result = await NotificationService.scheduleTestNotification();
    } catch (e) {
      result = 'Error: $e';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result), duration: const Duration(seconds: 5)),
    );
  }

  Future<void> _runNotificationDiagnostic() async {
    if (!mounted) return;
    // แสดง loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    String result;
    try {
      result = await NotificationService.runDiagnostic();
    } catch (e) {
      result = 'Diagnostic crashed: $e';
    }

    if (!mounted) return;
    Navigator.pop(context); // ปิด loading

    // แสดงผลลัพธ์
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ผลทดสอบระบบแจ้งเตือน'),
        content: SingleChildScrollView(
          child: Text(result, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddReminder() async {
    final messageController = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('ตั้งเตือนใหม่'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: messageController,
                      decoration: const InputDecoration(
                        labelText: 'เรื่องที่ต้องทำ',
                        hintText: 'เช่น ไปหาหมอ, ประชุม',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text(selectedDate != null
                          ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                          : 'เลือกวันที่'),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time),
                      title: Text(selectedTime != null
                          ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                          : 'เลือกเวลา'),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: () {
                    if (messageController.text.trim().isEmpty ||
                        selectedDate == null ||
                        selectedTime == null) {
                      return;
                    }
                    Navigator.pop(ctx, {
                      'message': messageController.text.trim(),
                      'date': selectedDate,
                      'time': selectedTime,
                    });
                  },
                  child: const Text('ตั้งเตือน'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final date = result['date'] as DateTime;
    final time = result['time'] as TimeOfDay;
    final message = result['message'] as String;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);

    if (dt.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เวลาต้องเป็นอนาคตนะ~')),
        );
      }
      return;
    }

    try {
      final remindAt =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

      // 1. เก็บลงเครื่องก่อน (ควรสำเร็จเสมอ)
      await LocalStorage.saveReminder(message: message, remindAt: remindAt);
      debugPrint('Reminder saved locally: $message at $remindAt');

      // 2. ตั้ง notification (อาจ fail ได้ — ไม่ fatal เพราะ save แล้ว)
      try {
        await NotificationService.scheduleReminder(
          id: dt.millisecondsSinceEpoch ~/ 1000,
          title: '🤖 ฟ้าเตือน~',
          body: message,
          scheduledTime: dt,
        );
      } catch (e) {
        debugPrint('Notification scheduling failed (non-fatal): $e');
      }

      // 3. Sync ไปยัง SharedPrefs (สำหรับ WorkManager backup)
      await LocalStorage.syncRemindersToSharedPrefs();

      // 4. บันทึกลง backend (ไม่ fatal)
      try {
        await ApiService.addReminder(
          userId: LocalStorage.userId,
          message: message,
          remindAt: remindAt,
        );
      } catch (_) {}

      debugPrint('Custom reminder complete: $message at $dt');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ตั้งเตือน "$message" เรียบร้อย!')),
        );
      }
    } catch (e) {
      debugPrint('Failed to save reminder: $e');
      if (mounted) {
        final errMsg = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ตั้งเตือนไม่สำเร็จ: ${errMsg.substring(0, min(80, errMsg.length))}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    TtsService.removeListener(_onTtsChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
