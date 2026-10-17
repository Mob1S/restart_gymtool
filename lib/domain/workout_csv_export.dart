import 'weight_value.dart';

class WorkoutCsvRow {
  final String sessionId;
  final String? sessionName;
  final int startedAt, finishedAt;
  final String exerciseName;
  final int setPosition;
  final EquipmentWeight reading;
  final int reps;

  const WorkoutCsvRow({
    required this.sessionId,
    this.sessionName,
    required this.startedAt,
    required this.finishedAt,
    required this.exerciseName,
    required this.setPosition,
    required this.reading,
    required this.reps,
  });
}

String encodeWorkoutCsv(List<WorkoutCsvRow> rows) {
  String cell(Object? value) {
    final text = value?.toString() ?? '';
    return text.contains(RegExp('[",\r\n]'))
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  String instant(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toIso8601String();

  final output = StringBuffer(
    'session_id,start_time,end_time,title,exercise_title,set_index,weight,weight_unit,weight_kg,reps\r\n',
  );
  for (final row in rows) {
    output.write(
      [
        row.sessionId,
        instant(row.startedAt),
        instant(row.finishedAt),
        row.sessionName,
        row.exerciseName,
        row.setPosition + 1,
        row.reading.amount.text,
        row.reading.unit.name,
        row.reading.kilograms,
        row.reps,
      ].map(cell).join(','),
    );
    output.write('\r\n');
  }
  return output.toString();
}
