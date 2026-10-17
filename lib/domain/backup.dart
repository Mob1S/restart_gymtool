import 'dart:math' as math;

import 'weight_value.dart';

const backupFormat = 'gym-tracker-backup';
const backupVersion = 4;
const maxBackupBytes = 20 * 1024 * 1024;
const maxBackupRecords = 100000;
const maxBackupTimestamp = 8640000000000000;

class BackupValidationException implements Exception {
  final String message;
  const BackupValidationException(this.message);
  @override
  String toString() => message;
}

/// Constructed only by validation; every nested collection is immutable.
class BackupFile {
  final int version;
  final int schemaVersion;
  final int exportedAt;
  final Map<String, List<Map<String, Object?>>> data;
  const BackupFile._(
    this.version,
    this.schemaVersion,
    this.exportedAt,
    this.data,
  );

  bool get hasSettings => data.containsKey('settings');
  List<Map<String, Object?>> rows(String name) => data[name] ?? const [];
  int get activeSessions =>
      rows('sessions').where((r) => r['finishedAt'] == null).length;
  int get completedSessions => rows('sessions').length - activeSessions;
  Map<String, Object?> toJson() => {
    'format': backupFormat,
    'version': version,
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt,
    'data': data,
  };
}

enum _Field {
  id,
  text,
  nullableText,
  boolean,
  integer,
  nullableInteger,
  number,
  time,
  nullableTime,
}

const _fields = <String, Map<String, _Field>>{
  'exercises': {
    'id': _Field.id,
    'name': _Field.id,
    'muscleGroup': _Field.nullableText,
    'equipment': _Field.nullableText,
    'isCustom': _Field.boolean,
    'isArchived': _Field.boolean,
    'createdAt': _Field.time,
  },
  'sessions': {
    'id': _Field.id,
    'name': _Field.nullableText,
    'startedAt': _Field.time,
    'finishedAt': _Field.nullableTime,
    'note': _Field.nullableText,
    'templateId': _Field.nullableText,
  },
  'sessionExercises': {
    'id': _Field.id,
    'sessionId': _Field.id,
    'exerciseId': _Field.id,
    'position': _Field.integer,
    'note': _Field.nullableText,
  },
  'sets': {
    'id': _Field.id,
    'sessionExerciseId': _Field.id,
    'position': _Field.integer,
    'weight': _Field.number,
    'reps': _Field.integer,
    'isCompleted': _Field.boolean,
    'restSeconds': _Field.nullableInteger,
    'restStartedAt': _Field.nullableTime,
    'completedAt': _Field.nullableTime,
  },
  'templates': {
    'id': _Field.id,
    'name': _Field.id,
    'position': _Field.integer,
    'createdAt': _Field.time,
  },
  'templateExercises': {
    'id': _Field.id,
    'templateId': _Field.id,
    'exerciseId': _Field.id,
    'position': _Field.integer,
  },
  'settings': {'key': _Field.id, 'value': _Field.text},
  'exercisePreferences': {
    'exerciseId': _Field.id,
    'weightStepMilli': _Field.integer,
    'isFavorite': _Field.boolean,
    'equipmentNote': _Field.text,
  },
};

Map<String, Map<String, _Field>> _versionFields(int version) => {
  ..._fields,
  if (version >= 4) ...{
    'plans': {
      'id': _Field.id,
      'name': _Field.id,
      'position': _Field.integer,
      'createdAt': _Field.time,
    },
    'templates': {..._fields['templates']!, 'planId': _Field.id},
    'sessions': {
      ..._fields['sessions']!,
      'planId': _Field.nullableText,
      'planNameSnapshot': _Field.nullableText,
      'dayNameSnapshot': _Field.nullableText,
      'origin': _Field.id,
    },
    'sets': {
      ..._fields['sets']!,
      'sourceWeight': _Field.nullableText,
      'sourceUnit': _Field.id,
    },
    'exercisePreferences': {
      'exerciseId': _Field.id,
      'weightUnit': _Field.id,
      'kgStep': _Field.text,
      'lbStep': _Field.text,
      'showKgEquivalent': _Field.boolean,
      'isFavorite': _Field.boolean,
      'equipmentNote': _Field.text,
    },
  },
};

