import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/analysis/analysis_home_page.dart';
import '../../features/analysis/analysis_session_page.dart';
import '../../features/analysis/motion_catalog_page.dart';
import '../api/plugin_manifest.dart';
import '../flutter/plugin_ui_adapter.dart';

final motionManifest = PluginManifest(
  id: 'gym.motion',
  name: '动作分析',
  description: '本地视频分析、拍摄和训练组复盘。视频保存在本机，不包含在 JSON 备份中。',
  version: '1.0.0',
  platforms: {'android', 'web'},
  requiredCapabilities: {
    'motion.projects',
    'training.set.read',
    'media.pick',
    'camera.capture',
  },
);
PluginUiAdapter motionUi(PluginExitRegistry exits) {
  GoRoute session(String path, Widget Function(GoRouterState) builder) =>
      GoRoute(
        path: path,
        builder: (_, state) => builder(state),
        onExit: (_, state) => exits.leave(state.uri.path),
      );
  return PluginUiAdapter(
    pluginId: 'gym.motion',
    allowedQueryParameters: const {'motion'},
    destinations: const [
      PluginDestination(
        id: 'motion',
        pluginId: 'gym.motion',
        route: '/analysis',
        label: '动作分析',
        icon: Icons.accessibility_new,
        order: 300,
      ),
    ],
    setActions: [
      TrainingSetAction(
        label: '动作分析',
        icon: Icons.video_library_outlined,
        route: (id) => '/review/${Uri.encodeComponent(id)}',
      ),
    ],
    routes: [
      GoRoute(
        path: '/review/:setId',
        redirect: (_, s) =>
            '/analysis/group/${Uri.encodeComponent(s.pathParameters['setId']!)}',
      ),
      GoRoute(path: '/analysis', builder: (_, _) => const AnalysisHomePage()),
      GoRoute(
        path: '/analysis/catalog',
        builder: (_, _) => const MotionCatalogPage(),
      ),
      GoRoute(
        path: '/analysis/catalog/:id',
        builder: (_, s) => MotionDetailPage(motionId: s.pathParameters['id']!),
      ),
      session(
        '/analysis/import',
        (s) => AnalysisSessionPage(motionId: s.uri.queryParameters['motion']),
      ),
      session(
        '/analysis/camera',
        (s) => AnalysisSessionPage(
          mode: 'camera',
          motionId: s.uri.queryParameters['motion'],
        ),
      ),
      session(
        '/analysis/project/:id',
        (s) => AnalysisSessionPage(projectId: s.pathParameters['id']),
      ),
      session(
        '/analysis/group/:id',
        (s) => AnalysisSessionPage(setId: s.pathParameters['id']),
      ),
    ],
  );
}
