import 'dart:convert';

import 'backup.dart';

String backupFileName(int exportedAt) {
  final date = DateTime.fromMillisecondsSinceEpoch(exportedAt);
  String two(int value) => value.toString().padLeft(2, '0');
  return 'gym-backup-${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}-'
      '${two(date.hour)}${two(date.minute)}${two(date.second)}.json';
}

BackupFile decodeBackup(List<int> bytes) {
  _checkLength(bytes.length);
  try {
    var text = utf8.decode(bytes);
    if (text.startsWith('\ufeff')) text = text.substring(1);
    return validateBackup(jsonDecode(text));
  } on FormatException {
    throw const BackupValidationException('文件不是有效的 UTF-8 JSON 备份');
  }
}

List<int> encodeBackup(BackupFile backup) {
  final bytes = utf8.encode(
    jsonEncode(validateBackup(backup.toJson()).toJson()),
  );
  _checkLength(bytes.length);
  return bytes;
}

void _checkLength(int size) {
  if (size > maxBackupBytes) {
    throw const BackupValidationException('数据超过 20 MiB 单份备份上限，未读写文件');
  }
}
