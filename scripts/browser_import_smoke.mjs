import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

export async function run(h) {
  const {check,clickText,expectText,send,output,upload,exportFile,restoreFile,screenshot}=h;
  async function openImport(){
    await clickText('历史',true);
    await clickText('记录操作',true);
    await clickText('导入 CSV',true);
  }
  let baseline;
  const file=path.join(output,'strong.csv');
  await writeFile(file,'Date,Workout Name,Exercise Name,Weight,Reps\n2024-01-01 10:00,"Imported, push",深蹲,20,8\n2024-01-01 18:00,Evening,深蹲,30,10\ninvalid,Bad,深蹲,2,8');
  await check('real CSV upload previews physical bad row; cancel does not append',async()=>{
    await openImport();await upload(file);await expectText('已了解将跳过 1 行');
    await expectText('追加 0 场训练');await screenshot('01-preview');
    await clickText('取消预览');await clickText('Back');
    baseline=await exportFile('01-canceled');assert.equal(baseline.data.data.sessions.length,0);
  });
  await check('acknowledged CSV appends two same-day sessions with exact set values',async()=>{
    await openImport();await upload(file);await clickText('已了解将跳过 1 行');await clickText('追加 2 场训练');
    await expectText('Imported, push');await expectText('Evening');await screenshot('02-history');
    baseline=await exportFile('02-appended');const data=baseline.data.data;
    assert.equal(data.sessions.length,2);assert.equal(data.sets.length,2);
    assert.deepEqual(data.sets.map(s=>[s.weight,s.reps]),[[20,8],[30,10]]);
    assert(data.sessions.every(s=>s.templateId===null && s.note.includes('时长未知')));
    assert(data.sets.every(s=>s.isCompleted && s.restSeconds===null && s.restStartedAt===null && s.completedAt!==null));
  });
  await check('repeated file defaults to no selection and can be canceled',async()=>{
    await openImport();await upload(file);await expectText('疑似重复');await expectText('追加 0 场训练');
    await screenshot('03-duplicates');await clickText('取消预览');await clickText('Back');
    assert.deepEqual((await exportFile('03-unchanged')).data.data,baseline.data.data);
  });
  await check('exported append survives real file restore and page reload',async()=>{
    await restoreFile(baseline.file);await send('Page.reload');
    assert.deepEqual((await exportFile('04-roundtrip')).data.data,baseline.data.data);
  });
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE='import';import('./browser_backup_smoke.mjs').catch(error=>{console.error(error);process.exitCode=1;});
}
