import assert from 'node:assert/strict';
import path from 'node:path';
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

export async function run(h) {
  const {check,send,evaluate,expectText,clickText} = h;
  async function navigate(route='/calories') {
    await send('Page.navigate',{url:h.origin+'/#'+route});
    await h.until(()=>h.has('训练'),'main navigation');
    if(route === '/calories') await clickText('热量',true);
    await expectText(route === '/calories' ? '已记录饮料热量' : '开始训练');
  }
  async function reveal(text,exact=false) {
    for (let i=0;i<40;i++) {
      const height=await evaluate('innerHeight');
      const nodes=await h.semantics();
      const bottom=nodes.some(e=>e.text==='进步'&&e.y>height-100)?height-80:height;
      const item=nodes.filter(e=>exact?e.text===text:e.text.includes(text)).sort((a,b)=>a.width*a.height-b.width*b.height)[0];
      if(item && item.y>55 && item.y+item.height<bottom-5) return item;
      await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:200,y:height-160,deltaX:0,deltaY:item?.y<55?-240:250});
      await delay(150);
    }
    throw Error('Cannot reveal '+text);
  }
  async function press(text,exact=true) {await reveal(text,exact);await clickText(text,exact);}
  async function backToCalories() {
    for(let i=0;i<5&&!await h.has('已记录饮料热量');i++) {await clickText('Back',true);await delay(500);}
    await expectText('已记录饮料热量');
  }
  async function fill(label,text) {
    const item=await reveal(label);
    await h.clickAt(item.x+item.width/2,item.y+item.height/2);
    await send('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
    await send('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',modifiers:2,windowsVirtualKeyCode:65});
    await send('Input.insertText',{text});
    await delay(150);
  }
  if(process.argv.includes('--label-only')) {
    await check('actual Open Food Facts package photo enters local OCR review',async()=>{
      const source='https://images.openfoodfacts.org/images/products/489/000/810/1306/nutrition_fr.5.400.jpg';
      const response=await fetch(source,{signal:AbortSignal.timeout(25000)});assert(response.ok);
      const file=path.join(h.output,'actual-package-label.jpg');await writeFile(file,Buffer.from(await response.arrayBuffer()));
      await navigate();await press('记录饮料');await press('手动添加');
      await evaluate(`(()=>{window.ocrEvidence=[];const scan=gymBeverage.scan.bind(gymBeverage);gymBeverage.scan=async camera=>{const start=performance.now();const result=await scan(camera);ocrEvidence.push({elapsedMs:performance.now()-start,text:JSON.parse(result)?.text});return result;};return true})()`);
      await h.chooseImage('导入标签图片',file);await h.until(()=>evaluate('ocrEvidence.length>0'),'actual local photo OCR',120000);await delay(500);
      const evidence=await evaluate('ocrEvidence');assert(evidence[0].text?.trim());
      await writeFile(path.join(h.output,'actual-photo-ocr.json'),JSON.stringify({source,evidence},null,2));
      await h.screenshot('actual-photo-review');
      await backToCalories();const data=await h.exportFile('cancel-actual-photo');assert.equal(data.data.data.beverages.length,0);assert.equal(data.data.data.drinkRecords.length,0);
    });
    return;
  }
  let baseline;
  await check('five navigation labels and empty beverage state at 360px',async()=>{
    await send('Emulation.setDeviceMetricsOverride',{width:360,height:800,deviceScaleFactor:1,mobile:true});
    await navigate();
    for(const label of ['训练','热量','动作分析','历史','进步']) assert(await h.has(label));
    await expectText('尚未记录'); await h.screenshot('01-empty');
  });
  await check('manual drink review -> half serving -> immutable SQLite record',async()=>{
    await press('记录饮料'); await press('手动添加');
    await fill('饮料名称','可乐验收样例');
    await fill('每份体积','330'); await fill('标注能量','42');
    await press('确认资料'); await press('0.5 份'); await expectText('69.3');
    await press('保存记录'); await expectText('69.3 kcal');
    await h.screenshot('02-recorded');
    baseline=await h.exportFile('beverage-v7');
    assert.equal(baseline.data.version,7); assert.equal(baseline.data.schemaVersion,11);
    assert.equal(baseline.data.data.beverages.length,1); assert.equal(baseline.data.data.drinkRecords.length,1);
    const record=JSON.parse(baseline.data.data.drinkRecords[0].payload);
    assert.equal(record.amount,'0.5');assert.equal(record.calories,'693/10');assert.equal(record.snapshot.energyValue,'42');
  });
  await check('reload preserves exact backup snapshot and settings has fallback return',async()=>{
    await send('Page.reload');await h.until(()=>h.has('训练'),'app after reload');
    await navigate();
    const reloaded=await h.exportFile('beverage-reload');
    assert.deepEqual(reloaded.data.data,baseline.data.data);
    await clickText('Back',true);await expectText('已记录饮料热量');
    await expectText('69.3 kcal');
  });
  await check('7 and 30 day trends distinguish missing dates',async()=>{
    await press('7 / 30 天趋势');await expectText('区间已知合计');await expectText('尚未记录');
    await press('近 30 天');await h.screenshot('03-trends-30');await clickText('Back',true);
  });
  await check('local Chinese OCR image input reaches review and cancel never persists',async()=>{
    await evaluate(`(()=>{window.ocrEvidence=[];const scan=gymBeverage.scan.bind(gymBeverage);gymBeverage.scan=async camera=>{const start=performance.now();const result=await scan(camera);const data=JSON.parse(result);ocrEvidence.push({elapsedMs:performance.now()-start,text:data?.text??null});return result;};return true})()`);
    const png=await evaluate(`(()=>{const c=document.createElement('canvas');c.width=1300;c.height=740;const x=c.getContext('2d');x.fillStyle='white';x.fillRect(0,0,c.width,c.height);x.fillStyle='black';x.font='64px "Microsoft YaHei", sans-serif';['可口可乐','营养成分表','每100毫升','能量 180 kJ','净含量 330 mL'].forEach((s,i)=>x.fillText(s,60,100+i*125));return c.toDataURL('image/png').split(',')[1]})()`);
    const file=path.join(h.output,'controlled-label.png');await writeFile(file,Buffer.from(png,'base64'));
    await press('记录饮料');await press('手动添加');
    await h.chooseImage('导入标签图片',file);
    await h.until(()=>h.has('已提取标签文字'),'real local OCR result',120000);
    await h.screenshot('04-local-ocr');
    const energyField=await reveal('标注能量');
    await h.clickAt(energyField.x+energyField.width/2,energyField.y+energyField.height/2);
    const values=await evaluate(`Array.from(document.querySelectorAll('input,textarea')).map(e=>({label:e.getAttribute('aria-label'),value:e.value}))`);
    await writeFile(path.join(h.output,'ocr-fields.json'),JSON.stringify(values,null,2));
    assert(values.some(v=>v.value==='180'),JSON.stringify(values));
    for (const variant of ['rotated','small','glare']) {
      const variantPng=await evaluate(`(async()=>{const bitmap=await createImageBitmap(await(await fetch('data:image/png;base64,${png}')).blob());const c=document.createElement('canvas');c.width=${variant==='rotated'?740:variant==='small'?390:1300};c.height=${variant==='rotated'?1300:variant==='small'?222:740};const x=c.getContext('2d');x.fillStyle='white';x.fillRect(0,0,c.width,c.height);${variant==='rotated'?'x.translate(c.width,0);x.rotate(Math.PI/2);x.drawImage(bitmap,0,0);':'x.drawImage(bitmap,0,0,c.width,c.height);'}${variant==='glare'?'const g=x.createLinearGradient(0,0,900,0);g.addColorStop(0,"rgba(255,255,255,0)");g.addColorStop(.45,"rgba(255,255,255,.95)");g.addColorStop(1,"rgba(255,255,255,0)");x.fillStyle=g;x.fillRect(0,280,1100,310);':''}bitmap.close();return c.toDataURL('image/png').split(',')[1]})()`);
      const variantFile=path.join(h.output,`controlled-label-${variant}.png`);await writeFile(variantFile,Buffer.from(variantPng,'base64'));
      await reveal('导入标签图片',true);const count=await evaluate('ocrEvidence.length');
      await h.chooseImage('导入标签图片',variantFile);await h.until(()=>evaluate(`ocrEvidence.length>${count}`),'OCR '+variant,120000);await delay(300);
      await h.screenshot('ocr-'+variant);
    }
    await writeFile(path.join(h.output,'ocr-evidence.json'),JSON.stringify(await evaluate('ocrEvidence'),null,2));
    await backToCalories();
    const after=await h.exportFile('after-cancel-ocr');assert.deepEqual(after.data.data,baseline.data.data);
  });
  await check('offline recording and explicit zero survive a real JSON roundtrip',async()=>{
    await navigate();
    await send('Network.enable');await send('Network.emulateNetworkConditions',{offline:true,latency:0,downloadThroughput:-1,uploadThroughput:-1});
    await press('记录饮料');await press('手动添加');
    await fill('饮料名称','无糖验收样例');await fill('每份体积','500');await fill('标注能量','0');
    await press('确认资料');await press('保存记录');
    await expectText('69.3 kcal');
    await send('Network.emulateNetworkConditions',{offline:false,latency:0,downloadThroughput:-1,uploadThroughput:-1});
    const data=await h.exportFile('offline-zero');
    assert.equal(data.data.data.drinkRecords.length,2);
    assert(data.data.data.drinkRecords.some(r=>JSON.parse(r.payload).calories==='0/1'));
    await h.restoreFile(data.file);const restored=await h.exportFile('restored-v7');assert.deepEqual(restored.data.data,data.data.data);
  });
  await check('legacy restore preview preserves beverages and current history',async()=>{
    const before=await h.exportFile('before-old-restore');
    const old=structuredClone(before.data);old.version=6;old.schemaVersion=8;delete old.data.beverages;delete old.data.drinkRecords;
    const file=path.join(h.output,'legacy-v6.json');await writeFile(file,JSON.stringify(old));
    await h.selectFile(file);await expectText('旧备份没有饮料数据');await clickText('替换并恢复',true);await expectText('开始训练');
    const after=await h.exportFile('after-old-restore');assert.deepEqual(after.data.data.beverages,before.data.data.beverages);assert.deepEqual(after.data.data.drinkRecords,before.data.data.drinkRecords);
  });
  await check('real OFF CORS search and product details, or explicit external unavailability',async()=>{
    // This check records the live service response; unit tests separately assert
    // failure/timeout UI. Never substitute fabricated public results.
    const result=await evaluate(`(async()=>{const results=await Promise.allSettled(['https://search.openfoodfacts.org/search?q=coca%20cola&page_size=3','https://search.openfoodfacts.org/search?q=%E5%8F%AF%E4%B9%90&page_size=3','https://world.openfoodfacts.org/api/v2/product/4890008101306?fields=code,product_name,quantity,serving_size,nutriments,image_nutrition_url'].map(async u=>JSON.parse(await gymBeverage.get(u))));const [s,c,p]=results.map(r=>r.status==='fulfilled'?r.value:null);return {available:!!s?.hits,cola:s?.hits?.map(p=>({code:p.code,name:p.product_name,quantity:p.quantity})),chinese:c?.hits?.length,product:p?.product,errors:results.map(r=>r.status==='rejected'?String(r.reason):null)};})()`);
    await writeFile(path.join(h.output,'real-off.json'),JSON.stringify(result,null,2));
    if(result.available) {
      assert(result.cola?.length>0);
      const url=result.product?.image_nutrition_url;
      if(url && new URL(url).hostname==='images.openfoodfacts.org') {
        try {
          const response=await fetch(url,{signal:AbortSignal.timeout(20000)});assert(response.ok);
          const file=path.join(h.output,'off-4890008101306-label.jpg');await writeFile(file,Buffer.from(await response.arrayBuffer()));
          await navigate();await press('记录饮料');await press('手动添加');
          await evaluate(`(()=>{window.ocrEvidence=[];const scan=gymBeverage.scan.bind(gymBeverage);gymBeverage.scan=async camera=>{const start=performance.now();const result=await scan(camera);const data=JSON.parse(result);ocrEvidence.push({elapsedMs:performance.now()-start,text:data?.text??null});return result;};return true})()`);
          await h.chooseImage('导入标签图片',file);
          await h.until(()=>h.has('已提取标签文字')||h.has('未能确定唯一')||h.has('检测到每 100 g'),'real product label OCR',120000);
          await h.screenshot('06-real-product-label');
          const raw=await evaluate('ocrEvidence?.slice(-1)??[]');await writeFile(path.join(h.output,'real-label-ocr.json'),JSON.stringify({source:url,raw},null,2));
          await backToCalories();
        } catch(error) {await writeFile(path.join(h.output,'real-label-unavailable.txt'),String(error));}
      }
    } else console.log('External OFF unavailable: '+JSON.stringify(result.errors));
  });
  await check('narrow landscape calories, settings return and reduced motion',async()=>{
    await navigate();
    await send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
    await send('Emulation.setDeviceMetricsOverride',{width:640,height:360,deviceScaleFactor:1,mobile:true});
    await h.screenshot('05-landscape');
    await clickText('设置',true);await clickText('Back',true);await expectText('已记录饮料热量');
  });
  await check('training record, history, progress and analysis remain usable',async()=>{
    await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await clickText('训练',true);await press('开始训练');await press('添加动作');
    await fill('搜索动作','深蹲');await press('深蹲',false);await press('添加 1 个动作');
    await clickText('完成这组');await clickText('结束训练');await expectText('160');await press('完成');
    await clickText('历史',true);await expectText('未命名训练');
    await clickText('进步',true);await expectText('深蹲');
    await clickText('动作分析',true);await expectText('看见每一次动作');
    await clickText('热量',true);await expectText('69.3 kcal');
    await h.screenshot('07-regression-complete');
  });
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE='calories';import('./browser_backup_smoke.mjs').catch(error=>{console.error(error);process.exitCode=1;});
}
