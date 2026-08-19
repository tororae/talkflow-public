// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TalkFlow",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "TalkFlow", targets: ["TalkFlowApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1")
    ],
    targets: [
        .target(name: "TalkFlowDomain"),
        .target(
            name: "TalkFlowApplication",
            dependencies: ["TalkFlowDomain"]
        ),
        .target(
            name: "TalkFlowInfrastructure",
            dependencies: [
                "TalkFlowDomain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "TalkFlowFeatures",
            dependencies: ["TalkFlowDomain", "TalkFlowApplication"]
        ),
        .executableTarget(
            name: "TalkFlowApp",
            dependencies: [
                "TalkFlowApplication",
                "TalkFlowInfrastructure",
                "TalkFlowFeatures"
            ]
        ),
        .testTarget(
            name: "TalkFlowDomainTests",
            dependencies: ["TalkFlowDomain"]
        ),
        .testTarget(
            name: "TalkFlowApplicationTests",
            dependencies: ["TalkFlowApplication", "TalkFlowDomain"]
        ),
        .testTarget(
            name: "TalkFlowFeaturesTests",
            dependencies: ["TalkFlowFeatures", "TalkFlowApplication", "TalkFlowDomain"]
        ),
        .testTarget(
            name: "TalkFlowInfrastructureTests",
            dependencies: [
                "TalkFlowInfrastructure",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
