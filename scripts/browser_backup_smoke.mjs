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
const feature = process.env.GYM_BROWSER_FEATURE;
assert(!feature || ['import', 'plans', 'workout_efficiency', 'training_redesign', 'rest_days'].includes(feature));
const output = path.join(root, 'build', 'acceptance', `browser-${feature || 'backup'}-${stamp}`);
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

const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
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
    const clear=await evaluate(`(()=>{const target=document.getElementById(${JSON.stringify(next.id)});const hit=document.elementFromPoint(${next.x+next.width/2},${next.y+next.height/2});return !!target&&!!hit&&(target.contains(hit)||hit.contains(target))})()`);
    return clear ? next : null;
  }, `clickable text: ${text}`);
  await clickAt(element.x + element.width / 2, element.y + element.height / 2);
}
async function tapText(text) {
  await delay(200);
  const e=await until(async()=>{
    const next=(await semantics()).find(e=>e.text===text&&e.role==='button'&&!e.disabled);
    if(!next) return null;
    const clear=await evaluate(`(()=>{const target=document.getElementById(${JSON.stringify(next.id)});const hit=document.elementFromPoint(${next.x+next.width/2},${next.y+next.height/2});return !!target&&!!hit&&(target.contains(hit)||hit.contains(target))})()`);
    return clear?next:null;
  },'unobscured touch target '+text);
  const point={x:e.x+e.width/2,y:e.y+e.height/2};
  await send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[point]});
  await send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  await delay(400);
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
async function swipeLeft() {
  await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 345, y: 380 }] });
  for (let x = 325; x >= 45; x -= 20) {
    await send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: 380 }] });
    await delay(20);
  }
  await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await delay(700);
}

