// swift-tools-version: 6.2
//
//  Package.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import PackageDescription

let package = Package(
    name: "ScreenSaverKit",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ScreenSaverKit", targets: ["ScreenSaverKit"])],
    targets: [
        .target(name: "ScreenSaverKit"),
        // Plays layouts over the local snapshot for design review: `make run-saver-demo`.
        .executableTarget(name: "ScreenSaverDemo", dependencies: ["ScreenSaverKit"]),
        .testTarget(name: "ScreenSaverKitTests", dependencies: ["ScreenSaverKit"])
    ]
)
