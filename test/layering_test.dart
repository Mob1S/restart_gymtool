import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 分层规则的**机械守卫**。
///
/// 规格 §2.2：旧项目把这三条叫「硬性规则」，但只靠约定守。而旧文档 §4.2 记着
/// 「判据两边同时写错的时候，只有端到端测试能发现」—— 约定守不住的东西，
/// 让测试守。
///
/// 规则 1 / 3 / 4 **不看内容、只看 import 字符串**，所以它们不会因为重构而误报。
/// 规则 2 要看字符串内容，判据与它自己的验证见下面的长注释。

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
  final re = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  return re.allMatches(source).map((m) => m.group(1)!).toList();
}

/// 这个文件是否属于某个目录（用于前缀匹配）。
bool _under(String path, String prefix) => path.startsWith(prefix);

// ===========================================================================
// 规则 2 用的扫描器
// ===========================================================================

/// 一个字符串字面量：内容（不含引号）+ 它在文件里的行号。
class _DartString {
  final String text;
  final int line;

  const _DartString(this.text, this.line);
}

/// 字符级状态机，走一遍 Dart 源码，**只收下字符串字面量的内容**。
///
/// ## 为什么不能直接对整份源码做正则
///
/// Task 4 实测过两条误报，都是「正则分不清这段字符是什么」造成的：
///
/// 1. 注释里提到 SQL 就红 —— 例如 `// 不要写 'SELECT * FROM session'`；
/// 2. 英文文案里出现 `Insert Into` 这类词组就红。
///
/// 而且**正则根本没法正确地剥注释**：一个 `/` 是除号、是注释开头、还是
/// 字符串里的一个字符，只有按字符走一遍才知道。所以这里不用正则。
///
/// ## 三条状态规则
///
/// 1. `//` 之后到行尾 → 注释，丢弃。（`///` 与 `//` 同一条规则：文档注释就是
///    三个斜杠开头，前两个即注释符。）
/// 2. `/*` 之后到配对的 `*/` → 注释，丢弃。Dart 的块注释**可以嵌套**，
///    所以要数层数，不能找到第一个 `*/` 就收。
/// 3. 引号之间 → 字符串，**内容原样收下**（`'` `"` `'''` `"""`，可带 `r` 前缀）。
///    其余的一切都是代码，不参与匹配。
///
/// 「剥掉注释」在这里不是一个单独的步骤，而是「只看字符串字面量」的**副产品**：
/// 注释里的字符压根不会被收进任何字面量。反过来说，注释**必须**被跳过 ——
/// 注释里的一个撇号（`// don't`）会让扫描器错位，把后面半份文件当成字符串。
///
/// ## 三个专门处理过的坑
///
/// - **字符串里的 `//`**：进字符串之后就不再判注释，直到配对引号。
///   `'http://x'` 不会被看成注释。
/// - **`${...}` 里又是代码**：`'${a['k']}'` 这种写法里嵌着字符串，
///   不处理的话扫描器会在 `a[` 后面的那个 `'` 上提前收尾。所以遇到 `$` + `{`
///   **递归**回到代码态，按大括号配对找回来。这个坑是真实存在的：
///   `lib/domain/format.dart` 里就有 `'${x.split(' ').first} …'`。
/// - **`--` 不是 Dart 注释**：它是 SQL 的注释符，Dart 里是减减运算符。
///   所以状态机**完全不认它** —— 多行 SQL 串里的 `-- 注释` 原样留在字面量里。
class _DartScanner {
  final String _s;
  final int _n;
  final List<_DartString> _found = [];
  int _i = 0;

  // 行号：字面量的起点位置是单调递增的，所以边走边数，整体只扫一遍。
  int _line = 1;
  int _countedTo = 0;

  _DartScanner(this._s) : _n = _s.length;

  static final RegExp _identChar = RegExp(r'[A-Za-z0-9_$]');

  List<_DartString> scan() {
    _scanCode(stopAtBrace: false);
    return _found;
  }

  int _lineAt(int pos) {
    while (_countedTo < pos && _countedTo < _n) {
      if (_s[_countedTo] == '\n') _line++;
      _countedTo++;
    }
    return _line;
  }

