// AdsOS RN banner component (D-87 functional baseline). Requires the host
// app to provide react-native peers; the WebView for html/html5 comes from
// react-native-webview when installed (display fallback: text status).
import React, { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Image, Linking, StyleSheet, Text, View, type StyleProp, type ViewStyle } from 'react-native';

import { requestAd, trackImpression, clickThrough, type AdRequestInput, type AdsosRnConfig, type Decision } from './index';

export interface AdsosBannerProps {
  config: AdsosRnConfig;
  input: Omit<AdRequestInput, 'device'>;
  /** Host-built device basics (see deviceBasics()); sent as-is. */
  device: AdRequestInput['device'];
  style?: StyleProp<ViewStyle>;
  onNoFill?: () => void;
  onError?: (error: Error) => void;
  /** Host override for opening the landing page (deep link stays Q-129). */
  openLanding?: (url: string) => void;
}

/**
 * Coarse device basics (D-87): platform form factor and screen size in px.
 * Language/region stay host-provided (locale APIs differ per RN runtime and
 * the host knows its own consent posture); no persistent ids, no GPS.
 */
export function deviceBasics(): AdRequestInput['device'] {
  // Imported lazily so the core module stays framework-free for CI.
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const rn = require('react-native');
  const { Platform, Dimensions, PixelRatio } = rn;
  const d = Dimensions.get('window');
  const scale = PixelRatio.get();
  return {
    type: Platform.isPad ? 'tablet' : 'mobile',
    width: Math.round(d.width * scale),
    height: Math.round(d.height * scale),
  };
}

export function AdsosBanner({ config, input, device, style, onNoFill, onError, openLanding }: AdsosBannerProps) {
  const [decision, setDecision] = useState<Decision | null>(null);
  const [status, setStatus] = useState<string>('loading…');

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const res = await requestAd(config, { ...input, device });
        if (!alive) return;
        if (!res.filled || !res.decision) {
          setStatus('no fill');
          onNoFill?.();
          return;
        }
        setDecision(res.decision);
        await trackImpression(config, res.decision).catch(() => undefined);
      } catch (e) {
        if (alive) setStatus(String(e));
        onError?.(e as Error);
      }
    })();
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [input.siteId, input.zoneId, input.publisherId]);

  const handleClick = useCallback(async () => {
    if (!decision) return;
    const landing = await clickThrough(config, decision).catch(() => decision.landingUrl);
    if (openLanding) openLanding(landing);
    else Linking.openURL(landing).catch(() => undefined);
  }, [config, decision, openLanding]);

  const kind = decision?.kind ?? '';
  const html = decision?.html;
  const imageUrl = decision && 'imageUrl' in decision ? (decision as Record<string, unknown>).imageUrl as string | undefined : undefined;

  if (!decision) {
    return (
      <View style={[styles.box, style]}>
        <ActivityIndicator size="small" />
        <Text style={styles.text}>{status}</Text>
      </View>
    );
  }
  let body: React.ReactNode;
  if (html && (kind === 'html' || kind === 'html5')) {
    // WebView 承载 html5 包：优先 react-native-webview（可选 peer），未安装
    // 时如实显示状态，不静默用无 WebView 的降级伪装渲染成功。
    body = renderWebView(html, config, () => setStatus('react-native-webview 未安装：html 渲染需宿主安装该 peer 依赖'));
  } else if (kind === 'image' && imageUrl) {
    body = <Image source={{ uri: imageUrl }} style={styles.fill} resizeMode="contain" />;
  } else {
    body = <Text style={styles.text}>{`kind "${kind}" not renderable on this host yet`}</Text>;
  }
  return (
    <View style={[styles.box, style]}>
      <View style={styles.fill}>
        {body}
      </View>
      <View style={styles.hit} onTouchEnd={handleClick} />
    </View>
  );
}

function renderWebView(html: string, config: AdsosRnConfig, fallback: () => void): React.ReactNode {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { WebView } = require('react-native-webview');
    const origin = new URL('x', config.endpoint).origin;
    return <WebView source={{ html, baseUrl: origin }} style={styles.fill} />;
  } catch {
    fallback();
    return <Text style={styles.text}>html rendering requires the react-native-webview peer</Text>;
  }
}

const styles = StyleSheet.create({
  box: { backgroundColor: '#0001', justifyContent: 'center', alignItems: 'center', overflow: 'hidden' },
  fill: { width: '100%', height: '100%' },
  hit: { position: 'absolute', width: '100%', height: '100%' },
  text: { fontSize: 12, textAlign: 'center' },
});