let browserSocket;
let chooser;
const downloads = new Map();
const downloadNames = new Map();
const downloadDirectory = path.join(output, 'downloads');
await mkdir(downloadDirectory, { recursive: true });
async function browserSend(method, params = {}) {
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { pending.delete(id); reject(new Error(`Browser CDP timeout: ${method}`)); }, 30000);
    pending.set(id, { resolve, reject, timeout });
    browserSocket.send(JSON.stringify({ id, method, params }));
  });
}
async function exportFile(label) {
  await clickText('设置', true);
  const previous = new Set(downloads.keys());
  await clickText('导出备份', true);
  const guid = await until(() => [...downloads].find(([id, state]) => !previous.has(id) && state === 'completed')?.[0], 'download completed');
  const file = path.join(downloadDirectory, guid);
  const data = JSON.parse(await readFile(file, 'utf8'));
  await writeFile(path.join(output, `${label}.json`), JSON.stringify(data, null, 2));
  assert.match(downloadNames.get(guid), /^gym-backup-\d{4}-\d{2}-\d{2}-\d{6}\.json$/);
  await expectText('已请求下载备份');
  return { file, data };
}
async function downloadCsv() {
  await clickText('历史', true);
  const previous = new Set(downloads.keys());
  await clickText('记录操作');
  await clickText('导出当前列表 CSV');
  const guid = await until(() => [...downloads].find(([id,state]) => !previous.has(id) && state === 'completed')?.[0], 'CSV download completed');
  assert.match(downloadNames.get(guid), /\.csv$/);
  return {file:path.join(downloadDirectory,guid), text:await readFile(path.join(downloadDirectory,guid),'utf8')};
}
async function selectFile(file) {
  await clickText('设置', true);
  chooser = null;
  await clickText('从备份恢复', true);
  await until(() => chooser, 'system upload input');
  await send('DOM.setFileInputFiles', { files: [file], backendNodeId: chooser.backendNodeId });
}
async function restoreFile(file) {
  await selectFile(file);
  await expectText('替换并恢复');
  await clickText('替换并恢复', true);
  await until(async () => (await has('开始训练')) || (await has('开始新训练')) ||
    (await has('继续训练')) || (await has('今天休息')) || (await has('今日已完成')), 'restored workout home');
}
let failed = false;
try {
  const devtools = await until(async () => {
    try { return (await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]; }
    catch { return null; }
  }, 'Chrome DevTools port');
  const targets = await (await fetch(`http://127.0.0.1:${devtools}/json/list`)).json();
  const target = targets.find(item => item.type === 'page');
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    const task = pending.get(message.id);
    if (task) {
      pending.delete(message.id);
      clearTimeout(task.timeout);
      if (message.error) task.reject(new Error(JSON.stringify(message.error)));
      else task.resolve(message.result);
    } else if (message.method === 'Page.fileChooserOpened') {
      chooser = message.params;
    } else if (message.method === 'Runtime.exceptionThrown') {
      errors.push(message.params.exceptionDetails);
    }
  });
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await send('Emulation.setTouchEmulationEnabled', { enabled: true });
  await send('Page.navigate', { url: origin });
  await until(() => evaluate(`document.title === '健身记录'`), 'AppBootstrap ready');
  await until(() => evaluate(`(() => { const e = document.querySelector('flt-semantics-placeholder');
    if (!e) return document.querySelectorAll('flt-semantics').length > 0; e.click(); return true; })()`), 'enable Flutter semantics');

  const version = await (await fetch(`http://127.0.0.1:${devtools}/json/version`)).json();
  browserSocket = new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    browserSocket.addEventListener('open', resolve, { once: true });
    browserSocket.addEventListener('error', reject, { once: true });
  });
  browserSocket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    const task = pending.get(message.id);
    if (task) {
      pending.delete(message.id); clearTimeout(task.timeout);
      if (message.error) task.reject(new Error(JSON.stringify(message.error))); else task.resolve(message.result);
    } else if (message.method === 'Browser.downloadWillBegin') {
      downloadNames.set(message.params.guid, message.params.suggestedFilename);
    } else if (message.method === 'Browser.downloadProgress') {
      downloads.set(message.params.guid, message.params.state);
    }
  });
  await browserSend('Browser.setDownloadBehavior', { behavior: 'allowAndName', downloadPath: downloadDirectory, eventsEnabled: true });
  await send('Page.setInterceptFileChooserDialog', { enabled: true });
  if (feature) {
    const { run } = await import(`./browser_${feature}_smoke.mjs`);
    await run({check,clickText,clickAt,tapText,expectText,has,semantics,send,evaluate,screenshot,
      until,exportFile,restoreFile,selectFile,downloadCsv,root,output,origin,
      upload:async(file)=>{chooser=null;await clickText('选择 CSV 文件',true);await until(()=>chooser,'CSV file chooser');await send('DOM.setFileInputFiles',{files:[file],backendNodeId:chooser.backendNodeId});},
    });
  } else {
  let baseline;
  await check('create training via UI and download a real JSON file', async () => {
    await tapText('开始训练'); await clickText('添加动作');
    await until(() => has('胸'), 'exercise picker data ready');
    await clickAt(100,166);
    await send('Input.insertText', { text: '深蹲' }); await clickText('深蹲');
    await clickText('添加 1 个动作',true);
    await clickText('完成这组'); await clickText('结束训练'); await expectText('160'); await clickText('完成', true);
    await clickText('设置', true); await clickText('深色', true);
    baseline = await exportFile('01-original-backup');
    assert.equal(baseline.data.format, 'gym-tracker-backup');
    assert.equal(baseline.data.version, 5); assert.equal(baseline.data.schemaVersion, 7);
    assert.equal(baseline.data.data.sessions.length, 1);
    assert.equal(baseline.data.data.sets[0].weight, 20); assert.equal(baseline.data.data.sets[0].reps, 8);
    assert(baseline.data.data.settings.some(row => row.key === 'theme_mode' && row.value === 'dark'));
    await screenshot('01-export');
  });
  await check('isolated empty origin: cancel preview then restore downloaded file', async () => {
    // Different origin gives SQLite/IndexedDB an independent empty database.
    await send('Page.navigate', { url: origin.replace('127.0.0.1', 'localhost') });
    await clickText('历史', true); await expectText('还没有已完成的训练'); await screenshot('02-empty-target');
    await selectFile(baseline.file); await expectText('本机的 0 场训练'); await screenshot('03-preview');
    await clickText('取消', true); await clickText('历史', true); await expectText('还没有已完成的训练');
    await restoreFile(baseline.file);
    await clickText('历史', true); await expectText('1 组 · 160 kg'); await screenshot('04-restored-history');
    await clickText('未命名训练'); await expectText('训练详情'); await expectText('160'); await clickText('Back');
    await clickText('进步', true); await expectText('最重 20 kg × 8'); await screenshot('05-restored-progress');
    assert.deepEqual((await exportFile('02-after-restore')).data.data, baseline.data.data);
  });
  await check('reload and export preserve every field and setting', async () => {
    await send('Page.reload');
    assert.deepEqual((await exportFile('03-after-reload')).data.data, baseline.data.data);
    await screenshot('06-reloaded-settings');
  });
  await check('bad JSON, protocol and orphan reference leave data unchanged', async () => {
    const orphan = structuredClone(baseline.data); orphan.data.sets[0].sessionExerciseId = 'does-not-exist';
    for (const [name, content, message] of [
      ['bad-json', '{broken', '不是有效的'],
      ['bad-protocol', JSON.stringify({ format: 'other' }), '不是本应用'],
      ['orphan', JSON.stringify(orphan), '引用完整性'],
    ]) {
      const file = path.join(output, `${name}.json`); await writeFile(file, content);
      await selectFile(file); await expectText(message); await screenshot(`07-${name}`);
      assert.deepEqual((await exportFile(`unchanged-${name}`)).data.data, baseline.data.data);
    }
  });
  await check('legacy v1 and v2 retain plans, active training, pending sets and raw rest values', async () => {
    for (const name of ['legacy-v1', 'legacy-v2']) {
      const file = path.join(root, 'test', 'fixtures', 'backup', `${name}.json`);
      const expected = JSON.parse(await readFile(file, 'utf8'));
      await restoreFile(file);
      if (name === 'legacy-v2') await expectText('继续');
      const restored = (await exportFile(`restored-${name}`)).data;
      for (const key of Object.keys(expected.data)) {
        const rows = structuredClone(expected.data[key]);
        if (key === 'sessions' && name === 'legacy-v1') rows.forEach(row => { row.templateId ??= null; });
        assert.equal(restored.data[key].length, rows.length, `${name}.${key} count`);
        for (let i=0;i<rows.length;i++) {
          for (const [field,value] of Object.entries(rows[i])) {
            assert.deepEqual(restored.data[key][i][field], value, `${name}.${key}[${i}].${field}`);
          }
        }
      }
      assert(restored.data.settings.some(row => row.key === 'theme_mode' && row.value === 'dark'));
      assert(restored.data.sessions.every(row => row.origin === 'legacy'));
      assert(restored.data.sets.every(row => row.sourceUnit === 'kg' && Number(row.sourceWeight) === row.weight));
      assert.equal(restored.data.plans.length, expected.data.templates?.length ? 1 : 0);
      assert(restored.data.templates.every(row => row.planId === restored.data.plans[0].id));
      await screenshot(`08-${name}`);
    }
  });
  await check('empty backup warning, immediate refresh and persistence without reseeding', async () => {
    const file = path.join(root, 'test', 'fixtures', 'backup', 'current-v2.json');
    await selectFile(file); await expectText('此备份没有训练记录'); await expectText('本机有进行中的训练');
    await screenshot('09-empty-warning'); await clickText('替换并恢复', true); await expectText('开始训练');
    assert(!(await has('继续')));
    await send('Page.reload');
    const restored = (await exportFile('empty-after-reload')).data;
    assert.equal(restored.data.exercises.length, 0); assert.equal(restored.data.sessions.length, 0);
    await clickText('历史', true); await expectText('还没有已完成的训练'); await screenshot('10-final-empty');
  });
  }
  assert.equal(errors.length, 0, `Browser runtime errors: ${JSON.stringify(errors)}`);
} catch (error) {
  failed = true;
  errors.push(String(error.stack || error));
  if (socket?.readyState === WebSocket.OPEN) {
    try { await screenshot('failure'); } catch { /* Original failure is kept in results.json. */ }
  }
  console.error(error);
} finally {
  await writeFile(path.join(output, 'results.json'), JSON.stringify({
    timestamp: stamp, passed: !failed, origin, profile, checks, errors,
    scope: 'Chrome preview with real SQLite wasm; does not replace Android device acceptance.',
  }, null, 2));
  await writeFile(path.join(output, 'chrome.log'), chromeLog);
  if (socket?.readyState === WebSocket.OPEN) {
    try { await send('Browser.close'); } catch { /* Chrome can close before replying. */ }
    socket.close();
  }
  browserSocket?.close();
  if (chrome.exitCode === null) chrome.kill();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  console.log(`Evidence: ${output}`);
  process.exitCode = failed ? 1 : 0;
}
