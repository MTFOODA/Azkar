// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "azkar_mobile",
  platforms: [.iOS("15.0")],
  products: [.library(name: "azkar-mobile", targets: ["azkar_mobile"])],
  targets: [.target(name: "azkar_mobile", dependencies: [])]
)
