import 'package:flutter/material.dart';

import '../../state/active_session_controller.dart';

Future<RemoveExerciseChoice?> showRemoveExerciseDialog(
  BuildContext context,
  ExerciseRemovalPreview preview,
) {
  if (preview.completedSets == 0) {
    return Future.value(RemoveExerciseChoice.deleteRecorded);
  }
  return showDialog<RemoveExerciseChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('移除「${preview.exerciseName}」？'),
      content: Text(
        '已记 ${preview.completedSets} 组。保留后，本次不再继续此动作，历史和总结仍保留这些组。删掉后无法撤销。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, RemoveExerciseChoice.cancel),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, RemoveExerciseChoice.keepRecorded),
          child: const Text('保留已记组'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, RemoveExerciseChoice.deleteRecorded),
          child: Text('删掉这 ${preview.completedSets} 组'),
        ),
      ],
    ),
  );
}
