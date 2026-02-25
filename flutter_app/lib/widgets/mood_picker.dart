/// mood_picker.dart — UI เลือกอารมณ์ประจำวัน
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_storage.dart';

class MoodPicker extends StatefulWidget {
  final VoidCallback? onSaved;

  const MoodPicker({super.key, this.onSaved});

  @override
  State<MoodPicker> createState() => _MoodPickerState();
}

class _MoodPickerState extends State<MoodPicker> {
  int? _selectedScore;
  bool _isSaving = false;

  static const _moods = [
    {'score': 1, 'emoji': '😢', 'label': 'แย่มาก'},
    {'score': 2, 'emoji': '😔', 'label': 'ไม่ค่อยดี'},
    {'score': 3, 'emoji': '😐', 'label': 'เฉย ๆ'},
    {'score': 4, 'emoji': '🙂', 'label': 'ดี'},
    {'score': 5, 'emoji': '😊', 'label': 'ดีมาก'},
  ];

  Future<void> _saveMood(int score) async {
    setState(() {
      _selectedScore = score;
      _isSaving = true;
    });

    try {
      await ApiService.sendMood(
        userId: LocalStorage.userId,
        score: score,
      );
      widget.onSaved?.call();
    } catch (_) {
      // ถ้าส่งไม่ได้ก็ไม่เป็นไร
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Column(
        children: [
          const Text(
            'วันนี้รู้สึกยังไงบ้าง?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _moods.map((mood) {
              final score = mood['score'] as int;
              final isSelected = _selectedScore == score;
              return GestureDetector(
                onTap: _isSaving ? null : () => _saveMood(score),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF6C9BCF).withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: const Color(0xFF6C9BCF), width: 2)
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        mood['emoji'] as String,
                        style: TextStyle(fontSize: isSelected ? 32 : 28),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mood['label'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? const Color(0xFF6C9BCF)
                              : Colors.grey,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_selectedScore != null && !_isSaving)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'บันทึกแล้ว ✓',
                style: TextStyle(color: Color(0xFF4CAF50), fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
