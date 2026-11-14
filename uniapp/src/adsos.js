// AdsOS uni-app plugin SDK — minimal frozen contract (ADN-06).
// Core logic is dependency-free JS; the host injects `request` so the same
// core runs under uni.request (App) or the H5 compile target without changes.

'use strict';

/**
 * @typedef {{region: string, tcf?: string, gpp?: string, ccpa?: string, purposeConsents?: string[]}} ConsentSignal
 * @typedef {{endpoint: string, request: (opts: {url: string, method: string, body?: unknown}) => Promise<{status: number, body: string, headers: Record<string, string>}>, now?: () => number, requestIdPrefix?: string}} AdsosUniConfig
 * @typedef {{siteId: string, zoneId: string, publisherId?: string, device: {type: string, language?: string, width?: number, height?: number}, geo?: {country?: string}, consent: ConsentSignal, keywords?: string[]}} AdRequestInput
 */

function newRequestId(prefix, now) {
  const rand = Math.random().toString(36).slice(2, 10);
  return prefix + now.toString(36) + rand;
}

/** Build the frozen /v1/ad/request payload (shape pinned by server contract). */
function buildPayload(cfg, input, now) {
  return {
    requestId: newRequestId(cfg.requestIdPrefix || 'uni', now),
    siteId: input.siteId,
    zoneId: input.zoneId,
    publisherId: input.publisherId,
    ts: now,
    device: input.device,
    geo: input.geo || {},
    consent: input.consent,
    keywords: input.keywords,
  };
}

/** Resolve a tracker path against the configured endpoint. */
function trackerUrl(cfg, path) {
  return path.indexOf('http') === 0 ? path : cfg.endpoint + path;
}

/** Parse the decision body; returns {filled, decision} or throws on HTTP errors. */
function parseDecision(status, body) {
  if (status === 204) {
    return { filled: false };
  }
  if (status !== 200) {
    throw new Error('ad request failed: HTTP ' + status);
  }
  const parsed = JSON.parse(body);
  const decision = parsed && parsed.decision;
  if (!decision || !decision.trackers || !decision.trackers.click) {
    throw new Error('ad request returned malformed decision');
  }
  return { filled: true, decision: decision };
}

/** Request an ad (POST /v1/ad/request) via the injected request adapter. */
async function requestAd(cfg, input) {
  const now = (cfg.now || Date.now)();
  const payload = buildPayload(cfg, input, now);
  const resp = await cfg.request({
    url: cfg.endpoint + '/v1/ad/request',
    method: 'POST',
    body: payload,
  });
  return parseDecision(resp.status, resp.body);
}

/** Fire the impression beacon once, after the creative is actually rendered. */
async function trackImpression(cfg, decision) {
  await cfg.request({ url: trackerUrl(cfg, decision.trackers.impression), method: 'GET' });
}

/** Follow the click tracker; resolves with the landing URL (server 302s). */
async function clickThrough(cfg, decision) {
  const resp = await cfg.request({ url: trackerUrl(cfg, decision.trackers.click), method: 'GET' });
  return resp.headers.location || decision.landingUrl;
}

module.exports = { buildPayload, trackerUrl, parseDecision, requestAd, trackImpression, clickThrough, newRequestId };
