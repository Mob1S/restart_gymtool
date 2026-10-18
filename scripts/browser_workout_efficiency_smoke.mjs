import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFile,writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';

export async function run(h) {
  const {check,clickAt,expectText,send}=h;
  // Settings now contain explicit unit/custom-step choices. Scroll the real
  // Flutter sheet to its controls rather than clicking offscreen coordinates.
  async function clickText(text, exact = false) {
    for (let attempt = 0; attempt < 12; attempt++) {
      const candidates = (await h.semantics()).filter(e =>
        (exact ? e.text === text || e.value === text : e.text.includes(text) || e.value?.includes(text)) &&
        (text.startsWith('收藏 ') || !e.text.startsWith('收藏 ')))
        .sort((a,b) => a.width*a.height - b.width*b.height);
      const element = candidates[0];
      const height = await h.evaluate('window.innerHeight');
      if (!element || (element.y >= 0 && element.y + element.height <= height)) {
        return h.clickText(text, exact);
      }
      await send('Input.dispatchMouseEvent', {type:'mouseWheel',
        x: Math.max(24, Math.min(element.x + element.width/2, 360)),
        y: height - 100, deltaY: element.y < 0 ? -250 : 250, deltaX:0});
      await delay(180);
    }
    throw new Error('Control did not scroll into view: ' + text);
  }
  async function adjust(target, dx, dy) {
    const slider = await h.until(async () => (await h.semantics())
      .find(e => e.role === 'slider' && e.text === target), target + ' native slider');
    const x = slider.x + slider.width/2, y = slider.y + slider.height/2;
    const valueBefore = slider.value;
    await send('Input.dispatchTouchEvent', {type:'touchStart', touchPoints:[{id:1,x,y}]});
    for (let n=1; n<=8; n++) {
      await send('Input.dispatchTouchEvent', {type:'touchMove', touchPoints:[{id:1,x:x+dx*n/8,y:y+dy*n/8}]});
      await delay(20);
    }
    await send('Input.dispatchTouchEvent', {type:'touchEnd', touchPoints:[]});
    await delay(400);
    const after = (await h.semantics()).find(e => e.role === 'slider' && e.text === target);
    assert(after && after.value !== valueBefore, target + ' gesture must change its accessible native value');
  }
  async function type(value) { await send('Input.insertText',{text:value});await delay(300); }
  async function replaceText(value) {
    await send('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2});
    await send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2});
    await type(value);
  }
  async function search(name) { await clickText('搜索动作');await replaceText(name);const row=await h.until(async()=> (await h.semantics()).find(e=>e.text.split('\n')[0]===name && e.width>100),'exact action '+name);await clickAt(row.x+100,row.y+row.height/2); }
  async function backToRecord() { await clickText('训练',true);await clickText('继续训练',true); }
  async function snapshot(label) { for(let i=0;i<5 && !(await h.semantics()).some(e=>e.text==='设置');i++) {
    if((await h.semantics()).some(e=>e.text==='Back')) await clickText('Back');
    else {
      await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
      await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
      await delay(400);
    }
  }await h.until(async()=>(await h.semantics()).some(e=>e.text==='设置'),'home navigation tabs');const result=await h.exportFile(label);await backToRecord();return result; }
  async function editFirst(weight,reps) {
    await clickText('本场已记 ');await clickText('第 1 组 ·');
    await expectText('修改第 1 组');await h.screenshot('edit-fields');
    await clickText('重量 kg');await replaceText(weight);
    await clickText('实际次数');await replaceText(reps);await clickText('保存',true);
    await clickAt(8,40);
  }
  let baseline;
  await check('multi-selection preserves B then A order and creates only one placeholder each',async()=>{
    await clickText('开始训练',true);await clickText('添加动作',true);await h.until(()=>h.has('胸'),'picker data');
    await search('坐姿绳索划船');await search('卧推');await clickText('添加 2 个动作',true);
    await expectText('完成这组');
    const {data}=await snapshot('01-batch');
    const names=new Map(data.data.exercises.map(e=>[e.id,e.name]));
    assert.deepEqual(data.data.sessionExercises.map(e=>names.get(e.exerciseId)),['坐姿绳索划船','卧推']);
    assert.equal(data.data.sets.length,2);
  });
  await check('zero-set replacement creates an independent target and keeps the other exercise',async()=>{
    await clickText('替换当前动作',true);await search('哑铃卧推');await clickText('替换为 哑铃卧推',true);
    const {data}=await snapshot('02-zero-replacement');
    assert.equal(data.data.sessionExercises.length,2);assert.equal(data.data.sets.length,2);
    assert(data.data.sessionExercises.every(e=>data.data.sets.some(s=>s.sessionExerciseId===e.id)));
  });
  await check('per-exercise step and Unicode equipment note save through real settings',async()=>{
    await clickText('动作设置',true);await clickText('1.25 kg',true);
    await clickText('器械备忘');await type('座椅第 4 档\n短握把 😀');await clickText('保存',true);
    await expectText('座椅第 4 档');
    const {data}=await snapshot('03-preferences');
    assert.equal(data.data.exercisePreferences.length,1);
    assert.equal(data.data.exercisePreferences[0].kgStep,'1.25');
    assert.equal(data.data.exercisePreferences[0].lbStep,'5');
    assert.equal(data.data.exercisePreferences[0].weightUnit,'kg');
    assert.equal(data.data.exercisePreferences[0].equipmentNote,'座椅第 4 档\n短握把 😀');
    await clickText('动作设置',true);await clickText('器械备忘');await replaceText('取消的输入');await clickText('取消',true);
    assert.equal((await snapshot('03-note-canceled')).data.data.exercisePreferences[0].equipmentNote,'座椅第 4 档\n短握把 😀');
    await clickText('动作设置',true);await clickText('器械备忘');await replaceText('');await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});await clickText('保存',true);
    assert.equal((await snapshot('03-note-cleared')).data.data.exercisePreferences[0].equipmentNote,'');
    await clickText('动作设置',true);await clickText('器械备忘');await type('座椅第 4 档\n短握把 😀');await clickText('保存',true);
    await clickText('卧推',true);await clickText('动作设置',true);await clickText('5 kg',true);await clickText('保存',true);
    const independent=(await snapshot('03-independent-steps')).data.data.exercisePreferences;
    assert.deepEqual(independent.map(p=>p.kgStep).sort(),['1.25','5']);
    assert(independent.every(p=>p.lbStep==='5' && p.weightUnit==='kg'));
    await clickText('哑铃卧推',true);

  });
  await check('actual correction preserves completion and rest timestamps, cancellation writes nothing',async()=>{
    await clickText('完成这组');
    const before=(await snapshot('04-completed')).data.data.sets.find(s=>s.isCompleted);
    await editFirst('40','8');
    const after=(await snapshot('05-corrected')).data.data.sets.find(s=>s.isCompleted);
    assert.equal(after.weight,40);assert.equal(after.reps,8);
    assert.equal(after.completedAt,before.completedAt);assert.equal(after.restStartedAt,before.restStartedAt);
    await clickText('本场已记 ');await clickText('第 1 组 ·');await clickText('实际次数');await replaceText('99');
    await clickText('取消',true);await clickAt(8,40);
    assert.deepEqual((await snapshot('06-cancel-edit')).data.data.sets.find(s=>s.isCompleted),after);
  });
  await check('undo restores original set id, then recompletion leaves one completed and one pending set',async()=>{
    await clickText('误点完成？撤销',true);await clickText('撤销完成',true);await expectText('完成这组');
    await clickText('完成这组');
    const {data}=await snapshot('07-undo-recomplete');
    assert.equal(data.data.sets.filter(s=>s.isCompleted).length,1);
    assert.equal(data.data.sets.length,3);
  });
  await check('rest weight survives reload, actual reps chosen later, and recorded replacement retains both sets',async()=>{
    // A diagonal gesture still belongs to the weight region; reps stay fixed.
    await adjust('重量',32,-17);
    await send('Page.reload');await expectText('继续训练');await clickText('继续训练',true);await expectText('下一组重量');
    const prepared=(await snapshot('08-prepared')).data;
    const completed=prepared.data.sets.find(s=>s.isCompleted);
    const pending=prepared.data.sets.find(s=>s.sessionExerciseId===completed.sessionExerciseId && !s.isCompleted);
    assert.equal(pending.weight,41.25);assert.equal(completed.weight,40);
    await clickText('开始第 2 组',true);
    await adjust('次数',-48,-36);
    await clickText('完成这组');
    await clickText('替换当前动作',true);await search('卧推');await clickText('替换为 卧推',true);
    await clickText('完成这组');
    baseline=await snapshot('09-recorded-replacement');
    assert.equal(baseline.data.data.sets.filter(s=>s.isCompleted).length,3);
    const old=baseline.data.data.sets.filter(s=>s.sessionExerciseId===completed.sessionExerciseId);
    assert.equal(old.length,2);assert(old.every(s=>s.isCompleted && s.restStartedAt===null));
    assert.equal(old[1].weight,41.25);assert.equal(old[1].reps,6);
  });
  await check('retained hidden exercise remains editable after replacement',async()=>{
    await editFirst('40','7');
    const {data}=await snapshot('09-hidden-edit');
    assert.equal(data.data.sets.filter(s=>s.isCompleted && s.reps===7).length,1);
  });
  await check('favorite is independent from selection and search covers all actions',async()=>{
    await clickText('添加动作');await clickText('全部',true);
    await clickText('搜索动作');await replaceText('卧推');await clickText('收藏 卧推',true);
    await expectText('添加 0 个动作');await clickText('常用',true);
    await search('深蹲');await clickText('添加 1 个动作',true);await expectText('完成这组');
    baseline=await snapshot('10-favorite');
    assert(baseline.data.data.exercisePreferences.some(p=>p.isFavorite));
    await clickText('深蹲',true);await expectText('完成这组');
  });
  await check('small landscape viewport keeps primary action reachable by scrolling',async()=>{
    await send('Emulation.setDeviceMetricsOverride',{width:640,height:360,deviceScaleFactor:1,mobile:true});
    await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:320,y:220,deltaY:700,deltaX:0});await delay(500);
    await expectText('完成这组');
    const primary=(await h.semantics()).find(e=>e.text==='✓ 完成这组' && e.role==='button');
    assert(primary && primary.y>=0 && primary.y+primary.height<=360,'landscape primary button must be on screen after scrolling');
    await clickAt(primary.x+primary.width/2,primary.y+primary.height/2);await expectText('下一组重量');
    await h.screenshot('11-landscape');
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await clickText('Back');baseline=await h.exportFile('11-v5-baseline');
  });
  await check('real v5 file restores into isolated origin and survives restart field-for-field',async()=>{
    await send('Page.navigate',{url:h.origin.replace('127.0.0.1','localhost')});
    await h.restoreFile(baseline.file);
    assert.deepEqual((await h.exportFile('12-roundtrip')).data.data,baseline.data.data);
    await send('Page.reload');
    assert.deepEqual((await h.exportFile('13-reloaded')).data.data,baseline.data.data);
  });
  await check('bad v5 refuses writes; legacy v1/v2 clear new preferences',async()=>{
    const bad=structuredClone(baseline.data);bad.data.exercisePreferences[0].exerciseId='missing';
    const file=path.join(h.output,'bad-v5.json');await writeFile(file,JSON.stringify(bad));
    // Upload to the real restore picker and assert rejection without confirmation.
    await h.selectFile(file);await expectText('找不到对应');
    assert.deepEqual((await h.exportFile('14-bad-unchanged')).data.data,baseline.data.data);
    for(const name of ['legacy-v1','legacy-v2']) {
      const legacy=path.join(h.root,'test','fixtures','backup',name+'.json');
      const expected=JSON.parse(await readFile(legacy,'utf8'));
      await h.restoreFile(legacy);const {data}=await h.exportFile('15-'+name);
      assert.deepEqual(data.data.exercisePreferences,[]);
      assert.equal(data.data.sessions.length,expected.data.sessions.length);
    }
  });
}
if(process.argv[1] && path.resolve(process.argv[1]).toLowerCase()===fileURLToPath(import.meta.url).toLowerCase()) {
  process.env.GYM_BROWSER_FEATURE='workout_efficiency';
  import('./browser_backup_smoke.mjs').catch(error=>{console.error(error);process.exitCode=1;});
}
