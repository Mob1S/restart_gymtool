import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 分层规则的**机械守卫**。
///
/// 规格 §2.2：旧项目把这三条叫「硬性规则」，但只靠约定守。而旧文档 §4.2 记着
/// 「判据两边同时写错的时候，只有端到端测试能发现」—— 约定守不住的东西，
/// 让测试守。
///
/// 这条测试**不看内容、只看 import 字符串**，所以它不会因为重构而误报。

/// 递归取出 `lib/` 下所有 `.dart` 文件，返回「相对路径 → 源码」。
Map<String, String> _allLibSources() {
  final result = <String, String>{};
  final dir = Directory('lib');
  if (!dir.existsSync()) return result;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Windows 上是反斜杠，统一成正斜杠再做前缀判断
    final rel = entity.path.replaceAll(r'\', '/');
    result[rel] = entity.readAsStringSync();
  }
  return result;
}

/// 取出一个源文件里所有 `import '...'` / `export '...'` 的目标字符串。
List<String> _importsOf(String source) {
  final re = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
  return re.allMatches(source).map((m) => m.group(1)!).toList();
}

/// 这个文件是否属于某个目录（用于前缀匹配）。
bool _under(String path, String prefix) => path.startsWith(prefix);

void main() {
  final sources = _allLibSources();

  test('lib/ 下有源文件（防止 glob 写错导致本测试空转）', () {
    expect(sources, isNotEmpty);
  });

  test('规则 1：features/ 与 ui/ 永不直接 import data/db/', () {
    final violations = <String>[];
    sources.forEach((path, source) {
      if (!_under(path, 'lib/features/') && !_under(path, 'lib/ui/')) return;
      for (final imp in _importsOf(source)) {
        if (imp.contains('data/db/') || imp.contains('data\\db\\')) {
          violations.add('$path → $imp');
        }
      }
    });
    expect(violations, isEmpty,
        reason: '界面层只能通过 repositories 访问数据，不能碰 db/：\n${violations.join('\n')}');
  });

  test('规则 2：SQL 字符串只允许出现在 data/repositories/', () {
    // 识别「看起来是 SQL」的字符串字面量。保守：只认最典型的开头，
    // 避免把界面上的一句文案误判成 SQL。
    // 注意：`'''` 这一支必须拆成相邻字符串字面量写，因为一个原生三引号
    // 字符串里没法再直接嵌三个单引号。相邻字面量在编译期拼接，与 `+` 等价 ——
    // 而 `+` 会触发 `prefer_adjacent_string_concatenation`，让 `flutter analyze` 变红。
    final sqlRe = RegExp(
      r'''(?:''' "'''" r'''|"|')\s*(?:SELECT|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|CREATE\s+TABLE|ALTER\s+TABLE|PRAGMA)\b''',
      caseSensitive: false,
    );

    final violations = <String>[];
    sources.forEach((path, source) {
      // db/ 放 schema 与迁移 SQL，repositories/ 放查询 SQL —— 这两处是允许的
      if (_under(path, 'lib/data/db/') || _under(path, 'lib/data/repositories/')) {
        return;
      }
      if (sqlRe.hasMatch(source)) violations.add(path);
    });
    expect(violations, isEmpty,
        reason: 'SQL 只允许出现在 data/db/ 与 data/repositories/：\n${violations.join('\n')}');
  });

  test('规则 3：lib/domain/ 不得 import Flutter（它必须能用纯 dart test 跑）', () {
    final violations = <String>[];
    sources.forEach((path, source) {
      if (!_under(path, 'lib/domain/')) return;
      for (final imp in _importsOf(source)) {
        if (imp.startsWith('package:flutter/') ||
            imp.startsWith('package:sqflite') ||
            imp.startsWith('dart:ui')) {
          violations.add('$path → $imp');
        }
      }
    });
    expect(violations, isEmpty,
        reason: 'domain/ 是纯逻辑层，不得依赖 Flutter / 数据库：\n${violations.join('\n')}');
  });

  test('规则 4：lib/ui/ 必须是纯视觉层 —— 不碰数据库、不含状态', () {
    // 规格 §2.1 对 ui/ 的定义：「纯视觉层：不碰数据库、不含状态、只回答长什么样」。
    //
    // 这条规则**替换了计划初版的一条废规则**。初版写的是
    // `test('规则 4：lib/features/ 不得 import lib/state/ 之外的状态实现细节')`，
    // 但实现检查的是「同一个 import URI 里同时含 `repositories/` 和 `sqflite`」——
    // 那既不是真实存在的违规写法，也不对应任何设计约束，**名字与实现互相说谎**。
    // 一条名字说谎的测试比没有测试更糟：它让人以为某个约束被守住了。
    //
    // 换成这条，因为它守的是规格里**真实写下过**的约束，且可机械判定：
    // ui/ 一旦 import state/ 或 features/，它就不再是纯视觉层，
    // 「换一套配色不用碰业务」这个好处就没了。
    final violations = <String>[];
    sources.forEach((path, source) {
      if (!_under(path, 'lib/ui/')) return;
      for (final imp in _importsOf(source)) {
        if (imp.contains('state/') || imp.contains('features/')) {
          violations.add('$path → $imp');
        }
      }
    });
    expect(violations, isEmpty,
        reason: 'ui/ 是纯视觉层，不得依赖状态或业务界面：\n${violations.join('\n')}');
  });
}
