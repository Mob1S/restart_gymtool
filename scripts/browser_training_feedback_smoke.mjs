import assert from 'node:assert/strict';
import path from 'node:path';
import {writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {enableBundledPlugins} from './browser_plugin_helpers.mjs';

export async function run(h) {
  const {check, clickText, expectText, send} = h;
  const navigate = route => send('Page.navigate', {url: h.origin + '/#' + route});
  const resumeLabel = '继续训练，验收训练，已完成 1 组';
  async function reveal(text, exact = false) {
    for (let i = 0; i < 25; i++) {
      const height = await h.evaluate('innerHeight');
      const candidates = (await h.semantics()).filter(e => exact ? e.text === text : e.text.includes(text));
      const element = candidates.sort((a, b) => a.width * a.height - b.width * b.height)[0];
      if (element && element.y + element.height / 2 > 60 &&
          element.y + element.height / 2 < height - 8) return element;
      await send('Input.dispatchMouseEvent', {type: 'mouseWheel', x: 180,
        y: Math.max(90, height - 170), deltaX: 0, deltaY: element?.y < 45 ? -220 : 240});
      await delay(180);
    }
    throw new Error('Cannot reveal ' + text);
  }
  async function visibleClick(text, exact = false) {
    await reveal(text, exact);
    await clickText(text, exact);
  }
  // Flutter merges static summary text into a single accessibility node. Check
  // its contents, then scroll the real viewport for visual evidence.
  async function showComparison(text) {
    await expectText(text);
    const height = await h.evaluate('innerHeight');
    for (let i = 0; i < 4; i++) {
      await send('Input.dispatchMouseEvent', {type: 'mouseWheel', x: 180,
        y: height / 2, deltaX: 0, deltaY: 650});
      await delay(180);
    }
  }
  async function typeField(label, text) {
    await visibleClick(label);
    for (const type of ['keyDown', 'keyUp']) {
      await send('Input.dispatchKeyEvent', {type, key: 'a', code: 'KeyA', modifiers: 2, windowsVirtualKeyCode: 65});
    }
    await send('Input.insertText', {text});
  }

  const now = Date.now() - 300000;
  const before = now - 3 * 86400000;
  const exercise = (id, name, group, equipment) => ({id, name, muscleGroup: group,
    equipment, isCustom: true, isArchived: false, createdAt: before - 1000});
  const session = (id, name, at, finishedAt) => ({id, name, startedAt: at,
    finishedAt, note: null, templateId: null});
  const set = (id, owner, position, weight, reps, completed, restStartedAt = null) => ({
    id, sessionExerciseId: owner, position, weight, reps, isCompleted: completed,
    restSeconds: null, restStartedAt, completedAt: completed ? now - 10000 : null,
  });
  const fixture = {format: 'gym-tracker-backup', version: 2, schemaVersion: 4,
    exportedAt: Date.now(), data: {
      exercises: [exercise('feedback-bench', '验收卧推', '胸', '杠铃'),
        exercise('feedback-row', '验收划船', '背', '器械')],
      sessions: [session('feedback-previous', '上次验收', before, before + 60000),
        session('feedback-current', '验收训练', now, null)],
      sessionExercises: [
        {id: 'previous-bench', sessionId: 'feedback-previous', exerciseId: 'feedback-bench', position: 0, note: null},
        {id: 'current-bench', sessionId: 'feedback-current', exerciseId: 'feedback-bench', position: 0, note: null},
        {id: 'current-row', sessionId: 'feedback-current', exerciseId: 'feedback-row', position: 1, note: null},
      ],
      sets: [set('previous-set', 'previous-bench', 0, 60, 7, true),
        set('current-set', 'current-bench', 0, 60, 8, true, now - 10000),
        set('current-pending', 'current-bench', 1, 60, 8, false),
        set('row-pending', 'current-row', 0, 30, 8, false)],
      templates: [], templateExercises: [], settings: [{key: 'theme_mode', value: 'dark'}],
    }};
  fixture.data.sets[0].completedAt = before + 50000;
  const fixturePath = path.join(h.output, 'feedback-fixture-v2.json');
  await writeFile(fixturePath, JSON.stringify(fixture));

  await check('cold progress deep link restores the active workout above three-tab navigation', async () => {
    await expectText('开始训练');
    await h.restoreFile(fixturePath);
    await navigate('/progress');
    await send('Page.reload');
    await expectText(resumeLabel);
    assert(await h.has('历史'));
    assert(!await h.has('动作分析'));
    await h.screenshot('01-progress-resume-bar');
  });

  await check('resume round trip keeps selected exercise and recorded rest timestamp', async () => {
    await clickText(resumeLabel, true);
    await expectText('开始第 2 组');
    await clickText('验收划船', true);
    await expectText('30 kg');
    await clickText('Back', true);
    await clickText('历史', true);
    await clickText(resumeLabel, true);
    await expectText('30 kg');
    assert(!await h.has('开始第 2 组'));
    await clickText('Back', true);
    await navigate('/progress');
    const exported = await h.exportFile('resume-preserved');
    assert.equal(exported.data.data.sessions.length, 2);
    assert.equal(exported.data.data.sessions.filter(s => s.finishedAt === null).length, 1);
    assert.equal(exported.data.data.sets.find(s => s.id === 'current-set').restStartedAt, now - 10000);
    assert.equal(exported.data.data.sets.filter(s => s.sessionExerciseId === 'current-bench').length, 2);
  });

  await check('five enabled destinations keep their order and the same resume entry', async () => {
    await enableBundledPlugins(h);
    await navigate('/progress');
    await expectText(resumeLabel);
    const labels = (await h.semantics()).filter(e => ['训练', '热量', '动作分析', '历史', '进步'].includes(e.text));
    const bottom = labels.filter(e => e.y > 650).sort((a, b) => a.x - b.x).map(e => e.text);
    assert.deepEqual(bottom, ['训练', '热量', '动作分析', '历史', '进步']);
    await h.screenshot('02-five-tabs-resume');
  });

  await check('finish shows raw previous records and first-record feedback without an active bar', async () => {
    await clickText(resumeLabel, true);
    await expectText('30 kg');
    await clickText('完成这组');
    await clickText('结束训练');
    await expectText('训练总结');
    await showComparison('训练量变化：1 组 → 1 组 · 容量增加 60 kg');
    await h.screenshot('03-session-comparison-dark');
    await expectText('首次记录，暂没有上次可对比');
    await visibleClick('完成', true);
    await navigate('/progress');
    assert(!(await h.has('继续训练，')));
  });

  await check('editing a previous actual set updates the current comparison', async () => {
    await navigate('/history/feedback-previous');
    await visibleClick('第 1 组 · 60 kg × 7');
    await expectText('修改第 1 组');
    await typeField('实际次数', '6');
    await visibleClick('保存', true);
    await expectText('训练详情');
    await navigate('/history/feedback-current');
    await showComparison('训练量变化：1 组 → 1 组 · 容量增加 120 kg');
    await h.screenshot('04-corrected-baseline');
  });

  await check('light narrow comparison retains readable raw records', async () => {
    await navigate('/settings');
    await clickText('浅色', true);
    await navigate('/history/feedback-current');
    await send('Emulation.setDeviceMetricsOverride', {width: 320, height: 640, deviceScaleFactor: 1, mobile: true});
    await showComparison('训练量变化：1 组 → 1 组 · 容量增加 120 kg');
    const rows = await h.semantics();
    assert(rows.filter(e => e.text.includes('容量增加 120 kg')).every(e => e.x >= 0 && e.x + e.width <= 321));
    await h.screenshot('05-comparison-light-narrow');
    await send('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 1, mobile: true});
  });

  await check('removing a prior session recalculates first-record status', async () => {
    await navigate('/history/feedback-previous');
    await clickText('删除这场训练', true);
    await expectText('此操作无法撤销');
    await clickText('删除这场训练', true);
    await navigate('/history/feedback-current');
    await showComparison('首次记录，暂没有上次可对比');
    assert(!await h.has('容量增加 120 kg'));
    await h.screenshot('06-deleted-baseline');
    await navigate('/history');
    const exported = await h.exportFile('feedback-final');
    assert.equal(exported.data.version, 8);
    assert.equal(exported.data.schemaVersion, 12);
    assert.deepEqual(exported.data.data.sessions.map(s => s.id), ['feedback-current']);
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE = 'training_feedback';
  import('./browser_backup_smoke.mjs').catch(error => {console.error(error); process.exitCode = 1;});
}
