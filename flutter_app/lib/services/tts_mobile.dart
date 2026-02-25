// tts_mobile.dart — Mobile implementation: เล่นเสียงจาก backend /tts endpoint
// ใช้ http POST + audioplayers เล่น MP3 จาก backend Google TTS
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

String _baseUrl = '';
final AudioPlayer _player = AudioPlayer();
void Function()? _onStart;
void Function()? _onComplete;
void Function(String)? _onError;

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

  // Listen to player state changes
  _player.onPlayerStateChanged.listen((state) {
    if (state == PlayerState.playing) {
      _onStart?.call();
    } else if (state == PlayerState.completed) {
      _onComplete?.call();
    } else if (state == PlayerState.stopped) {
      _onComplete?.call();
    }
  });
}

Future<void> speak(String text) async {
  await stop();

  try {
    _onStart?.call();

    // ใช้ POST เพื่อรองรับข้อความยาว
    final response = await http.post(
      Uri.parse('$_baseUrl/tts'),
      headers: {'Content-Type': 'application/json'},
      body: '{"text": ${_jsonEncode(text)}}',
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      _onError?.call('TTS server error: ${response.statusCode}');
      return;
    }

    // บันทึกไฟล์เสียงชั่วคราว แล้วเล่น
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tts_audio.mp3');
    await file.writeAsBytes(response.bodyBytes);
    await _player.play(DeviceFileSource(file.path));
  } catch (e) {
    _onError?.call(e.toString());
  }
}

Future<void> stop() async {
  try {
    await _player.stop();
  } catch (_) {}
}

String _jsonEncode(String text) {
  return '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
}
