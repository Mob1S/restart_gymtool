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
const webRoot = path.join(root, 'build', 'web');
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const output = path.join(root, 'build', 'acceptance', `browser-${stamp}`);
const chromePath = process.env.CHROME_EXECUTABLE || [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
].find(existsSync);
assert(chromePath, 'Set CHROME_EXECUTABLE to the Chrome executable.');
assert(existsSync(path.join(webRoot, 'main.dart.js')), 'Run flutter build web first.');
await mkdir(output, { recursive: true });
const profileRoot = path.join(root, '.tooling', 'acceptance');
await mkdir(profileRoot, { recursive: true });
const profile = await mkdtemp(path.join(profileRoot, 'chrome-'));
const checks = [];
const errors = [];

const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs':'text/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf' };
const server = http.createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
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
    }, 30000);
    pending.set(id, { resolve, reject, timeout });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
async function evaluate(expression) {
  const result = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
const semanticsExpression = `Array.from(document.querySelectorAll('flt-semantics')).map(e => {
  const r = e.getBoundingClientRect();
  const slider = e.querySelector('input[type=range]');
  const editable = Array.from(e.querySelectorAll('input:not([type=range]),textarea')).find(i=>i.closest('flt-semantics')===e);
  return {id:e.id, text: e.getAttribute('aria-label') || Array.from(e.querySelectorAll('input,textarea')).map(i=>i.getAttribute('aria-label') || i.placeholder || '').filter(Boolean).join('\\n') || e.innerText || '', role: e.getAttribute('role') || slider?.getAttribute('role') || (editable ? 'textbox' : null), value: e.getAttribute('aria-valuetext') || slider?.getAttribute('aria-valuetext') || '', disabled: e.getAttribute('aria-disabled') === 'true',
    x: r.x, y: r.y, width: r.width, height: r.height};
}).filter(e => e.width && e.height)`;
async function semantics() {
  await evaluate(`(() => {
    if (!document.querySelector('flt-semantics')) {
      document.querySelector('flt-semantics-placeholder')?.click();
    }
  })()`);
  return evaluate(semanticsExpression);
}
async function has(text) { return (await semantics()).some(e => e.text.includes(text) || e.value?.includes(text)); }
async function expectText(text) { await until(() => has(text), `text: ${text}`); }
async function clickAt(x, y) {
  await send('Input.dispatchMouseEvent', {type:'mouseMoved',x,y});
  await delay(50);
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', buttons:type==='mousePressed'?1:0, clickCount: 1 });
  }
  await delay(400);
}
async function clickText(text, exact = false) {
  let previous;
  const element = await until(async () => {
    const matches = (await semantics()).filter(e => !e.disabled && (exact ? e.text === text || e.value === text : e.text.includes(text) || e.value?.includes(text)) && (text.startsWith('收藏 ') || !e.text.startsWith('收藏 ')));
    const next = matches.sort((a, b) => a.width * a.height - b.width * b.height)[0];
    const stable = next && previous && next.x === previous.x && next.y === previous.y && next.width === previous.width && next.height === previous.height;
    previous = next;
    if(!stable) return null;
    return next;
  }, `clickable text: ${text}`);
  await clickAt(element.x + element.width / 2, element.y + element.height / 2);
}
async function screenshot(name) {
  const shot = await send('Page.captureScreenshot', { format: 'png' });
  await writeFile(path.join(output, `${name}.png`), Buffer.from(shot.data, 'base64'));
  await writeFile(path.join(output, `${name}.json`), JSON.stringify(await semantics(), null, 2));
}
async function check(name, action) {
  await action();
  checks.push(name);
  console.log(`PASS ${name}`);
}

