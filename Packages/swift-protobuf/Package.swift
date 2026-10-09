// swift-tools-version:6.2
// Runtime-only distribution of Apple SwiftProtobuf 1.38.1.
// Copyright Apple Inc. and the project authors.
// Licensed under Apache License v2.0 with Runtime Library Exception.
import PackageDescription
let package = Package(
    name: "SwiftProtobuf",
    products: [.library(name: "SwiftProtobuf", targets: ["SwiftProtobuf"])],
    traits: [
        .trait(name: "BinaryDelimitedStreams", description: "Foundation stream APIs."),
        .trait(name: "FieldMaskUtilities", description: "FieldMask utilities."),
        .default(enabledTraits: ["BinaryDelimitedStreams", "FieldMaskUtilities"])
    ],
    targets: [.target(name: "SwiftProtobuf", exclude: ["CMakeLists.txt"],
        resources: [.copy("PrivacyInfo.xcprivacy")],
        swiftSettings: [.enableUpcomingFeature("ExistentialAny")])],
    swiftLanguageModes: [.v6]
)