DecimalReading _decimal(Object? value, String path, {bool positive = false}) {
  if (value is! String) _fail(path, '必须是十进制文本');
  try {
    final reading = DecimalReading.parse(value);
    if (positive && reading.asDouble <= 0) _fail(path, '必须大于 0');
    return reading;
  } on FormatException {
    _fail(path, '必须是非负有限十进制数');
  }
}

WeightUnit _unit(Object? value, String path) => switch (value) {
  'kg' => WeightUnit.kg,
  'lb' => WeightUnit.lb,
  _ => _fail(path, '必须是 kg 或 lb'),
};

Never _fail(String path, String reason) =>
    throw BackupValidationException('$path $reason');

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    _fail(path, '必须是对象');
  }
  return value.cast<String, Object?>();
}

Object? _value(Object? value, _Field kind, String path) {
  if (value == null &&
      {
        _Field.nullableText,
        _Field.nullableInteger,
        _Field.nullableTime,
      }.contains(kind)) {
    return null;
  }
  switch (kind) {
    case _Field.id:
      if (value is! String || value.trim().isEmpty) _fail(path, '必须是非空字符串');
      return value;
    case _Field.text:
    case _Field.nullableText:
      if (value is! String) {
        _fail(path, '必须是字符串${kind == _Field.nullableText ? '或 null' : ''}');
      }
      return value;
    case _Field.boolean:
      if (value is! bool) _fail(path, '必须是布尔值');
      return value;
    case _Field.number:
      if (value is! num || !value.isFinite || value < 0) {
        _fail(path, '必须是非负有限数字');
      }
      return value.toDouble();
    case _Field.integer:
    case _Field.nullableInteger:
    case _Field.time:
    case _Field.nullableTime:
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          value % 1 != 0 ||
          value > maxBackupTimestamp) {
        _fail(path, '必须是范围内的非负整数');
      }
      return value.toInt();
  }
}

