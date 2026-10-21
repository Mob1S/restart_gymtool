import assert from 'node:assert/strict';
import path from 'node:path';
import {writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

export async function run(h) {
  const {check,clickText,expectText,send}=h;
  async function visible(text) {
    for (let i=0;i<12;i++) {
      const height=await h.evaluate('innerHeight');
      const item=(await h.semantics()).filter(e=>e.text===text).sort((a,b)=>a.width*a.height-b.width*b.height)[0];
      if (item&&item.y>=0&&item.y+item.height<height-85) return clickText(text,true);
      await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:190,y:height-160,deltaX:0,deltaY:item?.y<35?-250:200});
      await delay(250);
    }
    throw new Error('Cannot reveal '+text);
  }
  async function field(value) {
    const item=await h.until(async()=>(await h.semantics()).find(e=>e.role==='textbox'&&e.y>0&&e.y<700),'text field');
    await h.clickAt(item.x+40,item.y+item.height/2);
    await send('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
    await send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
    await send('Input.insertText',{text:value});
  }
  async function add(name,rest=false,exercise=false) {
    await visible(rest?'添加休息日':'添加训练日'); await field(name);
    if (rest) assert(!(await h.has('添加动作')));
    if (exercise) {
      await visible('添加动作'); await h.until(()=>h.has('胸'),'catalog'); await field('深蹲');
      await clickText('深蹲'); await clickText('添加 1 个动作',true);
    }
    await visible('完成');
  }
  let baseline;
  await check('create a four-day cycle with two explicit rest days through real editor',async()=>{
    await clickText('管理计划'); await clickText('新建计划',true); await field('自然日验收');
    await add('上肢',false,true); await add('恢复一',true); await add('恢复二',true); await add('下肢');
    await visible('保存'); await clickText('Back'); await expectText('上肢');
    baseline=await h.exportFile('01-created-cycle');
    assert.equal(baseline.data.version,7); assert.equal(baseline.data.schemaVersion,11);
    const days=baseline.data.data.templates.slice().sort((a,b)=>a.position-b.position);
    assert.deepEqual(days.map(d=>d.kind),['training','rest','rest','training']);
    assert(baseline.data.data.plans[0].activatedOn);
    assert(days.filter(d=>d.kind==='rest').every(d=>!baseline.data.data.templateExercises.some(e=>e.templateId===d.id)));
  });
  await check('finishing training today displays completed and tomorrow rest without rest sessions',async()=>{
    await clickText('训练',true); await clickText('开始训练',true); await clickText('完成这组');
    await clickText('结束训练'); await clickText('完成',true); await expectText('今日已完成'); await expectText('明天休息');
    await h.screenshot('02-completed-today');
    baseline=await h.exportFile('02-completed-cycle');
    assert.equal(baseline.data.data.sessions.length,1);
    await clickText('训练',true); await send('Page.reload'); await expectText('今日已完成');
  });
  async function restoreAgo(daysAgo,label) {
    const raw=structuredClone(baseline.data);
    const date=new Date(); date.setDate(date.getDate()-daysAgo); date.setHours(12,0,0,0);
    const time=date.getTime();
    raw.data.sessions[0].startedAt=time-3600000; raw.data.sessions[0].finishedAt=time;
    for (const set of raw.data.sets) if (set.completedAt!==null) set.completedAt=time-1000;
    const file=path.join(h.output,label+'.json'); await writeFile(file,JSON.stringify(raw)); await h.restoreFile(file);
    return raw;
  }
  await check('yesterday completion restores to first rest today and training-only picker',async()=>{
    await restoreAgo(1,'rest-first'); await expectText('今天休息'); await expectText('恢复一'); await expectText('下一次：下肢');
    await visible('选择训练日'); assert(!(await h.has('恢复一'))); assert(!(await h.has('恢复二')));
    await clickText('取消',true); await h.screenshot('03-rest-first');
    const before=await h.exportFile('03-rest-export'); await send('Page.reload');
    const after=await h.exportFile('03-rest-reloaded'); assert.deepEqual(after.data.data,before.data.data);
  });
  await check('consecutive second rest consumes one more natural day',async()=>{
    await restoreAgo(2,'rest-second'); await expectText('今天休息'); await expectText('恢复二');
    const exported=await h.exportFile('04-rest-second'); assert.equal(exported.data.data.sessions.length,1);
  });
  await check('elapsed rest stops at next uncompleted training even after a long absence',async()=>{
    await restoreAgo(8,'rest-ended'); await expectText('开始训练'); await expectText('下肢');
    assert(!(await h.has('今天休息'))); await h.screenshot('05-next-training');
  });
  await check('free training during rest leaves plan completion unchanged',async()=>{
    await restoreAgo(1,'rest-free'); await visible('自由训练'); await expectText('开始训练');
    await clickText('开始训练',true); await clickText('Back'); await expectText('继续训练');
    const exported=await h.exportFile('06-free-active');
    const active=exported.data.data.sessions.find(s=>s.finishedAt===null);
    assert(active); assert.equal(active.planId,null); assert.equal(active.templateId,null);
    await clickText('训练',true); await clickText('切换计划',true); await clickText('自然日验收');
    await expectText('继续训练'); await expectText('恢复一');
  });
  await check('invalid rest with exercises is refused before writes',async()=>{
    await h.restoreFile(baseline.file);
    const before=await h.exportFile('07-before-invalid'); const invalid=structuredClone(before.data);
    invalid.data.templates[0].kind='rest';
    const file=path.join(h.output,'invalid-rest-actions.json'); await writeFile(file,JSON.stringify(invalid));
    await h.selectFile(file); await expectText('休息日不能包含动作');
    assert.deepEqual((await h.exportFile('07-after-invalid')).data.data,before.data.data);
  });
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE='rest_days';
  import('./browser_backup_smoke.mjs').catch(e=>{console.error(e);process.exitCode=1;});
}
