# @adsos/sdk-react-native（ADN-06，D-87 功能基线）

React Native 客户端 SDK，最小已冻结契约：`POST /v1/ad/request` + beacon。
核心（`src/index.ts`）零运行时依赖、由宿主注入 fetch；`src/banner.tsx` 提供
`AdsosBanner` 组件：请求广告并真实渲染（image 用 Image；html/html5 用可选
peer `react-native-webview` 承载、未安装时如实显示状态不伪装渲染成功），
渲染后发曝光 beacon，点击经点击中转 302 到落地页外跳。设备基础数据（平台
形态/屏幕尺寸，粗粒度、无持久标识）随契约字段上报，语言/地区由宿主提供
（D-87：不未经同意自采持久标识）。客户端不伪造可见性/计费证明；视频/奖励
与安装归因按 Q-127 至 Q-129 未冻不实现。

## 精确工具链（候选值，待 Q-127 冻结复核）

- Node `^22.23.3`、pnpm `10.34.7`（packageManager 字段锁定）
- TypeScript `5.9.3`、vitest `5.0.4`（devDependencies 固定精确版本，与工作区缓存一致）
- React Native 宿主版本待 Q-127；本包不 import react-native 运行时，宿主只注入 fetch

## 本机检查（已过，2026-11-14）

```sh
pnpm install --frozen-lockfile --offline
pnpm run test   # vitest：真实 node:http 桩金标 3 项
```

## 未覆盖（如实登记，不改 PASS）

- Android/iOS 宿主中的真实显示验收（Runner）；RN 桥接/生命周期按 Q-127 未冻
- 视频/奖励/移动归因（Q-127 至 Q-129）未实现
