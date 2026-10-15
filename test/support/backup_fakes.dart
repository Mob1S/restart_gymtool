import 'dart:convert';
import 'dart:io';

import 'package:gym_tracker/data/files/backup_file_store.dart';

class MemoryBackupFiles implements BackupFileStore {
  PickedBackup? selected;
  String? savedName;
  List<int>? savedBytes;
  int picks = 0;
  int saves = 0;
  Future<PickedBackup?> Function()? choose;
  Future<BackupSaveResult> Function()? write;
  BackupSaveResult saveResult = BackupSaveResult.saved;

  void useFixture([String name = 'legacy-v2']) {
    selected = PickedBackup(
      '$name.json',
      File('test/fixtures/backup/$name.json').readAsBytesSync(),
    );
  }

  void useJson(Object? value) {
    selected = PickedBackup('input.json', utf8.encode(jsonEncode(value)));
  }

  @override
  Future<PickedBackup?> pick() async {
    picks++;
    return choose == null ? selected : await choose!();
  }

  @override
  Future<BackupSaveResult> save(String name, List<int> bytes) async {
    saves++;
    savedName = name;
    savedBytes = bytes;
    return write == null ? saveResult : await write!();
  }
}
