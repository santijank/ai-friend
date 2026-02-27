/// voice_mode_overlay.dart — J.A.R.V.I.S. Voice Conversation Mode
/// กดค้างปุ่มไมค์เพื่อเข้าโหมดสนทนาด้วยเสียงแบบต่อเนื่อง
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';

enum VoiceModeState { listening, thinking, speaking }

class VoiceModeOverlay extends StatefulWidget {
  /// ส่งข้อความไป API แล้ว return คำตอบ AI (null = error)
  final Future<String?> Function(String userText) onSendMessage;

  const VoiceModeOverlay({super.key, required this.onSendMessage});

  @override
  State<VoiceModeOverlay> createState() => _VoiceModeOverlayState();
}

class _VoiceModeOverlayState extends State<VoiceModeOverlay>
    with TickerProviderStateMixin {
  VoiceModeState _state = VoiceModeState.listening;
  String _transcript = '';
  String _lastAiReply = '';
  bool _isActive = true;
  int _silenceCount = 0;
  int _sttErrorCount = 0;
  static const int _maxSilence = 3;
  static const int _maxSttErrors = 5;
  Timer? _ttsTimeoutTimer;
  bool _waitingForTtsComplete = false;

  late AnimationController _pulseCtrl;
  late AnimationController _thinkCtrl;
  late AnimationController _speakCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _thinkCtrl = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _speakCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    TtsService.addListener(_onTtsChanged);
    _startListening();
  }

  @override
  void dispose() {
    _isActive = false;
    _ttsTimeoutTimer?.cancel();
    TtsService.removeListener(_onTtsChanged);
    _pulseCtrl.dispose();
    _thinkCtrl.dispose();
    _speakCtrl.dispose();
    super.dispose();
  }

  // ==================== Voice Loop ====================

  Future<void> _startListening() async {
    if (!_isActive || !mounted) return;

    // หยุด TTS + audio ให้เรียบร้อยก่อนเปิดไมค์
    await TtsService.stop();
    await Future.delayed(const Duration(milliseconds: 300));

    if (!_isActive || !mounted) return;

    setState(() {
      _state = VoiceModeState.listening;
      _transcript = '';
    });
    _stopAllAnimations();
    _pulseCtrl.repeat(reverse: true);

    debugPrint('JARVIS: startListening (silence=$_silenceCount, sttErr=$_sttErrorCount)');

    await SttService.startListening(
      onResult: (text) {
        if (!mounted) return;
        _sttErrorCount = 0; // reset error count on any result
        setState(() => _transcript = text);
      },
      onDone: () {
        if (!mounted || !_isActive) return;
        debugPrint('JARVIS: STT done, transcript="${_transcript}"');
        _onSpeechDone();
      },
      onError: (error) {
        debugPrint('JARVIS: STT error: $error');
        if (!mounted || !_isActive) return;
        _sttErrorCount++;
        if (_sttErrorCount >= _maxSttErrors) {
          debugPrint('JARVIS: too many STT errors, exiting');
          _exit();
          return;
        }
        Future.delayed(const Duration(milliseconds: 800), () {
          if (_isActive && mounted) _startListening();
        });
      },
      listenFor: const Duration(seconds: 15),
    );
  }

  void _onSpeechDone() {
    final text = _transcript.trim();

    if (text.isEmpty) {
      _silenceCount++;
      if (_silenceCount >= _maxSilence) {
        _exit();
        return;
      }
      _startListening();
      return;
    }

    _silenceCount = 0;
    _sendAndSpeak(text);
  }

  Future<void> _sendAndSpeak(String text) async {
    if (!_isActive || !mounted) return;

    setState(() => _state = VoiceModeState.thinking);
    _stopAllAnimations();
    _thinkCtrl.repeat();

    debugPrint('JARVIS: sending message...');

    try {
      final reply = await widget.onSendMessage(text);

      if (!_isActive || !mounted) return;
      _stopAllAnimations();

      if (reply != null && reply.isNotEmpty) {
        debugPrint('JARVIS: got reply (${reply.length} chars), speaking...');
        setState(() {
          _state = VoiceModeState.speaking;
          _lastAiReply = reply;
        });
        _speakCtrl.repeat(reverse: true);

        // ตั้ง timeout — ถ้า TTS ไม่จบใน 20 วินาที ให้วนลูปต่อ
        _waitingForTtsComplete = true;
        _ttsTimeoutTimer?.cancel();
        _ttsTimeoutTimer = Timer(const Duration(seconds: 20), () {
          debugPrint('JARVIS: TTS timeout! forcing next listen cycle');
          if (_isActive && mounted && _waitingForTtsComplete) {
            _waitingForTtsComplete = false;
            _continueToListening();
          }
        });

        await TtsService.speak(reply);
        // _onTtsChanged หรือ timeout จะ handle การวนลูป
      } else {
        debugPrint('JARVIS: empty reply, back to listening');
        _startListening();
      }
    } catch (e) {
      debugPrint('JARVIS: send error: $e');
      if (!_isActive || !mounted) return;
      _startListening();
    }
  }

  void _onTtsChanged() {
    if (!mounted || !_isActive) return;

    debugPrint('JARVIS: TTS changed — playing=${TtsService.isPlaying}, state=$_state, waiting=$_waitingForTtsComplete');

    if (!TtsService.isPlaying && _state == VoiceModeState.speaking && _waitingForTtsComplete) {
      _waitingForTtsComplete = false;
      _ttsTimeoutTimer?.cancel();
      debugPrint('JARVIS: TTS completed, scheduling next listen');
      _continueToListening();
    }
  }

  void _continueToListening() {
    _stopAllAnimations();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (_isActive && mounted) {
        _startListening();
      }
    });
  }

  void _stopAllAnimations() {
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    _thinkCtrl.stop();
    _thinkCtrl.reset();
    _speakCtrl.stop();
    _speakCtrl.reset();
  }

  void _exit() {
    _isActive = false;
    SttService.stopListening();
    TtsService.stop();
    if (mounted) Navigator.of(context).pop();
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        _exit();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              const Spacer(flex: 2),
              _buildOrb(),
              const SizedBox(height: 32),
              _buildStatusText(),
              const SizedBox(height: 20),
              _buildContentText(),
              const Spacer(flex: 3),
              _buildEndButton(),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 16),
                SizedBox(width: 6),
                Text(
                  'J.A.R.V.I.S. Mode',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 24),
            onPressed: _exit,
          ),
        ],
      ),
    );
  }

  Widget _buildOrb() {
    final Color orbColor;
    final IconData orbIcon;
    final AnimationController activeCtrl;

    switch (_state) {
      case VoiceModeState.listening:
        orbColor = const Color(0xFF4FC3F7);
        orbIcon = Icons.mic_rounded;
        activeCtrl = _pulseCtrl;
        break;
      case VoiceModeState.thinking:
        orbColor = const Color(0xFFAB47BC);
        orbIcon = Icons.psychology_rounded;
        activeCtrl = _thinkCtrl;
        break;
      case VoiceModeState.speaking:
        orbColor = const Color(0xFF66BB6A);
        orbIcon = Icons.graphic_eq_rounded;
        activeCtrl = _speakCtrl;
        break;
    }

    return AnimatedBuilder(
      animation: activeCtrl,
      builder: (context, _) {
        final pulse = _state == VoiceModeState.listening
            ? 1.0 + activeCtrl.value * 0.12
            : 1.0;
        final rotate = _state == VoiceModeState.thinking
            ? activeCtrl.value * 2 * 3.14159
            : 0.0;
        final bounce = _state == VoiceModeState.speaking
            ? 1.0 + activeCtrl.value * 0.08
            : 1.0;

        return Transform.scale(
          scale: pulse * bounce,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: orbColor.withValues(alpha: 0.15 + activeCtrl.value * 0.15),
                    width: 2,
                  ),
                ),
              ),
              // Middle ring
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: orbColor.withValues(alpha: 0.2 + activeCtrl.value * 0.1),
                    width: 1.5,
                  ),
                ),
              ),
              // Main orb
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      orbColor,
                      orbColor.withValues(alpha: 0.7),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: orbColor.withValues(alpha: 0.4),
                      blurRadius: 30 + activeCtrl.value * 20,
                      spreadRadius: activeCtrl.value * 8,
                    ),
                  ],
                ),
                child: Transform.rotate(
                  angle: rotate,
                  child: Icon(orbIcon, color: Colors.white, size: 40),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusText() {
    final String statusText;
    final Color statusColor;

    switch (_state) {
      case VoiceModeState.listening:
        statusText = 'กำลังฟัง...';
        statusColor = const Color(0xFF4FC3F7);
        break;
      case VoiceModeState.thinking:
        statusText = 'กำลังคิด...';
        statusColor = const Color(0xFFAB47BC);
        break;
      case VoiceModeState.speaking:
        statusText = 'กำลังพูด...';
        statusColor = const Color(0xFF66BB6A);
        break;
    }

    return Text(
      statusText,
      style: TextStyle(
        color: statusColor,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildContentText() {
    final String displayText;
    final Color textColor;

    switch (_state) {
      case VoiceModeState.listening:
        displayText = _transcript.isEmpty ? 'พูดภาษาไทยได้เลย...' : _transcript;
        textColor = _transcript.isEmpty ? Colors.white24 : Colors.white70;
        break;
      case VoiceModeState.thinking:
        displayText = _transcript;
        textColor = Colors.white54;
        break;
      case VoiceModeState.speaking:
        displayText = _lastAiReply;
        textColor = Colors.white70;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        height: 100,
        child: SingleChildScrollView(
          child: Text(
            displayText,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildEndButton() {
    return GestureDetector(
      onTap: _exit,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.shade600,
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.call_end_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}
