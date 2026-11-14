import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// AdsOS Flutter client SDK — minimal frozen contract (ADN-06):
/// POST /v1/ad/request → decision + trackers; beacons are plain GETs.
/// The SDK never fabricates viewability/billing proof; video/reward and
/// mobile attribution (install, lifecycle) stay blocked on Q-127..Q-129.
class AdsosClient {
  final Uri endpoint;
  final String requestIdPrefix;

  AdsosClient({required this.endpoint, this.requestIdPrefix = 'flt'});

  Map<String, dynamic> consent(String region,
      {String? tcf, String? gpp, String? ccpa, List<String>? purposeConsents}) {
    final c = <String, dynamic>{'region': region};
    if (tcf != null) c['tcf'] = tcf;
    if (gpp != null) c['gpp'] = gpp;
    if (ccpa != null) c['ccpa'] = ccpa;
    if (purposeConsents != null) c['purposeConsents'] = purposeConsents;
    return c;
  }

  /// Request an ad. Never sends client-side IP: the server fills it authoritatively.
  /// Returns the decision map, or null on 204 (no fill).
  Future<Map<String, dynamic>?> requestAd({
    required String siteId,
    required String zoneId,
    String? publisherId,
    required String deviceType,
    String? language,
    int? width,
    int? height,
    String? geoCountry,
    required Map<String, dynamic> consent,
    List<String>? keywords,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(0xFFFFFFFF).toRadixString(36);
    final payload = <String, dynamic>{
      'requestId': '$requestIdPrefix${now.toRadixString(36)}-$rnd',
      'siteId': siteId,
      'zoneId': zoneId,
      if (publisherId != null) 'publisherId': publisherId,
      'ts': now,
      'device': {
        'type': deviceType,
        if (language != null) 'language': language,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      },
      'geo': {if (geoCountry != null) 'country': geoCountry},
      'consent': consent,
      if (keywords != null && keywords.isNotEmpty) 'keywords': keywords,
    };

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(endpoint.replace(path: '/v1/ad/request'));
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      req.write(jsonEncode(payload));
      final resp = await req.close();
      if (resp.statusCode == 204) return null;
      final text = await utf8.decoder.bind(resp).join();
      if (resp.statusCode != 200) {
        throw AdsosException('ad request failed: HTTP ${resp.statusCode}');
      }
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final decision = decoded['decision'] as Map<String, dynamic>?;
      final trackers = decision?['trackers'] as Map<String, dynamic>?;
      if (decision == null || trackers == null || (trackers['click'] as String?)!.isEmpty) {
        throw const AdsosException('ad request returned malformed decision');
      }
      return decision;
    } finally {
      client.close();
    }
  }

  /// Fire the impression beacon once, after the creative is actually rendered.
  Future<void> trackImpression(Map<String, dynamic> decision) async {
    await _get(_trackerUrl(decision['trackers']['impression'] as String));
  }

  /// Follow the click tracker; returns the landing URL (server 302s).
  Future<String> clickThrough(Map<String, dynamic> decision) async {
    final url = _trackerUrl(decision['trackers']['click'] as String);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.openUrl('GET', Uri.parse(url));
      final resp = await req.close();
      await resp.drain<void>();
      return resp.headers.value(HttpHeaders.locationHeader) ??
          (decision['landingUrl'] as String? ?? '');
    } finally {
      client.close();
    }
  }

  String _trackerUrl(String path) =>
      path.startsWith('http') ? path : endpoint.replace(path: path).toString();

  Future<HttpClientResponse> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.openUrl('GET', Uri.parse(url));
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final resp = await req.close();
      await resp.drain<void>();
      return resp;
    } finally {
      client.close();
    }
  }
}

class AdsosException implements Exception {
  final String message;
  const AdsosException(this.message);
  @override
  String toString() => message;
}
