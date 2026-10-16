import 'types.dart';

bool isRecordingExercise(List<SetEntry> sets) =>
    sets.any((s) => !s.isCompleted);
int resolveRecordingIndex(
  List<String> ids,
  String? preferred,
  int previousIndex,
) {
  if (ids.isEmpty) return 0;
  final found = preferred == null ? -1 : ids.indexOf(preferred);
  return found >= 0 ? found : previousIndex.clamp(0, ids.length - 1).toInt();
}
