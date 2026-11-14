import Foundation

/// AdsOS iOS client SDK — minimal frozen contract (ADN-06):
/// POST /v1/ad/request → decision + trackers; beacons are plain GETs.
/// The SDK never fabricates viewability/billing proof; video/reward and mobile
/// attribution (install, ATT/IDFA, lifecycle) stay blocked on Q-127..Q-129.
public final class AdsosClient {
    public struct Consent: Codable {
        public var region: String
        public var tcf: String?
        public var gpp: String?
        public var ccpa: String?
        public var purposeConsents: [String]?

        public init(region: String, tcf: String? = nil, gpp: String? = nil,
                    ccpa: String? = nil, purposeConsents: [String]? = nil) {
            self.region = region
            self.tcf = tcf
            self.gpp = gpp
            self.ccpa = ccpa
            self.purposeConsents = purposeConsents
        }
    }

    public struct AdInput {
        public var siteId: String
        public var zoneId: String
        public var publisherId: String?
        public var deviceType: String
        public var language: String?
        public var width: Int?
        public var height: Int?
        public var geoCountry: String?
        public var consent: Consent
        public var keywords: [String]?

        public init(siteId: String, zoneId: String, publisherId: String? = nil,
                    deviceType: String, language: String? = nil, width: Int? = nil,
                    height: Int? = nil, geoCountry: String? = nil,
                    consent: Consent, keywords: [String]? = nil) {
            self.siteId = siteId
            self.zoneId = zoneId
            self.publisherId = publisherId
            self.deviceType = deviceType
            self.language = language
            self.width = width
            self.height = height
            self.geoCountry = geoCountry
            self.consent = consent
            self.keywords = keywords
        }
    }

    public struct Decision: Codable {
        public let auctionId: String?
        public let campaignId: String
        public let creativeId: String
        public let billingModel: String?
        public let format: String?
        public let kind: String?
        public let html: String?
        public let imageUrl: String?
        public let title: String?
        public let body: String?
        public let cta: String?
        public let deepLinkUrl: String?
        public let bundleUrl: String?
        public let trackers: Trackers
        public let landingUrl: String?

        public struct Trackers: Codable {
            public let impression: String
            public let click: String
        }
    }

    public enum AdResult {
        case filled(Decision)
        case noFill
    }

    public enum AdsosError: Error {
        case httpStatus(Int)
        case malformedDecision
    }

    private let endpoint: URL
    private let session: URLSession
    private let requestIdPrefix: String

    /// The delivery origin resolved for bundle/html base URLs.
    public var baseEndpoint: URL? { endpoint }

    public init(endpoint: URL, session: URLSession = .shared, requestIdPrefix: String = "ios") {
        self.endpoint = endpoint
        self.session = session
        self.requestIdPrefix = requestIdPrefix
    }

    /// Request an ad. Never sends client-side IP: the server fills it authoritatively.
    public func requestAd(_ input: AdInput) async throws -> AdResult {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let requestId = requestIdPrefix + String(now, radix: 36) + "-" + UUID().uuidString.prefix(8)

        struct Device: Codable { let type: String; var language: String?; var width: Int?; var height: Int? }
        struct Geo: Codable { var country: String? }
        struct Body: Codable {
            let requestId: String
            let siteId: String
            let zoneId: String
            var publisherId: String?
            let ts: Int64
            let device: Device
            let geo: Geo
            let consent: Consent
            var keywords: [String]?
        }
        let body = Body(requestId: String(requestId), siteId: input.siteId, zoneId: input.zoneId,
                        publisherId: input.publisherId, ts: now,
                        device: Device(type: input.deviceType, language: input.language,
                                       width: input.width, height: input.height),
                        geo: Geo(country: input.geoCountry), consent: input.consent,
                        keywords: input.keywords)

        var req = URLRequest(url: endpoint.appendingPathComponent("/v1/ad/request"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        req.timeoutInterval = 10
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 204 { return .noFill }
        guard status == 200 else { throw AdsosError.httpStatus(status) }

        struct Wrapper: Codable { let decision: Decision? }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
        guard let decision = wrapper.decision, !decision.trackers.click.isEmpty else {
            throw AdsosError.malformedDecision
        }
        return .filled(decision)
    }

    /// Fire the impression beacon once, after the creative is actually rendered.
    public func trackImpression(_ decision: Decision) async throws {
        _ = try await beacon(decision.trackers.impression)
    }

    /// Follow the click tracker; returns the landing URL if the server
    /// 302s to one (deep-link fallback stays blocked on Q-129).
    public func clickThrough(_ decision: Decision) async throws -> String? {
        let (_, response) = try await beacon(decision.trackers.click)
        return (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location")
            ?? decision.landingUrl
    }

    private func beacon(_ path: String) async throws -> (Data, URLResponse) {
        let url = path.hasPrefix("http") ? URL(string: path)! : endpoint.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        req.timeoutInterval = 10
        return try await session.data(for: req)
    }
}
