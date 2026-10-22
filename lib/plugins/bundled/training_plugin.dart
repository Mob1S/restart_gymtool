import 'package:flutter/material.dart';

import '../api/plugin_manifest.dart';
import '../flutter/plugin_ui_adapter.dart';

final trainingManifest = PluginManifest(
  id: 'gym.training',
  name: '基础训练',
  description: '训练记录、计划、历史、进步统计、导入与备份。',
  version: '1.0.0',
  platforms: {'android', 'web', 'windows', 'linux', 'macos', 'ios'},
  requiredByHost: true,
);
const trainingUi = PluginUiAdapter(
  pluginId: 'gym.training',
  destinations: [
    PluginDestination(
      id: 'training',
      pluginId: 'gym.training',
      route: '/',
      label: '训练',
      icon: Icons.fitness_center,
      order: 100,
    ),
    PluginDestination(
      id: 'history',
      pluginId: 'gym.training',
      route: '/history',
      label: '历史',
      icon: Icons.history,
      order: 400,
    ),
    PluginDestination(
      id: 'progress',
      pluginId: 'gym.training',
      route: '/progress',
      label: '进步',
      icon: Icons.show_chart,
      order: 500,
    ),
  ],
);
