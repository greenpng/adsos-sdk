// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AdsosSDK",
    platforms: [.iOS(.v15)],
    products: [.library(name: "AdsosSDK", targets: ["AdsosSDK"])],
    targets: [.target(name: "AdsosSDK", path: "Sources/AdsosSDK")]
)
