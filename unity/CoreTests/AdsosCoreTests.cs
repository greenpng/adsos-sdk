using System;
using System.Collections.Generic;
using Adsos.Sdk.Core;

namespace Adsos.Sdk.CoreTests
{
    /// <summary>
    /// Dependency-free test runner for the Unity SDK core (CI: dotnet run).
    /// Independent expectations are written by hand before assertions; a
    /// failure exits non-zero. This is engine-free logic verification only —
    /// it is NOT Unity display acceptance (no Editor, no rendering).
    /// </summary>
    public static class Program
    {
        private static int failures;

        private static void Check(string name, bool condition)
        {
            if (condition)
            {
                Console.WriteLine("ok - " + name);
            }
            else
            {
                failures++;
                Console.WriteLine("FAIL - " + name);
            }
        }

        public static int Main()
        {
            var now = 1_700_000_000_000L;
            var rng = new Random(20261114);

            // 载荷形状：与已冻结契约逐字段一致；客户端不上报 IP。
            var body = AdsosCore.BuildRequestBody(
                "unt012abc", "site-1", "mrec-1", "pub-1", "mobile", "zh-CN", 1080, 2400,
                "CN", new ConsentData { region = "NONE" }, new[] { "gaming" }, now);
            Check("requestId kept", body.Contains("\"requestId\":\"unt012abc\""));
            Check("site/zone kept", body.Contains("\"siteId\":\"site-1\"") && body.Contains("\"zoneId\":\"mrec-1\""));
            Check("publisher kept", body.Contains("\"publisherId\":\"pub-1\""));
            Check("ts ms", body.Contains("\"ts\":1700000000000"));
            Check("device type", body.Contains("\"device\":{\"type\":\"mobile\",\"language\":\"zh-CN\",\"width\":1080,\"height\":2400}"));
            Check("geo country", body.Contains("\"geo\":{\"country\":\"CN\"}"));
            Check("consent region", body.Contains("\"consent\":{\"region\":\"NONE\"}"));
            Check("keywords array", body.Contains("\"keywords\":[\"gaming\"]"));
            Check("no client ip", !body.Contains("\"ip\""));

            // consent 变体：GDPR 带 TCF/用途清单。
            var gdpr = AdsosCore.BuildConsentJson(new ConsentData
            {
                region = "GDPR", tcf = "CPX", purposeConsents = new[] { "ads" },
            });
            Check("gdpr tcf", gdpr.Contains("\"tcf\":\"CPX\""));
            Check("gdpr purposes", gdpr.Contains("\"purposeConsents\":[\"ads\"]"));

            // requestId：同参数多次调用互不相同、前缀保留。
            var a = AdsosCore.NewRequestId("unt", rng, now);
            var b = AdsosCore.NewRequestId("unt", rng, now);
            Check("ids differ", a != b && a.StartsWith("unt", StringComparison.Ordinal));

            // JSON 转义：引号/反斜杠/控制字符。
            Check("escape quote", AdsosCore.JsonEscape("a\"b") == "a\\\"b");
            Check("escape backslash", AdsosCore.JsonEscape("a\\b") == "a\\\\b");
            Check("escape control", AdsosCore.JsonEscape("a\nb") == "a\\nb");
            Check("escape null-safe", AdsosCore.JsonEscape(null) == "");

            // 决策解析：冻结形状、转义还原、缺 trackers 判畸形。
            var json = "{\"decision\":{\"auctionId\":\"auc-1\",\"campaignId\":\"cmp-1\"," +
                       "\"creativeId\":\"crt-1\",\"billingModel\":\"CPM\",\"format\":\"320x50\"," +
                       "\"kind\":\"html\",\"html\":\"<b>x</b>\"," +
                       "\"trackers\":{\"impression\":\"/v1/track/impression?e=1\",\"click\":\"/v1/track/click?e=1\"}," +
                       "\"landingUrl\":\"https://landing.example.com\"}}";
            var d = AdsosCore.ParseDecision(json);
            Check("decision parsed", d != null && d.campaignId == "cmp-1" && d.creativeId == "crt-1");
            Check("tracker click", d.clickUrl == "/v1/track/click?e=1");
            Check("tracker impression", d.impressionUrl == "/v1/track/impression?e=1");
            Check("landing kept", d.landingUrl == "https://landing.example.com");
            Check("html decoded", d.html == "<b>x</b>");
            Check("malformed null", AdsosCore.ParseDecision("{\"decision\":{}}") == null);
            Check("null-safe null", AdsosCore.ParseDecision(null) == null);

            // tracker URL 解析：相对路径拼端点，绝对路径原样。
            Check("relative tracker", AdsosCore.TrackerUrl("https://ads.example.com", "/v1/track/click") == "https://ads.example.com/v1/track/click");
            Check("absolute tracker", AdsosCore.TrackerUrl("https://ads.example.com", "https://cdn.example.com/b") == "https://cdn.example.com/b");

            Console.WriteLine(failures == 0 ? "ALL PASS" : failures + " FAILURES");
            return failures == 0 ? 0 : 1;
        }
    }
}
