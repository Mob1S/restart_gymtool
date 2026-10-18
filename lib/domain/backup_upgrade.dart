import 'backup.dart';
import 'weight_value.dart';

/// Validate the source before adding any missing legacy fields. Stable IDs make
/// repeat previews identical; absent settings continue to mean “preserve local”.
Map<String, Object?> upgradeBackupToV4(Map<String, Object?> root) {
  final source = validateBackup(root);
  if (source.version >= 4) return source.toJson();
  final data = <String, Object?>{
    for (final entry in source.data.entries)
      entry.key: [
        for (final row in entry.value) {...row},
      ],
  };
  final templates = source.rows('templates');
  String? planId;
  if (templates.isNotEmpty) {
    final occupied = {
      for (final rows in source.data.values)
        for (final row in rows)
          if (row['id'] is String) row['id'] as String,
    };
    const stem = 'legacy-training-plan';
    planId = stem;
    var suffix = 1;
    while (occupied.contains(planId)) {
      planId = '$stem-${suffix++}';
    }
  }
  data['plans'] = [
    if (planId != null)
      {
        'id': planId,
        'name': '我的训练计划',
        'position': 0,
        'createdAt': templates
            .map((row) => row['createdAt'] as int)
            .reduce((a, b) => a < b ? a : b),
      },
  ];
  data['templates'] = [
    for (final row in templates) {...row, 'planId': planId},
  ];
  final templateById = {for (final row in templates) row['id']: row};
  data['sessions'] = [
    for (final row in source.rows('sessions'))
      {
        ...row,
        'planId': templateById.containsKey(row['templateId']) ? planId : null,
        'planNameSnapshot': templateById.containsKey(row['templateId'])
            ? '我的训练计划'
            : null,
        'dayNameSnapshot': templateById[row['templateId']]?['name'],
        'origin': 'legacy',
      },
  ];
  data['sets'] = [
    for (final row in source.rows('sets'))
      {
        ...row,
        'sourceWeight': EquipmentWeight.kg(row['weight'] as double).amount.text,
        'sourceUnit': 'kg',
      },
  ];
  data['exercisePreferences'] = [
    for (final row in source.rows('exercisePreferences'))
      {
        'exerciseId': row['exerciseId'],
        'weightUnit': 'kg',
        'kgStep': DecimalReading.parse(
          ((row['weightStepMilli'] as int) / 1000).toString(),
        ).text,
        'lbStep': '5',
        'showKgEquivalent': false,
        'isFavorite': row['isFavorite'],
        'equipmentNote': row['equipmentNote'],
      },
  ];
  return validateBackup({
    'format': backupFormat,
    'version': 4,
    'schemaVersion': 6,
    'exportedAt': source.exportedAt,
    'data': data,
  }).toJson();
}

/// Legacy normalization remains independently available; current restores
/// additionally fill rest-day fields without changing historical readings.
Map<String, Object?> upgradeBackupToV5(Map<String, Object?> root) {
  final source = validateBackup(upgradeBackupToV4(root));
  if (source.version >= 5) return source.toJson();
  return validateBackup({
    ...source.toJson(),
    'version': 5,
    'schemaVersion': 7,
    'data': {
      ...source.data,
      'plans': [
        for (final row in source.rows('plans')) {...row, 'activatedOn': null},
      ],
      'templates': [
        for (final row in source.rows('templates'))
          {...row, 'kind': 'training'},
      ],
    },
  }).toJson();
}

Map<String, Object?> upgradeBackupToV6(Map<String, Object?> root) {
  final source = validateBackup(upgradeBackupToV5(root));
  if (source.version >= 6) return source.toJson();
  return validateBackup({
    ...source.toJson(),
    'version': 6,
    'schemaVersion': 8,
    'data': {
      ...source.data,
      'catalogBindings': [],
      'programs': [],
      'prescriptions': [],
      'setDetails': [],
    },
  }).toJson();
}
