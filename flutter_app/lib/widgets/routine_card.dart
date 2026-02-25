/// routine_card.dart — การ์ดแสดงกิจวัตร
import 'package:flutter/material.dart';
import '../models/routine.dart';

class RoutineCard extends StatelessWidget {
  final Routine routine;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const RoutineCard({
    super.key,
    required this.routine,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: routine.doneToday ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: routine.doneToday
          ? const Color(0xFFF0F9F0)
          : Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: GestureDetector(
          onTap: routine.doneToday ? null : onComplete,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: routine.doneToday
                  ? const Color(0xFF4CAF50)
                  : Colors.transparent,
              border: Border.all(
                color: routine.doneToday
                    ? const Color(0xFF4CAF50)
                    : Colors.grey.shade400,
                width: 2,
              ),
            ),
            child: routine.doneToday
                ? const Icon(Icons.check, size: 20, color: Colors.white)
                : null,
          ),
        ),
        title: Text(
          routine.title,
          style: TextStyle(
            fontSize: 16,
            decoration:
                routine.doneToday ? TextDecoration.lineThrough : null,
            color: routine.doneToday ? Colors.grey : Colors.black87,
          ),
        ),
        subtitle: routine.time.isNotEmpty
            ? Text(
                routine.time,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: routine.doneToday
                    ? const Color(0xFF4CAF50).withOpacity(0.1)
                    : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                routine.doneToday ? '+${routine.points}⭐' : '${routine.points}⭐',
                style: TextStyle(
                  fontSize: 12,
                  color: routine.doneToday ? const Color(0xFF4CAF50) : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.grey.shade400,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
