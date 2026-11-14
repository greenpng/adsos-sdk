package io.adsos.sdk

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale
import kotlin.concurrent.thread

/**
 * AdsOS banner view (D-87 functional baseline): request an ad, render
 * html/html5 creatives in a WebView and image creatives in an ImageView,
 * fire the impression beacon after real rendering and route clicks through
 * the click tracker to the landing page. The SDK never fabricates
 * viewability/billing proof; video/reward formats and install attribution
 * stay blocked on Q-127..Q-129.
 *
 * The host supplies consent; the SDK only collects coarse device basics
 * (locale, display metrics) plus an app-scoped visitor id when the host
 * explicitly provides one (no unsolicited persistent identifiers).
 */
class AdsosBannerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    private var client: AdsosClient? = null
    private var visitorIdProvider: (() -> String?)? = null
    private var keywords: List<String>? = null
    private var consent: AdsosClient.Consent = AdsosClient.Consent(region = "NONE")
    private var lastDecision: AdsosClient.Decision? = null

    /** Bind the delivery endpoint, e.g. https://ads.example.com */
    fun configure(endpoint: String, consent: AdsosClient.Consent) {
        this.client = AdsosClient(endpoint)
        this.consent = consent
    }

    /** Optional app-scoped visitor id; only sent when the host opts in. */
    fun setVisitorIdProvider(provider: (() -> String?)?) {
        this.visitorIdProvider = provider
    }

    fun setKeywords(keys: List<String>?) {
        this.keywords = keys
    }

    /** Load an ad for [siteId]/[zoneId]; results render inside this view. */
    fun load(siteId: String, zoneId: String, publisherId: String? = null) {
        val c = client ?: throw IllegalStateException("configure() must be called before load()")
        removeAllViews()
        thread(name = "adsos-request") {
            try {
                val result = c.requestAd(buildInput(siteId, zoneId, publisherId))
                post {
                    when (result) {
                        is AdsosClient.AdResult.Filled -> render(result.decision)
                        AdsosClient.AdResult.NoFill -> renderNoFill()
                    }
                }
            } catch (e: Exception) {
                post { renderError(e.message ?: "ad request failed") }
            }
        }
    }

    private fun buildInput(siteId: String, zoneId: String, publisherId: String?): AdsosClient.AdInput {
        val dm = resources.displayMetrics
        return AdsosClient.AdInput(
            siteId = siteId,
            zoneId = zoneId,
            publisherId = publisherId,
            deviceType = "mobile",
            language = Locale.getDefault().toLanguageTag(),
            width = dm.widthPixels,
            height = dm.heightPixels,
            geoCountry = Locale.getDefault().country.takeIf { it.isNotBlank() },
            consent = consent,
            keywords = keywords,
        )
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun render(decision: AdsosClient.Decision) {
        lastDecision = decision
        val c = client ?: return
        removeAllViews()
        when {
            decision.html != null && (decision.kind == "html" || decision.kind == "html5") -> {
                val web = WebView(context).apply {
                    layoutParams = LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    settings.javaScriptEnabled = true
                    // The bundle sandbox is enforced server-side by the delivery
                    // domain's bundle route (CSP sandbox attr); WebView stays a
                    // passive renderer and never reports billing evidence.
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView,
                            url: String,
                        ): Boolean = false
                    }
                }
                // Load relative bundle assets against the delivery origin.
                val base = c.absoluteBase()
                web.loadDataWithBaseURL(base, decision.html, "text/html", "UTF-8", null)
                addView(web)
                thread(name = "adsos-beacon") { runCatching { c.trackImpression(decision) } }
            }
            decision.kind == "image" && !decision.imageUrl.isNullOrEmpty() -> {
                val img = ImageView(context).apply {
                    layoutParams = LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    scaleType = ImageView.ScaleType.FIT_CENTER
                }
                thread(name = "adsos-image") {
                    val bytes = c.fetchBytes(c.absolute(decision.imageUrl!!))
                    val bmp = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                    post {
                        if (bmp != null) {
                            img.setImageBitmap(bmp)
                            thread(name = "adsos-beacon") { runCatching { c.trackImpression(decision) } }
                        } else {
                            renderError("creative asset failed to load")
                        }
                    }
                }
                addView(img)
            }
            else -> renderError("creative kind ${decision.kind} not renderable on this host yet")
        }
        setOnClickListener { openClick() }
    }

    private fun openClick() {
        val c = client ?: return
        val d = lastDecision ?: return
        thread(name = "adsos-click") {
            val landing = runCatching { c.clickThrough(d) }.getOrDefault(d.landingUrl)
            post { c.openExternally(context, landing) }
        }
    }

    private fun renderNoFill() {
        removeAllViews()
        addView(label("no fill"))
    }

    private fun renderError(message: String) {
        removeAllViews()
        addView(label(message))
    }

    private fun label(text: String) = TextView(context).apply {
        layoutParams = LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        val pad = (12 * resources.displayMetrics.density).toInt()
        setPadding(pad, pad, pad, pad)
        textSize = 13f
        setTypeface(typeface, Typeface.BOLD)
        this.text = text
    }
}
