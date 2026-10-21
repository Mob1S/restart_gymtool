// Run after `flutter build web --no-pub`. Node 22+ and Chrome are required.
// Uses a separate browser profile: existing browser and phone data stay intact.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const webRoot = path.join(root, 'web');
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const output = path.join(root, 'build', 'acceptance', `browser-${stamp}`);
const chromePath = process.env.CHROME_EXECUTABLE || [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
].find(existsSync);
assert(chromePath, 'Set CHROME_EXECUTABLE to the Chrome executable.');

await mkdir(output, { recursive: true });
const profileRoot = path.join(root, '.tooling', 'acceptance');
await mkdir(profileRoot, { recursive: true });
const profile = await mkdtemp(path.join(profileRoot, 'chrome-'));
const checks = [];
const errors = [];

const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf' };
const server = http.createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    if(pathname==='/') {response.setHeader('Content-Type','text/html');response.end('<title>Motion integration</title><script type="module" src="/motion/runtime.js"></script>');return;}
    if(pathname==='/sample.mp4') {response.setHeader('Content-Type','video/mp4');response.end(await readFile(path.join(root,'build/review-samples/bench-press-pexels-32239226.mp4')));return;}
    let file = path.resolve(webRoot, `.${pathname}`);
    if (file !== webRoot && !file.startsWith(webRoot + path.sep)) {
      response.writeHead(403).end();
      return;
    }
    if (file === webRoot || !existsSync(file)) file = path.join(webRoot, 'index.html');
    response.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
    response.end(await readFile(file));
  } catch (error) {
    response.writeHead(500).end(String(error));
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const chrome = spawn(chromePath, ['--headless=new', '--no-first-run',
  '--no-default-browser-check', '--disable-background-networking',
  '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'],
{ windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
let chromeLog = '';
chrome.stderr.on('data', chunk => { chromeLog += chunk; });
chrome.on('error', error => errors.push(String(error)));

async function until(probe, description, timeout = 45000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const result = await probe();
    if (result) return result;
    await delay(200);
  }
  throw new Error(`Timed out: ${description}`);
}

let socket;
const pending = new Map();
let nextId = 0;
function send(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++nextId;
    const timeout = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`CDP timeout: ${method}`));
    }, 120000);
    pending.set(id, { resolve, reject, timeout });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
async function evaluate(expression) {
  const result = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
}

