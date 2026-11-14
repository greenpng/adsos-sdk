'use strict';
// 金标（node --test，零依赖）：载荷形状、requestId 前缀、204/错误分支、
// beacon 解析与点击落地解析。独立预期先写定，不用实现自证。
const test = require('node:test');
const assert = require('node:assert');
const { buildPayload, trackerUrl, parseDecision, newRequestId } = require('../src/adsos');

const cfg = { endpoint: 'https://ads.example.com', requestIdPrefix: 'uni', now: () => 1700000000000 };
const input = {
  siteId: 'site-1',
  zoneId: 'mrec-1',
  publisherId: 'pub-1',
  device: { type: 'mobile', language: 'zh-CN', width: 390, height: 844 },
  geo: { country: 'CN' },
  consent: { region: 'NONE' },
};

test('payload matches the frozen request contract', () => {
  const p = buildPayload(cfg, input, 1700000000000);
  assert.equal(p.requestId.slice(0, 3), 'uni');
  assert.equal(p.siteId, 'site-1');
  assert.equal(p.zoneId, 'mrec-1');
  assert.equal(p.ts, 1700000000000);
  assert.equal(p.device.type, 'mobile');
  assert.equal(p.consent.region, 'NONE');
  assert.ok(!('ip' in p), 'client never self-reports ip');
});

test('request ids differ across calls', () => {
  assert.notEqual(newRequestId('uni', 1), newRequestId('uni', 1));
});

test('tracker urls resolve against endpoint, absolute passes through', () => {
  assert.equal(trackerUrl(cfg, '/v1/track/x'), 'https://ads.example.com/v1/track/x');
  assert.equal(trackerUrl(cfg, 'https://cdn.example.com/b'), 'https://cdn.example.com/b');
});

test('decision parsing: 204 no-fill, error status, malformed body', () => {
  assert.deepEqual(parseDecision(204, ''), { filled: false });
  assert.throws(() => parseDecision(500, ''), /HTTP 500/);
  assert.throws(() => parseDecision(200, '{"decision":{"trackers":{}}}'), /malformed/);
  const ok = parseDecision(
    200,
    JSON.stringify({
      decision: { campaignId: 'c', trackers: { impression: '/i', click: '/c' }, landingUrl: 'https://l' },
    }),
  );
  assert.equal(ok.filled, true);
  assert.equal(ok.decision.campaignId, 'c');
});
