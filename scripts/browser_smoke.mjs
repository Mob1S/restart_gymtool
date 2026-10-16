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
  return {text: e.getAttribute('aria-label') || Array.from(e.querySelectorAll('input,textarea')).map(i=>i.getAttribute('aria-label') || i.placeholder || '').filter(Boolean).join('\\n') || e.innerText || '', role: e.getAttribute('role'),
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
async function has(text) { return (await semantics()).some(e => e.text.includes(text)); }
async function expectText(text) { await until(() => has(text), `text: ${text}`); }
async function clickAt(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  }
  await delay(400);
}
async function clickText(text, exact = false) {
  const element = await until(async () => {
    const matches = (await semantics()).filter(e => (exact ? e.text === text : e.text.includes(text)) && (text.startsWith('收藏 ') || !e.text.startsWith('收藏 ')));
    return matches.sort((a, b) => a.width * a.height - b.width * b.height)[0];
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
async function swipeLeft() {
  await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 345, y: 380 }] });
  for (let x = 325; x >= 45; x -= 20) {
    await send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: 380 }] });
    await delay(20);
  }
  await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await delay(700);
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

  await check('empty history and progress', async () => {
    await clickText('历史', true);
    await expectText('还没有已完成的训练');
    await screenshot('01-empty-history');
    await clickText('进步', true);
    await expectText('还没有练过的动作');
    await screenshot('02-empty-progress');
  });
  await check('record one real set and finish workout', async () => {
    await clickText('训练', true);
    await clickText('开始训练');
    await clickText('添加动作');
    await clickAt(100,166);
    await send('Input.insertText', { text: '深蹲' });
    await clickText('深蹲');
    await clickText('添加 1 个动作',true);
    await expectText('完成这组');
    await screenshot('03-record');
    await clickText('完成这组');
    await expectText('开始第 2 组');
    await screenshot('04-rest');
    await clickText('结束训练');
    await expectText('总容量（重量 × 次数）');
    await expectText('160');
    await screenshot('05-summary');
    await clickText('完成', true);
  });
  await check('history list to detail and back', async () => {
    await clickText('历史', true);
    await expectText('1 组 · 160 kg');
    await screenshot('06-history');
    await clickText('未命名训练');
    await expectText('训练详情');
    await expectText('160');
    await screenshot('07-history-detail');
    await clickText('Back');
    await expectText('1 组 · 160 kg');
  });
  await check('progress list and three metric cards', async () => {
    await clickText('进步', true);
    await clickText('深蹲');
    await expectText('最大重量');
    await expectText('再练一次就能看到走势');
    await screenshot('08-top-weight');
    await swipeLeft();
    await expectText('估算 · 仅供参考');
    await expectText('来自 20 kg × 8');
    await expectText('25');
    await screenshot('09-e1rm');
    await swipeLeft();
    await expectText('最高 ·');
    await expectText('160');
    await screenshot('10-volume');
    assert(!(await has('个人最好')), 'Forbidden metric wording');
    await clickText('Back');
    await expectText('最重 20 kg × 8');
  });
  await check('IndexedDB survives reload', async () => {
    await send('Page.reload');
    await clickText('进步', true);
    await expectText('最重 20 kg × 8');
    await screenshot('11-reloaded-progress');
  });
  await check('50 kg x 8 x 4 sets: e1RM 62 and volume 1600', async () => {
    await clickText('训练', true);
    await clickText('开始训练');
    // The next workout copies the previous exercise and its last set values.
    await expectText('20 kg');
    const weight = (await semantics()).find(e => e.text === '20 kg');
    assert(weight, 'Weight control must show 20 kg before editing.');
    const plus = (await semantics()).filter(e => e.role === 'button' && e.text === '增加' &&
      e.x > weight.x + weight.width / 2 && e.y >= weight.y + weight.height &&
      e.y < weight.y + weight.height + 100).sort((a, b) => a.y - b.y)[0];
    assert(plus, 'Weight increment control must be visible.');
    for (let i = 0; i < 12; i++) await clickAt(plus.x + plus.width / 2, plus.y + plus.height / 2);
    await expectText('50 kg');
    await screenshot('12-record-50kg');
    for (let i = 1; i <= 4; i++) {
      await clickText('完成这组');
      await expectText(`开始第 ${i + 1} 组`);
      if (i < 4) await clickText(`开始第 ${i + 1} 组`);
    }
    await clickText('结束训练');
    await expectText('1600');
    await expectText('8 / 8 / 8 / 8');
    await screenshot('13-four-set-summary');
    await clickText('完成', true);
    await clickText('历史', true);
    await expectText('4 组 · 1600 kg');
    await screenshot('14-four-set-history');
    await clickText('进步', true);
    await expectText('最重 50 kg × 8');
    await clickText('深蹲');
    await swipeLeft();
    await expectText('来自 50 kg × 8');
    await expectText('62');
    await screenshot('15-e1rm-62');
    await swipeLeft();
    await expectText('最高 ·');
    await expectText('1600');
    await screenshot('16-volume-1600');
  });
  await check('unknown exercise deep link', async () => {
    await send('Page.navigate', { url: `${origin}/#/progress/acceptance-missing-exercise` });
    await expectText('这个动作还没有记录');
    await screenshot('17-unknown-exercise');
  });
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
  if (chrome.exitCode === null) chrome.kill();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  console.log(`Evidence: ${output}`);
  process.exitCode = failed ? 1 : 0;
}
