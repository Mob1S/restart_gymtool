import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/db/database.dart';
import '../data/db/sql_executor.dart';
import '../data/files/backup_file_store.dart';
import '../data/repositories/exercise_repo.dart';
import '../data/repositories/exercise_catalog_repo.dart';
import '../data/repositories/settings_repo.dart';
import '../domain/backup.dart';
import '../state/active_session_controller.dart';
import '../state/theme_controller.dart';
import '../state/exercise_preferences_controller.dart';
import '../state/backup_controller.dart';
import '../state/data_revision.dart';
import '../state/video_review_cleanup.dart';
import '../data/files/beverage_ocr.dart';
import '../data/files/motion_bridge.dart';
import '../data/repositories/plugin_state_repo.dart';
import '../data/repositories/plugin_document_repo.dart';
import '../plugins/api/plugin_runtime.dart';
import '../plugins/bundled/bundled_catalog.dart';
import '../plugins/flutter/plugin_ui_adapter.dart';
import '../plugins/host/legacy_feature_services.dart';
import '../plugins/host/plugin_host.dart';
import '../plugins/host/scoped_plugin_store.dart';
import '../plugins/runtime/feature_activity.dart';
import '../plugins/runtime/plugin_manager.dart';
import '../data/repositories/video_review_repo.dart';
import '../state/import_controller.dart';
import '../state/plan_controller.dart';
import '../state/record_management_controller.dart';
import '../ui/theme.dart';
import '../ui/tokens.dart';
import 'router.dart';

/// App 的依赖装配与启动流程。
///
/// **顺序不可反**：打开库 → 跑迁移 → 播种 → 读主题偏好 → 才放行子树。
/// 最后一条见规格 §6.5：偏好读出来之前不放行子树，否则每次启动都会闪一帧。
class AppBootstrap extends StatefulWidget {
  final Future<SqlExecutor> Function()? openDatabase;
  final BackupFileStore? backupFiles;
  final String? pluginPlatform;
  const AppBootstrap({
    super.key,
    this.openDatabase,
    this.backupFiles,
    this.pluginPlatform,
  });

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  SqlExecutor? _exec;
  ActiveSessionController? _session;
  ThemeController? _theme;
  ExercisePreferencesController? _preferences;
  BackupController? _backup;
  ImportController? _import;
  PlanController? _plans;
  RecordManagementController? _records;
  final _revision = DataRevision();
  Object? _error;
  VideoReviewCleanup? _reviewCleanup;
  PluginManager? _plugins;
  PluginUiRegistry? _pluginUi;
  PluginFeatureAccess? _featureAccess;
  final _exits = PluginExitRegistry();
  final _pluginEvents = StreamController<JsonMap>.broadcast();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<String?> _syncCatalog(SqlExecutor exec) async {
    try {
      await syncExerciseCatalog(exec);
      return null;
    } on BackupValidationException {
      return '动作库扩充达到容量上限，已有记录仍可使用；释放空间后重启重试。';
    } catch (_) {
      return '动作库扩充暂未完成，已有记录仍可使用；重启后重试。';
    }
  }

