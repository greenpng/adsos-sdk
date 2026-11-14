package io.adsos.sdk

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/**
 * AdsOS Android client SDK — minimal frozen contract (ADN-06):
 * POST /v1/ad/request → decision + trackers; beacons are plain GETs.
 * The SDK never fabricates viewability/billing proof; video/reward and mobile
 * attribution (install, lifecycle) stay blocked on Q-127..Q-129.
 */
class AdsosClient(
    private val endpoint: String,
    private val requestIdPrefix: String = "and",
) {
    data class Consent(
        val region: String,
        val tcf: String? = null,
        val gpp: String? = null,
        val ccpa: String? = null,
        val purposeConsents: List<String>? = null,
    )

    data class AdInput(
        val siteId: String,
        val zoneId: String,
        val publisherId: String? = null,
        val deviceType: String,
        val language: String? = null,
        val width: Int? = null,
        val height: Int? = null,
        val geoCountry: String? = null,
        val consent: Consent,
        val keywords: List<String>? = null,
    )

    data class Decision(
        val auctionId: String,
        val campaignId: String,
        val creativeId: String,
        val billingModel: String,
        val format: String,
        val width: Int,
        val height: Int,
        val kind: String,
        val html: String?,
        val imageUrl: String?,
        val title: String?,
        val body: String?,
        val cta: String?,
        val deepLinkUrl: String?,
        val bundleUrl: String?,
        val impressionUrl: String,
        val clickUrl: String,
        val landingUrl: String,
    )

    sealed class AdResult {
        data class Filled(val decision: Decision) : AdResult()
        object NoFill : AdResult()
    }

    /** Request an ad. Never sends client-side IP: the server fills it authoritatively. */
    fun requestAd(input: AdInput): AdResult {
        val now = System.currentTimeMillis()
        val body = JSONObject().apply {
            put("requestId", requestIdPrefix + now.toString(36) + "-" + UUID.randomUUID().toString().take(8))
            put("siteId", input.siteId)
            put("zoneId", input.zoneId)
            input.publisherId?.let { put("publisherId", it) }
            put("ts", now)
            put(
                "device",
                JSONObject().apply {
                    put("type", input.deviceType)
                    input.language?.let { put("language", it) }
                    input.width?.let { put("width", it) }
                    input.height?.let { put("height", it) }
                },
            )
            put(
                "geo",
                JSONObject().apply {
                    input.geoCountry?.let { put("country", it) }
                },
            )
            put(
                "consent",
                JSONObject().apply {
                    put("region", input.consent.region)
                    input.consent.tcf?.let { put("tcf", it) }
                    input.consent.gpp?.let { put("gpp", it) }
                    input.consent.ccpa?.let { put("ccpa", it) }
                    input.consent.purposeConsents?.let { put("purposeConsents", it.joinToString(",")) }
                },
            )
            input.keywords?.takeIf { it.isNotEmpty() }?.let {
                put("keywords", it.joinToString(","))
            }
        }

        val conn = URL("$endpoint/v1/ad/request").openConnection() as HttpURLConnection
        conn.requestMethod = "POST"
        conn.doOutput = true
        conn.connectTimeout = 5_000
        conn.readTimeout = 10_000
        conn.setRequestProperty("Content-Type", "application/json")
        conn.setRequestProperty("Cache-Control", "no-store")
        conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
        val status = conn.responseCode
        if (status == 204) {
            conn.disconnect()
            return AdResult.NoFill
        }
        val text = (if (status in 200..299) conn.inputStream else conn.errorStream)
            ?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
        conn.disconnect()
        if (status != 200) {
            throw AdRequestException("ad request failed: HTTP $status")
        }
        val decision = JSONObject(text!!).getJSONObject("decision")
        val trackers = decision.getJSONObject("trackers")
        return AdResult.Filled(
            Decision(
                auctionId = decision.optString("auctionId"),
                campaignId = decision.getString("campaignId"),
                creativeId = decision.getString("creativeId"),
                billingModel = decision.optString("billingModel"),
                format = decision.optString("format"),
                width = decision.optInt("width"),
                height = decision.optInt("height"),
                kind = decision.optString("kind"),
                html = decision.optString("html").takeIf { it.isNotEmpty() },
                imageUrl = decision.optString("imageUrl").takeIf { it.isNotEmpty() },
                title = decision.optString("title").takeIf { it.isNotEmpty() },
                body = decision.optString("body").takeIf { it.isNotEmpty() },
                cta = decision.optString("cta").takeIf { it.isNotEmpty() },
                deepLinkUrl = decision.optString("deepLinkUrl").takeIf { it.isNotEmpty() },
                bundleUrl = decision.optString("bundleUrl").takeIf { it.isNotEmpty() },
                impressionUrl = absolute(trackers.getString("impression")),
                clickUrl = absolute(trackers.getString("click")),
                landingUrl = decision.optString("landingUrl"),
            ),
        )
    }

    /** Fire the impression beacon once, after the creative is actually rendered. */
    fun trackImpression(decision: Decision) {
        get(decision.impressionUrl)
    }

    /**
     * Follow the click tracker; returns the landing URL (server 302s).
     * The host app opens the URL itself — deep-link fallback stays blocked on Q-129.
     */
    fun clickThrough(decision: Decision): String {
        val conn = URL(decision.clickUrl).openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = false
        conn.connectTimeout = 5_000
        conn.readTimeout = 10_000
        val loc = conn.getHeaderField("Location")
        conn.disconnect()
        return loc ?: decision.landingUrl
    }

    fun absolute(path: String): String =
        if (path.startsWith("http")) path else endpoint + path

    /** Delivery origin for bundle/html base URLs (html5 包相对资源挂投放域名）。 */
    fun absoluteBase(): String = endpoint

    /** Fetch raw bytes for creative assets (image kind). */
    fun fetchBytes(url: String): ByteArray? {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 5_000
        conn.readTimeout = 15_000
        conn.setRequestProperty("Cache-Control", "no-store")
        return try {
            if (conn.responseCode in 200..299) conn.inputStream.use { it.readBytes() } else null
        } finally {
            conn.disconnect()
        }
    }

    /** Open the landing URL outside the SDK view (host-visible system browser). */
    fun openExternally(context: android.content.Context, url: String) {
        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun get(url: String) {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 5_000
        conn.readTimeout = 10_000
        conn.setRequestProperty("Cache-Control", "no-store")
        conn.responseCode
        conn.disconnect()
    }
}

class AdRequestException(message: String) : Exception(message)
