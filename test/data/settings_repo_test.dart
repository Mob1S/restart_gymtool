import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
  });

  tearDown(() async => exec.close());

  test('没设置过时返回 null（不是空串 —— 两者必须能区分）', () async {
    expect(await getSetting(exec, 'nope'), isNull);
  });

  test('写入后能读回', () async {
    await setSetting(exec, 'k', 'v');
    expect(await getSetting(exec, 'k'), 'v');
  });

  test('空串是一个合法的、被显式写入过的值', () async {
    await setSetting(exec, 'k', '');
    expect(await getSetting(exec, 'k'), '');
  });

  test('重复写同一个键是覆盖，不是插入第二行', () async {
    await setSetting(exec, 'k', 'a');
    await setSetting(exec, 'k', 'b');
    expect(await getSetting(exec, 'k'), 'b');
    final rows = await exec.all("SELECT * FROM app_setting WHERE key = 'k'");
    expect(rows, hasLength(1));
  });

  test('没设置过主题 → 默认跟随系统', () async {
    expect(await getThemeMode(exec), AppThemeMode.system);
  });

  test('主题存进去能读回来', () async {
    await setThemeMode(exec, AppThemeMode.dark);
    expect(await getThemeMode(exec), AppThemeMode.dark);
    await setThemeMode(exec, AppThemeMode.light);
    expect(await getThemeMode(exec), AppThemeMode.light);
  });

  test('库里存了非法值 → 退回 system，而不是抛错', () async {
    // 主题读不出来不该让整个 App 起不来
    await setSetting(exec, themeModeKey, 'neon-pink');
    expect(await getThemeMode(exec), AppThemeMode.system);
  });
}
