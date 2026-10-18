import 'package:flutter/material.dart';

import '../../domain/training_plans.dart';

const freeTrainingChoice = '__free_training__';

Future<String?> showPlanPicker(
  BuildContext context,
  List<TrainingPlanDetail> plans, {
  String? selectedId,
}) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    builder: (_, scroll) => ListView(
      controller: scroll,
      children: [
        const ListTile(
          title: Text('切换计划'),
          subtitle: Text('每套计划独立轮换；也可以选择自由训练。'),
        ),
        for (final plan in plans)
          ListTile(
            title: Text(plan.name),
            subtitle: Text(
              '${plan.days.where((d) => d.kind == TrainingDayKind.training).length} 个训练日 · ${plan.days.where((d) => d.kind == TrainingDayKind.rest).length} 个休息日',
            ),
            trailing: selectedId == plan.id ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, plan.id),
          ),
        ListTile(
          title: const Text('自由训练'),
          subtitle: const Text('不推进任何计划的轮换'),
          onTap: () => Navigator.pop(context, freeTrainingChoice),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  ),
);

Future<String?> showTrainingDayPicker(
  BuildContext context,
  TrainingPlanDetail plan, {
  String? selectedId,
}) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    builder: (_, scroll) => ListView(
      controller: scroll,
      children: [
        ListTile(title: const Text('选择训练日'), subtitle: Text(plan.name)),
        for (final day in plan.days.where(
          (d) => d.kind == TrainingDayKind.training,
        ))
          ListTile(
            title: Text(day.name),
            subtitle: Text('${day.exerciseIds.length} 个动作'),
            trailing: selectedId == day.id ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, day.id),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  ),
);
