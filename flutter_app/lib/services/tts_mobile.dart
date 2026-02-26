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

  debugPrint('TTS init: baseUrl = $_baseUrl');

  // Setup audioplayers listener
  _player.onPlayerStateChanged.listen((state) {
    if (state == PlayerState.playing) {
      _onStart?.call();
    } else if (state == PlayerState.completed) {
      _onComplete?.call();
    } else if (state == PlayerState.stopped) {
      _onComplete?.call();
    }
  });

  // Setup device TTS fallback
  try {
    await _deviceTts.setLanguage('th-TH');
    await _deviceTts.setSpeechRate(0.5);
    await _deviceTts.setVolume(1.0);
    _deviceTts.setStartHandler(() => _onStart?.call());
    _deviceTts.setCompletionHandler(() => _onComplete?.call());
    _deviceTts.setErrorHandler((msg) => _onError?.call(msg.toString()));
    _deviceTtsReady = true;
    debugPrint('TTS fallback (device) ready');
  } catch (e) {
    debugPrint('TTS fallback init error: $e');
  }
}

Future<void> speak(String text) async {
  await stop();
  debugPrint('TTS speak: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');

  // ลอง Backend Google TTS ก่อน (เสียงดี)
  if (_baseUrl.isNotEmpty) {
    try {
      final success = await _speakViaBackend(text);
      if (success) return;
    } catch (e) {
      debugPrint('TTS backend error: $e');
    }
  }

  // Fallback: ใช้ device TTS
  debugPrint('TTS fallback to device TTS');
  await _speakViaDevice(text);
}

Future<bool> _speakViaBackend(String text) async {
  debugPrint('TTS trying backend: $_baseUrl/tts');
  _onStart?.call();

  final response = await http.post(
    Uri.parse('$_baseUrl/tts'),
    headers: {'Content-Type': 'application/json; charset=utf-8'},
    body: jsonEncode({'text': text}),
  ).timeout(const Duration(seconds: 10));

  debugPrint('TTS backend response: ${response.statusCode}');

  if (response.statusCode != 200) {
    debugPrint('TTS backend error body: ${response.body}');
    return false;
  }

  if (response.bodyBytes.length < 100) {
    debugPrint('TTS backend returned too small audio (${response.bodyBytes.length} bytes)');
    return false;
  }

  // Save and play MP3
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/tts_audio.mp3');
  await file.writeAsBytes(response.bodyBytes);
  debugPrint('TTS playing MP3 (${response.bodyBytes.length} bytes)');
  await _player.play(DeviceFileSource(file.path));
  return true;
}

Future<void> _speakViaDevice(String text) async {
  if (!_deviceTtsReady) {
    debugPrint('TTS device not ready, cannot speak');
    _onError?.call('Device TTS not available');
    return;
  }

  _onStart?.call();
  // ตัดข้อความให้สั้นลงสำหรับ device TTS
  final shortText = text.length > 300 ? text.substring(0, 300) : text;
  debugPrint('TTS device speaking: ${shortText.length} chars');
  await _deviceTts.speak(shortText);
}

Future<void> stop() async {
  try {
    await _player.stop();
  } catch (_) {}
  try {
    await _deviceTts.stop();
  } catch (_) {}
}
