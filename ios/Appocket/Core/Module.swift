import Foundation

struct Module: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String?
    var version: String
    var entry: String
    var minHostVersion: String
    var bridgeVersion: Int
    var stateSchemaVersion: Int
    var allowedOrigins: [String]
    var downloadUrl: String?
    var size: Int?
    var sha256: String?
    var minimumAllowedVersion: String?
    func validate() throws {
        guard id.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
              Version(version) != nil, Version(minHostVersion) != nil,
              entry == "index.html", bridgeVersion == 1, stateSchemaVersion == 1,
              allowedOrigins.count <= 30 else { throw ModuleError.invalid("模块信息无效或协议不兼容") }
        if let minimumAllowedVersion, Version(minimumAllowedVersion) == nil { throw ModuleError.invalid("最低版本无效") }
        for origin in allowedOrigins { guard NetworkPolicy.origin(origin) == origin else { throw ModuleError.invalid("域名配置无效") } }
    }
}
struct Version: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let items = value.split(separator: ".", omittingEmptySubsequences: false)
        guard items.count == 3, items.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }), items.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = items.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}
enum ModuleError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
struct Catalog: Codable {
    var modules: [Module]
    func validate() throws {
        guard modules.count <= 100, Set(modules.map(\.id)).count == modules.count else { throw ModuleError.invalid("模块目录重复或过大") }
        for module in modules { try module.validate() }
    }
}
struct HostConfiguration: Codable {
    var catalogURL: String
    static var bundled: Self {
        guard let url = Bundle.main.url(forResource: "HostConfig", withExtension: "json"), let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Self.self, from: data) else { return .init(catalogURL: "") }
        return config
    }
}
enum NetworkPolicy {
    static func origin(_ raw: String) -> String? {
        guard let u = URLComponents(string: raw), u.scheme == "https", let host = u.host, !host.isEmpty, u.user == nil, u.password == nil else { return nil }
        let wrapped = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "https://\(wrapped.lowercased())" + (u.port.map { $0 == 443 ? "" : ":\($0)" } ?? "")
    }
    static func allows(_ url: URL, origins: [String]) -> Bool {
        guard let origin = origin(url.absoluteString) else { return false }
        return origins.contains(origin)
    }
}
