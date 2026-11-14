import UIKit
import WebKit

/// AdsOS banner view (D-87 functional baseline): request an ad, render
/// html/html5 in a WKWebView and image creatives in a UIImageView, fire the
/// impression beacon after real rendering and route clicks through the click
/// tracker. The SDK never fabricates viewability/billing proof; video/reward
/// formats and install attribution stay blocked on Q-127..Q-129.
public final class AdsosBannerView: UIView {
    private var client: AdsosClient?
    private var consent: AdsosClient.Consent = .init(region: "NONE")
    private var keywords: [String]?
    private var lastDecision: AdsosClient.Decision?
    private var statusLabel: UILabel?

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Bind the delivery endpoint and consent (host-owned consent decision).
    public func configure(endpoint: URL, consent: AdsosClient.Consent) {
        self.client = AdsosClient(endpoint: endpoint)
        self.consent = consent
    }

    public func setKeywords(_ keys: [String]?) {
        keywords = keys
    }

    /// Load an ad for siteId/zoneId; results render inside this view.
    public func load(siteId: String, zoneId: String, publisherId: String? = nil) {
        guard let client else {
            show(status: "configure() must be called before load()")
            return
        }
        clear()
        var input = AdsosClient.AdInput(
            siteId: siteId, zoneId: zoneId, publisherId: publisherId,
            deviceType: UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile",
            consent: consent)
        // 粗粒度设备基础数据：语言/屏幕尺寸/地区（locale 派生，无 GPS）。
        input.language = Locale.current.identifier
        input.width = Int(UIScreen.main.bounds.width * UIScreen.main.scale)
        input.height = Int(UIScreen.main.bounds.height * UIScreen.main.scale)
        // regionCode 在 iOS 16 起软弃用（替代为 Locale.region），但 iOS 15 目标可用。
        input.geoCountry = Locale.current.regionCode

        Task { [weak self] in
            do {
                let result = try await client.requestAd(input)
                await MainActor.run {
                    switch result {
                    case .filled(let decision): self?.render(decision)
                    case .noFill: self?.show(status: "no fill")
                    }
                }
            } catch {
                await MainActor.run { self?.show(status: "ad error: \(error)") }
            }
        }
    }

    private func render(_ decision: AdsosClient.Decision) {
        lastDecision = decision
        clear()
        guard let client else { return }
        let base = client.baseEndpoint
        if let html = decision.html, decision.kind == "html" || decision.kind == "html5" {
            let web = WKWebView(frame: bounds)
            web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            web.isOpaque = false
            web.backgroundColor = .clear
            addSubview(web)
            // The bundle sandbox is enforced server-side by the delivery
            // domain's bundle route; WKWebView stays a passive renderer.
            web.loadHTMLString(html, baseURL: base)
            Task { [weak self] in try? await client.trackImpression(decision) }
        } else if decision.kind == "image", let imageUrl = decision.imageUrl,
                  let url = URL(string: imageUrl.starts(with: "http") ? imageUrl : (base?.absoluteString ?? "") + imageUrl) {
            let img = UIImageView(frame: bounds)
            img.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            img.contentMode = .scaleAspectFit
            addSubview(img)
            Task { [weak self] in
                do {
                    let (data, resp) = try await URLSession.shared.data(from: url)
                    await MainActor.run {
                        if let bmp = UIImage(data: data), (resp as? HTTPURLResponse)?.statusCode == 200 {
                            img.image = bmp
                            Task { [weak self] in try? await client.trackImpression(decision) }
                        } else {
                            self?.show(status: "creative asset failed to load")
                        }
                    }
                } catch {
                    Task { await MainActor.run { self?.show(status: "creative asset failed to load") } }
                }
            }
        } else {
            show(status: "creative kind \(decision.kind ?? "?") not renderable on this host yet")
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        guard let client, let d = lastDecision else { return }
        Task {
            let landing = (try? await client.clickThrough(d)) ?? d.landingUrl ?? ""
            if let url = URL(string: landing) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
        }
    }

    private func show(status: String) {
        clear()
        let label = UILabel(frame: bounds)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.text = status
        label.textAlignment = .center
        label.font = .boldSystemFont(ofSize: 13)
        addSubview(label)
        statusLabel = label
    }

    private func clear() {
        subviews.forEach { $0.removeFromSuperview() }
        statusLabel = nil
    }
}