BackupFile validateBackup(Object? input) {
  final root = _object(input, '备份');
  if (root['format'] != backupFormat) _fail('format', '不是本应用的备份文件');
  final version = root['version'];
  if (version is! int || version < 1 || version > backupVersion) {
    _fail('version', '不受支持，请使用格式 1 / 2 / 3 / 4 的备份；新版本文件请先升级应用');
  }
  final schema = root['schemaVersion'];
  if (schema is! int ||
      schema < 1 ||
      switch (version) {
        4 => schema != 6,
        3 => schema < 5 || schema > 6,
        _ => schema > 4,
      }) {
    _fail('schemaVersion', '不受支持，请先升级应用');
  }
  if (!root.containsKey('exportedAt')) _fail('exportedAt', '缺少字段');
  final exportedAt =
      _value(root['exportedAt'], _Field.time, 'exportedAt') as int;
  final raw = _object(root['data'], 'data');
  final fields = _versionFields(version);
  var count = 0;
  final sources = <String, List>{};
  final normalized = <String, List<Map<String, Object?>>>{};
  for (final table in fields.entries) {
    final name = table.key;
    if (name == 'settings' && !raw.containsKey(name)) continue;
    if (name == 'exercisePreferences' && version < 3) continue;
    final Object? source =
        version == 1 &&
            (name == 'templates' || name == 'templateExercises') &&
            !raw.containsKey(name)
        ? const []
        : raw[name];
    if (source is! List) _fail('data.$name', '必须是数组');
    count += source.length;
    if (count > maxBackupRecords) _fail('data', '记录总数超过 100,000 条上限');
    sources[name] = source;
  }
  for (final table in fields.entries) {
    final name = table.key;
    final source = sources[name];
    if (source == null) continue;
    final records = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var i = 0; i < source.length; i++) {
      final path = 'data.$name 第 ${i + 1} 条';
      final record = _object(source[i], path);
      final row = <String, Object?>{};
      for (final field in table.value.entries) {
        final missingTemplate =
            name == 'sessions' &&
            field.key == 'templateId' &&
            version == 1 &&
            !record.containsKey(field.key);
        if (!record.containsKey(field.key) && !missingTemplate) {
          _fail('$path 的 ${field.key}', '缺少字段');
        }
        row[field.key] = _value(
          record[field.key],
          field.value,
          '$path 的 ${field.key}',
        );
      }
      final key = name == 'settings'
          ? 'key'
          : name == 'exercisePreferences'
          ? 'exerciseId'
          : 'id';
      final id = row[key] as String;
      if (name == 'exercisePreferences') {
        if (version < 4 &&
            ![500, 1000, 1250, 2500, 5000].contains(row['weightStepMilli'])) {
          _fail(path, '调重幅度无效');
        }
        if (version >= 4) {
          _unit(row['weightUnit'], '$path 的 weightUnit');
          _decimal(row['kgStep'], '$path 的 kgStep', positive: true);
          _decimal(row['lbStep'], '$path 的 lbStep', positive: true);
        }
        if ((row['equipmentNote'] as String).runes.length > 500) {
          _fail(path, '器械备忘最多 500 个字符');
        }
      }
      if (!seen.add(id)) {
        _fail(path, '包含重复 ${name == 'settings' ? 'key' : 'id'}：$id');
      }
      records.add(Map.unmodifiable(row));
    }
    normalized[name] = List.unmodifiable(records);
  }
  void references(
    String child,
    String field,
    String parent, {
    bool nullable = false,
  }) {
    final ids = normalized[parent]!.map((row) => row['id']).toSet();
    final children = normalized[child]!;
    for (var i = 0; i < children.length; i++) {
      final id = children[i][field];
      if (nullable && id == null) continue;
      if (!ids.contains(id)) {
        _fail('data.$child 第 ${i + 1} 条的 $field', '找不到对应的 $parent（引用完整性）');
      }
    }
  }

  if (version >= 3) {
    references('exercisePreferences', 'exerciseId', 'exercises');
  }
  references('sessionExercises', 'sessionId', 'sessions');
  references('sessionExercises', 'exerciseId', 'exercises');
  references('sets', 'sessionExerciseId', 'sessionExercises');
  references('templateExercises', 'templateId', 'templates');
  references('templateExercises', 'exerciseId', 'exercises');
  references('sessions', 'templateId', 'templates', nullable: true);
  if (version >= 4) {
    references('templates', 'planId', 'plans');
    references('sessions', 'planId', 'plans', nullable: true);
    final templates = {
      for (final row in normalized['templates']!) row['id']: row,
    };
    for (final row in normalized['sessions']!) {
      final template = templates[row['templateId']];
      if (template != null && template['planId'] != row['planId']) {
        _fail('data.sessions ${row['id']}', '训练日与计划不匹配');
      }
      if (!{'legacy', 'live', 'manual', 'csv'}.contains(row['origin'])) {
        _fail('data.sessions ${row['id']} 的 origin', '训练来源无效');
      }
    }
    for (final row in normalized['sets']!) {
      final path = 'data.sets ${row['id']}';
      final unit = _unit(row['sourceUnit'], '$path 的 sourceUnit');
      final source = row['sourceWeight'];
      if (source == null) {
        if (unit != WeightUnit.kg) _fail(path, '缺少磅数原始读数');
        continue;
      }
      final reading = EquipmentWeight(
        _decimal(source, '$path 的 sourceWeight'),
        unit,
      );
      final weight = row['weight'] as double;
      final tolerance = math.max(1e-9, weight.abs() * 1e-12);
      if ((reading.kilograms - weight).abs() > tolerance) {
        _fail(path, '原始读数与标准 kg 重量不一致');
      }
    }
  }
  final result = BackupFile._(
    version,
    schema,
    exportedAt,
    Map.unmodifiable(normalized),
  );
  if (result.activeSessions > 1) _fail('data.sessions', '包含多场未结束训练，只能保留一场');
  return result;
}
