# @adsos/sdk-uniapp（ADN-06，D-87 功能基线）

uni-app 插件形态客户端 SDK：核心逻辑为零依赖纯 JS（`src/adsos.js`），请求
实现由宿主注入（uni.request / 各编译目标网络 API）。`src/adsos-banner.vue`
提供 `AdsosBanner` 组件：请求广告并真实渲染（image 用内建 `<image>`；
html/html5 用内建 `<web-view>` 承载，内联 html 经 data URL 加载——App 端
web-view 对 data URL 的支持差异如实登记，不以 H5 行为代表 App 端）；渲染后
发曝光 beacon，点击经点击中转 302 到落地页交给宿主导航。设备基础数据
（系统信息：平台/语言/屏幕尺寸，粗粒度、无持久标识）随契约字段上报。
客户端不伪造可见性/计费证明；视频/奖励与安装归因按 Q-127 至 Q-129 未冻
不实现。

组件按宿主 easycom 约定放置（拷入宿主 `components/` 或在 pages.json 注册）。

## 契约

同 `../README.md` 统一契约：POST /v1/ad/request + impression/click beacon；
客户端不伪造可见性/计费证明；视频/奖励/归因按 Q-127 至 Q-129 未冻不实现。

## 精确工具链（候选值，待 Q-127 冻结复核）

- 本机核心检查：Node `^22.23.3`（node --test，零依赖）
- uni-app 编译器/HBuilderX 宿主版本待 Q-127 冻结；插件 manifest 候选值见 `manifest.json`

## 本机检查（已过，2026-11-14）

```sh
node --test   # 4 项金标
```

## 未覆盖（如实登记，不改 PASS）

- uni-app 编译器/插件宿主中的真实显示验收（Q-127 冻结前留 Runner/合法宿主）
- App 端插件与 H5 端行为差异不互相代表（三模块安排第 4 节）
