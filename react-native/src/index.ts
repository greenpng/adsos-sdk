// AdsOS React Native client SDK — minimal frozen contract (ADN-06):
// POST /v1/ad/request → decision + trackers; beacons are plain GETs.
// The SDK never fabricates viewability/billing proof; video/reward/mobile
// attribution stay blocked on Q-127..Q-129 and are intentionally absent.

export interface ConsentSignal {
  region: 'GDPR' | 'GPP' | 'CCPA' | 'PIPL' | 'NONE';
  tcf?: string;
  gpp?: string;
  ccpa?: string;
  purposeConsents?: string[];
}

export interface AdRequestInput {
  siteId: string;
  zoneId: string;
  publisherId?: string;
  device: { type: 'mobile' | 'tablet'; language?: string; width?: number; height?: number };
  geo?: { country?: string };
  consent: ConsentSignal;
  keywords?: string[];
}

export interface Decision {
  auctionId: string;
  campaignId: string;
  creativeId: string;
  billingModel: string;
  format: string;
  width: number;
  height: number;
  kind: string;
  html?: string;
  trackers: { impression: string; click: string };
  landingUrl: string;
}

export interface AdResult {
  filled: boolean;
  decision?: Decision;
}

export interface AdsosRnConfig {
  endpoint: string; // delivery origin, e.g. https://ads.example.com
  /** request implementation (React Native fetch injected by the host app). */
  fetchImpl: typeof fetch;
  /** deterministic request ids for tests; defaults to crypto/random fallback. */
  requestIdPrefix?: string;
  now?: () => number;
}

export class NoFillError extends Error {
  constructor() {
    super('no fill');
    this.name = 'NoFillError';
  }
}

function newRequestId(prefix: string, now: number): string {
  const rand = Math.random().toString(36).slice(2, 10);
  return `${prefix}${now.toString(36)}${rand}`;
}

async function fireBeacon(cfg: AdsosRnConfig, path: string): Promise<void> {
  const url = path.startsWith('http') ? path : cfg.endpoint + path;
  // Beacons are fire-and-forget GETs; the server marks them no-store.
  await cfg.fetchImpl(url, { method: 'GET', headers: { 'Cache-Control': 'no-store' } });
}

/** Request an ad and return the decision, or throw NoFillError on 204. */
export async function requestAd(cfg: AdsosRnConfig, input: AdRequestInput): Promise<AdResult> {
  const now = (cfg.now ?? Date.now)();
  const requestId = newRequestId(cfg.requestIdPrefix ?? 'rn', now);
  const payload = {
    requestId,
    siteId: input.siteId,
    zoneId: input.zoneId,
    publisherId: input.publisherId,
    ts: now,
    device: input.device,
    geo: input.geo ?? {},
    consent: input.consent,
    keywords: input.keywords,
  };
  const resp = await cfg.fetchImpl(`${cfg.endpoint}/v1/ad/request`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (resp.status === 204) {
    return { filled: false };
  }
  if (resp.status !== 200) {
    throw new Error(`ad request failed: HTTP ${resp.status}`);
  }
  const body = (await resp.json()) as { decision?: Decision };
  if (!body.decision || !body.decision.trackers?.click) {
    throw new Error('ad request returned malformed decision');
  }
  return { filled: true, decision: body.decision };
}

/** Fire the impression beacon once, after the creative is actually rendered. */
export function trackImpression(cfg: AdsosRnConfig, decision: Decision): Promise<void> {
  return fireBeacon(cfg, decision.trackers.impression);
}

/**
 * Follow the click: GET the click tracker (server 302s to the landing page)
 * and return the landing URL. The SDK does not open browsers itself — the
 * host app decides how to present the URL (deep-link fallback stays blocked
 * on Q-129).
 */
export async function clickThrough(cfg: AdsosRnConfig, decision: Decision): Promise<string> {
  const url = decision.trackers.click.startsWith('http')
    ? decision.trackers.click
    : cfg.endpoint + decision.trackers.click;
  const resp = await cfg.fetchImpl(url, { method: 'GET', redirect: 'manual' });
  const loc = resp.headers.get('location');
  return loc ?? decision.landingUrl;
}
