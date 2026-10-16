// Historical helper for the 2026-10-16 isolated-package evidence.
// The user now wants normal main-package updates and UI record cleanup;
// use android_acceptance.mjs for subsequent main-package acceptance.
// These original destructive operations remain restricted to .acceptance.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, writeFile, appendFile, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'build/acceptance/android-2026-10-16-final');
const testPackage = 'com.mobis.gym_tracker.acceptance';
const mainPackage = 'com.mobis.gym_tracker';
const remote = '/sdcard/Download/GymAcceptance_20261016';
const adb = path.join(root, '.tooling/android-sdk/platform-tools/adb.exe');
const env = { ...process.env, ANDROID_USER_HOME: path.join(root, '.tooling/home/.android') };
await mkdir(output, { recursive: true });
const devices = execFileSync(adb, ['devices'], { env, encoding: 'utf8', windowsHide: true })
  .split(/\r?\n/).filter(line => /\sdevice$/.test(line)).map(line => line.split(/\s+/)[0]);
assert.equal(devices.length, 1, 'Connect exactly one authorized device.');
const serial = devices[0];
function run(args, binary = false, timeout = 45000) {
  return execFileSync(adb, ['-s', serial, ...args], {
    env, windowsHide: true, timeout, maxBuffer: 40 * 1024 * 1024,
    encoding: binary ? undefined : 'utf8',
  });
}
function name(value) {
  assert(/^[a-zA-Z0-9_-]+$/.test(value), 'Use a simple evidence label.');
  return value;
}
function decode(value) {
  return value.replace(/&#10;/g, '\n').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}
function dump() {
  for(let attempt=0;;attempt++) {
    try { run(['shell', 'uiautomator', 'dump', '/sdcard/gym-acceptance.xml']); break; }
    catch(error) { if(attempt>=2) throw error; Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,500); }
  }
  const xml = run(['shell', 'cat', '/sdcard/gym-acceptance.xml']);
  const nodes = [...xml.matchAll(/<node\b[^>]*>/g)].map(match => {
    const attrs = Object.fromEntries([...match[0].matchAll(/([\w-]+)="([^"]*)"/g)]
      .map(item => [item[1], decode(item[2])]));
    return { label: attrs['content-desc'] || attrs.text || '', text: attrs.text,
      clickable: attrs.clickable === 'true', enabled: attrs.enabled === 'true',
      resource: attrs['resource-id'], class: attrs.class,
      bounds: attrs.bounds?.match(/\d+/g)?.map(Number), package: attrs.package };
  });
  return { xml, nodes };
}
function click(node) {
  assert(node.bounds?.length === 4);
  const [l,t,r,b] = node.bounds;
  run(['shell','input','tap',String(Math.round((l+r)/2)),String(Math.round((t+b)/2))]);
}
function target(nodes, action) {
  let matches = nodes.filter(node => action.exact ? node.label === action.text : node.label.includes(action.text));
  if (action.class) matches = matches.filter(node => node.class === action.class);
  if (action.resource) matches = matches.filter(node => node.resource === action.resource);
  matches.sort((a,b) => Number(b.clickable)-Number(a.clickable));
  const node = matches[action.index || 0];
  assert(node, `Missing UI target: ${JSON.stringify(action)}`);
  assert(node.enabled, `Disabled UI target: ${node.label}`);
  return node;
}
async function snapshot(label) {
  const {xml,nodes} = dump();
  await writeFile(path.join(output, `${name(label)}.xml`),xml);
  await writeFile(path.join(output, `${label}.json`),JSON.stringify(nodes,null,2));
  const image = path.join(output, `${label}.png`);
  await writeFile(image,run(['exec-out','screencap','-p'],true));
  return {image,nodes:nodes.filter(n=>n.label).map(n=>({label:n.label,clickable:n.clickable,enabled:n.enabled,class:n.class,bounds:n.bounds,resource:n.resource,package:n.package}))};
}
async function database(label) {
  const directory = path.join(output,'databases',name(label));
  await mkdir(directory,{recursive:true});
  const files = run(['shell','run-as',testPackage,'ls','databases']).split(/\s+/);
  for (const suffix of ['','-wal','-shm']) {
    const file = `gym_tracker.db${suffix}`;
    if (files.includes(file)) await writeFile(path.join(directory,file),run(['exec-out','run-as',testPackage,'cat',`databases/${file}`],true));
  }
  const { DatabaseSync } = await import('node:sqlite');
  const db = new DatabaseSync(path.join(directory,'gym_tracker.db'),{readOnly:true});
  try {
    const tables = ['app_meta','app_setting','exercise','session','session_exercise','set_entry','split_template','template_exercise'];
    const data = Object.fromEntries(tables.map(table=>[table,db.prepare(`SELECT * FROM ${table} ORDER BY rowid`).all()]));
    assert.equal(db.prepare('PRAGMA integrity_check').get().integrity_check,'ok');
    assert.deepEqual(db.prepare('PRAGMA foreign_key_check').all(),[]);
    await writeFile(path.join(directory,'data.json'),JSON.stringify(data,null,2));
    return {directory,counts:Object.fromEntries(tables.map(t=>[t,data[t].length])),settings:data.app_setting,meta:data.app_meta,
      sessions:data.session,sets:data.set_entry,plans:data.split_template,planExercises:data.template_exercise};
  } finally { db.close(); }
}
async function action(a) {
  switch(a.type) {
    case 'info': return {serial,model:run(['shell','getprop','ro.product.model']).trim(),sdk:run(['shell','getprop','ro.build.version.sdk']).trim(),size:run(['shell','wm','size']).trim(),packages:run(['shell','pm','list','packages','--user','0','com.mobis.gym_tracker']).trim(),window:run(['shell','dumpsys','window']).split(/\r?\n/).filter(l=>/mCurrentFocus|mShowingLockscreen/.test(l))};
    case 'install-test':
    case 'install-main': {
      const apk = a.type==='install-test' ? path.join(output,'gym-acceptance-debug.apk') : path.join(root,'build/app/outputs/flutter-apk/app-release.apk');
      const result = run(['install','--user','0','-r',apk],false,180000);
      assert(result.includes('Success'),result); return result;
    }
    case 'start':
    case 'start-main': return run(['shell','am','start','-n',`${a.type==='start'?testPackage:mainPackage}/com.mobis.gym_tracker.MainActivity`]);
    case 'stop': return run(['shell','am','force-stop',testPackage]);
    case 'clear-test': return run(['shell','pm','clear','--user','0',testPackage]);
    case 'uninstall-test': return run(['uninstall','--user','0',testPackage]);
    case 'home': return run(['shell','input','keyevent','3']);
    case 'back': {const result=run(['shell','input','keyevent','4']);await delay(400);return result;}
    case 'snapshot': return snapshot(a.label);
    case 'db': return database(a.label);
    case 'tap': {
      let nodes=dump().nodes;
      if(a.scroll) {
        for(let i=0;i<8&&!nodes.some(n=>a.exact?n.label===a.text:n.label.includes(a.text));i++) {
          const [from,to]=i<4?[2300,950]:[950,2300];
          run(['shell','input','swipe','700',String(from),'700',String(to),'300']);
          nodes=dump().nodes;
        }
      }
      const node=target(nodes,a); click(node); return node;
    }
    case 'tap-at': {
      assert([a.x,a.y].every(n=>Number.isInteger(n)&&n>=0&&n<4000));
      return run(['shell','input','tap',String(a.x),String(a.y)]);
    }
    case 'swipe': {
      assert([a.x1,a.y1,a.x2,a.y2].every(n=>Number.isInteger(n)&&n>=0&&n<4000));
      return run(['shell','input','swipe',...[a.x1,a.y1,a.x2,a.y2,a.duration||350].map(String)]);
    }
    case 'fill': {
      assert(typeof a.value==='string' && /^[\x20-\x7E]{0,120}$/.test(a.value) && !/[\x22\x27\x24\x60\x26\x3B\x7C\x3C\x3E\x5C]/.test(a.value),'Use safe ASCII text.');
      const nodes=dump().nodes;
      const field=a.text ? target(nodes,{...a,class:'android.widget.EditText'}) : nodes.filter(n=>n.class==='android.widget.EditText')[a.index||0];
      assert(field,'Missing editable field'); click(field);
      run(['shell','input','keyevent','123']);
      run(['shell','input','keyevent',...Array(120).fill('67')]);
      if(a.value) run(['shell','input','text',a.value.replace(/ /g,'%s')]);
      if(a.dismiss!==false) run(['shell','input','keyevent','4']);
      return {field:field.label,value:a.value};
    }
    case 'assert': {
      const nodes=dump().nodes;
      for(const text of a.contains||[]) assert(nodes.some(n=>n.label.includes(text)),`Missing text: ${text}`);
      for(const text of a.absent||[]) assert(!nodes.some(n=>n.label.includes(text)),`Unexpected text: ${text}`);
      return {contains:a.contains,absent:a.absent};
    }
    case 'wait': assert(a.ms>=0&&a.ms<=45000); await delay(a.ms); return a.ms;
    case 'fixtures': {
      run(['shell','mkdir','-p',remote]);
      const files=[];
      for(const kind of ['backup','import']) for(const file of await readdir(path.join(root,'test/fixtures',kind))) {
        const local=path.join(root,'test/fixtures',kind,file);
        run(['push',local,`${remote}/${file}`]); files.push(file);
      }
      const extra=path.join(output,'fixtures'); await mkdir(extra,{recursive:true});
      const current=JSON.parse(await readFile(path.join(root,'test/fixtures/backup/legacy-v2.json'),'utf8'));
      current.data.sessionExercises[0].exerciseId='missing-exercise';
      const protocol={...current,format:'other-format'};
      const values={'bad-json.json':'{bad json','bad-protocol.json':JSON.stringify(protocol),'bad-reference.json':JSON.stringify(current),'all-bad.csv':'Date,Workout Name,Exercise Name,Weight,Reps\nnot-a-date,Bad,Bench,nope,8\n'};
      for(const [file,content] of Object.entries(values)) {
        const local=path.join(extra,file); await writeFile(local,content); run(['push',local,`${remote}/${file}`]); files.push(file);
      }
      return {remote,files};
    }
    case 'list-files': return run(['shell','ls','-l',remote]);
    case 'pull-export': {
      assert(/^GymAcceptance-[a-zA-Z0-9_-]+\.json$/.test(a.file));
      const destination=path.join(output,'exports');await mkdir(destination,{recursive:true});
      const local=path.join(destination,a.file);
      run(['pull',`/sdcard/Download/${a.file}`,local]);
      const data=JSON.parse(await readFile(local,'utf8'));
      return {local,counts:Object.fromEntries(Object.entries(data.data).map(([key,rows])=>[key,rows.length]))};
    }
    case 'export': {
      const label=name(a.label);
      if(!dump().nodes.some(n=>n.label==='导出备份')) await action({type:'tap',text:'设置'});
      await action({type:'tap',text:'导出备份',exact:true});
      await snapshot(`${label}-save-dialog`);
      await action({type:'tap',text:'显示根目录',exact:true});
      await action({type:'tap',text:'下载内容',exact:true,resource:'android:id/title'});
      await action({type:'fill',value:`GymAcceptance-${label}.json`});
      await action({type:'tap',text:'保存',exact:true});
      await delay(300);
      await action({type:'assert',contains:['备份已保存']});
      return action({type:'pull-export',file:`GymAcceptance-${label}.json`});
    }
    case 'select-backup':
    case 'select-csv': {
      assert(/^[a-zA-Z0-9_-]+\.(json|csv)$/.test(a.file));
      if(a.type==='select-backup') {
        if(!dump().nodes.some(n=>n.label==='从备份恢复')) await action({type:'tap',text:'设置'});
        await action({type:'tap',text:'从备份恢复',exact:true});
      } else {
        if(!dump().nodes.some(n=>n.label==='选择 CSV 文件')) {
          await action({type:'tap',text:'设置'});
          await action({type:'tap',text:'从 CSV 追加记录',exact:true});
        }
        await action({type:'tap',text:'选择 CSV 文件',exact:true});
      }
      const nodes=dump().nodes;
      const breadcrumbs=nodes.filter(n=>n.resource==='com.android.documentsui:id/breadcrumb_text').map(n=>n.label);
      if(!breadcrumbs.includes('GymAcceptance_20261016')||!breadcrumbs.includes('Download')) {
        await action({type:'tap',text:'显示根目录',exact:true});
        await action({type:'tap',text:'荣耀Magic6 Pro',exact:true});
        await action({type:'tap',text:'Download',exact:true,scroll:true});
        await action({type:'tap',text:'GymAcceptance_20261016',exact:true,scroll:true});
      }
      if(dump().nodes.some(n=>n.label==='列表视图')) await action({type:'tap',text:'列表视图',exact:true});
      await action({type:'tap',text:a.file,exact:true,scroll:true});
      return {file:a.file};
    }
    default: throw new Error(`Unknown acceptance action: ${a.type}`);
  }
}
const argument=process.argv[2];
assert(argument,'Pass one JSON action or an array of actions.');
const parsed=JSON.parse(argument);
for(const a of Array.isArray(parsed)?parsed:[parsed]) {
  try {
    const result=await action(a);
    await appendFile(path.join(output,'actions.jsonl'),JSON.stringify({at:new Date().toISOString(),serial,action:a,result})+'\n');
    console.log(JSON.stringify({action:a,result}));
  } catch(error) {
    await appendFile(path.join(output,'actions.jsonl'),JSON.stringify({at:new Date().toISOString(),serial,action:a,error:String(error.stack||error)})+'\n');
    throw error;
  }
}
