import '../../domain/beverage.dart';
import '../../domain/local_date.dart';
import 'plugin_runtime.dart';

abstract interface class MotionProjectStore {
  Future<List<Map<String, dynamic>>> list();
  Future<Map<String, dynamic>?> load(String id);
  Future<Map<String, dynamic>?> forSet(String setId);
  Future<List<Map<String, Object?>>> completedSets();
  Future<void> save({
    required String id,
    String? setId,
    required String mode,
    required String folder,
    required Map<String, dynamic> payload,
  });
  Future<void> delete(String id);
  Future<Map<String, String>> resultFiles();
}

/// Typed views of serializable host capabilities; never exposes a database.
class CaloriesClient {
  final PluginHost host;
  static int _nextSearch = 0;
  final String _searchSession;
  CaloriesClient(this.host) : _searchSession = 'search-${++_nextSearch}';
  Future<List<Beverage>> library({bool includeArchived = false}) async {
    final data = await host.request('calories.library', {
      'includeArchived': includeArchived,
    });
    return [
      for (final item in data['items'] as List)
        Beverage.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<List<DrinkRecord>> records({
    LocalDate? from,
    LocalDate? through,
  }) async {
    final data = await host.request('calories.records', {
      'from': from?.key,
      'through': through?.key,
    });
    return [
      for (final item in data['items'] as List)
        DrinkRecord.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<void> saveBeverage(Beverage beverage) async {
    await host.request('calories.saveBeverage', {
      'beverage': beverage.toJson(),
    });
  }

  Future<void> saveRecord(DrinkRecord record, {Beverage? newBeverage}) async {
    await host.request('calories.saveRecord', {
      'record': record.toJson(),
      'newBeverage': newBeverage?.toJson(),
    });
  }

  Future<void> deleteRecord(String id) async {
    await host.request('calories.deleteRecord', {'id': id});
  }

  Future<List<Beverage>> search(String query) async {
    final result = await host.request('network.foodSearch', {
      'query': query,
      'sessionId': _searchSession,
    });
    return [
      for (final item in result['items'] as List)
        Beverage.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<Beverage> details(Beverage beverage) async {
    final result = await host.request('network.foodDetails', {
      'beverage': beverage.toJson(),
      'sessionId': _searchSession,
    });
    return Beverage.fromJson(
      Map<String, dynamic>.from(result['beverage'] as Map),
    );
  }

  Future<void> cancelSearch() async {
    if (!host.grantedCapabilities.contains('network.foodSearch')) return;
    try {
      await host.request('network.foodCancel', {'sessionId': _searchSession});
    } on PluginException catch (error) {
      if (error.code != PluginErrorCode.pluginDisabled &&
          error.code != PluginErrorCode.cancelled) {
        rethrow;
      }
    }
  }
}

class MotionProjectsClient implements MotionProjectStore {
  final PluginHost host;
  const MotionProjectsClient(this.host);
  Future<JsonMap> _call(String method, [JsonMap args = const {}]) =>
      host.request('motion.projects.$method', args);
  @override
  Future<List<Map<String, dynamic>>> list() async => [
    for (final item in (await _call('list'))['items'] as List)
      Map<String, dynamic>.from(item as Map),
  ];
  @override
  Future<Map<String, dynamic>?> load(String id) async =>
      _item(await _call('load', {'id': id}));
  @override
  Future<Map<String, dynamic>?> forSet(String setId) async =>
      _item(await _call('forSet', {'setId': setId}));
  Map<String, dynamic>? _item(JsonMap data) => data['item'] == null
      ? null
      : Map<String, dynamic>.from(data['item'] as Map);
  @override
  Future<List<Map<String, Object?>>> completedSets() async => [
    for (final item in (await _call('completedSets'))['items'] as List)
      Map<String, Object?>.from(item as Map),
  ];
  @override
  Future<void> save({
    required String id,
    String? setId,
    required String mode,
    required String folder,
    required Map<String, dynamic> payload,
  }) async {
    await _call('save', {
      'id': id,
      'setId': setId,
      'mode': mode,
      'folder': folder,
      'payload': payload,
    });
  }

  @override
  Future<void> delete(String id) async {
    await _call('delete', {'id': id});
  }

  @override
  Future<Map<String, String>> resultFiles() async =>
      Map<String, String>.from((await _call('resultFiles'))['files'] as Map);
  Future<Map<String, Object?>?> trainingSet(String id) async {
    final data = await host.request('training.set.read', {'setId': id});
    return data['item'] == null
        ? null
        : Map<String, Object?>.from(data['item'] as Map);
  }
}
