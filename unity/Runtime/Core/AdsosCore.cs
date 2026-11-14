using System;
using System.Globalization;
using System.Text;

namespace Adsos.Sdk.Core
{
    /// <summary>
    /// Pure, engine-free core of the Unity SDK (payload building, minimal JSON
    /// parsing, request-id and tracker helpers). Kept free of UnityEngine
    /// references so the same logic is unit-testable with plain .NET in CI;
    /// the Unity MonoBehaviour glue lives in AdsosClient.cs.
    /// </summary>
    public static class AdsosCore
    {
        /// <summary>Build the frozen /v1/ad/request request body. The caller
        /// supplies the timestamp (Unix ms) so tests can pin the contract.</summary>
        public static string BuildRequestBody(string requestId, string siteId, string zoneId,
            string publisherId, string deviceType, string language, int? screenWidth,
            int? screenHeight, string geoCountry, ConsentData consent, string[] keywords,
            long timestampMillis)
        {
            var sb = new StringBuilder("{");
            sb.Append("\"requestId\":\"").Append(JsonEscape(requestId)).Append("\",");
            sb.Append("\"siteId\":\"").Append(JsonEscape(siteId)).Append("\",");
            sb.Append("\"zoneId\":\"").Append(JsonEscape(zoneId)).Append("\",");
            if (!string.IsNullOrEmpty(publisherId))
                sb.Append("\"publisherId\":\"").Append(JsonEscape(publisherId)).Append("\",");
            sb.Append("\"ts\":").Append(timestampMillis.ToString(CultureInfo.InvariantCulture)).Append(",");
            sb.Append("\"device\":{\"type\":\"").Append(JsonEscape(deviceType)).Append("\"");
            if (!string.IsNullOrEmpty(language))
                sb.Append(",\"language\":\"").Append(JsonEscape(language)).Append("\"");
            if (screenWidth.HasValue)
                sb.Append(",\"width\":").Append(screenWidth.Value.ToString(CultureInfo.InvariantCulture));
            if (screenHeight.HasValue)
                sb.Append(",\"height\":").Append(screenHeight.Value.ToString(CultureInfo.InvariantCulture));
            sb.Append("},");
            sb.Append("\"geo\":{\"country\":");
            sb.Append(!string.IsNullOrEmpty(geoCountry)
                ? "\"" + JsonEscape(geoCountry) + "\"" : "\"\"");
            sb.Append("},");
            sb.Append("\"consent\":").Append(BuildConsentJson(consent));
            if (keywords != null && keywords.Length > 0)
            {
                sb.Append(",\"keywords\":[");
                for (int i = 0; i < keywords.Length; i++)
                {
                    if (i > 0) sb.Append(",");
                    sb.Append("\"").Append(JsonEscape(keywords[i])).Append("\"");
                }
                sb.Append("]");
            }
            sb.Append("}");
            return sb.ToString();
        }

        /// <summary>Serialize the consent block (frozen server contract).</summary>
        public static string BuildConsentJson(ConsentData c)
        {
            var sb = new StringBuilder("{");
            sb.Append("\"region\":\"").Append(JsonEscape(c?.region ?? "NONE")).Append("\"");
            if (!string.IsNullOrEmpty(c?.tcf)) sb.Append(",\"tcf\":\"").Append(JsonEscape(c.tcf)).Append("\"");
            if (!string.IsNullOrEmpty(c?.gpp)) sb.Append(",\"gpp\":\"").Append(JsonEscape(c.gpp)).Append("\"");
            if (!string.IsNullOrEmpty(c?.ccpa)) sb.Append(",\"ccpa\":\"").Append(JsonEscape(c.ccpa)).Append("\"");
            if (c?.purposeConsents != null && c.purposeConsents.Length > 0)
            {
                sb.Append(",\"purposeConsents\":[");
                for (int i = 0; i < c.purposeConsents.Length; i++)
                {
                    if (i > 0) sb.Append(",");
                    sb.Append("\"").Append(JsonEscape(c.purposeConsents[i])).Append("\"");
                }
                sb.Append("]");
            }
            sb.Append("}");
            return sb.ToString();
        }

