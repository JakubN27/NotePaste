// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "NotePasteCamera",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "NotePasteCamera", targets: ["NotePasteCamera"])
  ],
  targets: [
    .executableTarget(name: "NotePasteCamera")
  ]
)
