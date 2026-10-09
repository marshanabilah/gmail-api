// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExpenseTracker",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ExpenseTrackerCore", targets: ["ExpenseTrackerCore"]),
    ],
    targets: [
        .target(name: "ExpenseTrackerCore"),
        .executableTarget(name: "CoreVerification", dependencies: ["ExpenseTrackerCore"]),
        .testTarget(name: "ExpenseTrackerCoreTests", dependencies: ["ExpenseTrackerCore"]),
    ]
)
