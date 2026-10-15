import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/backup.dart';

enum BackupSaveResult { saved, downloadRequested, canceled }

class PickedBackup {
  final String name;
  final List<int> bytes;

  PickedBackup(this.name, List<int> bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
}

abstract interface class BackupFileStore {
  Future<PickedBackup?> pick();
  Future<BackupSaveResult> save(String name, List<int> bytes);
}

typedef SaveBackupBytes = Future<Uri?> Function(String name, Uint8List bytes);

Future<PickedBackup> readBoundedBackup(
  String name,
  Stream<List<int>> stream, {
  int? reportedLength,
}) async {
  void check(int size) {
    if (size > maxBackupBytes) {
      throw const BackupValidationException('文件超过 20 MiB，未读取备份');
    }
  }

  if (reportedLength != null) check(reportedLength);
  final builder = BytesBuilder(copy: false);
  var received = 0;
  try {
    await for (final chunk in stream) {
      received += chunk.length;
      check(received);
      builder.add(chunk);
    }
    return PickedBackup(name, builder.takeBytes());
  } on BackupValidationException {
    rethrow;
  } catch (_) {
    throw const BackupValidationException('无法读取所选文件，请检查文件是否可访问');
  }
}

class PlatformBackupFileStore implements BackupFileStore {
  final Future<PlatformFile?> Function() _choose;
  final SaveBackupBytes _write;
  final bool _web;

  PlatformBackupFileStore({
    Future<PlatformFile?> Function()? choose,
    SaveBackupBytes? write,
    bool? web,
  }) : _choose = choose ?? (() => FilePicker.pickFile(type: FileType.any)),
       _write =
           write ??
           ((name, bytes) => FilePicker.saveFile(
             fileName: name,
             bytes: bytes,
             mimeType: 'application/json',
             dialogTitle: '保存备份',
           )),
       _web = web ?? kIsWeb;

  @override
  Future<PickedBackup?> pick() async {
    try {
      final file = await _choose();
      if (file == null) return null;
      final length = file.lengthSync() ?? await file.length();
      // Check before creating the stream too: platform adapters may start I/O
      // as soon as readAsByteStream is called.
      if (length != null && length > maxBackupBytes) {
        throw const BackupValidationException('文件超过 20 MiB，未读取备份');
      }
      return await readBoundedBackup(
        file.name,
        file.readAsByteStream(),
        reportedLength: length,
      );
    } on BackupValidationException {
      rethrow;
    } catch (_) {
      throw const BackupValidationException('无法读取所选文件，请检查文件是否可访问');
    }
  }

  @override
  Future<BackupSaveResult> save(String name, List<int> bytes) async {
    if (bytes.length > maxBackupBytes) {
      throw const BackupValidationException('备份超过 20 MiB，未保存文件');
    }
    try {
      final uri = await _write(name, Uint8List.fromList(bytes));
      if (_web) return BackupSaveResult.downloadRequested;
      return uri == null ? BackupSaveResult.canceled : BackupSaveResult.saved;
    } catch (_) {
      throw const BackupValidationException('无法保存备份，请检查目标位置后重试');
    }
  }
}
