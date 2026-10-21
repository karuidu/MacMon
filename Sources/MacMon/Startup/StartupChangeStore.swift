import Foundation

/// 启动项变更的落盘存储。
///
/// 只存最近 `limit` 条：这类记录的价值在于「最近发生了什么」，
/// 攒到几百条既没人翻，也会让每次读写多花几十毫秒。
final class StartupChangeStore {

    static let limit = 20

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
            self.fileURL = base
                .appendingPathComponent("MacMon", isDirectory: true)
                .appendingPathComponent("startup-changes.json")
        }
    }

    var path: String { fileURL.path }

    // MARK: - 读写

    func load() -> [StartupChange] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let decoded = try? Self.decoder.decode([StartupChange].self, from: data) else {
            // 解码失败（手改坏了、或者日期策略变了）当空数组处理，
            // 绝不 crash——这只是审计日志，不是关键数据
            return []
        }
        return Array(decoded.prefix(Self.limit))
    }

    func save(_ changes: [StartupChange]) {
        let trimmed = Array(changes.prefix(Self.limit))
        guard let data = try? Self.encoder.encode(trimmed) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // 落盘失败不影响告警，静默降级
        }
    }

    // MARK: - 编解码器

    /// 编码器与解码器的日期策略**必须一致**：
    /// 编码用了默认的 `deferredToDate`（浮点秒），解码若换成 `.iso8601`
    /// 就会「写得进、读不出」，而且 `try?` 会把错误吞掉，表现为记录莫名消失。
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