  /// 扫一段代码。[stopAtBrace] 为真时，遇到一个**不配对**的 `}` 就返回
  /// （调用方正在扫 `'${…}'`，用这个条件收尾）。
  void _scanCode({required bool stopAtBrace}) {
    var depth = 0;
    while (_i < _n) {
      final c = _s[_i];
      if (stopAtBrace && c == '}' && depth == 0) return;

      // 规则 1：行注释
      if (c == '/' && _i + 1 < _n && _s[_i + 1] == '/') {
        while (_i < _n && _s[_i] != '\n') {
          _i++;
        }
        continue;
      }
      // 规则 2：块注释（可嵌套）
      if (c == '/' && _i + 1 < _n && _s[_i + 1] == '*') {
        var nesting = 1;
        _i += 2;
        while (_i < _n && nesting > 0) {
          if (_s[_i] == '/' && _i + 1 < _n && _s[_i + 1] == '*') {
            nesting++;
            _i += 2;
          } else if (_s[_i] == '*' && _i + 1 < _n && _s[_i + 1] == '/') {
            nesting--;
            _i += 2;
          } else {
            _i++;
          }
        }
        continue;
      }
      // 规则 3：字符串（引号本身，或 r/R 前缀 + 引号）
      final isQuote = c == "'" || c == '"';
      final isRawPrefix =
          (c == 'r' || c == 'R') &&
          _i + 1 < _n &&
          (_s[_i + 1] == "'" || _s[_i + 1] == '"') &&
          (_i == 0 || !_identChar.hasMatch(_s[_i - 1]));
      if (isQuote || isRawPrefix) {
        _scanString();
        continue;
      }

      if (c == '{') depth++;
      if (c == '}') depth--;
      _i++;
    }
  }

  void _scanString() {
    var isRaw = false;
    if (_s[_i] == 'r' || _s[_i] == 'R') {
      isRaw = true;
      _i++;
    }
    final quote = _s[_i];
    final isTriple = _i + 2 < _n && _s[_i + 1] == quote && _s[_i + 2] == quote;
    final line = _lineAt(_i);
    _i += isTriple ? 3 : 1;

    final buf = StringBuffer();
    while (_i < _n) {
      final c = _s[_i];

      // 转义：把反斜杠和它后面那个字符一起收下，别把 `\'` 当成收尾
      if (!isRaw && c == r'\') {
        buf.write(c);
        if (_i + 1 < _n) buf.write(_s[_i + 1]);
        _i += 2;
        continue;
      }

      // 插值：`${…}` 里又是代码，还可能再嵌字符串 —— 递归扫，用 `$` 占位
      if (!isRaw && c == r'$' && _i + 1 < _n) {
        if (_s[_i + 1] == '{') {
          _i += 2;
          _scanCode(stopAtBrace: true);
          if (_i < _n && _s[_i] == '}') _i++;
          buf.write(r'$');
          continue;
        }
        if (_identChar.hasMatch(_s[_i + 1])) {
          // `$name` 简单插值：原样保留，它就是一个标识符
          buf.write(c);
          _i++;
          while (_i < _n && _identChar.hasMatch(_s[_i])) {
            buf.write(_s[_i]);
            _i++;
          }
          continue;
        }
      }

      if (c == quote) {
        if (!isTriple) {
          _i++;
          break;
        }
        if (_i + 2 < _n && _s[_i + 1] == quote && _s[_i + 2] == quote) {
          _i += 3;
          break;
        }
      }

      buf.write(c);
      _i++;
    }

    _found.add(_DartString(buf.toString(), line));
  }
}

/// 扫一个源文件，返回它所有的字符串字面量（注释与代码里的字符串都不算）。
List<_DartString> _dartStrings(String source) => _DartScanner(source).scan();

// ===========================================================================
// 规则 2 的判据
// ===========================================================================

/// SQL 语句头 + 一处结构。
///
/// 关键字表覆盖 Task 4 实测漏报的 6 类：`INSERT OR REPLACE INTO`、
/// `INSERT OR IGNORE INTO`、`CREATE INDEX IF NOT EXISTS`、`WITH … SELECT`、
/// `DROP TABLE`、`REPLACE INTO`。
///
/// 每条分支都不止要求一个关键字，还要求关键字后面的**结构**（表名 / 列名 /
/// 参数占位符）。只要求一个关键字是不够的 —— 那正是「英文文案里出现
/// `Insert Into` 就红」的成因。
///
/// 引号写成 `\x27` / `\x22`：Dart 的原始字符串里没法内嵌转义引号，
/// 而正则引擎认识 `\xHH`。
final RegExp _sqlShaped = RegExp(
  r'^\s*(?:'
  r'SELECT\s+[\s\S]*?\s+FROM\s+[^\s\x27\x22]'
  r'|INSERT\s+(?:OR\s+\w+\s+)?INTO\s+[^\s\x27\x22(]+\s*(?:\(|VALUES\b|SELECT\b)'
  r'|REPLACE\s+INTO\s+[^\s\x27\x22(]+\s*(?:\(|VALUES\b|SELECT\b)'
  r'|UPDATE\s+\S+\s+SET\s+[^\s\x27\x22]'
  r'|DELETE\s+FROM\s+[^\s\x27\x22]+\s*(?:WHERE\b|;|$)'
  r'|CREATE\s+(?:UNIQUE\s+)?(?:TABLE|INDEX|VIEW|TRIGGER)\s+[^\s\x27\x22]'
  r'|DROP\s+(?:TABLE|INDEX|VIEW|TRIGGER)\s+[^\s\x27\x22]'
  r'|ALTER\s+TABLE\s+[^\s\x27\x22]'
  r'|WITH\s+[\s\S]*?\bAS\s*\([\s\S]*\)\s*SELECT\b'
  r'|PRAGMA\s+\w+\s*='
  r')',
  caseSensitive: false,
);

