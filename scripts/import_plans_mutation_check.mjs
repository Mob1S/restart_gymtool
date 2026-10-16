// Every mutation is restored byte-for-byte, including after failed tooling.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdir,readFile,writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const output=path.join(root,'build','acceptance',`import-plan-mutations-${new Date().toISOString().replace(/[:.]/g,'-')}`);
await mkdir(output,{recursive:true});
const cases=[
  ['same-day','lib/domain/workout_csv.dart','[source.name, start, workoutName]','[source.name, 0, workoutName]','test/domain/import_pipeline_test.dart'],
  ['pounds','lib/domain/workout_csv.dart','pounds ? 0.45359237 : 1','pounds ? 0.5 : 1','test/domain/import_pipeline_test.dart'],
  ['stale-import','lib/data/repositories/import_repo.dart','if (jsonEncode(snapshot.data) != batch.token)','if (false)','test/data/import_repo_test.dart'],
  ['backup-capacity','lib/data/repositories/import_repo.dart','encodeBackup(await readBackupSnapshot(tx, exportedAt: now));','// omit export boundary','test/data/import_repo_test.dart'],
  ['rotation-active','lib/data/repositories/session_repo.dart','WHERE finished_at IS NOT NULL AND template_id IS NOT NULL','WHERE template_id IS NOT NULL','test/data/plans_and_records_test.dart'],
  ['plan-detach','lib/data/repositories/template_repo.dart',"'UPDATE session SET template_id=NULL WHERE template_id=?'","'UPDATE session SET name=name WHERE template_id=?'",'test/data/plans_and_records_test.dart'],
  ['keep-completed','lib/data/repositories/record_management_repo.dart','WHERE session_exercise_id=? AND is_completed=0','WHERE session_exercise_id=? AND is_completed=1','test/state/remove_exercise_test.dart'],
  ['last-visible','lib/state/active_session_controller.dart','if (current.visibleCount <= 1)','if (false)','test/state/remove_exercise_test.dart'],
  ['cancel-removal','lib/state/active_session_controller.dart','if (choice == RemoveExerciseChoice.cancel || writing)','if (writing)','test/state/remove_exercise_test.dart'],
];
const results=[];
for(const [name,file,before,after,test] of cases){
  const target=path.join(root,file);const original=await readFile(target);const source=original.toString('utf8').replace(/\r\n/g,'\n');
  assert.equal(source.split(before).length,2,`Mutation matches once: ${name}`);
  try{
    await writeFile(target,source.replace(before,after));
    const command=`. .\\scripts\\env.ps1; flutter test --no-pub ${test} --reporter expanded; exit $LASTEXITCODE`;
    const result=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-Command',command],
      {cwd:root,windowsHide:true,encoding:'utf8',timeout:180000,maxBuffer:8*1024*1024});
    const log=`${result.stdout||''}\n${result.stderr||''}`;await writeFile(path.join(output,`${name}.txt`),log);
    assert.equal(result.status,1,`Expected failing test: ${name}`);assert.match(log,/Expected:/);
    assert.doesNotMatch(log,/Compilation failed|Failed to load/);
    results.push({name,detected:true,exitCode:result.status});console.log(`PASS detected ${name}`);
  }finally{await writeFile(target,original);}
}
await writeFile(path.join(output,'results.json'),JSON.stringify(results,null,2));console.log(`Evidence: ${output}`);
