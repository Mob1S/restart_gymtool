import 'weight_value.dart';
import 'set_detail.dart';
import 'training_prescription.dart';

class WorkoutCsvRow {
  final SetDetail? detail;
  final String? groupId;
  final String sessionId;
  final String? sessionName;
  final int startedAt, finishedAt;
  final String exerciseName;
  final int setPosition;
  final EquipmentWeight reading;
  final int reps;

  const WorkoutCsvRow({
    this.detail,
    this.groupId,
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
    'session_id,start_time,end_time,title,exercise_title,set_index,weight,weight_unit,weight_kg,reps,group_id,segment_index,pause_seconds,set_role,effort_kind,effort_value,effort_bound,set_detail\r\n',
  );
  for (final (index, row) in rows.indexed) {
    void writeSegment(
      EquipmentWeight reading,
      int reps,
      int segment,
      int pause,
      Effort? effort,
    ) {
      output.write(
        [
          row.sessionId,
          instant(row.startedAt),
          instant(row.finishedAt),
          row.sessionName,
          row.exerciseName,
          row.setPosition + 1,
          reading.amount.text,
          reading.unit.name,
          reading.kilograms,
          reps,
          row.groupId ?? 'group-$index',
          segment,
          pause,
          row.detail?.role ?? 'unknown',
          effort?.kind,
          effort?.value,
          effort?.bound,
          segment == 1 ? row.detail?.encode() : null,
        ].map(cell).join(','),
      );
      output.write('\r\n');
    }

    writeSegment(row.reading, row.reps, 1, 0, row.detail?.effort);
    for (final (i, segment)
        in (row.detail?.continuations ?? <RecordedSegment>[]).indexed) {
      writeSegment(
        segment.reading,
        segment.reps,
        i + 2,
        segment.pauseSeconds,
        segment.effort,
      );
    }
  }
  return output.toString();
}
