// 金标：真实 HTTP 桩（node:http）验证请求形状、beacon 与 204/错误分支。
// 独立预期先于断言手工写定：载荷字段与域模型一一对应；beacon 只发 GET。
import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { clickThrough, requestAd, trackImpression, type AdsosRnConfig } from '../src/index';

let server: Server;
let baseUrl = '';
const beacons: string[] = [];
let bodies: unknown[] = [];

beforeAll(async () => {
  server = createServer((req, res) => {
    if (req.method === 'POST' && req.url === '/v1/ad/request') {
      let raw = '';
      req.on('data', (c: Buffer) => {
        raw += c;
      });
      req.on('end', () => {
        bodies.push(JSON.parse(raw));
        if (bodies.length === 2) {
          res.writeHead(204);
          res.end();
          return;
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            decision: {
              auctionId: 'auc-1',
              campaignId: 'cmp-1',
              creativeId: 'crt-1',
              billingModel: 'CPM',
              format: '320x50',
              width: 320,
              height: 50,
              kind: 'html',
              trackers: { impression: '/v1/track/impression?e=1', click: '/v1/track/click?e=1' },
              landingUrl: 'https://landing.example.com',
            },
          }),
        );
      });
      return;
    }
    if (req.method === 'GET' && req.url?.startsWith('/v1/track/')) {
      beacons.push(req.url);
      if (req.url.startsWith('/v1/track/click')) {
        res.writeHead(302, { Location: 'https://landing.example.com' });
        res.end();
        return;
      }
      res.writeHead(200);
      res.end();
      return;
    }
    res.writeHead(404);
    res.end();
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const addr = server.address();
  if (addr && typeof addr === 'object') baseUrl = `http://127.0.0.1:${addr.port}`;
});

afterAll(() => {
  server.close();
});

function cfg(): AdsosRnConfig {
  return { endpoint: baseUrl, fetchImpl: fetch, now: () => 1_700_000_000_000 };
}

const input = {
  siteId: 'site-1',
  zoneId: 'mrec-1',
  publisherId: 'pub-1',
  device: { type: 'mobile' as const, language: 'en', width: 390, height: 844 },
  geo: { country: 'US' },
  consent: { region: 'NONE' as const },
};

describe('AdsOS React Native SDK', () => {
  it('sends the frozen request shape and returns the decision', async () => {
    const res = await requestAd(cfg(), input);
    expect(res.filled).toBe(true);
    expect(res.decision?.campaignId).toBe('cmp-1');
    const sent = bodies[0] as Record<string, unknown>;
    expect(sent.requestId).toMatch(/^rn/);
    expect(sent.siteId).toBe('site-1');
    expect(sent.zoneId).toBe('mrec-1');
    expect(sent.ts).toBe(1_700_000_000_000);
    expect((sent.device as Record<string, unknown>).type).toBe('mobile');
    expect((sent.consent as Record<string, unknown>).region).toBe('NONE');
  });

  it('reports no fill on 204 and throws on server error', async () => {
    const res = await requestAd(cfg(), input);
    expect(res.filled).toBe(false);
    await expect(requestAd({ ...cfg(), endpoint: 'http://127.0.0.1:1' }, input)).rejects.toThrow(/failed/);
  });

  it('fires the impression beacon once and follows click to landing', async () => {
    const res = await requestAd(cfg(), input);
    await trackImpression(cfg(), res.decision!);
    const landing = await clickThrough(cfg(), res.decision!);
    expect(beacons.filter((b) => b.startsWith('/v1/track/impression')).length).toBe(1);
    expect(beacons.some((b) => b.startsWith('/v1/track/click'))).toBe(true);
    expect(landing).toBe('https://landing.example.com');
  });
});