/// 语句头是 `SELECT` 的字面量。`SELECT` 是全表里唯一只有**一个**关键字的分支，
/// 所以它单独加一道闸。
final RegExp _selectHead = RegExp(r'^\s*SELECT\b', caseSensitive: false);

/// 「SQL 才有的东西」：参数占位符 / 运算符 / 逗号括号星号，snake_case 的表名列名，
/// 或几个只在 SQL 里成词的关键字。人话里不会长这样。
final RegExp _sqlEvidence = RegExp(
  r'[?=,(*]'
  r'|[a-z][a-z0-9]*_[a-z0-9_]*'
  r'|\b(?:WHERE|VALUES|JOIN|LIMIT|ORDER\s+BY|GROUP\s+BY|NOT\s+NULL'
  r'|PRIMARY\s+KEY|ON\s+CONFLICT|ON\s+DELETE|REFERENCES|ADD\s+COLUMN)\b',
  caseSensitive: false,
);

/// 这个字符串字面量**长得像一条 SQL 语句**吗？
bool _looksLikeSql(String literal) {
  if (!_sqlShaped.hasMatch(literal)) return false;
  // `Select the exercise from the list` 这种英文句子能撞上 SELECT 那一支，
  // 所以再加一道：字面量里还必须出现 SQL 才有的东西。
  // 实测（见下方测试）：这道闸在数据层现有 37 条真实 SQL 上一条都没漏。
  if (_selectHead.hasMatch(literal) && !_sqlEvidence.hasMatch(literal)) {
    return false;
  }
  return true;
}