        /// <summary>Deterministic-enough request id: prefix + epoch36 + random suffix.</summary>
        public static string NewRequestId(string prefix, Random rng, long epochMillis)
        {
            var bytes = new byte[4];
            rng.NextBytes(bytes);
            var suffix = Convert.ToHexString(bytes).ToLowerInvariant();
            return prefix + epochMillis.ToString("x") + "-" + suffix;
        }

        /// <summary>JSON string escaping without any external dependency.</summary>
        public static string JsonEscape(string s)
        {
            if (s == null) return "";
            var sb = new StringBuilder(s.Length + 8);
            foreach (var ch in s)
            {
                switch (ch)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (ch < ' ') sb.Append("\\u").Append(((int)ch).ToString("x4"));
                        else sb.Append(ch);
                        break;
                }
            }
            return sb.ToString();
        }

        /// <summary>
        /// Minimal extraction of the frozen decision shape (string/int fields
        /// and the trackers object). Dependency-free and testable outside the
        /// Editor; hosts needing richer JSON may plug their own parser.
        /// </summary>
        public static DecisionData ParseDecision(string json)
        {
            if (json == null || json.IndexOf("\"trackers\"", StringComparison.Ordinal) < 0)
                return null;
            var click = StringField(json, "click");
            if (string.IsNullOrEmpty(click)) return null;
            return new DecisionData
            {
                auctionId = StringField(json, "auctionId"),
                campaignId = StringField(json, "campaignId"),
                creativeId = StringField(json, "creativeId"),
                billingModel = StringField(json, "billingModel"),
                format = StringField(json, "format"),
                kind = StringField(json, "kind"),
                html = StringField(json, "html"),
                clickUrl = click,
                impressionUrl = StringField(json, "impression"),
                landingUrl = StringField(json, "landingUrl"),
            };
        }

        /// <summary>Read a JSON string field (shallow, for the frozen shape).</summary>
        public static string StringField(string src, string name)
        {
            var key = "\"" + name + "\":";
            var i = src.IndexOf(key, StringComparison.Ordinal);
            if (i < 0) return null;
            i += key.Length;
            while (i < src.Length && char.IsWhiteSpace(src[i])) i++;
            if (i >= src.Length) return null;
            if (src[i] == '"')
            {
                i++;
                var sb = new StringBuilder();
                while (i < src.Length && src[i] != '"')
                {
                    if (src[i] == '\\' && i + 1 < src.Length)
                    {
                        var n = src[i + 1];
                        sb.Append(n == 'n' ? '\n' : n == 'r' ? '\r' : n == 't' ? '\t' : n);
                        i += 2;
                    }
                    else { sb.Append(src[i]); i++; }
                }
                return sb.ToString();
            }
            var j = i;
            while (j < src.Length && (char.IsDigit(src[j]) || src[j] == '-')) j++;
            return j > i ? src.Substring(i, j - i) : null;
        }

        /// <summary>Resolve a tracker path against the configured endpoint.</summary>
        public static string TrackerUrl(string endpoint, string path)
        {
            if (path == null) return endpoint;
            return path.StartsWith("http", StringComparison.Ordinal) ? path : endpoint.TrimEnd('/') + path;
        }
    }

    /// <summary>Consent block for the frozen contract.</summary>
    public sealed class ConsentData
    {
        public string region;
        public string tcf;
        public string gpp;
        public string ccpa;
        public string[] purposeConsents;
    }

    /// <summary>Parsed decision (frozen shape).</summary>
    public sealed class DecisionData
    {
        public string auctionId;
        public string campaignId;
        public string creativeId;
        public string billingModel;
        public string format;
        public string kind;
        public string html;
        public string impressionUrl;
        public string clickUrl;
        public string landingUrl;
    }
}