let failed=false,chooser;
try {
  const port=await until(async()=>{try{return (await readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0]}catch{return null}},'debug port');
  const targets=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  socket=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);
  await new Promise(resolve=>socket.addEventListener('open',resolve,{once:true}));
  socket.addEventListener('message',({data})=>{
    const m=JSON.parse(data),task=pending.get(m.id);
    if(task){pending.delete(m.id);clearTimeout(task.timeout);m.error?task.reject(Error(JSON.stringify(m.error))):task.resolve(m.result);}
    else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails);
    else if(m.method==='Page.fileChooserOpened')chooser=m.params;
  });
  await send('Page.enable');await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride',{width:360,height:800,deviceScaleFactor:1,mobile:true});
  await send('Page.navigate',{url:origin+'/#/analysis'});
  await expectText('动作分析');await clickText('动作分析');
  await expectText('看见每一次动作');await screenshot('01-home-360');checks.push('independent home and five destinations at 360px');
  await clickText('浏览和搜索动作库');await expectText('杠铃卧推');
  await clickText('杠铃卧推');
  await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:300,y:580,deltaY:450,deltaX:0});await delay(400);
  await clickText('导入视频分析');await expectText('选择本地视频');
  await send('Page.setInterceptFileChooserDialog',{enabled:true});
  await clickText('选择本地视频');await until(()=>chooser,'file chooser');
  await send('DOM.setFileInputFiles',{backendNodeId:chooser.backendNodeId,files:[path.join(root,'build/review-samples/bench-press-pexels-32239226.mp4')]});
  await expectText('标记片段首帧');await screenshot('02-real-import');
  // Scroll to the clip controls and select a short real interval using the accessible end slider.
  await evaluate(`window.uiEvents=[];gymMotion.subscribe(s=>{const e=JSON.parse(s);if(e.frame)uiEvents.push({t:e.frame.t,pose:e.frame.pose?.length,valid:e.frame.x!=null})});true`);
  const controls=await semantics();
  console.log('Imported real video through the Flutter picker');
  const endSlider=controls.filter(e=>e.text===''&&e.role==='slider'&&e.value==='100%').sort((a,b)=>a.width-b.width)[0];
  const startSlider=controls.filter(e=>e.text===''&&e.role==='slider'&&e.value==='0%'&&e.y===endSlider.y).sort((a,b)=>a.width-b.width)[0];
  const endX=endSlider.x+endSlider.width/2,startX=startSlider.x+startSlider.width/2,sliderY=endSlider.y+endSlider.height/2;
  await send('Input.dispatchMouseEvent',{type:'mouseMoved',x:endX,y:sliderY});
  await send('Input.dispatchMouseEvent',{type:'mousePressed',x:endX,y:sliderY,button:'left',buttons:1,clickCount:1});
  for(let step=1;step<=12;step++){await send('Input.dispatchMouseEvent',{type:'mouseMoved',x:endX-(endX-startX)*.87*step/12,y:sliderY,button:'left',buttons:1});await delay(50);}
  await send('Input.dispatchMouseEvent',{type:'mouseReleased',x:startX+(endX-startX)*.13,y:sliderY,button:'left',buttons:0,clickCount:1});
  await delay(500);
  // Marking the exact first decoded frame brings the still into the actual preview.
  await evaluate(`document.querySelector('flt-glass-pane').dispatchEvent(new Event('focus'));true`);
  // Use wheel scrolling to reach marking controls on narrow screens.
  async function scrollTo(text){for(let i=0;i<8;i++){const e=(await semantics()).find(e=>e.text.includes(text)&&e.y>=0&&e.y+e.height<700);if(e)return;await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:300,y:550,deltaY:350,deltaX:0});await delay(250)}throw Error('not visible '+text)}
  await scrollTo('标记片段首帧');await clickText('标记片段首帧');
  // Bring preview back into view; identify rendered video rectangle via its player element before selecting.
  await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:300,y:300,deltaY:-1500,deltaX:0});await delay(600);
  await screenshot('03-mark-frame');
  await clickAt(16+328*.28,248+184*.25);
  await scrollTo('开始分析');await clickText('开始分析',true);
  await until(()=>evaluate('uiEvents.length>2'),'incremental observations',60000);await screenshot('04-analysis-incremental');
  await until(()=>has('次数与节奏'),'finished real analysis',90000);
  await screenshot('05-result');await clickText('保存',true);await expectText('已保存');
  checks.push({name:'real picker -> mark -> incremental analysis -> save',frames:await evaluate('uiEvents.length'),trackingFrames:await evaluate('uiEvents.filter(e=>e.valid).length')});
  await clickText('动作分析',true);await expectText('本地分析项目');await screenshot('06-project-saved');
  assert((await semantics()).some(e=>e.text.includes('独立项目')));checks.push('saved independent project is listed');
  assert.equal(errors.length,0,JSON.stringify(errors));
} catch(e){failed=true;errors.push(String(e.stack??e));console.error(e);try{await screenshot('failure')}catch{}}
finally {
  await writeFile(path.join(output,'results.json'),JSON.stringify({passed:!failed,checks,errors},null,2));
  await writeFile(path.join(output,'chrome.log'),chromeLog);
  if(socket?.readyState===WebSocket.OPEN){try{await send('Browser.close')}catch{}socket.close();}
  if(chrome.exitCode===null)chrome.kill();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
  console.log(`Evidence: ${output}`);process.exitCode=failed?1:0;
}