/// 违规信息里附一小段 SQL，方便直接定位；太长就截断。
String _preview(String literal) {
  final oneLine = literal.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length <= 60 ? oneLine : '${oneLine.substring(0, 60)}…';
}

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
    expect(
      violations,
      isEmpty,
      reason: '界面层只能通过 repositories 访问数据，不能碰 db/：\n${violations.join('\n')}',
    );
  });

  test('规则 2：SQL 字符串只允许出现在 data/db/ 与 data/repositories/', () {
    // 判据分三层（每一层都对应 Task 4 实测过的一个问题）：
    //
    //   1. **只看字符串字面量** —— 注释与代码不参与任何匹配。
    //      消掉误报「注释里提到 SQL 就红」。
    //   2. **字面量要以 SQL 语句头开头** —— 关键字表补上了 6 类漏报。
    //   3. **语句头之后还要有结构**（表名 / 列名 / 占位符）。
    //      消掉误报「英文文案里出现 `Insert Into` 这类词组就红」。
    //
    // 这三层只收紧了、没有放宽：Task 4 那版能抓的，这一版都能抓
    // （见下面「该抓的抓、不该抓的不抓」那条测试）。
    final violations = <String>[];
    sources.forEach((path, source) {
      // db/ 放 schema 与迁移 SQL，repositories/ 放查询 SQL —— 这两处是允许的
      if (_under(path, 'lib/data/db/') ||
          _under(path, 'lib/data/repositories/')) {
        return;
      }
      for (final literal in _dartStrings(source)) {
        if (_looksLikeSql(literal.text)) {
          violations.add('$path:${literal.line} → ${_preview(literal.text)}');
        }
      }
    });
    expect(
      violations,
      isEmpty,
      reason:
          'SQL 只允许出现在 data/db/ 与 data/repositories/：\n${violations.join('\n')}',
    );
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
    expect(
      violations,
      isEmpty,
      reason: 'domain/ 是纯逻辑层，不得依赖 Flutter / 数据库：\n${violations.join('\n')}',
    );
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
    expect(
      violations,
      isEmpty,
      reason: 'ui/ 是纯视觉层，不得依赖状态或业务界面：\n${violations.join('\n')}',
    );
  });

  // ---------------------------------------------------------------------
  // 规则 2 自己的守卫。
  //
  // 规则 2 是四条规则里唯一「看内容」的一条，它的判据本身也会坏 ——
  // 最坏的一种坏法是扫描器吃掉了真实的 SQL 字面量，于是规则 2 变成一条
  // 永远绿的测试。下面这几条把判据的行为钉住，避免那种静默失效。
  // ---------------------------------------------------------------------

  group('规则 2 的判据', () {
    test('扫描器：注释里的 SQL 不算数，字符串里的算', () {
      final found = _dartStrings('''
// 不要写 'SELECT * FROM session'
/// 例：'INSERT INTO session' 也不行
/* 'DROP TABLE session' */
void f() {
  final sql = 'SELECT * FROM session';
  print(sql);
}
''');
      expect(found.map((l) => l.text), ['SELECT * FROM session']);
      expect(found.single.line, 5);
    });

    test('扫描器：注释里的撇号、字符串里的 //、多行串里的 --、插值里的嵌套串', () {
      // `// don't` 里的撇号若被当成字符串开头，后面半份文件会被吞掉
      final apostrophe = _dartStrings(
        "void f() {\n  // don't\n  final a = 'x';\n  print(a);\n}\n",
      );
      expect(apostrophe.map((l) => l.text), ['x']);

      final url = _dartStrings(
        "void f() { final u = 'http://x/y'; print(u); }\n",
      );
      expect(url.map((l) => l.text), ['http://x/y']);

      // `--` 是 SQL 的注释符、Dart 的减减运算符，必须原样留在字面量里
      final dashes = _dartStrings(
        "void f() { final q = 'SELECT 1 -- 注释'; print(q); }\n",
      );
      expect(dashes.single.text, contains('--'));

      // `${…}` 里嵌着单引号：不处理的话外层串会在这里被提前收尾
      final nested = _dartStrings(
        "void f() { final s = 'a\${m['k']}b'; print(s); }\n",
      );
      // 内容不含引号：嵌套的那个字面量收下的是 `k`，外层是 `a$b`
      expect(nested.map((l) => l.text), containsAll(<String>['k', r'a$b']));
    });

    test('判据：该抓的抓、不该抓的不抓', () {
      // 该抓的 —— 前三条是 Task 4 那版原本就能抓的，其余是当时实测漏报的
      const mustCatch = <String>[
        'SELECT * FROM session WHERE id = ?',
        'INSERT INTO set_entry (id) VALUES (?)',
        'UPDATE session SET finished_at = ? WHERE id = ?',
        'INSERT OR REPLACE INTO app_setting (key, value) VALUES (?, ?)',
        'INSERT OR IGNORE INTO app_setting (key, value) VALUES (?, ?)',
        'CREATE INDEX IF NOT EXISTS idx_a ON session(finished_at)',
        'WITH recent AS (SELECT id FROM session) SELECT * FROM recent',
        'DROP TABLE session',
        'REPLACE INTO app_setting (key, value) VALUES (?, ?)',
        'ALTER TABLE session ADD COLUMN template_id TEXT',
        'CREATE TABLE IF NOT EXISTS exercise (id TEXT PRIMARY KEY)',
        'PRAGMA foreign_keys = ON',
        // 多行写法（仓储里真实存在的那种）
        'SELECT \$cols\n  FROM set_entry st\n  JOIN session_exercise se ON se.id = st.x\n WHERE se.id = ?',
        // 小写写法
        'select * from session where id = ?',
      ];
      for (final sql in mustCatch) {
        expect(_looksLikeSql(sql), isTrue, reason: '这条 SQL 应当被抓到：$sql');
      }

      // 不该抓的 —— 英文文案、中文文案、普通常量
      const mustNotCatch = <String>[
        'Insert Into the log',
        'Insert Into',
        'Select the exercise from the list',
        'Delete from the list',
        'Update your weight',
        'Create a new exercise',
        'Drop set',
        'Replace exercise',
        'PRAGMA of the app',
        // 本 App 的界面文案
        '重量 × 次数',
        '估算 · 仅供参考',
        '深蹲 等 3 个动作 · 已记 12 组',
        '还没记录，先选个动作吧',
        '粗略参考',
        // 普通常量
        ' / ',
        'rest_seconds',
        'theme_mode',
        'session',
        'id',
      ];
      for (final text in mustNotCatch) {
        expect(_looksLikeSql(text), isFalse, reason: '这条不是 SQL，不该被抓：$text');
      }
    });
  });
}
