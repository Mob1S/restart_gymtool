import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/db/database.dart';
import '../data/db/sql_executor.dart';
import '../data/repositories/exercise_repo.dart';
import '../data/repositories/settings_repo.dart';
import '../state/active_session_controller.dart';
import '../state/theme_controller.dart';
import '../ui/theme.dart';
import '../ui/tokens.dart';
import 'router.dart';

/// App 的依赖装配与启动流程。
///
/// **顺序不可反**：打开库 → 跑迁移 → 播种 → 读主题偏好 → 才放行子树。
/// 最后一条见规格 §6.5：偏好读出来之前不放行子树，否则每次启动都会闪一帧。
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  SqlExecutor? _exec;
  ActiveSessionController? _session;
  ThemeController? _theme;
  Object? _error;

  /// **router 只建一次。** 写在 `build()` 里的话每次重建都会新建一个
  /// `GoRouter`，导航栈会被整个丢掉。
  late final _router = buildRouter();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final exec = await openAppDatabase();
      await seedExercisesIfEmpty(exec);

      final theme = ThemeController(exec);
      await theme.load(); // 不放行子树直到它完成 —— 否则每次启动闪一帧

      if (!mounted) return;
      setState(() {
        _exec = exec;
        _session = ActiveSessionController(exec);
        _theme = theme;
      });
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
      return MaterialApp(
        home: Scaffold(
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
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MultiProvider(
      providers: [
        Provider<SqlExecutor>.value(value: exec),
        ChangeNotifierProvider<ActiveSessionController>.value(value: session),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
      ],
      // 在 Provider 之下读主题，所以这一层必须是独立 widget
      child: _ThemedApp(router: _router),
    );
  }
}

/// 把 [ThemeController] 的三态偏好接到 `MaterialApp.themeMode` 上。
class _ThemedApp extends StatelessWidget {
  final GoRouter router;

  const _ThemedApp({required this.router});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    return MaterialApp.router(
      title: '健身记录',
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
