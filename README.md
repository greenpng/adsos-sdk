# sdk：广告联盟六目标客户端 SDK（ADN-06/ADN-12）

状态：六目标按 D-87 功能基线交付——App 开发者可集成、真实显示（html/html5/图像按宿主能力）、设备基础数据上报、与联盟系统对接；RN/uni-app/Unity 核心本机检查过，公开仓库 CI 全六 job 绿（RN/uniapp/unity-core 为测试级，Android/iOS 为编译级，Flutter 为分析级）；真实显示验收留 Runner/合法宿主 + 受控合成广告服务。公开仓库 `greenpng/adsos-sdk`（MIT + NOTICE，CI 仅源码/单元/编译级）。更新：2026-11-14。

本目录是广告联盟客户端 SDK 的六个目标（Android、iOS、Flutter、React Native、uni-app、Unity），另登记既有网页 SDK 与 Prebid 适配器（`../web/sdk/`）。不是根 `sdk/go` 运行时 SDK。

## 统一契约（各目标一致，来自已冻结的服务端 HTTP 契约）

1. **取广告**：`POST /v1/ad/request`，JSON：`requestId`（客户端生成、平台前缀）、`siteId`、`zoneId`、`publisherId?`、`ts`（Unix 毫秒）、`device{type,language,width,height}`、`geo{country}?`、`consent{region,tcf?,gpp?,ccpa?,purposeConsents?}`、`keywords?`。响应 200：`decision{auctionId,campaignId,creativeId,billingModel,format,width,height,kind,html,trackers{impression,click},landingUrl}`；204 无填充（no-store）；4xx/5xx 按错误处理。币种 USD（D-41）。
2. **beacon**：渲染后 GET `decision.trackers.impression`（no-store）；用户点击经 `decision.trackers.click` 302 到落地页（no-referrer）。URL 请求/预取不自动计费（A-HELP-009）；计费资格由服务端把关。
3. **客户端不伪造证据**：SDK 不产生可见性/计费证明，不把客户端进度当 vCPM 或奖励证据；视频/奖励/移动归因（安装、生命周期、通知）按 Q-127 至 Q-129 未冻保留，不在本目录实现。

## 目标与状态

| 目标 | 目录 | 语言/宿主 | 本机检查 | Runner/宿主待验 |
|---|---|---|---|---|
| Android | `android/` | Kotlin（零第三方依赖：HttpURLConnection + org.json + 平台 WebView/ImageView）；`AdsosBannerView` 真实渲染 + beacon + 外跳 | **CI 编译过**：Gradle 9.1.0 + AGP 8.13.0（候选值），assembleDebug | KVM 模拟器显示（无模拟器，显示未验） |
| iOS | `ios/` | Swift Package（URLSession + WKWebView/UIImageView，iOS 15+）；`AdsosBannerView` 真实渲染 + beacon + 外跳 | **CI 编译过**：Xcode iOS Simulator 目标（macos-latest Runner） | 模拟器显示（未验） |
| Flutter | `flutter/` | Dart 核心（dart:io，零依赖）+ 官方 `webview_flutter 4.13.0` 显示；`AdsosBanner` | **CI 过**：Flutter stable + `flutter analyze` | Android/iOS 宿主显示 |
| React Native | `react-native/` | TS 核心（fetch，零运行时依赖）+ `AdsosBanner`（react-native-webview 可选 peer） | **已过**：pnpm 10.34.7 + node 22.23.3，vitest 真实 HTTP 桩金标 3 项 | Android/iOS 宿主显示 |
| uni-app | `uniapp/` | JS 插件（请求适配器注入，零依赖）+ `AdsosBanner`（内建 web-view/image） | **已过**：node --test 4 项核心金标 | App 端/合法编译器宿主显示 |
| Unity | `unity/` | C#（UPM）：引擎无关核心 `Runtime/Core/`（dotnet 可测）+ UnityWebRequest 胶水 | **已过**：dotnet 8 核心金标 18 项；Editor 编译未运行 | Unity Editor/Android/iOS 导出宿主显示 |

## 独立检出与构建

每个子目录自成一体（不引用主库其他目录），含构建入口、精确工具链版本与锁文件/版本目录。宿主版本在 Q-127 冻结前按各目录 README 登记的候选值固定，不把候选值当已冻结许可。

显示验收口径（不是 HTTP 200/组件挂载/截图非空）见 [三模块安排](../../../../task/delivery/three-module-next-round.md) 第 4 节：受测 SDK 请求合成素材并记录真实可见画面/视频帧、宿主事件、失败/超时/同意拒绝分支；失败与未覆盖项保持登记，不改 PASS。

## 修订记录

| 日期 | 内容 | 原因 |
|---|---|---|
| 2026-11-14 | 建立六目标源码、构建材料与状态矩阵；RN/uni-app 本机金标过，其余宿主构建如实登记未运行 | ADN-06/12 第三批：SDK 源码/最小宿主及显示测试轨道，D-85 公开源码、D-86 mock 继续 |
| 2026-11-14 | 按 D-87 扩展功能基线：各目标显示组件（Android/iOS/Flutter/RN/uni-app WebView 系 + Unity 图像）、设备基础数据上报（粗粒度、同意后、无自采持久标识）、MIT + NOTICE、公开仓库 greenpng/adsos-sdk 与 SHA 固定 CI（RN/uniapp/unity-core/android-compile/ios-compile/flutter-analyze）；Unity 核心拆出 dotnet 可测（本机 18 项过） | 用户确认 SDK 必须达到 App 开发者可用、真实显示与对接，不以源码存在为完成；计费资格仍由服务端把关，显示验收留受控宿主 |
| 2026-11-14 | 公开仓库建立并 CI 全六 job 绿（https://github.com/greenpng/adsos-sdk 单提交 468fde5 → 修正迭代后 aac25ed，仅 sdk/ 内容）：RN 锁文件补 peer 声明、Flutter pubspec 描述引号与 Flutter SDK（webview_flutter 属 Flutter 插件）、Android 补 pluginManagement 仓库 + Gradle 9.1.0（AGP 8.13.0 不兼容 Runner 系统 Gradle 9.9.1）+ 修复 Intent/Uri 与 absolute 可见性、iOS 改 macos-latest（macos-14 即时取消）+ clickThrough 可空落地页 + regionCode 兼容 iOS 15 | CI 反馈驱动的诚实修复；工具链版本仍是 Q-127 候选值，显示验收与联盟系统对接实测留受控宿主场景 |
