import assert from 'node:assert/strict';
import path from 'node:path';
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

export async function run(h) {
  const {check,clickText,expectText,send}=h;
  async function navigate(route='/') { await send('Page.navigate',{url:h.origin+'/#'+route}); await delay(500); }
  async function reveal(text,exact=true) {
    for(let i=0;i<30;i++) {
      const height=await h.evaluate('innerHeight');
      const item=(await h.semantics()).filter(e=>exact?e.text===text:e.text.includes(text)).sort((a,b)=>a.width*a.height-b.width*b.height)[0];
      if(item && item.y>55 && item.y+item.height<height-5) return clickText(text,exact);
      await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:180,y:height-150,deltaX:0,deltaY:item?.y<55?-300:300}); await delay(150);
    }
    throw new Error('Cannot reveal '+text);
  }
  async function drag(label,dx,dy) {
    const item=await h.until(async()=>(await h.semantics()).find(e=>e.role==='slider'&&e.text===label),label);
    const x=item.x+item.width/2,y=item.y+item.height/2;
    await send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});
    for(let i=1;i<=8;i++) { await send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:x+dx*i/8,y:y+dy*i/8}]}); await delay(20); }
    await send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]}); await delay(300);
  }
  async function value(label) { return (await h.semantics()).find(e=>e.role==='slider'&&e.text===label)?.value; }
  async function raiseWeight() {
    const item=(await h.semantics()).find(e=>e.role==='slider'&&e.text==='重量');
    await h.evaluate(`(()=>{const e=document.getElementById(${JSON.stringify(item.id)});(e.querySelector('input')||e).focus();})()`);
    for(let i=0;i<2;i++) {
      await send('Input.dispatchKeyEvent',{type:'keyDown',key:'ArrowUp',code:'ArrowUp',windowsVirtualKeyCode:38});
      await send('Input.dispatchKeyEvent',{type:'keyUp',key:'ArrowUp',code:'ArrowUp',windowsVirtualKeyCode:38});
      await delay(200);
    }
  }
  async function snapshot(label) { await navigate(); await expectText('管理计划'); return h.exportFile(label); }
  let clean,kaitan,sid,seid,pid;
  if (process.env.GYM_BUILTIN_FIXTURE) {
    const file=path.resolve(process.env.GYM_BUILTIN_FIXTURE);
    clean={file,data:JSON.parse(await readFile(file,'utf8'))};
    kaitan=clean.data.data.plans.find(p=>p.name.startsWith('凯'));
    await h.restoreFile(file);
  } else {
  await check('fresh users see all 71 exercises and stable catalog bindings without importing',async()=>{
    const {data}=await h.exportFile('01-library');
    assert.equal(data.version,7); assert.equal(data.schemaVersion,11);
    assert.equal(data.data.exercises.length,71); assert.equal(data.data.catalogBindings.length,71);
    assert(data.data.exercises.some(e=>e.name==='高脚杯深蹲'));
    assert(data.data.exercises.some(e=>e.name==='器械辅助引体向上'));
  });
  for(const name of ['凯谭三分化 · 整理参考版','StrongLifts 5×5','PHUL · 上下肢四日']) {
    await check('preview and import '+name,async()=>{
      await navigate(); await expectText('管理计划'); await clickText('管理计划'); await clickText('内置计划',true);
      await clickText(name); await expectText('复制来源链接');
      await h.screenshot('preview-'+(name.startsWith('凯')?'kaitan':name.startsWith('PHUL')?'phul':'5x5'));
      await reveal('导入为我的计划'); await expectText('内置计划');
    });
  }
  await check('all presets retain independent cycles, editable stages and source attribution',async()=>{
    clean=await snapshot('02-all-presets'); const d=clean.data.data;
    assert.equal(d.plans.length,3); kaitan=d.plans.find(p=>p.name.startsWith('凯'));
    for(const [prefix,days,stages] of [['凯',4,11],['Strong',14,1],['PHUL',7,1]]) {
      const p=d.plans.find(p=>p.name.startsWith(prefix)); assert.equal(d.templates.filter(t=>t.planId===p.id).length,days);
      const program=JSON.parse(d.programs.find(r=>r.id===p.id).payload); assert.equal(program.stages.length,stages); assert(program.sourceUrl.startsWith('https://'));
    }
  });
  }
  await check('live plan starts with separate target feedback and durable rest-pause first segment',async()=>{
    await navigate(); await clickText('开始训练',true); await expectText('热身');
    // Reveal the final exercise in the real horizontal exercise strip.
    for(let i=0;i<7;i++) {
      const chip=(await h.semantics()).find(e=>e.text==='绳索 Y 字侧平举'&&e.y<145&&e.x>=0&&e.x+e.width<390);
      if(chip) { await h.evaluate(`document.getElementById(${JSON.stringify(chip.id)}).click()`); await delay(500); break; }
      await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:200,y:80,deltaX:250,deltaY:0}); await delay(300);
    }
    await expectText('完成第 1 段'); await clickText('RPE · 选填'); await reveal('RPE 8',false);
    await clickText('完成第 1 段'); await expectText('开始第 2 段');
    const {data}=await snapshot('03-partial'); const d=data.data;
    sid=d.sessions.find(s=>s.finishedAt===null).id;
    const row=d.setDetails.find(r=>JSON.parse(r.payload).firstCompletedAt!==null);
    pid=row.id; seid=d.sets.find(s=>s.id===pid).sessionExerciseId;
    const detail=JSON.parse(row.payload); assert.equal(detail.effort.value,8); assert.equal(detail.continuations.length,0);
    assert.equal(d.sets.find(s=>s.id===pid).isCompleted,false);
  });
  await check('manual stage change leaves active snapshots and natural-day activation intact',async()=>{
    const before=(await h.exportFile('04-before-stage')).data.data;
    await navigate('/plans/'+kaitan.id+'/program'); await expectText('进入下一阶段'); await clickText('进入下一阶段'); await expectText('当前执行：第 2 周');
    const after=(await snapshot('04-after-stage')).data.data;
    assert.deepEqual(after.prescriptions,before.prescriptions);
    assert.equal(after.plans.find(p=>p.id===kaitan.id).activatedOn,before.plans.find(p=>p.id===kaitan.id).activatedOn);
    assert.equal(JSON.parse(after.programs.find(p=>p.id===kaitan.id).payload).currentStageId,'stage-2');
  });
  await check('reload resumes the partially performed exercise and separates pause from execution',async()=>{
    await navigate(); await clickText('继续训练',true); await expectText('开始第 2 段'); await expectText('绳索 Y 字侧平举');
    await clickText('开始第 2 段'); await expectText('本段进行中'); await drag('重量',0,-32); await delay(1100);
    await clickText('完成第 2 段'); await expectText('开始第 2 组'); await clickText('结束训练'); await expectText('10+10');
    await h.screenshot('05-segment-summary'); await clickText('完成',true);
    const d=(await h.exportFile('05-segment-complete')).data.data;
    const set=d.sets.find(s=>s.id===pid), detail=JSON.parse(d.setDetails.find(r=>r.id===pid).payload);
    assert.equal(set.reps,10); assert.equal(detail.continuations[0].reps,10); assert.equal(detail.continuations[0].weight,'25');
    assert.equal(detail.segmentStartedAt,null); assert.equal(detail.intraRestStartedAt,null);
    assert.equal(d.sets.filter(s=>s.isCompleted).length,1);
  });
  let csv;
  await check('CSV exports separate physical segments and imports back as one logical group',async()=>{
    csv=await h.downloadCsv(); assert(csv.text.includes('segment_index')); assert(csv.text.includes(',2,'));
    await h.restoreFile(clean.file);
    await clickText('历史',true); await clickText('记录操作'); await clickText('导入 CSV'); await h.upload(csv.file);
    await expectText('1 场候选'); await reveal('追加 1 场训练'); await expectText('已导入 1 场');
    const d=(await snapshot('06-csv-imported')).data.data;
    assert.equal(d.sessions.length,1); assert.equal(d.sets.length,1);
    const detail=JSON.parse(d.setDetails[0].payload); assert.equal(detail.continuations.length,1); assert.equal(detail.effort.value,8);
  });
  await check('historical feedback edits preserve the immutable target and all continuation values',async()=>{
    const before=(await h.exportFile('07-before-edit')).data.data;
    await navigate('/history/'+before.sessions[0].id); await expectText('原目标：'); await reveal('第 1 组 ·',false);
    await clickText('RPE 8',true); await reveal('RPE 9.5',false); await reveal('保存');
    const after=(await snapshot('07-history-edited')).data.data;
    const old=JSON.parse(before.setDetails[0].payload), updated=JSON.parse(after.setDetails[0].payload);
    assert.equal(updated.effort.value,9.5); assert.deepEqual(updated.target,old.target); assert.deepEqual(updated.continuations,old.continuations);
  });
  await check('history-derived lb reference requires adoption and preserves draft REP and RPE',async()=>{
    const fixture=structuredClone(clean.data), d=fixture.data;
    const exercise=d.exercises.find(e=>e.name==='卧推'&&e.equipment==='杠铃').id;
    const now=Date.now();
    for(let i=1;i<=3;i++) {
      d.sessions.push({id:'history-'+i,name:'重量依据',startedAt:now-i*86400000,finishedAt:now-i*86400000+600000,note:null,templateId:null,planId:null,planNameSnapshot:null,dayNameSnapshot:null,origin:'manual'});
      d.sessionExercises.push({id:'history-e-'+i,sessionId:'history-'+i,exerciseId:exercise,position:0,note:null});
      d.sets.push({id:'history-s-'+i,sessionExerciseId:'history-e-'+i,position:0,weight:22.6796185,reps:12,isCompleted:true,restSeconds:null,restStartedAt:null,completedAt:now-i*86400000+500000,sourceWeight:'50',sourceUnit:'lb'});
      d.setDetails.push({id:'history-s-'+i,payload:JSON.stringify({version:1,role:'work',effort:{kind:'rpe',value:8,maxValue:null,bound:'exact'},target:null,targetIndex:null,firstCompletedAt:null,intraRestStartedAt:null,segmentStartedAt:null,continuations:[],endedEarly:false,reference:null,pendingWeight:null,pendingUnit:null})});
    }
    d.exercisePreferences.push({exerciseId:exercise,weightUnit:'lb',kgStep:'2.5',lbStep:'5',showKgEquivalent:true,isFavorite:false,equipmentNote:''});
    const file=path.join(h.output,'personal-reference-fixture.json'); await writeFile(file,JSON.stringify(fixture)); await h.restoreFile(file);
    await clickText('开始训练',true); await expectText('50 lb'); await clickText('完成这组'); await clickText('开始第 2 组');
    await expectText('参考 50 lb'); await delay(700); await raiseWeight(); assert.equal(await value('重量'),'60 lb'); await drag('次数',48,0);
    await clickText('RPE · 选填'); await reveal('RPE 9.5',false);
    assert.equal(await value('重量'),'60 lb');
    await clickText('采用',true); await h.until(async()=>await value('重量')==='50 lb','adopted reference');
    await expectText('RPE 9.5');
    await h.screenshot('08-reference-adopted'); await clickText('完成这组');
    const after=(await snapshot('08-reference-recorded')).data.data;
    const actual=after.sets.find(s=>s.isCompleted&&s.reps===14);
    assert(actual); assert.equal(actual.sourceWeight,'50'); assert.equal(actual.sourceUnit,'lb');
    const detail=JSON.parse(after.setDetails.find(r=>r.id===actual.id).payload); assert.equal(detail.effort.value,9.5); assert(detail.reference.includes('personal-v1'));
  });
  await check('desktop and narrow landscape render saved programs without runtime exceptions',async()=>{
    for(const [width,height] of [[1280,800],[360,640],[640,360]]) {
      await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<1000});
      await navigate('/plans/'+kaitan.id+'/program'); await expectText('组次与阶段'); await h.screenshot('viewport-'+width+'x'+height);
    }
  });
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE='builtin_programs';
  import('./browser_backup_smoke.mjs').catch(e=>{console.error(e);process.exitCode=1;});
}
