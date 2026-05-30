// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DataProvider",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DataProvider",
            targets: ["DataProvider"]),
        .library(
            name: "LibrarySync",
            targets: ["LibrarySync"])
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DataProvider"),
        .target(
            name: "LibrarySync",
            dependencies: ["DataProvider"]),
        .testTarget(
            name: "DataProviderTests",
            dependencies: ["DataProvider"]
        ),
        .testTarget(
            name: "LibrarySyncTests",
            dependencies: ["LibrarySync"]
        )
    ],
)