  void _showCatalogNotice(String? message) {
    if (message == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    });
  }

  /// **router 只建一次。** 写在 `build()` 里的话每次重建都会新建一个
  /// `GoRouter`，导航栈会被整个丢掉。
  GoRouter? _appRouter;
  String? _initialLocation;
  GoRouter get _router => _appRouter ??= buildRouter(
    plugins: _plugins,
    registry: _pluginUi,
    exits: _exits,
    initialLocation: _initialLocation,
  );

  void _pluginsChanged() {
    final router = _appRouter;
    if (router == null) return;
    final id = _pluginUi?.ownerOf(
      router.routeInformationProvider.value.uri.path,
    );
    if (id != null && _plugins!.stateOf(id) == PluginState.disabled) {
      router.go('/');
    }
  }

  @override
  void initState() {
    super.initState();
    // The temporary loading MaterialApp may normalize the browser URL. Keep
    // the launch target until the migrated database and route guards are ready.
    final launch = kIsWeb
        ? Uri.base.fragment
        : WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (launch.startsWith('/') && !launch.startsWith('//')) {
      _initialLocation = launch;
    }
    _boot();
  }

  Future<void> _boot() async {
    try {
      final exec = await (widget.openDatabase ?? openAppDatabase)();
      await seedExercisesIfEmpty(exec);
      final catalogNotice = await _syncCatalog(exec);

      final theme = ThemeController(exec);
      await theme.load(); // 不放行子树直到它完成 —— 否则每次启动闪一帧

      final session = ActiveSessionController(
        exec,
        onDataChanged: _revision.changed,
      );
      final training = FeaturePluginRuntime(FeatureActivityRegistry());
      final calories = FeaturePluginRuntime(
        FeatureActivityRegistry(),
        onStart: () => BeverageOcr().activate(),
        onStop: () => BeverageOcr().deactivate(),
      );
      final motion = FeaturePluginRuntime(
        FeatureActivityRegistry(),
        onStart: () async {
          await MotionBridge().activate();
          _reviewCleanup = VideoReviewCleanup(VideoReviewRepo(exec), _revision);
        },
        onStop: () async {
          await _reviewCleanup?.close();
          _reviewCleanup = null;
          if (MotionBridge.supported) await MotionBridge().deactivate();
        },
      );
      final services = LegacyFeatureServices(exec);
      final pluginPlatform =
          widget.pluginPlatform ??
          (kIsWeb ? 'web' : defaultTargetPlatform.name);
      final plugins = PluginManager(
        catalog: bundledCatalog(
          training: training,
          calories: calories,
          motion: motion,
        ),
        platform: pluginPlatform,
        loadPreferences: () => loadPluginPreferences(exec),
        savePreference: (id, enabled) =>
            savePluginPreference(exec, id, enabled),
        validateData: (definition) async {
          final version = await PluginDocumentRepo(exec)
              .dataVersion(definition.manifest.id);
          if (version != null &&
              !definition.supportedDataVersions.contains(version)) {
            throw const PluginException(
              PluginErrorCode.invalidData,
              '插件数据版本不兼容，原始数据已保留',
            );
          }
        },
        hostFactory: (manifest, scope) {
          final store = ScopedPluginStore(
            repository: PluginDocumentRepo(exec),
            scope: scope,
          );
          const methods = {
            'calories.library': 'calories.library',
            'calories.records': 'calories.records',
            'calories.saveBeverage': 'calories.library',
            'calories.saveRecord': 'calories.records',
            'calories.deleteRecord': 'calories.records',
            'network.foodSearch': 'network.foodSearch',
            'network.foodDetails': 'network.foodSearch',
            'network.foodCancel': 'network.foodSearch',
            'training.set.read': 'training.set.read',
            'motion.projects.list': 'motion.projects',
            'motion.projects.load': 'motion.projects',
            'motion.projects.forSet': 'motion.projects',
            'motion.projects.completedSets': 'motion.projects',
            'motion.projects.save': 'motion.projects',
            'motion.projects.delete': 'motion.projects',
            'motion.projects.resultFiles': 'motion.projects',
          };
          final supportedCapabilities = {
            ...methods.values,
            ...store.methods.values.map((method) => method.capability),
            if ({'android', 'web'}.contains(pluginPlatform)) ...{
              'media.pick',
              'camera.capture',
            },
          };
          return BoundPluginHost(
            scope: scope,
            grantedCapabilities: {
              ...manifest.requiredCapabilities,
              ...manifest.optionalCapabilities,
            }.intersection(supportedCapabilities),
            methods: {
              ...store.methods,
              'storage.private.write': HostMethod(
                capability: 'storage.private.write',
                handle: (args) async {
                  final result = await store.write(args);
                  scope.ensureActive();
                  _pluginEvents.add({
                    'type': 'storage.private.changed',
                    'pluginId': scope.pluginId,
                    'payload': const <String, Object?>{},
                  });
                  _revision.changed();
                  return result;
                },
              ),
              for (final entry in methods.entries)
                entry.key: HostMethod(
                  capability: entry.value,
                  handle: (args) => services.request(
                    entry.key,
                    args,
                    ensureActive: scope.ensureActive,
                    networkSessionPrefix:
                        '${scope.pluginId}:${scope.generation}',
                  ),
                ),
            },
            topics: {
              'data.changed': HostTopic(
                capability: 'storage.private.read',
                events: _pluginEvents.stream,
              ),
              'storage.private.changed': HostTopic(
                capability: 'storage.private.read',
                events: _pluginEvents.stream.where(
                  (event) => event['pluginId'] == scope.pluginId,
                ),
              ),
            },
          );
        },
      );
      await plugins.initialize();
      if (!mounted) {
        await plugins.shutdown();
        plugins.dispose();
        return;
      }
      _plugins = plugins;
      plugins.addListener(_pluginsChanged);
      _pluginUi = bundledUi(_exits);
      _featureAccess = PluginFeatureAccess(calories: calories, motion: motion);
      _revision.addListener(_publishPluginRevision);
      final backup = BackupController(
        exec: exec,
        files: widget.backupFiles ?? PlatformBackupFileStore(),
        beforeRestore: session.prepareForRestore,
        coordinateRestore: (action) => plugins.runWithPluginsPaused(action),
        onRestored: () async {
          final catalogNotice = await _syncCatalog(exec);
          _revision.changed();
          session.reset();
          await session.resume();
          await theme.load();
          _router.go('/');
          _showCatalogNotice(catalogNotice);
        },
      );

      final importer = ImportController(
        exec: exec,
        files: widget.backupFiles ?? PlatformBackupFileStore(),
        onCommitted: (_) async {
          _revision.changed();
        },
      );

      if (!mounted) return;
      setState(() {
        _exec = exec;
        _session = session;
        _theme = theme;
        _preferences = ExercisePreferencesController(exec, revision: _revision);
        _backup = backup;
        _import = importer;
        _plans = PlanController(
          exec,
          onChanged: _revision.changed,
          onDayDeleted: session.detachTemplate,
          onPlanDeleted: session.detachPlan,
        );
        _records = RecordManagementController(
          exec,
          active: session,
          onChanged: _revision.changed,
        );
      });
      _showCatalogNotice(catalogNotice);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exec = _exec;
    final session = _session;
    final theme = _theme;

    if (_error != null) {
      // 数据库打不开时也要给一个能读懂的界面，而不是白屏
      return _bootstrapScreen(
        Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text('数据库打开失败：$_error', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }

    if (exec == null || session == null || theme == null) {
      return _bootstrapScreen(
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MultiProvider(
      providers: [
        Provider<SqlExecutor>.value(value: exec),
        ChangeNotifierProvider<PluginManager>.value(value: _plugins!),
        Provider<PluginUiRegistry>.value(value: _pluginUi!),
        Provider<PluginFeatureAccess>.value(value: _featureAccess!),
        Provider<PluginExitRegistry>.value(value: _exits),
        ChangeNotifierProvider<ActiveSessionController>.value(value: session),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<ExercisePreferencesController>.value(
          value: _preferences!,
        ),
        ChangeNotifierProvider<BackupController>.value(value: _backup!),
        ChangeNotifierProvider<DataRevision>.value(value: _revision),
        ChangeNotifierProvider<ImportController>.value(value: _import!),
        ChangeNotifierProvider<PlanController>.value(value: _plans!),
        ChangeNotifierProvider<RecordManagementController>.value(
          value: _records!,
        ),
      ],
      // 在 Provider 之下读主题，所以这一层必须是独立 widget
      child: _ThemedApp(router: _router, messengerKey: _messengerKey),
    );
  }

  Widget _bootstrapScreen(Widget screen) => MaterialApp(
    onGenerateRoute: (settings) =>
        MaterialPageRoute<void>(settings: settings, builder: (_) => screen),
    onGenerateInitialRoutes: (name) => [
      MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => screen,
      ),
    ],
  );

  @override
  void dispose() {
    final plugins = _plugins;
    if (plugins != null) {
      plugins.removeListener(_pluginsChanged);
      unawaited(
        plugins
            .shutdown()
            .catchError((Object _) {})
            .whenComplete(plugins.dispose),
      );
    }
    _revision.removeListener(_publishPluginRevision);
    unawaited(_pluginEvents.close());
    _reviewCleanup?.dispose();
    _plans?.dispose();
    _records?.dispose();
    _import?.dispose();
    _preferences?.dispose();
    _revision.dispose();
    _backup?.dispose();
    _session?.dispose();
    _theme?.dispose();
    _appRouter?.dispose();
    super.dispose();
  }

  void _publishPluginRevision() {
    if (!_pluginEvents.isClosed) {
      _pluginEvents.add({
        'type': 'data.changed',
        'generation': _revision.value,
        'payload': const <String, Object?>{},
      });
    }
  }
}

/// 把 [ThemeController] 的三态偏好接到 `MaterialApp.themeMode` 上。
class _ThemedApp extends StatelessWidget {
  final GoRouter router;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  const _ThemedApp({required this.router, required this.messengerKey});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    return MaterialApp.router(
      title: '健身记录',
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(AppColors.light),
      darkTheme: buildTheme(AppColors.dark),
      themeMode: switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      routerConfig: router,
    );
  }
}
