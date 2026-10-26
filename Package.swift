// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickKey",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuickKey", targets: ["QuickKey"])],
    targets: [
        .target(name: "ShortcutCore", resources: [.process("Resources")]),
        .executableTarget(name: "QuickKey", dependencies: ["ShortcutCore"], exclude: ["Info.plist"]),
        .testTarget(name: "ShortcutCoreTests", dependencies: ["ShortcutCore"])
    ]
)
