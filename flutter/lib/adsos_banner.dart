import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'adsos.dart';

/// AdsOS banner widget (D-87 functional baseline): request an ad, render
/// html/html5 in the platform WebView and image creatives via Image.network,
/// fire the impression beacon after real rendering, and route clicks through
/// the click tracker. The SDK never fabricates viewability/billing proof;
/// video/reward formats and install attribution stay blocked on Q-127..Q-129.
class AdsosBanner extends StatefulWidget {
  final String endpoint;
  final String siteId;
  final String zoneId;
  final String? publisherId;
  final Map<String, dynamic> consent;
  final List<String>? keywords;
  final void Function(Object error)? onError;

  const AdsosBanner({
    super.key,
    required this.endpoint,
    required this.siteId,
    required this.zoneId,
    required this.consent,
    this.publisherId,
    this.keywords,
    this.onError,
  });

  @override
  State<AdsosBanner> createState() => _AdsosBannerState();
}

class _AdsosBannerState extends State<AdsosBanner> {
  final client = AdsosClient(endpoint: Uri.parse('https://placeholder'));
  Map<String, dynamic>? decision;
  String status = '';
  late final AdsosClient api;

  @override
  void initState() {
    super.initState();
    api = AdsosClient(endpoint: Uri.parse(widget.endpoint));
    _load();
  }

  Future<void> _load() async {
    final dpr = MediaQueryData.fromView(View.of(context)).devicePixelRatio;
    try {
      final d = await api.requestAd(
        siteId: widget.siteId,
        zoneId: widget.zoneId,
        publisherId: widget.publisherId,
        // 粗粒度设备基础数据：平台/语言/屏幕尺寸（逻辑像素×DPR）、locale 地区。
        deviceType: Platform.isAndroid || Platform.isIOS ? 'mobile' : 'desktop',
        language: ui.window.locale.toLanguageTag(),
        width: (ui.window.physicalSize.width / dpr).round(),
        height: (ui.window.physicalSize.height / dpr).round(),
        geoCountry: Platform.localeName.split('_').length > 1
            ? Platform.localeName.split('_')[1]
            : null,
        consent: widget.consent,
        keywords: widget.keywords,
      );
      if (!mounted) return;
      setState(() => decision = d);
      if (d != null) {
        await api.trackImpression(d);
      }
    } catch (e) {
      if (mounted) setState(() => status = '$e');
      widget.onError?.call(e);
    }
  }

  Future<void> _openClick() async {
    final d = decision;
    if (d == null) return;
    try {
      final landing = await api.clickThrough(d);
      if (landing.isNotEmpty) {
        // 深链回退按 Q-129 未冻；这里统一交给宿主的 url 启动器。
        await _openExternal(landing);
      }
    } catch (e) {
      widget.onError?.call(e);
    }
  }

  Future<void> _openExternal(String url) async {
    // 不引入 url_launcher（额外依赖）：宿主应用可覆盖此回调处理跳转。
    debugPrint('AdsosBanner open: $url');
  }

  @override
  Widget build(BuildContext context) {
    final d = decision;
    if (d == null) {
      return Container(
        alignment: Alignment.center,
        color: Colors.black12,
        child: Text(status.isEmpty ? 'loading…' : status,
            style: const TextStyle(fontSize: 12)),
      );
    }
    final kind = d['kind'] as String? ?? '';
    final html = d['html'] as String?;
    final imageUrl = d['imageUrl'] as String?;
    Widget child;
    if (html != null && (kind == 'html' || kind == 'html5')) {
      // html5 包相对资源以投放域名为基址（bundleUrl/投放 loader 已在服务端注入）。
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadHtmlString(html, baseUrl: widget.endpoint);
      child = WebViewWidget(controller: controller);
    } else if (kind == 'image' && imageUrl != null) {
      child = Image.network(imageUrl, fit: BoxFit.contain, errorBuilder:
          (context, error, stack) => const Center(child: Text('creative failed')));
    } else {
      child = Center(child: Text('kind "$kind" not renderable on this host yet',
          style: const TextStyle(fontSize: 12)));
    }
    return GestureDetector(
      onTap: _openClick,
      child: SizedBox.expand(child: child),
    );
  }
}
