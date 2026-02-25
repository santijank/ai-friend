/// routine_screen.dart — หน้ากิจวัตรประจำวัน
import 'package:flutter/material.dart';
import '../models/routine.dart';
import '../services/api_service.dart';
import '../services/local_storage.dart';
import '../widgets/routine_card.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key});

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  List<Routine> _routines = [];
  int _streak = 0;
  int _totalPoints = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = LocalStorage.userId;
      final results = await Future.wait([
        ApiService.getRoutines(userId),
        ApiService.getUserStats(userId),
      ]);

      final routinesData = results[0] as List<Map<String, dynamic>>;
      final stats = results[1] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _routines = routinesData.map((r) => Routine.fromJson(r)).toList();
          _streak = stats['streak'] as int? ?? 0;
          _totalPoints = stats['total_points'] as int? ?? 0;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeRoutine(Routine routine) async {
    try {
      await ApiService.completeRoutine(routine.id);
      await _loadData();
    } catch (_) {}
  }

  Future<void> _addRoutine() async {
    final titleController = TextEditingController();
    final timeController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มกิจวัตรใหม่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'ชื่อกิจวัตร',
                hintText: 'เช่น ออกกำลังกาย 30 นาที',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: timeController,
              decoration: const InputDecoration(
                labelText: 'เวลา (ไม่บังคับ)',
                hintText: 'เช่น 07:00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );

    if (result == true && titleController.text.isNotEmpty) {
      try {
        await ApiService.createRoutine(
          userId: LocalStorage.userId,
          title: titleController.text.trim(),
          time: timeController.text.trim(),
        );
        await _loadData();
      } catch (_) {}
    }

    titleController.dispose();
    timeController.dispose();
  }

  Future<void> _deleteRoutine(Routine routine) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบกิจวัตร'),
        content: Text('ลบ "${routine.title}" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.deleteRoutine(routine.id);
        await _loadData();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _routines.where((r) => r.doneToday).length;
    final totalCount = _routines.length;

    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // Header stats
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      decoration: const BoxDecoration(
                        color: Color(0xFF6C9BCF),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(24),
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            const Text(
                              'กิจวัตรวันนี้',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildStatItem(
                                  '🔥',
                                  '$_streak',
                                  'วันติดต่อ',
                                ),
                                _buildStatItem(
                                  '✅',
                                  '$doneCount/$totalCount',
                                  'ทำแล้ว',
                                ),
                                _buildStatItem(
                                  '⭐',
                                  '$_totalPoints',
                                  'คะแนนรวม',
                                ),
                              ],
                            ),
                            if (totalCount > 0) ...[
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: totalCount > 0
                                      ? doneCount / totalCount
                                      : 0,
                                  backgroundColor: Colors.white30,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Routine list
                  if (_routines.isEmpty)
                    const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'ยังไม่มีกิจวัตร\nกดปุ่ม + เพื่อเพิ่มกิจวัตรใหม่',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final routine = _routines[index];
                            return RoutineCard(
                              routine: routine,
                              onComplete: () => _completeRoutine(routine),
                              onDelete: () => _deleteRoutine(routine),
                            );
                          },
                          childCount: _routines.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRoutine,
        backgroundColor: const Color(0xFF6C9BCF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatItem(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }
}
