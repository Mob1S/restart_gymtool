import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'backup_file_store.dart';

typedef SaveCsvBytes = Future<Uri?> Function(String name, Uint8List bytes);

Future<BackupSaveResult> saveWorkoutCsv(
  String name,
  List<int> bytes, {
  SaveCsvBytes? write,
  bool? web,
}) async {
  final save =
      write ??
      ((String fileName, Uint8List content) => FilePicker.saveFile(
        fileName: fileName,
        bytes: content,
        mimeType: 'text/csv',
        dialogTitle: '导出训练记录',
      ));
  final result = await save(name, Uint8List.fromList(bytes));
  if (web ?? kIsWeb) return BackupSaveResult.downloadRequested;
  return result == null ? BackupSaveResult.canceled : BackupSaveResult.saved;
}
