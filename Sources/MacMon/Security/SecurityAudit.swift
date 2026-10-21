import Foundation
import Security

/// 代码签名校验：用 Security.framework 直接读静态签名信息。
///
/// 相比 `codesign -dv` 命令（每次 20–40ms 的进程启动开销），
/// 这里是内存调用，单次约 1ms，可以对几十个启动项逐个验签。
enum SecurityAudit {

    private static var cache: [String: SigningInfo] = [:]
    private static let lock = NSLock()

    static func signingInfo(path: String) -> SigningInfo {
        guard !path.isEmpty else { return .unknown }

        lock.lock()
        if let hit = cache[path] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let info = readSigning(path: path)

        lock.lock()
        cache[path] = info
        lock.unlock()
        return info
    }

    private static func readSigning(path: String) -> SigningInfo {
        guard FileManager.default.fileExists(atPath: path) else { return .unknown }

        let url = URL(fileURLWithPath: path) as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return SigningInfo(kind: .unsigned)
        }

        // 先做一次签名有效性校验（会走完整个 code directory）
        let validity = SecStaticCodeCheckValidity(code, [], nil)

        var rawInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &rawInfo) == errSecSuccess,
              let dict = rawInfo as? [String: Any] else {
            return SigningInfo(kind: validity == errSecSuccess ? .unknown : .unsigned)
        }

        let teamId = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let codeFlags = (dict[kSecCodeInfoFlags as String] as? UInt32) ?? 0

        // kSecCodeSignatureAdhoc = 0x0002
        if codeFlags & 0x0002 != 0 {
            return SigningInfo(kind: .adhoc, teamId: teamId, authority: "ad-hoc")
        }

        var authority: String?
        if let certificates = dict["certificates"] as? [Any],
           let first = certificates.first {
            // 只取描述信息用于展示，不做信任链判断
            authority = String(describing: type(of: first))
        }

        if validity != errSecSuccess {
            return SigningInfo(kind: .unsigned, teamId: teamId, authority: authority)
        }

        if teamId == nil {
            // 没有 Team ID 但签名有效，通常是 Apple 平台签名
            return SigningInfo(kind: .apple, teamId: nil, authority: authority)
        }
        return SigningInfo(kind: .developerId, teamId: teamId, authority: authority)
    }
}
