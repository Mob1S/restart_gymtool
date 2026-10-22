import '../runtime/feature_activity.dart';
import '../runtime/plugin_catalog.dart';
import '../flutter/plugin_ui_adapter.dart';
import 'training_plugin.dart';
import 'calories_plugin.dart';
import 'motion_plugin.dart';

/// The only production composition point for compiled plugins.
StaticPluginCatalog bundledCatalog({
  required FeaturePluginRuntime training,
  required FeaturePluginRuntime calories,
  required FeaturePluginRuntime motion,
}) => StaticPluginCatalog([
  PluginDefinition(manifest: trainingManifest, createRuntime: () => training),
  PluginDefinition(manifest: caloriesManifest, createRuntime: () => calories),
  PluginDefinition(manifest: motionManifest, createRuntime: () => motion),
]);

PluginUiRegistry bundledUi(PluginExitRegistry exits) =>
    PluginUiRegistry([trainingUi, caloriesUi(), motionUi(exits)]);
