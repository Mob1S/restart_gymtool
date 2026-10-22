import 'dart:async';

import '../../data/db/sql_executor.dart';
import '../../data/files/beverage_http.dart';
import '../../data/repositories/beverage_repo.dart';
import '../../data/repositories/motion_project_repo.dart';
import '../../data/repositories/public_beverage_search.dart';
import '../../data/repositories/video_review_repo.dart';
import '../../domain/beverage.dart';
import '../../domain/local_date.dart';
import '../api/plugin_runtime.dart';

/// Host-owned compatibility services. No executor crosses the capability boundary.
class LegacyFeatureServices {
  final SqlExecutor exec;
  const LegacyFeatureServices(this.exec);
  Future<JsonMap> request(
    String method,
    JsonMap args, {
    void Function()? ensureActive,
    String networkSessionPrefix = 'standalone',
  }) async {
    ensureActive?.call();
    final beverages = BeverageRepo(exec, ensureActive: ensureActive);
    final projects = MotionProjectRepo(exec, ensureActive: ensureActive);
    final session = args['sessionId'] ?? 'default';
    if (session is! String || session.isEmpty || session.length > 128) {
      throw const PluginException(PluginErrorCode.invalidData, '搜索会话无效');
    }
    final sessionId = '$networkSessionPrefix:$session';
    final search = PublicBeverageSearch(
      get: (uri) => beverageHttpGet(uri, sessionId: sessionId),
    );
    switch (method) {
      case 'calories.library':
        return {
          'items': (await beverages.library(
            includeArchived: args['includeArchived'] == true,
          )).map((b) => b.toJson()).toList(),
        };
      case 'calories.records':
        return {
          'items': (await beverages.records(
            from: LocalDate.tryParse(args['from'] as String?),
            through: LocalDate.tryParse(args['through'] as String?),
          )).map((r) => r.toJson()).toList(),
        };
      case 'calories.saveBeverage':
        await beverages.saveBeverage(
          Beverage.fromJson(Map<String, dynamic>.from(args['beverage'] as Map)),
        );
        return {};
      case 'calories.saveRecord':
        await beverages.saveRecord(
          DrinkRecord.fromJson(
            Map<String, dynamic>.from(args['record'] as Map),
          ),
          newBeverage: args['newBeverage'] == null
              ? null
              : Beverage.fromJson(
                  Map<String, dynamic>.from(args['newBeverage'] as Map),
                ),
        );
        return {};
      case 'calories.deleteRecord':
        await beverages.deleteRecord(args['id'] as String);
        return {};
      case 'network.foodSearch':
        return {
          'items': (await search.search(args['query'] as String))
              .map((b) => b.toJson())
              .toList(),
        };
      case 'network.foodDetails':
        return {
          'beverage': (await search.details(
            Beverage.fromJson(
              Map<String, dynamic>.from(args['beverage'] as Map),
            ),
          )).toJson(),
        };
      case 'network.foodCancel':
        await cancelBeverageHttpSession(sessionId);
        return {};
      case 'training.set.read':
        return {
          'item': await VideoReviewRepo(exec).group(args['setId'] as String),
        };
      case 'motion.projects.list':
        return {'items': await projects.list()};
      case 'motion.projects.load':
        return {'item': await projects.load(args['id'] as String)};
      case 'motion.projects.forSet':
        return {'item': await projects.forSet(args['setId'] as String)};
      case 'motion.projects.completedSets':
        return {'items': await projects.completedSets()};
      case 'motion.projects.save':
        await projects.save(
          id: args['id'] as String,
          setId: args['setId'] as String?,
          mode: args['mode'] as String,
          folder: args['folder'] as String,
          payload: Map<String, dynamic>.from(args['payload'] as Map),
        );
        return {};
      case 'motion.projects.delete':
        await projects.delete(args['id'] as String);
        return {};
      case 'motion.projects.resultFiles':
        return {'files': await projects.resultFiles()};
      default:
        throw StateError('不支持的能力请求');
    }
  }
}

/// Explicit host used by standalone page fixtures, where no runtime is installed.
class StandaloneFeatureHost implements PluginHost {
  final LegacyFeatureServices services;
  const StandaloneFeatureHost(this.services);
  @override
  Set<String> get grantedCapabilities => const {
    'calories.library',
    'calories.records',
    'motion.projects',
    'training.set.read',
    'network.foodSearch',
  };
  @override
  Future<JsonMap> request(String method, JsonMap arguments) =>
      services.request(method, arguments);
  @override
  Stream<JsonMap> subscribe(String topic) => const Stream.empty();
}
