import 'package:flutter/material.dart';

import '../../domain/format.dart';
import '../../state/active_session_controller.dart';
import '../../state/exercise_preferences_controller.dart';
import 'edit_set_sheet.dart';

Future<void> showCompletedSetsSheet(
  BuildContext context,
  ActiveSessionController controller,
  ExercisePreferencesController? preferences,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    builder: (context, scroll) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SafeArea(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Text('本场已记', style: Theme.of(context).textTheme.titleLarge),
            for (final item in controller.exercises)
              if (item.sets.any((s) => s.isCompleted)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(item.exerciseName),
                ),
                for (final (index, set)
                    in item.sets.where((s) => s.isCompleted).indexed)
                  ListTile(
                    title: Text(
                      '第 ${index + 1} 组 · ${formatWeightKg(set.weight)} kg × ${set.reps}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: controller.writing
                        ? null
                        : () async {
                            try {
                              final edit = await controller.previewCompletedSet(
                                set.id,
                              );
                              if (edit == null || !context.mounted) return;
                              await showEditSetSheet(
                                context,
                                controller,
                                edit,
                                item.exerciseName,
                                index + 1,
                                preferences
                                        ?.preferenceFor(
                                          item.sessionExercise.exerciseId,
                                        )
                                        .weightStepKg ??
                                    2.5,
                              );
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text('$e')));
                              }
                            }
                          },
                  ),
              ],
          ],
        ),
      ),
    ),
  ),
);
