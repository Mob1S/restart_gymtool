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
    final decoded = jsonDecode(text);
    _rejectDuplicateObjectKeys(text);
    return validateBackup(decoded);
  } on FormatException {
    throw const BackupValidationException('文件不是有效的 UTF-8 JSON 备份');
  }
}

/// jsonDecode normally silently keeps the final occurrence of a duplicate key.
/// Scan valid JSON tokens so namespace IDs and nested document keys cannot alias.
void _rejectDuplicateObjectKeys(String text) {
  final containers = <Set<String>?>[];
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (char == '{') {
      containers.add(<String>{});
    } else if (char == '[') {
      containers.add(null);
    } else if (char == '}' || char == ']') {
      containers.removeLast();
    } else if (char == '"') {
      final start = index++;
      while (index < text.length) {
        if (text[index] == r'\') {
          index += 2;
        } else if (text[index] == '"') {
          break;
        } else {
          index++;
        }
      }
      var next = index + 1;
      while (next < text.length && ' \r\n\t'.contains(text[next])) {
        next++;
      }
      if (next < text.length && text[next] == ':') {
        final key = jsonDecode(text.substring(start, index + 1)) as String;
        if (!containers.last!.add(key)) {
          throw BackupValidationException('JSON 对象包含重复 key：$key');
        }
      }
    }
    index++;
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
