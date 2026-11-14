# AdsOS Android SDK（ADN-06，D-87 功能基线）

Kotlin 客户端 SDK，最小已冻结契约：`POST /v1/ad/request` + beacon。
`AdsosBannerView` 请求广告并真实渲染：html/html5 用 WebView 承载（html5 包
相对资源以 bundleUrl 挂投放域名基址）、image 用 ImageView 下载位图；渲染后
发曝光 beacon，点击经点击中转 302 到落地页并外跳。设备基础数据（locale/
屏幕尺寸，粗粒度、无 GPS）随契约字段上报；持久 visitorId 只在宿主显式提供
时发送（D-87：不未经同意自采持久标识）。客户端不伪造可见性/计费证明；
视频/奖励与安装归因按 Q-127 至 Q-129 未冻不实现。
零第三方依赖（HttpURLConnection + org.json + 平台 WebView/ImageView）。

## 精确工具链（候选值，待 Q-127 冻结复核）

- Kotlin `2.2.20`、AGP `8.13.0`（`gradle/libs.versions.toml` 固定）
- minSdk 24 / targetSdk 由宿主应用决定；`compileSdk 36`
- 本机无 Gradle/Android SDK：构建**未运行**，不记 PASS（三模块安排第 4 节）
- Gradle wrapper 不入库（需 gradle-wrapper.jar 二进制）；构建入口按 `gradle wrapper` 生成后 `./gradlew :adsos-sdk:assembleRelease`，在冻结宿主后补

## 构建入口

```sh
gradle :adsos-sdk:assembleRelease   # 需要 Android SDK；Runner/合法宿主执行
```

## 显示验收（Runner 待验，不是编译通过）

Linux Runner + 可用 KVM 模拟器：安装样例宿主、请求合成素材、记录真实可见
画面与宿主事件；覆盖无填充/超时/取消/同意拒绝。无 KVM 时只编译不算模拟器
PASS（三模块安排第 4 节）。

## 未覆盖（如实登记）

- 模拟器/真机显示、生命周期（前后台/旋转/销毁重建）、安装归因（Q-129 未冻）
- 广告标识（GAID）与同意接入按 Q-127 未冻，未实现

## 用法示例

```kotlin
// XML 中直接放 <io.adsos.sdk.AdsosBannerView>，或代码内：
val banner = AdsosBannerView(this)
banner.configure("https://ads.example.com", AdsosClient.Consent(region = "NONE"))
banner.load("site-1", "mrec-1")   // 渲染后自动发曝光 beacon；点击外跳落地页

// 无 UI 场景（如 S2S 前的预取/服务端集成）也可直接用 client：
val client = AdsosClient("https://ads.example.com")
when (val r = client.requestAd(AdsosClient.AdInput(
    siteId = "site-1", zoneId = "mrec-1", deviceType = "mobile",
    consent = AdsosClient.Consent(region = "NONE"),
))) {
    is AdsosClient.AdResult.Filled -> {
        client.trackImpression(r.decision)
        val landing = client.clickThrough(r.decision)
    }
    AdsosClient.AdResult.NoFill -> { /* 无填充，不重试轰炸 */ }
}
```
