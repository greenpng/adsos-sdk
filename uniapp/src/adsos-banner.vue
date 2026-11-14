<template>
  <view class="adsos-banner" @click="onTap">
    <web-view v-if="html" :src="htmlSrc" class="fill" />
    <image v-else-if="imageUrl" :src="imageUrl" mode="aspectFit" class="fill" />
    <view v-else class="fill center">
      <text class="status">{{ status }}</text>
    </view>
  </view>
</template>

<script>
// AdsOS uni-app banner component (D-87 functional baseline): request an ad,
// render html/html5 via the built-in <web-view> and image creatives via
// <image>, fire the impression beacon after real rendering, and route clicks
// through the click tracker. The SDK never fabricates viewability/billing
// proof; video/reward formats and install attribution stay Q-127..Q-129.
import { requestAd, trackImpression, clickThrough, buildPayload } from './adsos.js';

export default {
  name: 'AdsosBanner',
  props: {
    endpoint: { type: String, required: true },
    siteId: { type: String, required: true },
    zoneId: { type: String, required: true },
    publisherId: { type: String, default: undefined },
    consent: { type: Object, required: true },
    keywords: { type: Array, default: undefined },
    requestAdapter: { type: Function, required: true },
  },
  data() {
    return { decision: null, status: 'loading…' };
  },
  computed: {
    html() {
      const d = this.decision;
      return d && d.html && (d.kind === 'html' || d.kind === 'html5') ? d.html : null;
    },
    htmlSrc() {
      // html5 包：bundleUrl 是投放域名的站内相对路径（/bundle/<id>/），
      // 直接加载绝对 URL（包相对资源解析到投放域名）；内联 html 用 data URL
      // 承载——App 端 web-view 对 data URL 的支持差异如实登记。
      const d = this.decision;
      if (d.bundleUrl) {
        return d.bundleUrl.indexOf('http') === 0 ? d.bundleUrl : this.endpoint + d.bundleUrl;
      }
      return 'data:text/html;charset=utf-8,' + encodeURIComponent(this.html);
    },
    imageUrl() {
      const d = this.decision;
      return d && d.kind === 'image' && d.imageUrl ? d.imageUrl : null;
    },
  },
  mounted() {
    this.load();
  },
  methods: {
    buildPayload,
    async load() {
      try {
        const res = await requestAd(this.adapterConfig(), {
          siteId: this.siteId,
          zoneId: this.zoneId,
          publisherId: this.publisherId,
          device: this.deviceBasics(),
          geo: {},
          consent: this.consent,
          keywords: this.keywords,
        });
        if (!res.filled) {
          this.status = 'no fill';
          return;
        }
        this.decision = res.decision;
        await trackImpression(this.adapterConfig(), res.decision);
      } catch (e) {
        this.status = String(e);
      }
    },
    adapterConfig() {
      return { endpoint: this.endpoint, request: this.requestAdapter, requestIdPrefix: 'uni' };
    },
    // 粗粒度设备基础数据：平台/语言/屏幕尺寸（无持久标识、无 GPS）。
    deviceBasics() {
      // eslint-disable-next-line no-undef
      const sys = uni.getSystemInfoSync();
      return {
        type: sys.deviceType === 'pad' || sys.deviceType === 'pc' ? sys.deviceType : 'mobile',
        language: sys.language,
        width: sys.screenWidth,
        height: sys.screenHeight,
      };
    },
    async onTap() {
      const cfg = this.adapterConfig();
      const d = this.decision;
      if (!d) return;
      const landing = await clickThrough(cfg, d).catch(() => d.landingUrl);
      // 深链回退按 Q-129 未冻；统一交给宿主导航 API。
      // eslint-disable-next-line no-undef
      if (landing) uni.navigateTo({ url: landing, fail: () => undefined });
    },
  },
};
</script>

<style>
.adsos-banner { width: 100%; height: 100%; overflow: hidden; }
.fill { width: 100%; height: 100%; }
.center { display: flex; align-items: center; justify-content: center; }
.status { font-size: 12px; text-align: center; }
</style>
