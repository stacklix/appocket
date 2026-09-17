import Foundation
import CryptoKit

final class MockProtocol: URLProtocol, @unchecked Sendable {
    static var responses: [String: (Int, Data)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.responses[request.url!.path] ?? (404, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Length": "\(data.count)"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct CoreChecks {
    @MainActor static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = fixtures.appendingPathComponent("state")
        func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); print("PASS \(message)") }
        func rejects(_ message: String, _ operation: () throws -> Void) { do { try operation(); fatalError("Expected rejection: \(message)") } catch { print("PASS \(message)") } }
        check(Version("1.10.0")! > Version("1.2.0")!, "semantic version ordering")
        check(Version("../1") == nil && Version("1.2") == nil, "invalid versions rejected")
        check(NetworkPolicy.allows(URL(string: "https://api.example.com/a")!, origins: ["https://api.example.com"]), "allowed origin")
        check(!NetworkPolicy.allows(URL(string: "https://api.example.com.evil.test")!, origins: ["https://api.example.com"]), "suffix spoof rejected")
        check(!NetworkPolicy.allows(URL(string: "https://api.example.com:444/a")!, origins: ["https://api.example.com"]), "port mismatch rejected")
        for name in ["traversal", "absolute", "compressed", "symlink", "truncated"] {
            let destination = fixtures.appendingPathComponent("extract-\(name)")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            rejects("reject ZIP \(name)") { try StoredZIP.extract(Data(contentsOf: fixtures.appendingPathComponent("\(name).zip")), to: destination) }
        }
        var module = try JSONDecoder().decode(Module.self, from: Data(contentsOf: fixtures.appendingPathComponent("builtin/sentra/manifest.json")))
        func catalog(_ module: Module) throws -> Data {
            try JSONEncoder().encode(Catalog(modules: [module]))
        }
        let decoded = try JSONDecoder().decode(Catalog.self, from: catalog(module))
        try decoded.validate()
        check(decoded.modules.count == 1, "plain JSON catalog accepted without keys")
        rejects("duplicate modules rejected") { try Catalog(modules: [module, module]).validate() }
        rejects("malformed catalog rejected") { _ = try JSONDecoder().decode(Catalog.self, from: Data("{}".utf8)) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: config)
        let hostConfig = HostConfiguration(catalogURL: "https://updates.test/catalog.json")
        let store = ModuleStore(root: root, config: hostConfig, session: session, builtinRoot: fixtures.appendingPathComponent("builtin"))
        check(store.modules.first?.version == "1.0.0", "bundled module available offline")
        let archive = try Data(contentsOf: fixtures.appendingPathComponent("valid.zip"))
        module.version = "1.1.0"; module.downloadUrl = "https://updates.test/module.zip"; module.size = archive.count
        module.sha256 = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        MockProtocol.responses = ["/catalog.json": (200, try catalog(module)), "/module.zip": (200, archive)]
        let insecureStore = ModuleStore(root: fixtures.appendingPathComponent("http-state"), config: HostConfiguration(catalogURL: "http://updates.test/catalog.json"), session: session, builtinRoot: fixtures.appendingPathComponent("builtin"))
        await insecureStore.checkForUpdates()
        check(insecureStore.modules.first?.version == "1.0.0" && insecureStore.notice.contains("HTTPS"), "HTTP catalog rejected before download")
        await store.checkForUpdates()
        check(store.modules.first?.version == "1.1.0", "HTTPS plain catalog update installed and activated")
        check(FileManager.default.fileExists(atPath: store.directory(for: module).appendingPathComponent("index.html").path), "installed resources readable")
        store.markHealthy(module)
        let restarted = ModuleStore(root: root, config: hostConfig, session: session, builtinRoot: fixtures.appendingPathComponent("builtin"))
        check(restarted.modules.first?.version == "1.1.0", "active version survives restart")
        MockProtocol.responses["/catalog.json"] = (200, Data("{}".utf8))
        await store.checkForUpdates()
        check(store.modules.first?.version == "1.1.0" && store.notice.contains("更新检查失败"), "invalid JSON catalog preserves active module")
        module.version = "1.2.0"; module.sha256 = String(repeating: "0", count: 64)
        MockProtocol.responses["/catalog.json"] = (200, try catalog(module))
        await store.checkForUpdates()
        check(store.modules.first?.version == "1.1.0", "bad hash preserves old version")
        let newer = try Data(contentsOf: fixtures.appendingPathComponent("newer.zip"))
        module.size = newer.count; module.sha256 = SHA256.hash(data: newer).map { String(format: "%02x", $0) }.joined()
        MockProtocol.responses = ["/catalog.json": (200, try catalog(module)), "/module.zip": (200, newer)]
        await store.checkForUpdates(); check(store.modules.first?.version == "1.2.0", "next update installed")
        store.rollback(module); check(store.modules.first?.version == "1.1.0", "failed startup rolls back to previous version")
        await store.checkForUpdates(); check(store.modules.first?.version == "1.1.0", "known bad version is not reinstalled")
        MockProtocol.responses["/catalog.json"] = (500, Data())
        await store.checkForUpdates(); check(store.modules.first?.version == "1.1.0", "offline update failure preserves available module")
        module.minimumAllowedVersion = "1.2.0"
        MockProtocol.responses["/catalog.json"] = (200, try catalog(module))
        await store.checkForUpdates()
        check(store.blocked.contains("sentra"), "mandatory minimum blocks retired fallback")
        let blockedRestart = ModuleStore(root: root, config: hostConfig, session: session, builtinRoot: fixtures.appendingPathComponent("builtin"))
        check(blockedRestart.blocked.contains("sentra"), "minimum version enforced while offline after restart")
        module.version = "2.0.0"; module.minHostVersion = "2.0.0"
        MockProtocol.responses["/catalog.json"] = (200, try catalog(module))
        await store.checkForUpdates()
        check(store.modules.first?.version == "1.1.0", "incompatible host version never installed")
        let brokenRoot = fixtures.appendingPathComponent("broken-registry")
        try FileManager.default.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: brokenRoot.appendingPathComponent("registry.json"))
        let brokenStore = ModuleStore(root: brokenRoot, config: hostConfig, session: session, builtinRoot: fixtures.appendingPathComponent("builtin"))
        check(brokenStore.modules.first?.version == "1.0.0", "corrupt registry still exposes bundled module")
        await brokenStore.checkForUpdates()
        check(try! String(contentsOf: brokenRoot.appendingPathComponent("registry.json"), encoding: .utf8) == "broken", "corrupt registry preserved without overwrite")
        print("All native core checks passed")
    }
}
