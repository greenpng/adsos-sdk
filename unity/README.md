# AdsOS Unity SDK（ADN-06）

Unity UPM 包形态客户端 SDK：`POST /v1/ad/request` + beacon，设备基础数据
（设备类型/系统语言/屏幕尺寸，粗粒度、由调用方按同意决定发送）随契约字段
上报。引擎无关逻辑拆在 `Runtime/Core/AdsosCore.cs`（无 UnityEngine 引用），
公开 CI 用 .NET 直接测试；UnityWebRequest/协程胶水在 `Runtime/AdsosClient.cs`。

## 精确工具链（候选值，待 Q-127 冻结复核）

- Unity Editor 版本候选：`6000.x`（`package.json` unity 字段；待 Q-127 冻结与合法 Editor 宿主核）
- 核心测试：.NET `net8.0`（GitHub 托管 runner / 本机 dotnet 8.0.428）
- 本机无合法 Unity Editor：Editor 编译**未运行**，不记 PASS

## 本机检查（已过，2026-11-14，D-87）

```sh
cd CoreTests && dotnet run   # 18 项核心金标：载荷形状/consent 变体/requestId/
                             # JSON 转义/决策解析/tracker 解析
```

## 构建入口（合法 Editor 宿主）

```sh
# Unity Package Manager 以本地包引用 Runtime/；编辑器编译与样例场景留宿主
```

## 显示验收（Runner 待验，不是 dotnet 测试）

固定 Editor/许可的工程构建、运行与适用 Android/iOS 导出宿主显示；缺合法
宿主如实阻塞，不要求采购（三模块安排第 4 节）。html5 沙箱包在 Unity 内
渲染需宿主 WebView 插件（无免费内建等价物），按未覆盖登记，不静默放宽。

## 未覆盖（如实登记）

- Editor/导出宿主显示、生命周期、html5 包渲染、安装归因（Q-127/129 未冻）
