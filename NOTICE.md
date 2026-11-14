# NOTICE

AdsOS 六目标客户端 SDK（Android / iOS / Flutter / React Native / uni-app / Unity）。

- 本仓库源码按 `LICENSE`（MIT）分发；版权归 greenpng。
- 广告服务的服务端实现、投放域名与业务系统不在本仓库；SDK 是客户端，与
  AdsOS 广告联盟平台配合使用，单独的 SDK 不构成完整广告系统。
- 客户端不伪造可见性/计费证明；计费资格由服务端把关。设备基础数据
  （类型/语言/屏幕尺寸/地区，粗粒度）按调用方传入的同意信号上报；持久
  广告标识（GAID/IDFA/持久 visitorId）只在宿主应用显式提供时发送。
- 显示能力依赖宿主平台组件：Android/iOS/uni-app 使用平台内建 WebView，
  Flutter 使用官方插件 `webview_flutter 4.13.0`（BSD-3-Clause，Flutter 团队
  版权），React Native html 渲染使用可选 peer `react-native-webview`
  （MIT，Microsoft/ react-native-webview 贡献者版权）。
- React Native 包的构建期开发依赖（仅 CI/测试使用，不进入 App 产物）：
  `typescript 5.9.3`（Apache-2.0，Microsoft）、`vitest 5.0.4`（MIT，
  VoidZero/Vitest 贡献者）。许可文本以各包分发的 LICENSE 为准。
- 工具链候选版本（Android Gradle/AGP、Swift、Dart、Unity Editor）在
  Q-127 冻结前为登记的候选值，不构成已冻结的平台支持承诺。
