using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace Adsos.Sdk
{
    /// <summary>
    /// AdsOS Unity client SDK — minimal frozen contract (ADN-06, D-87 baseline):
    /// POST /v1/ad/request → decision + trackers; beacons are plain GETs.
    /// Engine-free logic lives in Core/AdsosCore.cs (CI-tested with dotnet).
    /// The SDK never fabricates viewability/billing proof; video/reward and
    /// mobile attribution (install, lifecycle) stay blocked on Q-127..Q-129.
    /// </summary>
    public sealed class AdsosClient
    {
        private readonly string endpoint;
        private readonly string requestIdPrefix;
        private readonly System.Random rng = new System.Random();

        /// <summary>Persistent, app-scoped identifier. The host app owns this
        /// value and its storage; the SDK never generates or persists one on
        /// its own (privacy: D-87 — no unsolicited persistent ids).</summary>
        public string VisitorId { get; set; }

        public AdsosClient(string endpoint, string requestIdPrefix = "unt")
        {
            this.endpoint = endpoint.TrimEnd('/');
            this.requestIdPrefix = requestIdPrefix;
        }

        /// <summary>Device basics collected from the Unity runtime (coarse,
        /// consent-gated by the caller): type, OS language, screen size.</summary>
        public static void CollectDeviceBasics(out string deviceType, out string language,
            out int screenWidth, out int screenHeight, out string region)
        {
            deviceType = SystemInfo.deviceType == DeviceType.Handheld ? "mobile" : "desktop";
            language = Application.systemLanguage.ToString();
            screenWidth = Screen.currentResolution.width;
            screenHeight = Screen.currentResolution.height;
            region = Application.systemLanguage == SystemLanguage.ChineseSimplified
                ? "CN" : "";
        }

        /// <summary>
        /// Request an ad. geoCountry is coarse (no GPS); the server fills the
        /// authoritative IP. onFilled receives the parsed decision.
        /// </summary>
        public IEnumerator RequestAd(string siteId, string zoneId, string publisherId,
            Adsos.Sdk.Core.ConsentData consent, Action<Adsos.Sdk.Core.DecisionData> onFilled,
            Action onNoFill, Action<Exception> onError)
        {
            CollectDeviceBasics(out var deviceType, out var language, out var w, out var h, out var region);
            var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            var requestId = Adsos.Sdk.Core.AdsosCore.NewRequestId(requestIdPrefix, rng, now);
            var body = Adsos.Sdk.Core.AdsosCore.BuildRequestBody(
                requestId, siteId, zoneId, publisherId, deviceType, language, w, h,
                region, consent, null, now);

            using var req = new UnityWebRequest(endpoint + "/v1/ad/request", "POST");
            req.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));
            req.downloadHandler = new DownloadHandlerBuffer();
            req.SetRequestHeader("Content-Type", "application/json");
            req.SetRequestHeader("Cache-Control", "no-store");
            req.timeout = 10;
            yield return req.SendWebRequest();

            if (req.responseCode == 204L) { onNoFill?.Invoke(); yield break; }
            if (req.result != UnityWebRequest.Result.Success || req.responseCode != 200L)
            {
                onError?.Invoke(new Exception("ad request failed: HTTP " + req.responseCode));
                yield break;
            }
            var decision = Adsos.Sdk.Core.AdsosCore.ParseDecision(req.downloadHandler.text);
            if (decision == null)
                onError?.Invoke(new Exception("ad request returned malformed decision"));
            else
                onFilled?.Invoke(decision);
        }

        /// <summary>Fire the impression beacon once, after the creative renders.</summary>
        public IEnumerator TrackImpression(Adsos.Sdk.Core.DecisionData decision)
        {
            yield return Beacon(Adsos.Sdk.Core.AdsosCore.TrackerUrl(endpoint, decision.impressionUrl));
        }

        /// <summary>
        /// Follow the click tracker; the server 302s to the landing page —
        /// Application.OpenURL stays the host's decision (deep-link fallback
        /// is blocked on Q-129).
        /// </summary>
        public IEnumerator ClickThrough(Adsos.Sdk.Core.DecisionData decision, Action<string> onLanding)
        {
            yield return Beacon(Adsos.Sdk.Core.AdsosCore.TrackerUrl(endpoint, decision.clickUrl));
            onLanding?.Invoke(decision.landingUrl);
        }

        private static IEnumerator Beacon(string url)
        {
            using var req = UnityWebRequest.Get(url);
            req.SetRequestHeader("Cache-Control", "no-store");
            req.timeout = 10;
            yield return req.SendWebRequest();
        }
    }
}
