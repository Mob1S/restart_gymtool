import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../plugins/flutter/plugin_ui_adapter.dart';
import '../../ui/widgets/app_card.dart';
import '../../domain/motion_catalog.dart';

class AnalysisHomePage extends StatefulWidget {
  const AnalysisHomePage({super.key});
  @override
  State<AnalysisHomePage> createState() => _AnalysisHomePageState();
}

class _AnalysisHomePageState extends State<AnalysisHomePage> {
  late final projects = motionClient(context).list();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('看见每一次动作', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('深蹲、卧推、硬拉、引体向上 · 视频与识别数据均在设备本地处理。'),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => context.go('/analysis/catalog'),
          icon: const Icon(Icons.search),
          label: const Text('浏览和搜索动作库'),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => context.go('/analysis/import'),
          icon: const Icon(Icons.video_library_outlined),
          label: const Text('导入视频'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.go('/analysis/camera'),
          icon: const Icon(Icons.videocam_outlined),
          label: const Text('实时拍摄'),
        ),
        const SizedBox(height: 20),
        const AppCard(child: Text('固定手机并让动作全程入镜。先选择动作与机位，再查看当前可用的分析能力和限制。')),
        const SizedBox(height: 24),
        Text('本地分析项目', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder(
          future: projects,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('项目读取失败：${snapshot.error}');
            if (!snapshot.hasData) return const LinearProgressIndicator();
            if (snapshot.data!.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('还没有分析项目，无需创建训练即可开始。'),
              );
            }
            return Column(
              children: [
                for (final p in snapshot.data!)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      p['mode'] == 'camera'
                          ? Icons.videocam_outlined
                          : Icons.movie_outlined,
                    ),
                    title: Text(
                      '${MotionCatalog.byId(p['motionId'] as String?).name} · ${(p['reps'] as List? ?? []).length} 次视觉次数',
                    ),
                    subtitle: Text(
                      '${p['setId'] == null ? '独立项目' : '已关联训练组'} · ${p['status'] == 'incomplete' || p['status'] == 'interrupted' ? '不完整' : '已保存'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/analysis/project/${p['id']}'),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          '浏览器清理站点数据会删除本地分析。训练 JSON 备份不包含视频与视觉结果。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
