/// mood_history_screen.dart — กราฟอารมณ์รายสัปดาห์
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_storage.dart';

class MoodHistoryScreen extends StatefulWidget {
  const MoodHistoryScreen({super.key});

  @override
  State<MoodHistoryScreen> createState() => _MoodHistoryScreenState();
}

class _MoodHistoryScreenState extends State<MoodHistoryScreen> {
  List<Map<String, dynamic>> _moods = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMoods();
  }

  Future<void> _loadMoods() async {
    try {
      final moods = await ApiService.getMoodHistory(
        LocalStorage.userId,
        days: 30,
      );
      if (mounted) {
        setState(() {
          _moods = moods;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติอารมณ์'),
        backgroundColor: const Color(0xFF6C9BCF),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _moods.isEmpty
              ? const Center(
                  child: Text(
                    'ยังไม่มีข้อมูลอารมณ์\nลองบันทึกอารมณ์วันนี้สิ~',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : _buildMoodChart(),
    );
  }

  Widget _buildMoodChart() {
    final moodEmojis = {1: '😢', 2: '😔', 3: '😐', 4: '🙂', 5: '😊'};
    final moodColors = {
      1: Colors.red.shade300,
      2: Colors.orange.shade300,
      3: Colors.amber.shade300,
      4: Colors.lightGreen.shade300,
      5: Colors.green.shade400,
    };

    // คำนวณค่าเฉลี่ย
    final avg = _moods.isNotEmpty
        ? _moods.map((m) => m['score'] as int).reduce((a, b) => a + b) /
            _moods.length
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // สรุป
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C9BCF).withOpacity(0.1),
                  const Color(0xFF6C9BCF).withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  moodEmojis[(avg.round()).clamp(1, 5)] ?? '😐',
                  style: const TextStyle(fontSize: 48),
                ),
                const SizedBox(height: 8),
                Text(
                  'ค่าเฉลี่ย: ${avg.toStringAsFixed(1)}/5',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6C9BCF),
                  ),
                ),
                Text(
                  'จาก ${_moods.length} วันที่บันทึก',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'ประวัติอารมณ์',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Simple bar chart
          Container(
            height: 200,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _moods.reversed.take(14).toList().reversed.map((mood) {
                final score = mood['score'] as int;
                final dateStr = mood['created_at'] as String;
                final day = dateStr.length >= 10 ? dateStr.substring(8, 10) : '';
                final barHeight = (score / 5) * 140;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          moodEmojis[score] ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: moodColors[score],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          day,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // รายการแต่ละวัน
          ...(_moods.reversed.take(30).map((mood) {
            final score = mood['score'] as int;
            final note = mood['note'] as String? ?? '';
            final dateStr = mood['created_at'] as String;
            return ListTile(
              leading: Text(
                moodEmojis[score] ?? '😐',
                style: const TextStyle(fontSize: 28),
              ),
              title: Text(dateStr),
              subtitle: note.isNotEmpty ? Text(note) : null,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: moodColors[score]?.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$score/5'),
              ),
            );
          })),
        ],
      ),
    );
  }
}
