import assert from 'node:assert/strict';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

export async function run(h) {
  const {check,clickText,expectText,send,semantics}=h;
  const today=new Date();
  const key=[today.getFullYear(),String(today.getMonth()+1).padStart(2,'0'),String(today.getDate()).padStart(2,'0')].join('-');
  const dateLabel=`${today.getFullYear()}年${today.getMonth()+1}月${today.getDate()}日`;
  async function visibleClick(text,exact=true) {
    for(let attempt=0;attempt<10;attempt++) {
      const height=await h.evaluate('window.innerHeight');
      const nodes=await semantics();
      const bottom=nodes.some(e=>e.text==='进步'&&e.y>height-100)?height-80:height;
      const element=nodes.filter(e=>exact?e.text===text:e.text.includes(text)).sort((a,b)=>a.width*a.height-b.width*b.height)[0];
      if(element && element.y>40 && element.y+element.height<bottom-5) {await clickText(text,exact);return;}
      await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:180,y:Math.max(80,Math.min(650,height-140)),deltaX:0,deltaY:element?.y<40?-300:180});await delay(250);
    }
    throw new Error(`Cannot reveal ${text}`);
  }
  async function slider(label) {return h.until(async()=>(await semantics()).find(e=>e.role==='slider'&&e.text===label),label+' slider');}
  async function drag(label,dx,dy) {
    const e=await slider(label), x=e.x+e.width/2,y=e.y+e.height/2;
    await send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});
    for(let i=1;i<=8;i++){await send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:x+dx*i/8,y:y+dy*i/8}]});await delay(35);}
    await send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await delay(350);
  }
  async function values(weight,reps) {
    await h.until(async()=>{
      const w=await slider('重量'), r=await slider('次数');
      return w.value===weight&&r.value===String(reps);
    },`native controls ${weight} x ${reps}`);
  }
  await check('month navigation and start action remain centered at portrait size',async()=>{
    await expectText(`${today.getFullYear()}年${today.getMonth()+1}月`);
    const start=(await semantics()).find(e=>e.text==='开始训练'&&e.role==='button');
    assert(start);assert(Math.abs(start.y+start.height/2-(844-80)/2)<45,JSON.stringify(start));
    await h.tapText('上个月');await expectText('回到本月');await h.tapText('回到本月');
    await expectText(`${today.getFullYear()}年${today.getMonth()+1}月`);
    assert(!(await h.has('新建计划')));await h.screenshot('01-centered-home');
  });
  await check('calendar empty date opens unified history and prefills manual date',async()=>{
    await clickText(dateLabel);await expectText(`所选日期：${key}`);await expectText('当天没有训练记录');
    await clickText('补加',true);await expectText('手动补记录');
    await clickText('开始时间',true);
    const values=await h.evaluate(`Array.from(document.querySelectorAll('input,textarea')).map(e=>e.value)`);
    assert(values.some(value=>value.startsWith(key)),JSON.stringify(values));
    await clickText('Back');await expectText(`所选日期：${key}`);await clickText('训练',true);
  });
  await check('free training starts with equipment-native default and no plus-minus buttons',async()=>{
    await clickText('开始训练',true);await clickText('添加动作',true);
    await h.until(()=>h.has('胸'),'exercise catalog');await h.clickAt(100,166);
    await send('Input.insertText',{text:'深蹲'});await clickText('深蹲');await clickText('添加 1 个动作',true);
    await values('20 kg',8);assert(!(await h.has('增加')));assert(!(await h.has('减少')));
  });
  await check('weight gesture ignores horizontal drift and retains repetition count',async()=>{
    await drag('重量',80,-32);await values('25 kg',8);await h.screenshot('02-weight-diagonal');
  });
  await check('repetition gesture ignores vertical drift and crossing into weight region',async()=>{
    await drag('次数',48,-80);await values('25 kg',10);
    await drag('次数',-48,0);await values('25 kg',8);
  });
  await check('explicit step and unit selector cancel leaves values unchanged',async()=>{
    await clickText('幅度 2.5 kg');await clickText('lb',true);await clickText('10 lb',true);
    await visibleClick('取消');await values('25 kg',8);await expectText('幅度 2.5 kg');
  });
  await check('unit confirmation preserves equipment number and optional kg reference',async()=>{
    await clickText('幅度 2.5 kg');await clickText('lb',true);await clickText('10 lb',true);
    await visibleClick('同时显示换算后的 kg');await visibleClick('保存');
    await values('25 lb',8);await expectText('11.34 kg');await expectText('幅度 10 lb');
  });
  await check('pounds use explicit selected step and show integer equipment readings',async()=>{
    await drag('重量',0,-16);await values('35 lb',8);
    await clickText('幅度 10 lb');await clickText('5 lb',true);await visibleClick('保存');
    await drag('重量',0,-48);await values('50 lb',8);await expectText('22.68 kg');
    await clickText('幅度 5 lb');await clickText('2.5 lb',true);await visibleClick('保存');
    await drag('重量',0,-16);await values('52.5 lb',8);
    await drag('重量',0,16);await values('50 lb',8);
    await h.screenshot('03-native-pounds');
  });
  await check('completed set persists original pounds and canonical kilograms',async()=>{
    await clickText('完成这组');await expectText('开始第 2 组');
    await drag('重量',0,-16);
    await clickText('Back');await send('Page.reload');
    await clickText('继续训练',true);await expectText('开始第 2 组');
    await h.until(async()=>(await slider('重量')).value==='52.5 lb','pending reading survives reload');
    await clickText('动作设置',true);await clickText('5 lb',true);await visibleClick('保存');
    await clickText('结束训练');
    await expectText('50 lb');await clickText('完成',true);
    const backup=await h.exportFile('native-pounds');
    assert.equal(backup.data.version,8);assert.equal(backup.data.schemaVersion,12);
    const set=backup.data.data.sets.find(s=>s.isCompleted);
    assert.equal(set.sourceWeight,'50');assert.equal(set.sourceUnit,'lb');assert.equal(set.weight,22.6796185);
  });
  await check('calendar completion mark and date history show recorded unit',async()=>{
    await clickText('训练',true);await expectText(`${dateLabel}，今天，有已完成训练`);
    await clickText(dateLabel);await expectText(`所选日期：${key}`);await clickText('未命名训练');
    await expectText('50 lb');await clickText('Back');await expectText(`所选日期：${key}`);
  });
  await check('real CSV download retains source pounds and unrounded canonical weight',async()=>{
    const csv=await h.downloadCsv();
    assert(csv.text.includes('weight_unit,weight_kg'));assert(csv.text.includes(',50,lb,22.6796185,8'));
  });
  await check('reload and backup restore retain native readings and per-unit preferences',async()=>{
    const before=await h.exportFile('before-reload');await send('Page.reload');
    const after=await h.exportFile('after-reload');assert.deepEqual(after.data.data,before.data.data);
    await h.restoreFile(before.file);const restored=await h.exportFile('after-native-restore');
    assert.deepEqual(restored.data.data,before.data.data);
    const prefs=restored.data.data.exercisePreferences[0];assert.equal(prefs.weightUnit,'lb');assert.equal(prefs.kgStep,'2.5');assert.equal(prefs.lbStep,'5');assert.equal(prefs.showKgEquivalent,true);
  });
  await check('narrow and landscape layouts keep start and plan management reachable',async()=>{
    await clickText('训练',true);
    for(const [width,height] of [[360,740],[640,360]]) {
      await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:true});await delay(500);
      await expectText('开始训练');await visibleClick('管理计划');
      if(!(await h.has('新建计划'))) await h.tapText('管理计划');
      await expectText('新建计划');
      await clickText('Back');await h.screenshot(`viewport-${width}x${height}`);
    }
  });
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE='training_redesign';import('./browser_backup_smoke.mjs').catch(error=>{console.error(error);process.exitCode=1;});
}
