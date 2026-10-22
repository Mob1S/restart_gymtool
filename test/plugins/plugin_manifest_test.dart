import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/plugins/api/plugin_manifest.dart';
import 'package:gym_tracker/plugins/api/plugin_protocol.dart';
import 'package:gym_tracker/plugins/runtime/plugin_catalog.dart';

import '../support/plugin_fakes.dart';

void main() {
  test('完整清单可编码往返且集合只读', () {
    final platforms = {'web'};
    final manifest = fakePluginManifest(
      'community.example',
      platforms: platforms,
      requiredCapabilities: {'storage.private.write'},
      optionalCapabilities: {'network.foodSearch'},
      dependencies: [const PluginDependency(id: 'gym.training')],
    );
    platforms.clear();
    expect(manifest.platforms, {'web'});
    expect(() => manifest.platforms.add('android'), throwsUnsupportedError);
    final decoded = PluginManifest.fromJson(
      copyPluginJsonMap(jsonDecode(jsonEncode(manifest.toJson()))),
    );
    expect(decoded.toJson(), manifest.toJson());
    expect(decoded.supportsApi(1), isTrue);
    expect(decoded.supportsApi(2), isFalse);
  });

  test('清单拒绝非法标识和 API 范围', () {
    for (final id in ['training', 'Gym.Training', '', '../another']) {
      expect(() => fakePluginManifest(id), throwsA(isA<PluginException>()));
    }
    expect(
      () => fakePluginManifest('community.test', apiMin: 2, apiMax: 1),
      throwsA(isA<PluginException>()),
    );
  });

  test('目录发现不构造运行时且重复ID不可解析', () async {
    var constructions = 0;
    final definition = PluginDefinition(
      manifest: fakePluginManifest('community.test'),
      createRuntime: () {
        constructions++;
        return FakePluginRuntime();
      },
    );
    final catalog = StaticPluginCatalog([definition]);
    expect((await catalog.discover()).single.id, 'community.test');
    expect(constructions, 0);
    expect(
      () =>
          StaticPluginCatalog([definition, definition])
              .definitionFor('community.test'),
      throwsA(isA<PluginException>()),
    );
  });
}
