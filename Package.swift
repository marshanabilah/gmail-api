// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExpenseTracker",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ExpenseTrackerCore", targets: ["ExpenseTrackerCore"]),
        .executable(name: "ExpenseTracker", targets: ["ExpenseTracker"]),
    ],
    targets: [
        .target(name: "ExpenseTrackerCore"),
        .executableTarget(name: "ExpenseTracker", dependencies: ["ExpenseTrackerCore"]),
        .executableTarget(name: "CoreVerification", dependencies: ["ExpenseTrackerCore"]),
    ]
)
