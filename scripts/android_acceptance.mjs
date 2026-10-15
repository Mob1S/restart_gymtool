// Small ADB driver for manual acceptance. It never clears app data or installs APKs.
// Example: node scripts/android_acceptance.mjs snapshot 01-home
// Use ANDROID_SERIAL with multiple devices and GYM_ACCEPTANCE_OUTPUT to group evidence.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { appendFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const adb = process.env.ADB_EXECUTABLE || path.join(root, '.tooling/android-sdk/platform-tools/adb.exe');
const appPackage = process.env.GYM_ACCEPTANCE_PACKAGE || 'com.mobis.gym_tracker';
const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai',
  year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const output = path.resolve(process.env.GYM_ACCEPTANCE_OUTPUT || path.join(root, 'build/acceptance', `android-${date}`));
await mkdir(output, { recursive: true });
const devices = execFileSync(adb, ['devices'], { encoding: 'utf8', windowsHide: true })
  .split(/\r?\n/).filter(line => /\sdevice$/.test(line)).map(line => line.split(/\s+/)[0]);
const serial = process.env.ANDROID_SERIAL || (devices.length === 1 ? devices[0] : null);
assert(serial && devices.includes(serial), 'Connect and authorize one device, or set ANDROID_SERIAL.');
function run(args, binary = false) {
  return execFileSync(adb, ['-s', serial, ...args], {
    windowsHide: true, encoding: binary ? undefined : 'utf8', timeout: 45000,
    maxBuffer: 20 * 1024 * 1024,
  });
}
function decode(value) {
  return value.replace(/&#10;/g, '\n').replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}
function dump() {
  run(['shell', 'uiautomator', 'dump', '/sdcard/gym-acceptance.xml']);
  const xml = run(['shell', 'cat', '/sdcard/gym-acceptance.xml']);
  const nodes = [...xml.matchAll(/<node\b[^>]*>/g)].map(match => {
    const attrs = Object.fromEntries([...match[0].matchAll(/([\w-]+)="([^"]*)"/g)]
      .map(item => [item[1], decode(item[2])]));
    const bounds = attrs.bounds?.match(/\d+/g)?.map(Number);
    return { label: attrs['content-desc'] || attrs.text || '', clickable: attrs.clickable === 'true',
      class: attrs.class, bounds, package: attrs.package };
  });
  return { xml, nodes };
}
function tapNode(node) {
  assert(node.bounds?.length === 4, 'No valid target bounds.');
  const [left, top, right, bottom] = node.bounds;
  run(['shell', 'input', 'tap', String(Math.round((left + right) / 2)), String(Math.round((top + bottom) / 2))]);
}
const [command, ...args] = process.argv.slice(2);
let result;
switch (command) {
  case 'snapshot': {
    const name = args[0] || 'snapshot';
    assert(/^[a-zA-Z0-9_-]+$/.test(name), 'Use a simple evidence filename.');
    const { xml, nodes } = dump();
    assert(nodes.some(node => node.package === appPackage && node.label),
      'No app semantics: unlock the phone and confirm the app is in front before capturing.');
    await writeFile(path.join(output, `${name}.xml`), xml);
    await writeFile(path.join(output, `${name}.json`), JSON.stringify(nodes, null, 2));
    await writeFile(path.join(output, `${name}.png`), run(['exec-out', 'screencap', '-p'], true));
    result = { image: path.join(output, `${name}.png`), nodes: nodes.filter(node => node.label) };
    break;
  }
  case 'tap': {
    const label = args.join(' ');
    const candidates = dump().nodes.filter(node => node.label.includes(label));
    const target = candidates.find(node => node.clickable && node.label === label) ||
      candidates.find(node => node.clickable && node.label.startsWith(`${label}\nTab `)) ||
      candidates.find(node => node.clickable) || candidates.find(node => node.label === label) || candidates[0];
    assert(target, `No target containing ${label}`);
    tapNode(target);
    result = { tapped: target };
    break;
  }
  case 'assert': {
    const label = args.join(' ');
    assert(dump().nodes.some(node => node.label.includes(label)), `Missing text: ${label}`);
    result = { found: label };
    break;
  }
  case 'tap-at':
    assert(args.length === 2 && args.every(value => /^\d+$/.test(value)), 'tap-at needs x y');
    result = run(['shell', 'input', 'tap', ...args]);
    break;
  case 'swipe':
    assert(args.length === 5 && args.every(value => /^\d+$/.test(value)), 'swipe needs x1 y1 x2 y2 duration');
    result = run(['shell', 'input', 'swipe', ...args]);
    break;
  case 'back':
    result = run(['shell', 'input', 'keyevent', '4']);
    break;
  case 'text':
    // Android's input text supports ASCII here; Chinese selection uses the semantics tree.
    assert(args.length === 1 && /^[a-zA-Z0-9_-]+$/.test(args[0]), 'text needs one ASCII search token');
    result = run(['shell', 'input', 'text', args[0]]);
    break;
  case 'force-stop':
    result = run(['shell', 'am', 'force-stop', appPackage]);
    break;
  case 'start':
    assert(args.length <= 1 && (!args[0] || /^\/[a-zA-Z0-9/_-]*$/.test(args[0])), 'Use one optional route path.');
    result = run(['shell', 'am', 'start', '-n', `${appPackage}/com.mobis.gym_tracker.MainActivity`,
      ...(args[0] ? ['--es', 'route', args[0]] : [])]);
    break;
  case 'idle-check': {
    const screenTimeout = Number(run(['shell', 'settings', 'get', 'system', 'screen_off_timeout']).trim());
    assert(screenTimeout > 0 && screenTimeout <= 45000, 'Idle check requires a timeout of at most 45s.');
    const before = run(['shell', 'dumpsys', 'power']);
    assert(/mStayOn=false/.test(before), 'Disable USB forced stay-awake before testing app wakelock.');
    const started = Date.now();
    await delay(screenTimeout + 5000);
    const after = run(['shell', 'dumpsys', 'power']);
    const window = run(['shell', 'dumpsys', 'window']);
    result = { screenTimeout, elapsed: Date.now() - started,
      awake: /mWakefulness=Awake/.test(after), usbForcedAwake: !/mStayOn=false/.test(after),
      appKeepScreenOn: /fl=KEEP_SCREEN_ON/.test(window) };
    await writeFile(path.join(output, 'keep-awake.json'), JSON.stringify(result, null, 2));
    assert(result.awake && !result.usbForcedAwake && result.appKeepScreenOn, 'App did not keep the screen awake.');
    break;
  }
  case 'sleep-check': {
    const clock = nodes => nodes.find(node => /^\d{2,}:\d{2}$/.test(node.label))?.label;
    const seconds = label => label.split(':').reduce((sum, part) => sum * 60 + Number(part), 0);
    const before = clock(dump().nodes);
    assert(before, 'Enter the rest screen before testing sleep.');
    const started = Date.now();
    run(['shell', 'input', 'keyevent', '223']);
    await delay(35000);
    const sleeping = run(['shell', 'dumpsys', 'power']);
    run(['shell', 'input', 'keyevent', '224']);
    run(['shell', 'wm', 'dismiss-keyguard']);
    await delay(700);
    const after = clock(dump().nodes);
    result = { before, after: after || null, wallSeconds: (Date.now() - started) / 1000,
      slept: /mWakefulness=(Asleep|Dozing)/.test(sleeping),
      timerDelta: after ? seconds(after) - seconds(before) : null };
    await writeFile(path.join(output, 'sleep-timer.json'), JSON.stringify(result, null, 2));
    assert(after, 'Unlock the phone, then inspect the rest timer.');
    assert(result.slept && Math.abs(result.timerDelta - result.wallSeconds) <= 4,
      'The rest timer did not track wall time across sleep.');
    break;
  }
  case 'feedback': {
    const records = run(['shell', 'dumpsys', 'vibrator_manager']).split(/\r?\n/)
      .filter(line => line.includes(appPackage));
    await writeFile(path.join(output, 'haptic-feedback.txt'), records.join('\n') + '\n');
    assert(records.some(line => line.includes('finished')), 'No finished haptic effect for this app.');
    result = { hapticRecords: records };
    break;
  }
  case 'fresh-database': {
    assert(appPackage.endsWith('.acceptance'), 'Inspect only the separate acceptance package.');
    const files = run(['shell', 'run-as', appPackage, 'ls', 'databases']).split(/\s+/);
    const database = path.join(output, 'fresh-native.db');
    for (const suffix of ['', '-wal', '-shm']) {
      const name = `gym_tracker.db${suffix}`;
      if (files.includes(name)) {
        await writeFile(database + suffix, run(['exec-out', 'run-as', appPackage, 'cat', `databases/${name}`], true));
      }
    }
    const { DatabaseSync } = await import('node:sqlite');
    const db = new DatabaseSync(database, { readOnly: true });
    try {
      result = {
        // Android's SQLiteOpenHelper also creates android_metadata for locale.
        tables: db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' ORDER BY name").all().map(row => row.name),
        exercises: db.prepare('SELECT COUNT(*) AS n FROM exercise').get().n,
        sessions: db.prepare('SELECT COUNT(*) AS n FROM session').get().n,
        schemaVersion: db.prepare("SELECT value FROM app_meta WHERE key = 'schema_version'").get().value,
      };
      await writeFile(path.join(output, 'fresh-database.json'), JSON.stringify(result, null, 2));
      assert.deepEqual(result.tables, ['app_meta', 'app_setting', 'exercise', 'session', 'session_exercise', 'set_entry', 'split_template', 'template_exercise']);
      assert.equal(result.exercises, 52);
      assert.equal(result.sessions, 0);
      assert.equal(result.schemaVersion, '4');
    } finally { db.close(); }
    break;
  }
  default:
    throw new Error('Commands: snapshot, tap, assert, tap-at, swipe, back, text, force-stop, start, idle-check, sleep-check, feedback, fresh-database');
}
await appendFile(path.join(output, 'actions.jsonl'), JSON.stringify({
  at: new Date().toISOString(), command, args, result,
}) + '\n');
console.log(JSON.stringify(result, null, 2));
