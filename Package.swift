// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipStack",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // 可执行的 App 目标（菜单栏 + 弹出面板 + 系统集成）
        .executable(name: "ClipStack", targets: ["ClipStack"]),
        // 核心逻辑库（数据模型 / 存储 / 纯逻辑），可单元测试
        .library(name: "ClipStackCore", targets: ["ClipStackCore"])
    ],
    dependencies: [
        // 全局快捷键，支持用户自定义
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        // SQLite 封装，持久化存储
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "ClipStackCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "ClipStack",
            dependencies: [
                "ClipStackCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),
        .testTarget(
            name: "ClipStackCoreTests",
            dependencies: ["ClipStackCore"]
        )
    ]
)
