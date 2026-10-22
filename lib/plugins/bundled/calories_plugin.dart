import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/calories/calories_page.dart';
import '../api/plugin_manifest.dart';
import '../flutter/plugin_ui_adapter.dart';

final caloriesManifest = PluginManifest(
  id: 'gym.calories',
  name: '饮料热量',
  description: '个人饮料库、标签识别、饮用记录与热量趋势。停用保留已有数据。',
  version: '1.0.0',
  platforms: {'android', 'web'},
  requiredCapabilities: {
    'calories.library',
    'calories.records',
    'media.pick',
    'camera.capture',
  },
  optionalCapabilities: {'network.foodSearch'},
);
PluginUiAdapter caloriesUi() => PluginUiAdapter(
  pluginId: 'gym.calories',
  destinations: const [
    PluginDestination(
      id: 'calories',
      pluginId: 'gym.calories',
      route: '/calories',
      label: '热量',
      icon: Icons.local_drink_outlined,
      order: 200,
    ),
  ],
  routes: [GoRoute(path: '/calories', builder: (_, _) => const CaloriesPage())],
);