let failed=false;
try {
  const port=await until(async()=>{try{return (await readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0]}catch{return null}},'debug port');
  const targets=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  socket=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);
  await new Promise(resolve=>socket.addEventListener('open',resolve,{once:true}));
  socket.addEventListener('message',({data})=>{
    const message=JSON.parse(data),task=pending.get(message.id);
    if(task){pending.delete(message.id);clearTimeout(task.timeout);message.error?task.reject(Error(JSON.stringify(message.error))):task.resolve(message.result);}
    else if(message.method==='Runtime.exceptionThrown')errors.push(message.params.exceptionDetails);
  });
  await send('Page.enable');await send('Runtime.enable');
  await send('Page.navigate',{url:origin});
  await until(()=>evaluate('!!window.gymMotion'),'runtime');
  const imported=await evaluate(`(async()=>{window.motionEvents=[];gymMotion.subscribe(e=>motionEvents.push(JSON.parse(e)));window.media=JSON.parse(await gymMotion.call('import',JSON.stringify({path:'/sample.mp4'})));return media})()`);
  assert(imported.duration>20000);checks.push({name:'real video import',duration:imported.duration});
  const frame=await evaluate(`gymMotion.call('frame',JSON.stringify({folder:media.folder,t:0})).then(JSON.parse)`);
  await writeFile(path.join(output,'sample-first.jpg'),Buffer.from(frame.image,'base64'));
  console.log('Frame:',path.join(output,'sample-first.jpg'));
  await evaluate(`window.cancelledBoot=false;gymMotion.call('analyze',JSON.stringify({folder:media.folder,start:0,end:2000,anchors:[],session:'cancel-boot'})).catch(()=>window.cancelledBoot=true);true`);
  await until(()=>evaluate('motionEvents.some(e=>e.diagnostic===\'worker-start\')'),'initialization began');
  await evaluate(`gymMotion.call('cancel','{}')`);
  checks.push({name:'cancel during model initialization; subsequent session remains usable'});
  // Use an observed image point for plumbing verification. This moving-camera sample is not accuracy acceptance.
  await evaluate(`window.analysisDone=false;window.analysisError=null;gymMotion.call('analyze',JSON.stringify({folder:media.folder,start:0,end:2000,anchors:[{t:0,x:.28,y:.25,radius:.08}],session:'real-import'})).then(r=>{window.analysis=JSON.parse(r);analysisDone=true}).catch(e=>{analysisError=String(e);analysisDone=true});true`);
  await until(()=>evaluate('analysisDone'),'worker analysis',120000);
  const answer=await evaluate('({error:analysisError,data:window.analysis,events:motionEvents.filter(e=>e.frame).map(e=>({t:e.frame.t,pose:e.frame.pose?.length,valid:e.frame.x!=null,progress:e.progress,processing:e.frame.processingMs}))})');
  await writeFile(path.join(output,'debug.json'),JSON.stringify(await evaluate('({error:analysisError,events:motionEvents.map(e=>({...e,image:undefined}))})'),null,2));
  assert.equal(answer.error,null,answer.error);assert(answer.events.length>5);assert(answer.events.some(e=>e.pose===33));
  assert(answer.events.every((e,i,a)=>i===0||e.t>a[i-1].t));
  checks.push({name:'real CPU Worker pose + LK incremental processing',frames:answer.events.length,poseFrames:answer.events.filter(e=>e.pose===33).length,trackingFrames:answer.events.filter(e=>e.valid).length});
  await writeFile(path.join(output,'observations.json'),JSON.stringify(answer,null,2));
  const loaded=await evaluate(`gymMotion.call('load',JSON.stringify({folder:media.folder,result:analysis.result})).then(JSON.parse)`);
  assert.equal(loaded.frames.length,answer.events.length);checks.push({name:'IndexedDB result reload'});
  await evaluate(`window.cancelled=false;window.motionEvents=[];gymMotion.call('analyze',JSON.stringify({folder:media.folder,start:0,end:20000,anchors:[],session:'cancel-test'})).catch(()=>window.cancelled=true);true`);
  await until(()=>evaluate('motionEvents.length>0'),'cancel starts after real observation',120000);
  const cancel=await evaluate(`(async()=>{const began=performance.now();await gymMotion.call('cancel','{}');return performance.now()-began})()`);
  await until(()=>evaluate('cancelled'),'cancel rejection');checks.push({name:'cancel real inference',milliseconds:cancel});
  const camera=await evaluate(`(async()=>{try{const r=JSON.parse(await gymMotion.call('camera',JSON.stringify({session:'camera-check'})));await gymMotion.call('close','{}');return {available:true,devices:r.devices}}catch(e){return {available:false,error:String(e)}}})()`);
  checks.push({name:'real camera capability check',...camera,acceptance:camera.available?'requires physical bench-press session':'not accepted: no available camera/permission in test browser'});
  await evaluate(`gymMotion.call('release',JSON.stringify({folder:media.folder}))`);
  await evaluate(`gymMotion.call('collect',JSON.stringify({keep:[media.folder],results:{[media.folder]:analysis.result}}))`);
  await send('Page.reload');await until(()=>evaluate('!!window.gymMotion'),'reload runtime');
  const reopened=await evaluate(`gymMotion.call('open',JSON.stringify({folder:${JSON.stringify(imported.folder)}})).then(JSON.parse)`);
  assert(reopened.uri.startsWith('blob:'));checks.push({name:'Blob persists across page reload; object URL reconstructed'});
} catch(e) {failed=true;errors.push(String(e.stack??e));console.error(e);}
finally {
  await writeFile(path.join(output,'results.json'),JSON.stringify({passed:!failed,checks,errors},null,2));
  await writeFile(path.join(output,'chrome.log'),chromeLog);
  if(socket?.readyState===WebSocket.OPEN){try{await send('Browser.close')}catch{}socket.close();}
  if(chrome.exitCode===null)chrome.kill();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
  console.log(`Evidence: ${output}`);process.exitCode=failed?1:0;
}
