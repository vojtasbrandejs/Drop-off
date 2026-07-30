// swift-tools-version: 6.0

import PackageDescription
import Foundation

let isContinuousIntegration = ProcessInfo.processInfo.environment["CI"] == "true"
let localTestingFrameworkPath = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let localTestingLibraryPath = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let localTestSwiftSettings: [SwiftSetting]? = isContinuousIntegration ? nil : [
    .unsafeFlags(["-F", localTestingFrameworkPath]),
]

let localTestLinkerSettings: [LinkerSetting]? = isContinuousIntegration ? nil : [
    .unsafeFlags([
        "-F", localTestingFrameworkPath,
        "-Xlinker", "-rpath",
        "-Xlinker", localTestingFrameworkPath,
        "-Xlinker", "-rpath",
        "-Xlinker", localTestingLibraryPath,
    ]),
]

let package = Package(
    name: "Drop-off",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "DropOff", targets: ["DropOff"]),
    ],
    targets: [
        .executableTarget(
            name: "DropOff",
            path: "Sources/DropOff"
        ),
        .testTarget(
            name: "DropOffTests",
            dependencies: ["DropOff"],
            path: "Tests/DropOffTests",
            swiftSettings: localTestSwiftSettings,
            linkerSettings: localTestLinkerSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)
