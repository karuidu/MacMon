// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacMon",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacMon", targets: ["MacMon"])
    ],
    targets: [
        // libproc 的声明不在 Darwin 模块里，用一个极薄的 C 桥接 target 暴露出来。
        // 除了 include 一个系统头文件之外没有任何实现，纯粹为了 `import CProc`。
        .target(
            name: "CProc",
            path: "Sources/CProc",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "MacMon",
            dependencies: ["CProc"],
            path: "Sources/MacMon",
            swiftSettings: [
                // 采集层大量使用 C 互操作与后台线程，Swift 6 严格并发会带来
                // 大量与业务无关的标注噪音，这里固定在 Swift 5 语言模式。
                .unsafeFlags(["-strict-concurrency=minimal"])
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreFoundation"),
                .linkedLibrary("proc")
            ]
        )
    ]
)
