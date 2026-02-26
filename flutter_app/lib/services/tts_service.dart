// tts_service.dart — Text-to-Speech ผ่าน Backend (Google TTS)
// ใช้ backend /tts endpoint สร้างเสียง MP3 แล้วเล่นผ่าน HTML Audio (web)
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config.dart';

// Conditional import: web ใช้ dart:html, mobile ใช้ flutter_tts
import 'tts_web.dart' if (dart.library.io) 'tts_mobile.dart' as tts_platform;

class TtsService {
  static bool _isPlaying = false;
  static bool _isInitialized = false;
  static final List<VoidCallback> _listeners = [];

  static Future<void> init() async {
    try {
      await tts_platform.init(
        baseUrl: AppConfig.apiBaseUrl,
        onStart: () {
          _isPlaying = true;
          _notifyListeners();
        },
        onComplete: () {
          _isPlaying = false;
          _notifyListeners();
        },
        onError: (msg) {
          debugPrint('TTS error: $msg');
          _isPlaying = false;
          _notifyListeners();
        },
      );
      _isInitialized = true;
      debugPrint('TTS initialized OK — baseUrl: ${AppConfig.apiBaseUrl}');
    } catch (e) {
      debugPrint('TTS init error: $e');
      _isInitialized = true; // ยังให้ลองพูดได้
    }
  }

  static bool get isPlaying => _isPlaying;
  static bool get isAvailable => _isInitialized;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  static Future<void> speak(String text) async {
    debugPrint('TtsService.speak called: initialized=$_isInitialized, text=${text.length} chars');
    if (text.isEmpty || !_isInitialized) return;

    if (_isPlaying) {
      await stop();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final cleaned = _cleanText(text);
    if (cleaned.isEmpty) return;

    _isPlaying = true;
    _notifyListeners();

    try {
      await tts_platform.speak(cleaned);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      _isPlaying = false;
      _notifyListeners();
    }
  }

  static Future<void> stop() async {
    try {
      await tts_platform.stop();
    } catch (_) {}
    _isPlaying = false;
    _notifyListeners();
  }

  static Future<void> setRate(double rate) async {
    // Rate control not needed for backend TTS
  }

  static String _cleanText(String text) {
    final emojiPattern = RegExp(
      r'[\u{1F600}-\u{1F64F}]|'
      r'[\u{1F300}-\u{1F5FF}]|'
      r'[\u{1F680}-\u{1F6FF}]|'
      r'[\u{1F1E0}-\u{1F1FF}]|'
      r'[\u{2600}-\u{26FF}]|'
      r'[\u{2700}-\u{27BF}]|'
      r'[\u{FE00}-\u{FE0F}]|'
      r'[\u{1F900}-\u{1F9FF}]|'
      r'[\u{200D}]|'
      r'[\u{20E3}]|'
      r'[\u{FE0F}]',
      unicode: true,
    );
    String cleaned = text.replaceAll(emojiPattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAll('~', '');
    return cleaned;
  }
}
