/// routine.dart — โมเดลกิจวัตร
class Routine {
  final int id;
  final String title;
  final String time;
  final int points;
  final bool doneToday;

  Routine({
    required this.id,
    required this.title,
    this.time = '',
    this.points = 5,
    this.doneToday = false,
  });

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
        id: json['id'] as int,
        title: json['title'] as String,
        time: json['time'] as String? ?? '',
        points: json['points'] as int? ?? 5,
        doneToday: json['done_today'] as bool? ?? false,
      );
}
