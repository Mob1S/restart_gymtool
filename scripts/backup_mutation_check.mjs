// Temporarily break one guard at a time, require an assertion failure, and
// restore the exact original bytes even if the test command fails.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const output = path.join(root, 'build', 'acceptance', `backup-mutations-${stamp}`);
await mkdir(output, { recursive: true });
const cases = [
  { name: 'native-weight-consistency', file: 'lib/domain/backup.dart',
    before: 'if ((reading.kilograms - weight).abs() > tolerance)',
    after: 'if (false)',
    test: 'test/data/backup_v4_test.dart' },
  { name: 'parent-plan-reference', file: 'lib/domain/backup.dart',
    before: "references('templates', 'planId', 'plans');",
    after: '// Deliberately omit the parent reference guard.',
    test: 'test/data/backup_v4_test.dart' },
  { name: 'transaction', file: 'lib/data/repositories/backup_repo.dart',
    before: 'await exec.transaction((tx) async {',
    after: 'await Future.sync(() async { final tx = exec;',
    test: 'test/data/backup_repo_test.dart' },
  { name: 'reference', file: 'lib/domain/backup.dart',
    before: "references('sets', 'sessionExerciseId', 'sessionExercises');",
    after: '// Deliberately omit the set reference guard.',
    test: 'test/domain/backup_test.dart' },
  { name: 'row-order', file: 'lib/data/repositories/backup_repo.dart',
    before: "ORDER BY ${entry.key == 'settings' ? 'key' : 'rowid ASC'}",
    after: "${entry.key == 'settings' ? 'ORDER BY key' : ''}",
    test: 'test/data/backup_repo_boundaries_test.dart' },
  { name: 'cancel-save', file: 'lib/data/files/backup_file_store.dart',
    before: 'return uri == null ? BackupSaveResult.canceled : BackupSaveResult.saved;',
    after: 'return BackupSaveResult.saved;',
    test: 'test/data/backup_file_store_test.dart' },
  { name: 'template-reference', file: 'lib/domain/backup.dart',
    before: "references('sessions', 'templateId', 'templates', nullable: true);",
    after: '// Deliberately omit the session plan reference guard.',
    test: 'test/domain/backup_test.dart' },
  { name: 'stale-baseline', file: 'lib/data/repositories/backup_repo.dart',
    before: 'if (jsonEncode(current.data) != preview._baseline)',
    after: 'if (false)',
    test: 'test/data/backup_repo_test.dart' },
  { name: 'web-download', file: 'lib/data/files/backup_file_store.dart',
    before: 'if (_web) return BackupSaveResult.downloadRequested;',
    after: 'if (_web) return BackupSaveResult.canceled;',
    test: 'test/data/backup_file_store_test.dart' },
  { name: 'stale-selection', file: 'lib/state/backup_controller.dart',
    before: 'final selection = ++_selection;\n    _clearPreview();',
    after: 'final selection = ++_selection; // Deliberately keep the previous file.',
    test: 'test/state/backup_controller_test.dart' },
];
const results = [];
for (const item of cases) {
  const file = path.join(root, item.file);
  const original = await readFile(file);
  const source = original.toString('utf8').replace(/\r\n/g, '\n');
  assert.equal(source.split(item.before).length, 2, `Mutation must match exactly once: ${item.name}`);
  try {
    await writeFile(file, source.replace(item.before, item.after));
    const command = `. .\\scripts\\env.ps1; flutter test --no-pub ${item.test} --reporter expanded; exit $LASTEXITCODE`;
    const result = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
      { cwd: root, windowsHide: true, encoding: 'utf8', timeout: 180000, maxBuffer: 8 * 1024 * 1024 });
    const log = `${result.stdout || ''}\n${result.stderr || ''}`;
    await writeFile(path.join(output, `${item.name}.txt`), log);
    assert.equal(result.status, 1, `Mutation must fail: ${item.name}`);
    assert.match(log, /Expected:/, `Need an assertion failure, not a tool failure: ${item.name}`);
    assert.doesNotMatch(log, /Compilation failed|Failed to load/, `Invalid mutation: ${item.name}`);
    results.push({ mutation: item.name, detected: true, exitCode: result.status });
    console.log(`PASS detected ${item.name}`);
  } finally {
    await writeFile(file, original);
  }
}
await writeFile(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
console.log(`Evidence: ${output}`);
