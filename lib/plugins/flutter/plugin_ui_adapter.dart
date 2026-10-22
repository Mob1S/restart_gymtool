import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/db/sql_executor.dart';
import '../api/feature_clients.dart';
import '../host/legacy_feature_services.dart';
import '../runtime/feature_activity.dart';
import '../runtime/plugin_manager.dart';

class PluginDestination {
  final String id, pluginId, route, label;
  final IconData icon;
  final int order;
  const PluginDestination({
    required this.id,
    required this.pluginId,
    required this.route,
    required this.label,
    required this.icon,
    required this.order,
  });
  bool matches(String path) =>
      route == '/' ? path == '/' : path == route || path.startsWith('$route/');
}

class TrainingSetAction {
  final String label;
  final IconData icon;
  final String Function(String setId) route;
  const TrainingSetAction({
    required this.label,
    required this.icon,
    required this.route,
  });
}

class PluginSettingsSection {
  final String label, route, description;
  const PluginSettingsSection({
    required this.label,
    required this.route,
    this.description = '',
  });
}

class PluginUiAdapter {
  final String pluginId;
  final List<PluginDestination> destinations;
  final List<RouteBase> routes;
  final List<TrainingSetAction> setActions;
  final List<PluginSettingsSection> settingsSections;
  final Set<String> allowedQueryParameters;
  const PluginUiAdapter({
    required this.pluginId,
    this.destinations = const [],
    this.routes = const [],
    this.setActions = const [],
    this.settingsSections = const [],
    this.allowedQueryParameters = const {},
  });
}

class PluginUiRegistry {
  final List<PluginUiAdapter> adapters;
  const PluginUiRegistry(this.adapters);
  String? ownerOf(String path) {
    for (final adapter in adapters) {
      if (_matchesRoutes(adapter.routes, path)) return adapter.pluginId;
    }
    return null;
  }

  bool _matchesRoutes(
    List<RouteBase> routes,
    String path, [
    String prefix = '',
  ]) {
    for (final route in routes) {
      if (route is GoRoute) {
        final pattern = route.path.startsWith('/')
            ? route.path
            : '$prefix/${route.path}';
        final regex = pattern
            .split('/')
            .map((part) => part.startsWith(':') ? '[^/]+' : RegExp.escape(part))
            .join('/');
        if (RegExp('^$regex\$').hasMatch(path) ||
            _matchesRoutes(route.routes, path, pattern)) {
          return true;
        }
      }
    }
    return false;
  }

  bool validTarget(String pluginId, String? raw) {
    final uri = raw == null ? null : Uri.tryParse(raw);
    final adapter = adapters
        .where((adapter) => adapter.pluginId == pluginId)
        .firstOrNull;
    return adapter != null &&
        uri != null &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        !uri.hasFragment &&
        ownerOf(uri.path) == pluginId &&
        uri.queryParameters.keys.every(adapter.allowedQueryParameters.contains);
  }

  List<PluginSettingsSection> settingsSections(PluginManager? manager) => [
    for (final adapter in adapters)
      if (manager == null || manager.isEnabled(adapter.pluginId))
        ...adapter.settingsSections,
  ];

  List<PluginDestination> destinations(PluginManager? manager) => [
    for (final adapter in adapters)
      if (manager == null || manager.isEnabled(adapter.pluginId))
        ...adapter.destinations,
  ]..sort((a, b) => a.order.compareTo(b.order));
  List<TrainingSetAction> setActions(PluginManager? manager) => [
    for (final adapter in adapters)
      if (manager == null || manager.isEnabled(adapter.pluginId))
        ...adapter.setActions,
  ];
}

class PluginFeatureAccess {
  final FeaturePluginRuntime calories, motion;
  const PluginFeatureAccess({required this.calories, required this.motion});
}

CaloriesClient caloriesClient(BuildContext context) {
  final access = context.read<PluginFeatureAccess?>();
  return CaloriesClient(
    access?.calories.host ??
        StandaloneFeatureHost(
          LegacyFeatureServices(context.read<SqlExecutor>()),
        ),
  );
}

MotionProjectsClient motionClient(BuildContext context) {
  final access = context.read<PluginFeatureAccess?>();
  return MotionProjectsClient(
    access?.motion.host ??
        StandaloneFeatureHost(
          LegacyFeatureServices(context.read<SqlExecutor>()),
        ),
  );
}

FeatureActivityRegistry? caloriesActivities(BuildContext context) =>
    context.read<PluginFeatureAccess?>()?.calories.activities;
FeatureActivityRegistry? motionActivities(BuildContext context) =>
    context.read<PluginFeatureAccess?>()?.motion.activities;

List<TrainingSetAction> trainingSetActions(BuildContext context) {
  final manager = context.watch<PluginManager?>();
  final registry = context.read<PluginUiRegistry?>();
  return registry?.setActions(manager) ?? const [];
}

/// Each route owns its exit guards; stale pages can only remove their own token.
class PluginExitRegistry {
  final _guards = <Object, (String, Future<bool> Function())>{};
  void Function() register(String route, Future<bool> Function() guard) {
    final token = Object();
    _guards[token] = (route, guard);
    return () => _guards.remove(token);
  }

  Future<bool> leave(String route) async {
    for (final guard in _guards.values.toList().reversed) {
      if (guard.$1 == route && !await guard.$2()) return false;
    }
    return true;
  }
}
