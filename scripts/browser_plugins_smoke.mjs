import assert from 'node:assert/strict';
import path from 'node:path';
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {enableBundledPlugins} from './browser_plugin_helpers.mjs';

export async function run(h) {
  const {send,evaluate,expectText,clickText,check}=h;
  async function navigate(route='/') {
    await send('Page.navigate',{url:h.origin+'/#'+route});
    await h.until(()=>h.has(route==='/settings/plugins'?'插件管理':'训练'),'page ready');
  }
  async function toggle(name) {
    const element=await h.until(async()=>{
      const rows=await h.semantics();
      return rows.filter(row=>row.text.startsWith(name)&&!row.disabled).sort((a,b)=>a.width*a.height-b.width*b.height)[0];
    },'plugin switch '+name);
    await h.clickAt(element.x+element.width/2,element.y+element.height/2);
  }
  await check('fresh install has three destinations and loads no optional runtime',async()=>{
    await navigate();await expectText('开始训练');
    for(const label of ['训练','历史','进步']) assert(await h.has(label));
    assert(!await h.has('热量'));assert(!await h.has('动作分析'));
    const resources=await evaluate(`performance.getEntriesByType('resource').map(r=>r.name).filter(n=>n.includes('/motion/') || n.includes('/beverage/'))`);
    assert.deepEqual(resources,[]);
    assert.equal(await evaluate('!!window.gymMotion || !!window.gymBeverage'),false);
    await h.screenshot('01-fresh-three');
  });
  await check('disabled deep link is guarded; enable does not initialize OCR',async()=>{
    await send('Page.navigate',{url:h.origin+'/#/calories'});
    await expectText('此功能尚未启用');
    assert.equal(await evaluate('!!window.gymBeverage'),false);
    await clickText('启用并继续',true);await expectText('已记录饮料热量');
    assert.equal(await evaluate('!!window.gymBeverage'),false);
    await h.screenshot('02-calories-enabled');
  });
  let imported;
  await check('unknown plugin backup round trip while calories is disabled',async()=>{
    imported=(await h.exportFile('baseline')).data;
    assert.equal(imported.version,8);assert.equal(imported.schemaVersion,12);
    imported.plugins={'community.example':{dataVersion:3,records:[{key:'preferences',value:{name:'示例',amount:12,nullable:null,nested:[true,{value:'保留'}]}}]}};
    const file=path.join(h.output,'unknown-plugin-v8.json');
    await writeFile(file,JSON.stringify(imported));await h.restoreFile(file);
    await navigate('/settings/plugins');await toggle('饮料热量');
    await send('Page.reload');await expectText('插件管理');
    await navigate();assert(!await h.has('热量'));
    const exported=(await h.exportFile('unknown-disabled-roundtrip')).data;
    assert.deepEqual(exported.plugins,imported.plugins);
    await h.screenshot('03-disabled-backup');
  });
  await check('legacy review links remain guarded and motion can stop and restart',async()=>{
    await send('Page.navigate',{url:h.origin+'/#/review/test-set'});await expectText('此功能尚未启用');
    await enableBundledPlugins(h,['/analysis']);
    await navigate('/settings/plugins');await toggle('动作分析');
    await send('Page.navigate',{url:h.origin+'/#/analysis'});await expectText('此功能尚未启用');
    assert.equal(await evaluate(`gymPluginRuntime.load('motion').then(()=>false,()=>true)`),true);
    await clickText('启用并继续',true);await expectText('看见每一次动作');
    await send('Page.reload');await expectText('看见每一次动作');
    await h.screenshot('04-motion-reenabled');
    await navigate('/settings/plugins');await toggle('动作分析');
    await navigate();assert(!await h.has('动作分析'));
  });
  await check('toggling optional plugins preserves the same active workout',async()=>{
    await navigate();await clickText('开始训练',true);await expectText('添加动作');
    await navigate();await expectText('继续训练');
    const before=(await h.exportFile('active-before-toggle')).data;
    await navigate('/settings/plugins');await toggle('饮料热量');await toggle('饮料热量');
    await navigate();await expectText('继续训练');
    const after=(await h.exportFile('active-after-toggle')).data;
    assert.deepEqual(after.data.sessions,before.data.sessions);
    assert.deepEqual(after.data.sets,before.data.sets);
    await h.screenshot('05-active-workout-retained');
  });
  await check('empty schema 11 install upgrades to all five destinations',async()=>{
    // This disposable browser profile is the fixture. Removing only schema-12
    // additions reproduces published schema 11; no user database is accessed.
    await navigate();
    const fixture=await evaluate(`(async()=>{
      const worker=new SharedWorker(new URL('sqflite_sw.js',document.baseURI),'sqflite_common_ffi_web');
      const call=(method,args)=>new Promise((resolve,reject)=>{
        const channel=new MessageChannel();
        channel.port1.onmessage=e=>{channel.port1.close();e.data?.error?reject(Error(JSON.stringify(e.data.error))):resolve(e.data?.result)};
        worker.port.postMessage({method,arguments:args},[channel.port2]);
      });
      const root=await call('getDatabasesPath',null);
      const prefix=root.endsWith('/')?root.slice(0,-1):root;
      const opened=await call('openDatabase',{path:prefix+'/gym_tracker.db',singleInstance:true});
      const exec=sql=>call('execute',{id:opened.id,sql,arguments:[]});
      await exec('BEGIN IMMEDIATE');
      try {
        await exec('DELETE FROM session');
        await exec('DROP TABLE plugin_document');await exec('DROP TABLE plugin_data_version');await exec('DROP TABLE plugin_state');
        await exec("DELETE FROM app_meta WHERE key='plugin_install_origin'");
        await exec("UPDATE app_meta SET value='11' WHERE key='schema_version'");
        await exec('COMMIT');
      } catch(error) {await exec('ROLLBACK');throw error;}
      worker.port.close();return {schemaVersion:11,sessions:0};
    })()`);
    await writeFile(path.join(h.output,'legacy-fixture.json'),JSON.stringify(fixture));
    await send('Page.reload');await expectText('开始训练');
    for(const label of ['训练','热量','动作分析','历史','进步']) assert(await h.has(label));
    const upgraded=(await h.exportFile('legacy-upgraded')).data;
    assert.equal(upgraded.schemaVersion,12);assert.equal(upgraded.data.sessions.length,0);
    await h.screenshot('06-legacy-five');
  });
  await writeFile(path.join(h.output,'plugin-snapshot.json'),JSON.stringify(imported.plugins,null,2));
  assert(await readFile(path.join(h.output,'unknown-disabled-roundtrip.json'),'utf8'));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE='plugins';import('./browser_backup_smoke.mjs').catch(error=>{console.error(error);process.exitCode=1;});
}
