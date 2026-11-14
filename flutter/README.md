# AdsOS Flutter SDK（ADN-06，D-87 功能基线）

Dart 客户端 SDK，最小已冻结契约：`POST /v1/ad/request` + beacon。
`AdsosBanner`（`lib/adsos_banner.dart`）请求广告并真实渲染：html/html5 用
官方 webview_flutter 插件承载、image 用 Image.network；渲染后发曝光 beacon，
点击经点击中转 302 到落地页（外跳回调留给宿主覆盖，深链回退按 Q-129 未冻）。
设备基础数据（locale/屏幕尺寸，粗粒度、无 GPS）随契约字段上报；持久
visitorId 只在宿主显式提供时发送（D-87）。客户端不伪造可见性/计费证明；
视频/奖励与安装归因按 Q-127 至 Q-129 未冻不实现。

依赖：核心零第三方依赖；显示按 D-87 显式登记官方插件 `webview_flutter
4.13.0`（BSD-3，进许可清单）。

## 精确工具链（候选值，待 Q-127 冻结复核）

- Dart/Flutter SDK：`pubspec.yaml` environment 固定 `>=3.5.0 <4.0.0`（候选值）
- 本机无 Dart SDK：`dart analyze`/构建**未运行**，不记 PASS

## 构建入口（Runner/合法宿主）

```sh
dart pub get --enforced-lockfile
dart analyze
flutter build apk --debug   # Android 宿主样例；iOS 宿主另在 macOS Runner
```

## 显示验收（Runner 待验）

Android/iOS 各自宿主显示验收按三模块安排第 4 节；框架样例需真实宿主渲染，
不以 Dart 单测冒充。

## 未覆盖（如实登记）

- 宿主显示、生命周期、安装归因（Q-127/129 未冻），未实现

## 用法示例

```dart
final client = AdsosClient(endpoint: Uri.parse('https://ads.example.com'));
final d = await client.requestAd(
  siteId: 'site-1', zoneId: 'mrec-1', deviceType: 'mobile',
  consent: client.consent('NONE'));
if (d != null) {
  await client.trackImpression(d);
  final landing = await client.clickThrough(d);
}
```
