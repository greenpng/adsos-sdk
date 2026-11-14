# AdsOS iOS SDK（ADN-06，D-87 功能基线）

Swift Package 客户端 SDK，最小已冻结契约：`POST /v1/ad/request` + beacon。
`AdsosBannerView` 请求广告并真实渲染：html/html5 用 WKWebView 承载、image
用 UIImageView 下载位图；渲染后发曝光 beacon，点击经点击中转 302 到落地页
外跳。设备基础数据（locale/屏幕尺寸，粗粒度、无 GPS）随契约字段上报；持久
visitorId 只在宿主显式提供时发送（D-87）。客户端不伪造可见性/计费证明；
视频/奖励与安装归因按 Q-127 至 Q-129 未冻不实现。
零第三方依赖（URLSession + JSONDecoder + 平台 WKWebView/UIImageView）。

## 精确工具链（候选值，待 Q-127 冻结复核）

- Swift tools `5.9`，iOS `15.0`+（`Package.swift` 固定；async/await 需 15）
- 本机无 macOS/Xcode：构建**未运行**，不记 PASS；Linux 交叉编译不算 iOS 验证

## 构建入口（macOS Runner）

```sh
xcodebuild -scheme AdsosSDK -destination 'generic/platform=iOS Simulator' build
```

## 显示验收（Runner 待验）

macOS Runner Xcode 模拟器：样例宿主实际启动、请求合成素材、显示适用形态、
桥接回调/生命周期；模拟器不冒充真机/签名/ATT 实测（三模块安排第 4 节）。

## 未覆盖（如实登记）

- 模拟器/真机显示、ATT/IDFA、安装归因与生命周期（Q-127/129 未冻），未实现

## 用法示例

```swift
let client = AdsosClient(endpoint: URL(string: "https://ads.example.com")!)
let result = try await client.requestAd(.init(
    siteId: "site-1", zoneId: "mrec-1", deviceType: "mobile",
    consent: .init(region: "NONE")))
if case .filled(let d) = result {
    try await client.trackImpression(d)
    let landing = try await client.clickThrough(d)
}
```
