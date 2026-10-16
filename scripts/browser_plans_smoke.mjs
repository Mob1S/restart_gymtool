import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

export async function run(h) {
  const {check,clickText,expectText,send,exportFile,screenshot}=h;
  async function type(text){await send('Input.insertText',{text});await delay(250);}
  async function openPlans(){
    await clickText('设置',true);
    await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:180,y:550,deltaY:500,deltaX:0});await delay(350);
    await clickText('训练计划',true);
  }
  async function add(name,repeat=1){
    await clickText('新建',true);await expectText('空计划也可以保存');
    // Flutter's editable semantics node does not expose the painted label.
    await h.clickAt(100,96);await type(name);
    for(let i=0;i<repeat;i++){
      await clickText('添加动作',true);await clickText('全部',true);await h.until(()=>h.has('胸'),'exercise picker data ready');
      await h.clickAt(100,166);await type('深蹲');await clickText('深蹲');await clickText('添加 1 个动作',true);
    }
    await clickText('保存',true);await expectText(name);
  }
  await check('create ordered A B C plans through real editor, retaining duplicate actions',async()=>{
    await openPlans();await add('A',2);await add('B');await add('C');await screenshot('01-plan-list');
    await clickText('Back');const {data}=await exportFile('01-plans');
    assert.deepEqual(data.data.templates.map(t=>t.name),['A','B','C']);
    assert.equal(data.data.templateExercises.filter(e=>e.templateId===data.data.templates[0].id).length,2);
  });
  await check('complete A with duplicate exercises and show next plan B',async()=>{
    await clickText('训练',true);await expectText('本次：A');await clickText('开始训练',true);
    await clickText('完成这组');await clickText('结束训练');await clickText('完成',true);
    await expectText('本次：B');await screenshot('02-next-B');
  });
  await check('temporary plan choice creates no session, canceling preserves next choice',async()=>{
    await clickText('换一个计划',true);await clickText('取消',true);await expectText('本次：B');
    await clickText('换一个计划',true);await clickText('C');await expectText('本次：C');
    const {data}=await exportFile('02-choice-not-started');assert.equal(data.data.sessions.length,1);
    await clickText('训练',true);
  });
  await check('delete plan detaches finished session and preserves recorded sets',async()=>{
    await openPlans();await clickText('删除计划');await clickText('取消',true);
    await clickText('删除计划');await clickText('删除计划',true);await clickText('Back');
    const {data}=await exportFile('03-plan-deleted');assert.equal(data.data.sessions.length,1);
    assert.equal(data.data.sessions[0].templateId,null);assert.equal(data.data.sets.filter(s=>s.isCompleted).length,1);
  });
  await check('delete exact history workout cancels first, then removes children',async()=>{
    await clickText('历史',true);await clickText('A');await clickText('删除这场训练');await clickText('取消',true);
    await clickText('删除这场训练');await clickText('删除这场训练',true);await expectText('还没有已完成的训练');
    const {data}=await exportFile('04-record-deleted');assert.equal(data.data.sessions.length,0);assert.equal(data.data.sets.length,0);
  });
  await check('move ordered plans by buttons and create a three-action removal fixture',async()=>{
    await openPlans();await clickText('下移计划');await add('D',3);await clickText('Back');
    const {data}=await exportFile('05-reordered');assert.deepEqual(data.data.templates.slice().sort((a,b)=>a.position-b.position).map(t=>t.name),['C','B','D']);
  });
  await check('keep and hard-delete action branches survive reload with correct remaining sets',async()=>{
    await clickText('训练',true);await clickText('换一个计划',true);await clickText('D');await clickText('开始训练',true);
    await clickText('完成这组');await clickText('移除当前动作');await clickText('取消',true);
    await clickText('移除当前动作');await clickText('保留已记组',true);
    await send('Page.reload');await expectText('继续 ');await clickText('继续 ');await expectText('完成这组');
    await clickText('完成这组');await clickText('移除当前动作');await clickText('删掉这 1 组',true);
    assert.equal(await h.has('移除当前动作'),false);
    await clickText('完成这组');await screenshot('03-removal');await clickText('Back');
    const {data}=await exportFile('06-removed-actions');
    assert.equal(data.data.sessionExercises.length,2);assert.equal(data.data.sets.filter(s=>s.isCompleted).length,2);
    const hidden=data.data.sessionExercises.find(e=>data.data.sets.filter(s=>s.sessionExerciseId===e.id).every(s=>s.isCompleted));
    assert(hidden);assert(data.data.sets.filter(s=>s.sessionExerciseId===hidden.id).every(s=>s.restStartedAt===null));
  });
  await check('delete current active workout resets continue state and removes exactly its children',async()=>{
    await clickText('训练',true);await clickText('继续 ');await clickText('删除这场训练');await clickText('删除这场训练',true);
    await expectText('开始训练');assert.equal(await h.has('继续 '),false);
    const {data}=await exportFile('07-active-deleted');assert.equal(data.data.sessions.length,0);assert.equal(data.data.sessionExercises.length,0);assert.equal(data.data.sets.length,0);
  });
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE='plans';import('./browser_backup_smoke.mjs').catch(error=>{console.error(error);process.exitCode=1;});
}
