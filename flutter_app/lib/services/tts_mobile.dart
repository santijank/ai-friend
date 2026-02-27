// tts_mobile.dart — Mobile TTS: Backend Google TTS (primary) + Device TTS (fallback)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

String _baseUrl = '';
final AudioPlayer _player = AudioPlayer();
final FlutterTts _deviceTts = FlutterTts();
void Function()? _onStart;
void Function()? _onComplete;
void Function(String)? _onError;
bool _deviceTtsReady = false;
bool _usingBackendAudio = false;

Future<void> init({
  required String baseUrl,
  required void Function() onStart,
  required void Function() onComplete,
  required void Function(String) onError,
}) async {
  _baseUrl = baseUrl;
  _onStart = onStart;
  _onComplete = onComplete;
  _onError = onError;

  debugPrint('TTS init: baseUrl = "$_baseUrl"');

  // Setup audioplayers listener
  _player.onPlayerStateChanged.listen((state) {
    debugPrint('TTS audioplayer state: $state');
    if (state == PlayerState.playing) {
      _onStart?.call();
    } else if (state == PlayerState.completed || state == PlayerState.stopped) {
      if (_usingBackendAudio) {
        _usingBackendAudio = false;
        _onComplete?.call();
      }
    }
  });

  // Setup device TTS fallback
  try {
    // ตรวจสอบภาษาที่มี
    final languages = await _deviceTts.getLanguages;
    debugPrint('TTS available languages: $languages');

    // ลองตั้งภาษาไทย — fallback ไปภาษาอื่นถ้าไม่มี
    bool langSet = false;
    for (final lang in ['th-TH', 'th', 'en-US']) {
      try {
        final result = await _deviceTts.setLanguage(lang);
        debugPrint('TTS setLanguage($lang) result: $result');
        if (result == 1) {
          langSet = true;
          break;
        }
      } catch (e) {
        debugPrint('TTS setLanguage($lang) error: $e');
      }
    }

    await _deviceTts.setSpeechRate(0.5);
    await _deviceTts.setVolume(1.0);
    await _deviceTts.awaitSpeakCompletion(true);

    _deviceTts.setStartHandler(() {
      debugPrint('TTS device: started speaking');
      _onStart?.call();
    });
    _deviceTts.setCompletionHandler(() {
      debugPrint('TTS device: completed speaking');
      _onComplete?.call();
    });
    _deviceTts.setErrorHandler((msg) {
      debugPrint('TTS device error: $msg');
      _onError?.call(msg.toString());
    });

    _deviceTtsReady = true;
    debugPrint('TTS fallback (device) ready, langSet=$langSet');
  } catch (e) {
    debugPrint('TTS fallback init error: $e');
  }
}

Future<void> speak(String text) async {
  await stop();
  await Future.delayed(const Duration(milliseconds: 50));

  final preview = text.length > 50 ? text.substring(0, 50) : text;
  debugPrint('TTS speak: "$preview..." (${text.length} chars, baseUrl="$_baseUrl")');

  // ลอง Backend Google TTS ก่อน (เสียงดี)
  if (_baseUrl.isNotEmpty) {
    try {
      final success = await _speakViaBackend(text);
      if (success) return;
    } catch (e) {
      debugPrint('TTS backend exception: $e');
    }
  } else {
    debugPrint('TTS: no baseUrl, skipping backend');
  }

  // Fallback: ใช้ device TTS
  debugPrint('TTS: falling back to device TTS');
  await _speakViaDevice(text);
}

Future<bool> _speakViaBackend(String text) async {
  debugPrint('TTS trying backend POST: $_baseUrl/tts');

  try {
    final response = await http.post(
      Uri.parse('$_baseUrl/tts'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'text': text}),
    ).timeout(const Duration(seconds: 10));

    debugPrint('TTS backend response: ${response.statusCode}, ${response.bodyBytes.length} bytes');

    if (response.statusCode != 200) {
      debugPrint('TTS backend error body: ${response.body}');
      return false;
    }

    if (response.bodyBytes.length < 100) {
      debugPrint('TTS backend returned too small audio');
      return false;
    }

    // Save and play MP3
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tts_audio_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await file.writeAsBytes(response.bodyBytes);
    debugPrint('TTS saved MP3: ${file.path} (${response.bodyBytes.length} bytes)');

    _usingBackendAudio = true;
    _onStart?.call();
    await _player.play(DeviceFileSource(file.path));
    debugPrint('TTS audioplayer.play() called');
    return true;
  } catch (e) {
    debugPrint('TTS backend failed: $e');
    return false;
  }
}

Future<void> _speakViaDevice(String text) async {
  if (!_deviceTtsReady) {
    debugPrint('TTS device not ready');
    _onError?.call('Device TTS not available');
    return;
  }

  // ตัดข้อความให้สั้นลงสำหรับ device TTS
  final shortText = text.length > 500 ? text.substring(0, 500) : text;
  debugPrint('TTS device speaking: ${shortText.length} chars');

  try {
    final result = await _deviceTts.speak(shortText);
    debugPrint('TTS device speak result: $result');
  } catch (e) {
    debugPrint('TTS device speak error: $e');
    _onError?.call('Device TTS error: $e');
  }
}

Future<void> stop() async {
  _usingBackendAudio = false;
  try { await _player.stop(); } catch (_) {}
  try { await _deviceTts.stop(); } catch (_) {}
}
