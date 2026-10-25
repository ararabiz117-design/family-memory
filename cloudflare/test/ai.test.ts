import test from 'node:test';
import assert from 'node:assert/strict';
import { extractInvitation, answerGuide, DEFAULT_AI_MODEL, type AiRunner } from '../src/ai.js';

function mock(response: unknown) {
  const calls: { model: string; input: Record<string, unknown> }[] = [];
  const ai: AiRunner = { async run(model, input) { calls.push({ model, input }); return { response }; } };
  return { ai, calls };
}
const valid = { title: '三回忌', date: '2027-06-20', time: '10:30', place: '架空寺院', uncertainties: [] };

test('requires explicit operation consent and bounds input before AI invocation', async () => {
  const { ai, calls } = mock(valid);
  await assert.rejects(extractInvitation(ai, { text: '案内状', consent: false }));
  await assert.rejects(extractInvitation(ai, { text: 'a'.repeat(6001), consent: true }));
  await assert.rejects(answerGuide(ai, { question: 'a'.repeat(1201), consent: true }));
  assert.equal(calls.length, 0);
});

test('extracts validated candidate only and requires user confirmation', async () => {
  const { ai, calls } = mock(JSON.stringify(valid));
  const result = await extractInvitation(ai, { text: '2027年6月20日 10時30分 架空寺院 三回忌', consent: true });
  assert.equal(result.date, '2027-06-20');
  assert.equal(result.requiresConfirmation, true);
  assert.match(result.caution, /寺院/);
  assert.equal(calls[0]!.model, DEFAULT_AI_MODEL);
  assert.equal(calls[0]!.input.stream, false);
  assert.equal(calls[0]!.input.temperature, 0);
  assert.equal('tools' in calls[0]!.input, false);
});

test('does not accept model-provided actions, invalid dates/times or malformed responses', async () => {
  for (const response of [
    { ...valid, date: '2027-02-30' }, { ...valid, time: '24:01' },
    { ...valid, date: '1300-01-01' }, { ...valid, action: 'write_database' },
    { ...valid, uncertainties: ['a'.repeat(241)] }, 'not json', null,
  ]) await assert.rejects(extractInvitation(mock(response).ai, { text: '案内状', consent: true }));
});

test('allows unknown candidates, handles AI failure without fallback guesses', async () => {
  const result = await extractInvitation(mock({ title: null, date: null, time: null, place: null, uncertainties: ['年を確認してください。'] }).ai, { text: '6月20日', consent: true });
  assert.equal(result.date, null);
  await assert.rejects(extractInvitation({ async run() { throw new Error('unavailable'); } }, { text: '案内状', consent: true }));
});

test('guide output is structured and always carries fixed uncertainty guidance', async () => {
  const { ai, calls } = mock({ answer: '主催者や寺院へ確認してください。', checks: ['宗派と会場の指定を確認する'] });
  const result = await answerGuide(ai, { question: '法要の服装は？', consent: true });
  assert.equal(result.checks.length, 1); assert.equal(result.requiresConfirmation, true);
  assert.match(result.caution, /宗派・地域・家庭/);
  const system = (calls[0]!.input.messages as { content: string }[])[0]!.content;
  assert.match(system, /金融・法律・税務/);
  assert.match(system, /四十九日/);
  await assert.rejects(answerGuide(mock({ answer: '', checks: [] }).ai, { question: '服装', consent: true }));
});
