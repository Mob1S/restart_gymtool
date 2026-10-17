import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

export async function run(h) {
  const { check, clickText, expectText, send, exportFile, screenshot } = h;
  async function type(text) {
    await send('Input.insertText', { text });
    await delay(250);
  }
  async function enterField(text) {
    const field = await h.until(async () => (await h.semantics()).find(
      e => e.role === 'textbox' && e.x >= 0 && e.y >= 0 && e.y < 780),
    'visible editor text field');
    await h.clickAt(field.x + Math.min(60, field.width / 2), field.y + field.height / 2);
    await type(text);
  }
  async function openPlans() {
    await clickText('训练', true);
    await h.tapText('管理计划');
    await expectText('训练计划');
  }
  async function addDay(name, repeat = 1) {
    await clickText('添加训练日', true);
    await enterField(name);
    for (let i = 0; i < repeat; i++) {
      await clickText('添加动作', true);
      await clickText('全部', true);
      await h.until(() => h.has('胸'), 'exercise picker data ready');
      await enterField('深蹲');
      const row = await h.until(async () => (await h.semantics()).find(
        e => e.text.split('\n')[0] === '深蹲' && e.width > 100), 'exact squat row');
      await h.clickAt(row.x + 100, row.y + row.height / 2);
      await clickText('添加 1 个动作', true);
    }
    await clickText('完成', true);
    await expectText(name);
  }
  async function add(name, days) {
    await clickText('新建计划', true);
    await expectText('还没有训练日');
    await enterField(name);
    for (const day of days) await addDay(day.name, day.repeat);
    await clickText('保存', true);
    await expectText(name);
  }
  await check('create ordered A B C parent plans with independent days and duplicate actions', async () => {
    await openPlans();
    await add('A', [{ name: 'A1', repeat: 2 }, { name: 'A2', repeat: 1 }]);
    await add('B', [{ name: 'B1', repeat: 1 }]);
    await add('C', [{ name: 'C1', repeat: 1 }]);
    await screenshot('01-plan-list');
    await clickText('Back');
    const { data } = await exportFile('01-plans');
    assert.deepEqual(data.data.plans.slice().sort((a,b) => a.position-b.position).map(p => p.name), ['A', 'B', 'C']);
    const parentA = data.data.plans.find(p => p.name === 'A');
    const aDays = data.data.templates.filter(t => t.planId === parentA.id).sort((a,b) => a.position-b.position);
    assert.deepEqual(aDays.map(t => t.name), ['A1', 'A2']);
    assert.equal(data.data.templateExercises.filter(e => e.templateId === aDays[0].id).length, 2);
  });
  await check('complete A1 with duplicate exercises and recommend A2 within parent A', async () => {
    await clickText('训练', true);
    await expectText('A1');
    await clickText('开始训练', true);
    await clickText('完成这组');
    await clickText('结束训练');
    await clickText('完成', true);
    await expectText('A2');
    await screenshot('02-next-A2');
  });
  await check('temporary day and parent choices create no session and cancel preserves recommendation', async () => {
    await clickText('选择训练日', true);
    await clickText('取消', true);
    await expectText('A2');
    await clickText('选择训练日', true);
    await clickText('A1');
    await expectText('A1');
    await clickText('切换计划', true);
    await clickText('取消', true);
    await expectText('A1');
    await clickText('切换计划', true);
    await clickText('C');
    await expectText('C1');
    const { data } = await exportFile('02-choice-not-started');
    assert.equal(data.data.sessions.length, 1);
    const parentC = data.data.plans.find(p => p.name === 'C');
    const selection = data.data.settings.find(setting => setting.key === 'active_training_plan_id');
    if (selection) assert.equal(selection.value, parentC.id);
    await clickText('训练', true);
  });
  await check('delete parent plan detaches finished session and preserves recorded sets', async () => {
    await openPlans();
    await clickText('删除计划'); await clickText('取消', true);
    await clickText('删除计划'); await clickText('删除计划', true); await clickText('Back');
    const { data } = await exportFile('03-plan-deleted');
    assert.deepEqual(data.data.plans.map(p => p.name), ['B', 'C']);
    assert.equal(data.data.sessions.length, 1);
    assert.equal(data.data.sessions[0].templateId, null);
    assert.equal(data.data.sessions[0].planId, null);
    assert.equal(data.data.sessions[0].dayNameSnapshot, 'A1');
    assert.equal(data.data.sets.filter(s => s.isCompleted).length, 1);
  });
  await check('delete exact history workout cancels first then removes children', async () => {
    await clickText('历史', true); await clickText('A1');
    await clickText('删除这场训练'); await clickText('取消', true);
    await clickText('删除这场训练'); await clickText('删除这场训练', true);
    await expectText('还没有已完成的训练');
    const { data } = await exportFile('04-record-deleted');
    assert.equal(data.data.sessions.length, 0); assert.equal(data.data.sets.length, 0);
  });
  await check('move parent plans by buttons and create a three-action day fixture', async () => {
    await openPlans(); await clickText('下移计划');
    await add('D', [{ name: 'D1', repeat: 3 }]); await clickText('Back');
    const { data } = await exportFile('05-reordered');
    assert.deepEqual(data.data.plans.slice().sort((a,b) => a.position-b.position).map(p => p.name), ['C', 'B', 'D']);
    const parentD = data.data.plans.find(p => p.name === 'D');
    const dayD = data.data.templates.filter(t => t.planId === parentD.id);
    assert.equal(dayD.length, 1);
    assert.equal(data.data.templateExercises.filter(e => e.templateId === dayD[0].id).length, 3);
  });
  await check('keep and hard-delete exercise branches survive reload with correct remaining sets', async () => {
    await clickText('训练', true); await clickText('切换计划', true); await clickText('D');
    await expectText('D1'); await clickText('开始训练', true);
    await clickText('完成这组'); await clickText('移除当前动作'); await clickText('取消', true);
    await clickText('移除当前动作'); await clickText('保留已记组', true);
    await send('Page.reload'); await expectText('继续训练'); await clickText('继续训练', true);
    await expectText('完成这组');
    await clickText('完成这组'); await clickText('移除当前动作'); await clickText('删掉这 1 组', true);
    assert.equal(await h.has('移除当前动作'), false);
    await clickText('完成这组'); await screenshot('03-removal'); await clickText('Back');
    const { data } = await exportFile('06-removed-actions');
    assert.equal(data.data.sessionExercises.length, 2);
    assert.equal(data.data.sets.filter(s => s.isCompleted).length, 2);
    const hidden = data.data.sessionExercises.find(e => data.data.sets.filter(s => s.sessionExerciseId === e.id).every(s => s.isCompleted));
    assert(hidden);
    assert(data.data.sets.filter(s => s.sessionExerciseId === hidden.id).every(s => s.restStartedAt === null));
  });
  await check('delete current active workout resets continue state and removes exactly its children', async () => {
    await clickText('训练', true); await clickText('继续训练', true);
    await clickText('删除这场训练'); await clickText('删除这场训练', true);
    await expectText('开始训练'); assert.equal(await h.has('继续训练'), false);
    const { data } = await exportFile('07-active-deleted');
    assert.equal(data.data.sessions.length, 0);
    assert.equal(data.data.sessionExercises.length, 0);
    assert.equal(data.data.sets.length, 0);
  });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE = 'plans';
  import('./browser_backup_smoke.mjs').catch(error => { console.error(error); process.exitCode = 1; });
}
