import 'package:flutter/material.dart';

import '../../domain/plans.dart';

Future<String?> showPlanPicker(
  BuildContext context,
  List<TemplateSummary> plans,
) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    builder: (_, scroll) => ListView(
      controller: scroll,
      children: [
        const ListTile(title: Text('换本次计划'), subtitle: Text('选择后尚未开始，不会改变轮转。')),
        for (final p in plans)
          ListTile(
            title: Text(p.template.name),
            subtitle: Text('${p.exerciseCount} 个动作'),
            onTap: () => Navigator.pop(context, p.template.id),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  ),
);
