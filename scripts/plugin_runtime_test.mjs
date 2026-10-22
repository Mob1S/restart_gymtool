import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(value => { resolve = value; }); return { promise, resolve }; };
const base = { URL, Promise, Set, Map, WeakMap, Error, AbortController, AbortSignal, setTimeout, clearTimeout, Uint8Array, Blob, performance };

// Loader: no eager feature imports; concurrent loads share one promise; failure
// can retry; disabling an unused plugin never imports it.
{
  const scripts = [];
  const window = {};
  const document = { baseURI: 'https://gym.test/', createElement: () => ({ remove() { this.removed = true; } }), head: { append: script => scripts.push(script) } };
  const context = vm.createContext({ ...base, window, document });
  vm.runInContext(await readFile(new URL('../web/plugin_runtime_loader.js', import.meta.url), 'utf8'), context);
  const loader = window.gymPluginRuntime;
  await loader.activate('motion'); await loader.deactivate('beverage');
  assert.equal(scripts.length, 0);
  await assert.rejects(loader.load('beverage'), /插件已停用/);
  const first = loader.load('motion'), concurrent = loader.load('motion');
  assert.equal(first, concurrent); assert.equal(scripts.length, 1);
  scripts[0].onerror(); await assert.rejects(first, /未能加载/);
  assert.equal(scripts[0].removed, true);
  const retry = loader.load('motion'); assert.equal(scripts.length, 2);
  let stops = 0;
  window.gymMotion = { call: async method => { if (method === 'deactivate') stops++; } };
  scripts[1].onload(); await retry; await loader.deactivate('motion');
  assert.equal(stops, 1); assert.equal(scripts[1].type, 'module');
}

// Closing a motion session aborts pending video decoding, waits for its call,
// terminates the owned worker and discards events from its old generation.
{
  let created = 0, terminated = 0, stopped = 0, held;
  const devices = deferred();
  class Worker {
    constructor() { created++; }
    postMessage({ id }) { queueMicrotask(() => this.onmessage?.({ data: { id } })); }
    terminate() { terminated++; }
  }
  class Video extends EventTarget {
    requestVideoFrameCallback() {} pause() {} load() {} removeAttribute() {}
  }
  const window = { Worker, OffscreenCanvas: class {} };
  const context = vm.createContext({ ...base, window, Worker, queueMicrotask, isSecureContext: true,
    store: { get: async () => new Blob(['video']), collect: async (_, active) => { held = [...active]; } },
    document: { createElement: () => new Video(), addEventListener() {} },
    navigator: { mediaDevices: { getUserMedia: () => devices.promise } } });
  let source = await readFile(new URL('../web/motion/runtime.js', import.meta.url), 'utf8');
  source = source.replace("import * as store from './store.js';", '').replaceAll('import.meta.url', "'https://gym.test/motion/runtime.js'");
  vm.runInContext(source, context);
  const motion = window.gymMotion;
  await motion.call('activate', '{}'); await motion.call('capabilities', '{}');
  assert.equal(created, 0);
  const open = motion.call('open', '{"folder":"a"}');
  const openFailure = assert.rejects(open, /已取消/);
  await tick(); await motion.call('close', '{}'); await openFailure;
  await motion.call('collect', '{"keep":[]}');
  assert.deepEqual(held, ['a'], 'cancelled decoding keeps unsaved editor media pinned');
  await motion.call('release', '{"folder":"a"}');
  await motion.call('collect', '{"keep":[]}'); assert.deepEqual(held, []);
  const camera = motion.call('camera', '{"session":"old"}');
  const cameraFailure = assert.rejects(camera, /已取消/);
  await tick(); assert.equal(created, 1);
  let closed = false;
  const closing = motion.call('deactivate', '{}').then(() => { closed = true; });
  await tick(); assert.equal(closed, false);
  devices.resolve({ getTracks: () => [{ stop: () => { stopped++; } }] });
  await closing; await cameraFailure;
  assert.equal(stopped, 1); assert.equal(terminated, 1);
  await assert.rejects(motion.call('open', '{}'), /插件已停用/);
  await motion.call('activate', '{}'); await motion.call('capabilities', '{}');
  assert.equal(created, 1);
}

// OCR cancellation also waits for a worker still being created, including its
// asynchronous terminate acknowledgement; no stale recognition is published.
{
  const creating = deferred(), terminating = deferred();
  let picker, began = false, recognized = 0, terminations = 0;
  const window = {};
  const document = { baseURI: 'https://gym.test/', body: { append: value => { picker = value; } },
    head: { append: script => queueMicrotask(() => script.onload()) },
    createElement: tag => ({ tag, style: {}, remove() {}, click() {}, setAttribute() {} }) };
  const context = vm.createContext({ ...base, window, document, queueMicrotask,
    createImageBitmap: async () => ({ width: 10, height: 10, close() {} }),
    Tesseract: { createWorker: () => { began = true; return creating.promise; } } });
  vm.runInContext(await readFile(new URL('../web/beverage/runtime.js', import.meta.url), 'utf8'), context);
  const beverage = window.gymBeverage;
  const scan = beverage.scan(false); await tick();
  picker.files = [{ size: 10 }]; picker.onchange(); await tick();
  assert.equal(began, true);
  let closed = false;
  const close = beverage.deactivate().then(() => { closed = true; });
  creating.resolve({ recognize() { recognized++; }, terminate() { terminations++; return terminating.promise; } });
  await tick(); assert.equal(closed, false); assert.equal(terminations, 1);
  terminating.resolve(); await close;
  assert.equal(await scan, 'null'); assert.equal(recognized, 0);
  await assert.rejects(beverage.scan(false), /插件已停用/);
  beverage.activate();
  const picking = beverage.scan(false); await tick(); await beverage.cancel();
  assert.equal(await picking, 'null');

  const retryCreation = deferred();
  context.Tesseract.createWorker = () => retryCreation.promise;
  const failingScan = beverage.scan(false); await tick();
  const scanFailure = assert.rejects(failingScan, /termination failed/);
  picker.files = [{ size: 10 }]; picker.onchange(); await tick();
  const failedClose = assert.rejects(beverage.deactivate(), /资源尚未关闭/);
  let attempts = 0;
  retryCreation.resolve({ terminate() { if (++attempts === 1) return Promise.reject(new Error('termination failed')); } });
  await failedClose; await scanFailure;
  await beverage.deactivate();
  assert.equal(attempts, 2, 'failed termination remains owned and can be retried');
}

// Leaving one search page cancels only its own actual network requests.
{
  const window={};
  const context=vm.createContext({...base,window,document:{baseURI:'https://gym.test/'}});
  vm.runInContext(await readFile(new URL('../web/beverage/runtime.js',import.meta.url),'utf8'),context);
  const beverage=window.gymBeverage,operations=new Map();
  beverage.fetch=(url,signal)=>new Promise((resolve,reject)=>{
    operations.set(url,{resolve,signal});signal.addEventListener('abort',()=>reject(new Error('aborted')),{once:true});
  });
  const first=beverage.get('first','page-a'),second=beverage.get('second','page-b');
  const cancelled=assert.rejects(first,/aborted/);
  await beverage.cancelSearch('page-a');await cancelled;
  assert.equal(operations.get('second').signal.aborted,false);
  operations.get('second').resolve('ok');assert.equal(await second,'ok');
}
console.log('Plugin platform lifecycle: loader concurrency/retry, lazy activation, awaited motion/OCR cancellation, scoped search cancellation and reactivation passed.');
