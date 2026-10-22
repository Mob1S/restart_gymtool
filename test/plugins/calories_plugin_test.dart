import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/beverage_repo.dart';
import 'package:gym_tracker/plugins/api/feature_clients.dart';
import 'package:gym_tracker/plugins/api/plugin_runtime.dart';
import 'package:gym_tracker/plugins/bundled/calories_plugin.dart';
import 'package:gym_tracker/plugins/host/legacy_feature_services.dart';
import 'package:gym_tracker/plugins/host/plugin_host.dart';
import 'package:gym_tracker/plugins/runtime/feature_activity.dart';
import 'package:gym_tracker/plugins/runtime/plugin_catalog.dart';
import 'package:gym_tracker/plugins/runtime/plugin_manager.dart';
import 'package:gym_tracker/domain/beverage.dart';
import 'package:gym_tracker/domain/local_date.dart';

import '../data/backup_repo_test.dart' show FailingExecutor;
import '../domain/beverage_test.dart' show beverage, drink;

void main() {
  late FfiExecutor db;
  late FeaturePluginRuntime runtime;
  late PluginManager manager;
  late Map<String, bool> preferences;
  late int starts;
  late int stops;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    preferences = {};
    starts = 0;
    stops = 0;
    runtime = FeaturePluginRuntime(
      FeatureActivityRegistry(),
      onStart: () async {
        starts++;
      },
      onStop: () async {
        stops++;
      },
    );
    final services = LegacyFeatureServices(db);
    const methods = {
      'calories.library': 'calories.library',
      'calories.records': 'calories.records',
      'calories.saveBeverage': 'calories.library',
      'calories.saveRecord': 'calories.records',
      'calories.deleteRecord': 'calories.records',
      'network.foodSearch': 'network.foodSearch',
    };
    manager = PluginManager(
      catalog: StaticPluginCatalog([
        PluginDefinition(
          manifest: caloriesManifest,
          createRuntime: () => runtime,
        ),
      ]),
      platform: 'web',
      loadPreferences: () async => Map.of(preferences),
      savePreference: (id, value) async {
        preferences[id] = value;
      },
      hostFactory: (manifest, scope) => BoundPluginHost(
        scope: scope,
        grantedCapabilities: manifest.requiredCapabilities,
        methods: {
          for (final entry in methods.entries)
            entry.key: HostMethod(
              capability: entry.value,
              handle: (args) => services.request(
                entry.key,
                args,
                ensureActive: scope.ensureActive,
              ),
            ),
        },
      ),
    );
    await manager.initialize();
  });
  tearDown(() async {
    await manager.shutdown();
    manager.dispose();
    await db.close();
  });

  test('默认停用不启动资源，拒绝网络仍可录入并在停用重开保留精确快照', () async {
    expect(starts, 0);
    expect(manager.isEnabled('gym.calories'), isFalse);
    await manager.setEnabled('gym.calories', true);
    final oldClient = CaloriesClient(runtime.host);
    final b = beverage(
      energy: '418.4',
      energyUnit: EnergyUnit.kj,
      basis: EnergyBasis.perServing,
      volume: '500',
    );
    final record = drink(b: b, amount: '250');
    await oldClient.saveRecord(record, newBeverage: b.copyWith(favorite: true));
    expect((await oldClient.records()).single.calories!.exact, '50/1');
    await oldClient.saveBeverage(b.copyWith(archived: true));
    expect(await oldClient.library(), isEmpty);
    expect(
      (await oldClient.library(includeArchived: true)).single.archived,
      isTrue,
    );
    expect((await oldClient.records()).single.toJson(), record.toJson());
    await expectLater(
      oldClient.search('drink'),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.permissionDenied,
        ),
      ),
    );
    await manager.setEnabled('gym.calories', false);
    expect(stops, 1);
    expect((await BeverageRepo(db).records()).single.toJson(), record.toJson());
    await expectLater(
      oldClient.library(),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.pluginDisabled,
        ),
      ),
    );
    await manager.setEnabled('gym.calories', true);
    expect(
      (await CaloriesClient(runtime.host).records()).single.toJson(),
      record.toJson(),
    );
    expect(starts, 2);
  });

  test('公共客户端保留日期边界和未保存表单阻止停用', () async {
    await manager.setEnabled('gym.calories', true);
    final client = CaloriesClient(runtime.host);
    await client.saveRecord(drink(day: 19), newBeverage: beverage());
    expect(
      await client.records(
        from: LocalDate(2026, 10, 20),
        through: LocalDate(2026, 10, 20),
      ),
      isEmpty,
    );
    final unregister = runtime.activities.register(
      () => StopDecision.unsavedChanges,
      () async {},
    );
    await expectLater(
      manager.setEnabled('gym.calories', false),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.unsavedChanges,
        ),
      ),
    );
    expect(manager.isEnabled('gym.calories'), isTrue);
    expect((await client.records()).single.date.key, '2026-10-19');
    unregister();
    unregister();
    await manager.setEnabled('gym.calories', false);
  });

  test('宿主写入失败整批回滚个人库和饮用记录', () async {
    final faulty = LegacyFeatureServices(
      FailingExecutor(db, 'INSERT INTO drink_record', StateError('injected')),
    );
    final client = CaloriesClient(StandaloneFeatureHost(faulty));
    await expectLater(
      client.saveRecord(drink(), newBeverage: beverage()),
      throwsStateError,
    );
    expect(await BeverageRepo(db).library(), isEmpty);
    expect(await BeverageRepo(db).records(), isEmpty);
  });
}
