import Foundation
import CryptoKit
import Combine

final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class ModuleStore: ObservableObject {
    struct Installed: Codable { var active: Module; var previous: Module?; var healthy: Bool; var minimumAllowedVersion: String? }
    @Published var modules: [Module] = []
    @Published var checking = false
    @Published var statuses: [String: String] = [:]
    @Published var notice = ""
    @Published var blocked = Set<String>()
    private var registry: [String: Installed] = [:]
    private var builtins: [String: Module] = [:]
    private var activeSessions = Set<String>()
    private var rejectedVersions: [String: String] = [:]
    private var registryReadable = true
    private let root: URL
    private let config: HostConfiguration
    private let session: URLSession
    private let builtinRoot: URL?
    private var registryURL: URL { root.appendingPathComponent("registry.json") }
    init(root: URL? = nil, config: HostConfiguration = .bundled, session: URLSession? = nil, builtinRoot: URL? = nil) {
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        self.builtinRoot = builtinRoot ?? Bundle.main.resourceURL?.appendingPathComponent("BuiltinModules")
        self.config = config
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Appocket")
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            if let builtinRoot = self.builtinRoot, let dirs = try? FileManager.default.contentsOfDirectory(at: builtinRoot, includingPropertiesForKeys: nil) {
                for directory in dirs { if let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")), let module = try? JSONDecoder().decode(Module.self, from: data) { try module.validate(); builtins[module.id] = module } }
            }
            if FileManager.default.fileExists(atPath: registryURL.path) {
                do {
                    registry = try JSONDecoder().decode([String: Installed].self, from: Data(contentsOf: registryURL))
                    for (id, install) in registry {
                        try install.active.validate()
                        if let previous = install.previous { try previous.validate() }
                        guard id == install.active.id, install.previous.map({ $0.id == id }) ?? true else { throw ModuleError.invalid("模块注册表身份不一致") }
                    }
                } catch {
                    registryReadable = false; registry = [:]
                    notice = "模块注册表损坏，已保护原文件；暂时只使用内置模块。"
                }
            }
            rejectedVersions = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: self.root.appendingPathComponent("rejected.json")))) ?? [:]
            refresh()
            for install in registry.values where !install.healthy && UserDefaults.standard.bool(forKey: "launching.\(install.active.id).\(install.active.version)") { rollback(install.active) }
        } catch { notice = "本地模块读取失败：\(error.localizedDescription)"; refresh() }
    }
    private func refresh() {
        var all = builtins
        for (id, install) in registry { all[id] = install.active }
        modules = all.values.sorted { $0.id < $1.id }
        blocked = Set(registry.compactMap { id, install in
            if rejectedVersions[id] == install.active.version { return id }
            guard let minimum = install.minimumAllowedVersion.flatMap(Version.init), let current = Version(install.active.version), current < minimum else { return nil }; return id
        })
    }
    private func persist() throws { try JSONEncoder().encode(registry).write(to: registryURL, options: .atomic); refresh() }
    func directory(for module: Module) -> URL {
        let downloaded = root.appendingPathComponent("Modules/\(module.id)/\(module.version)")
        if FileManager.default.fileExists(atPath: downloaded.appendingPathComponent("manifest.json").path) { return downloaded }
        return builtinRoot!.appendingPathComponent(module.id)
    }
    func begin(_ module: Module) { activeSessions.insert(module.id); if registry[module.id]?.healthy == false { UserDefaults.standard.set(true, forKey: "launching.\(module.id).\(module.version)") } }
    func end(_ module: Module) { activeSessions.remove(module.id) }
    func markHealthy(_ module: Module) {
        guard registry[module.id]?.active.version == module.version else { return }
        registry[module.id]?.healthy = true
        UserDefaults.standard.removeObject(forKey: "launching.\(module.id).\(module.version)")
        do { try persist() } catch { notice = "模块状态保存失败" }
    }
    func rollback(_ module: Module) {
        guard let install = registry[module.id], install.active.version == module.version else { return }
        rejectedVersions[module.id] = module.version
        do {
            try JSONEncoder().encode(rejectedVersions).write(to: root.appendingPathComponent("rejected.json"), options: .atomic)
            let fallback = install.previous ?? builtins[module.id]
            if let fallback, install.minimumAllowedVersion.flatMap(Version.init).map({ Version(fallback.version)! >= $0 }) ?? true {
                registry[module.id] = Installed(active: fallback, previous: nil, healthy: true, minimumAllowedVersion: install.minimumAllowedVersion)
                try persist(); statuses[module.id] = "启动失败，已回退至 \(fallback.version)"
            } else { blocked.insert(module.id); statuses[module.id] = "模块启动失败，等待可用更新" }
        } catch { notice = "回退失败：\(error.localizedDescription)" }
    }
    private func fetch(_ url: URL, limit: Int) async throws -> Data {
        guard NetworkPolicy.origin(url.absoluteString) != nil else { throw ModuleError.invalid("更新地址必须使用 HTTPS") }
        var request = URLRequest(url: url); request.timeoutInterval = 30; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.expectedContentLength <= limit else { throw ModuleError.invalid("下载失败或资源过大") }
        var result = Data()
        for try await byte in bytes { if result.count >= limit { throw ModuleError.invalid("资源超过大小限制") }; result.append(byte) }
        return result
    }
    func checkForUpdates() async {
        guard !checking, registryReadable else { return }; checking = true; defer { checking = false }
        guard !config.catalogURL.isEmpty, let url = URL(string: config.catalogURL) else { notice = "当前使用内置模块；尚未配置更新目录。"; return }
        do {
            let catalog = try JSONDecoder().decode(Catalog.self, from: await fetch(url, limit: 1024 * 1024))
            try catalog.validate()
            notice = ""
            for remote in catalog.modules {
                if let current = modules.first(where: { $0.id == remote.id }) {
                    var installed = registry[remote.id] ?? Installed(active: current, healthy: true)
                    installed.minimumAllowedVersion = remote.minimumAllowedVersion; registry[remote.id] = installed
                    try persist()
                }
                guard Version(remote.minHostVersion)! <= Version("1.0.0")! else { statuses[remote.id] = "请更新 Lingrove 后使用新版"; continue }
                if let current = modules.first(where: { $0.id == remote.id }), Version(current.version)! >= Version(remote.version)! { statuses[remote.id] = "已是最新版本"; continue }
                guard rejectedVersions[remote.id] != remote.version else { statuses[remote.id] = "此版本曾启动失败，等待后续版本"; continue }
                if activeSessions.contains(remote.id) { statuses[remote.id] = "发现更新，退出模块后再检查"; continue }
                statuses[remote.id] = "正在下载 \(remote.version)…"
                do { try await install(remote); statuses[remote.id] = "已更新至 \(remote.version)" }
                catch { statuses[remote.id] = "更新失败，保留本地版本：\(error.localizedDescription)" }
            }
        } catch { notice = "更新检查失败，继续使用可用本地模块：\(error.localizedDescription)" }
    }
    private func install(_ module: Module) async throws {
        guard let rawURL = module.downloadUrl, let url = URL(string: rawURL), let expectedHash = module.sha256, expectedHash.count == 64,
              let expectedSize = module.size, expectedSize > 0, expectedSize <= 50 * 1024 * 1024 else { throw ModuleError.invalid("下载元数据无效") }
        let data = try await fetch(url, limit: expectedSize)
        guard data.count == expectedSize, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedHash else { throw ModuleError.invalid("安装包哈希不匹配") }
        let stage = root.appendingPathComponent("staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        try StoredZIP.extract(data, to: stage)
        let manifest = try JSONDecoder().decode(Module.self, from: Data(contentsOf: stage.appendingPathComponent("manifest.json")))
        try manifest.validate()
        guard manifest.id == module.id, manifest.version == module.version, manifest.entry == module.entry,
              manifest.allowedOrigins == module.allowedOrigins, manifest.minHostVersion == module.minHostVersion,
              FileManager.default.fileExists(atPath: stage.appendingPathComponent(module.entry).path) else { throw ModuleError.invalid("包内清单与目录不一致") }
        let destination = root.appendingPathComponent("Modules/\(module.id)/\(module.version)")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: stage, to: destination)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; var moduleDirectory = destination; try moduleDirectory.setResourceValues(values)
        let previous = modules.first { $0.id == module.id }; let oldRegistry = registry
        registry[module.id] = Installed(active: module, previous: previous, healthy: false, minimumAllowedVersion: module.minimumAllowedVersion)
        do { try persist() } catch { registry = oldRegistry; refresh(); throw error }
        // Keep at most the active and rollback versions; never remove state files.
        let retained = Set([module.version, previous?.version].compactMap { $0 })
        if let versions = try? FileManager.default.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil) {
            for version in versions where !retained.contains(version.lastPathComponent) { try? FileManager.default.removeItem(at: version) }
        }
    }
}
