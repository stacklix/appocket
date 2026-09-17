import SwiftUI
import WebKit
import CryptoKit

struct ModuleScreen: View {
    let module: Module
    @ObservedObject var store: ModuleStore
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    var body: some View {
        Group {
            if let failure {
                ContentUnavailableView { Label("子应用暂时无法打开", systemImage: "exclamationmark.triangle") } description: { Text(failure) } actions: { Button("返回应用列表") { dismiss() } }
            } else {
                ModuleWebView(module: module, directory: store.directory(for: module), onReady: { store.markHealthy(module) }, onFailure: { message in failure = message; store.rollback(module) })
            }
        }
        .navigationTitle(module.name).navigationBarTitleDisplayMode(.inline)
        .onAppear { store.begin(module) }.onDisappear { store.end(module) }
    }
}
struct ModuleWebView: UIViewRepresentable {
    let module: Module
    let directory: URL
    let onReady: () -> Void
    let onFailure: (String) -> Void
    func makeCoordinator() -> Runtime { Runtime(module: module, directory: directory, onReady: onReady, onFailure: onFailure) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "appocket")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "appocket")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1)
        view.navigationDelegate = context.coordinator; context.coordinator.webView = view
        view.load(URLRequest(url: URL(string: "appocket://\(module.id)/\(module.entry)")!))
        context.coordinator.startWatchdog()
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Runtime) {
        coordinator.close(); uiView.stopLoading(); uiView.configuration.userContentController.removeScriptMessageHandler(forName: "appocket", contentWorld: .page)
    }
}
@MainActor final class Runtime: NSObject, WKURLSchemeHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    let module: Module
    let directory: URL
    let onReady: () -> Void
    let onFailure: (String) -> Void
    weak var webView: WKWebView?
    private var networkTasks: [String: Task<Any, Error>] = [:]
    private var watchdog: Task<Void, Never>?
    private var ready = false
    private var closed = false
    private let stateRoot: URL
    private var extraOrigins: [String] = []
    private let injectedSession: URLSession?
    private lazy var session: URLSession = {
        if let injectedSession { return injectedSession }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 120
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()
    init(module: Module, directory: URL, onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void, networkSession: URLSession? = nil) {
        self.injectedSession = networkSession
        self.module = module; self.directory = directory; self.onReady = onReady; self.onFailure = onFailure
        stateRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Appocket/State/\(module.id)")
        super.init()
        extraOrigins = UserDefaults.standard.stringArray(forKey: "origins.\(module.id)") ?? []
    }
    func startWatchdog() {
        watchdog = Task { try? await Task.sleep(for: .seconds(20)); guard !Task.isCancelled, !ready, !closed else { return }; fail("页面启动超时；如果是下载版本，已尝试回退。") }
    }
    func close() { closed = true; watchdog?.cancel(); for task in networkTasks.values { task.cancel() }; networkTasks.removeAll(); session.invalidateAndCancel() }
    private func fail(_ reason: String) { guard !closed else { return }; onFailure(reason); close() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("页面进程已退出，请返回后重试。") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error.localizedDescription) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error.localizedDescription) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.scheme == "appocket" && url?.host == module.id ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url, url.host == module.id else { throw ModuleError.invalid("资源来源无效") }
            let path = url.path.removingPercentEncoding ?? url.path
            guard !path.contains("\\"), !path.split(separator: "/").contains("..") else { throw ModuleError.invalid("资源路径无效") }
            let file = directory.appendingPathComponent(path == "/" ? module.entry : String(path.dropFirst())).standardizedFileURL.resolvingSymlinksInPath()
            guard file.path.hasPrefix(directory.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { throw ModuleError.invalid("资源越界") }
            var data = try Data(contentsOf: file)
            let mime = ["html":"text/html", "js":"application/javascript", "css":"text/css", "json":"application/json", "svg":"image/svg+xml", "png":"image/png", "jpg":"image/jpeg", "woff2":"font/woff2", "mp3":"audio/mpeg"][file.pathExtension] ?? "application/octet-stream"
            if file.pathExtension == "html", let html = String(data: data, encoding: .utf8) {
                let csp = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\">"
                data = Data(html.replacingOccurrences(of: "<head>", with: "<head>" + csp).utf8)
            }
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
            urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard !closed, message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "appocket", message.frameInfo.request.url?.host == module.id,
              let body = message.body as? [String: Any], body["version"] as? Int == 1,
              let method = body["method"] as? String, let params = body["params"] as? [String: Any] else { replyHandler(nil, "非法通信请求"); return }
        Task {
            do { let result = try await handle(method, params); replyHandler(result, nil) }
            catch { replyHandler(nil, error.localizedDescription) }
        }
    }
    private func stateURL(_ key: String) throws -> URL {
        guard key.range(of: "^[a-zA-Z0-9._-]{1,100}$", options: .regularExpression) != nil else { throw ModuleError.invalid("存储键无效") }
        try FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)
        return stateRoot.appendingPathComponent(key + ".json")
    }
    private func handle(_ method: String, _ params: [String: Any]) async throws -> Any {
        switch method {
        case "runtime.ready": ready = true; watchdog?.cancel(); onReady(); return true
        case "state.get":
            guard let key = params["key"] as? String else { throw ModuleError.invalid("缺少存储键") }
            let url = try stateURL(key)
            if !FileManager.default.fileExists(atPath: url.path) { return NSNull() }
            return try String(contentsOf: url, encoding: .utf8)
        case "state.set":
            guard let key = params["key"] as? String, let value = params["value"] as? String, value.utf8.count <= 8 * 1024 * 1024 else { throw ModuleError.invalid("存储内容无效或过大") }
            try Data(value.utf8).write(to: stateURL(key), options: .atomic); return true
        case "clipboard.write":
            guard let text = params["text"] as? String, text.utf8.count <= 1024 * 1024 else { throw ModuleError.invalid("复制内容过大") }
            UIPasteboard.general.string = text; return true
        case "network.authorize":
            guard let raw = params["origin"] as? String, let origin = NetworkPolicy.origin(raw), origin == raw else { throw ModuleError.invalid("域名无效") }
            if (module.allowedOrigins + extraOrigins).contains(origin) { return true }
            guard extraOrigins.count < 20, let controller = webView?.window?.rootViewController else { throw ModuleError.invalid("无法添加域名") }
            var presenter = controller; while let presented = presenter.presentedViewController { presenter = presented }
            let allowed = await withCheckedContinuation { continuation in
                let alert = UIAlertController(title: "允许 \(module.name) 连接此服务？", message: "\(origin)\n\n你输入的句子和配置的服务商凭据将发送至此地址。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in continuation.resume(returning: false) })
                alert.addAction(UIAlertAction(title: "允许", style: .default) { _ in continuation.resume(returning: true) })
                presenter.present(alert, animated: true)
            }
            guard allowed, !closed else { throw ModuleError.invalid("未授权此域名") }
            extraOrigins.append(origin); UserDefaults.standard.set(extraOrigins, forKey: "origins.\(module.id)"); return true
        case "http.cancel": if let id = params["id"] as? String { networkTasks[id]?.cancel() }; return true
        case "http.request":
            guard let id = params["id"] as? String, id.count <= 80, networkTasks[id] == nil, networkTasks.count < 6 else { throw ModuleError.invalid("请求数量或标识无效") }
            let task = Task<Any, Error> { try await self.request(params, id: id) }
            networkTasks[id] = task
            defer { networkTasks.removeValue(forKey: id) }
            return try await task.value
        default: throw ModuleError.invalid("不支持的宿主方法")
        }
    }
    private func request(_ params: [String: Any], id: String) async throws -> Any {
        guard let raw = params["url"] as? String, let url = URL(string: raw), NetworkPolicy.allows(url, origins: module.allowedOrigins + extraOrigins) else { throw ModuleError.invalid("请求域名未授权，请在连接设置中保存此地址") }
        let method = (params["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].contains(method) else { throw ModuleError.invalid("不支持的 HTTP 方法") }
        var request = URLRequest(url: url); request.httpMethod = method
        if let body = params["body"] as? String { guard body.utf8.count <= 1024 * 1024 else { throw ModuleError.invalid("请求内容过大") }; request.httpBody = Data(body.utf8) }
        for (key, value) in params["headers"] as? [String: String] ?? [:] {
            guard !["host", "cookie", "origin", "referer", "content-length", "connection"].contains(key.lowercased()), !key.contains("\n"), !value.contains("\n"), !value.contains("\r") else { throw ModuleError.invalid("不允许的请求头") }
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ModuleError.invalid("无效 HTTP 响应") }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            let key = String(describing: entry.key).lowercased()
            if key != "set-cookie" { result[key] = String(describing: entry.value) }
        }
        let streaming = params["stream"] as? Bool == true && headers["content-type"]?.contains("text/event-stream") == true && (200..<300).contains(response.statusCode)
        var buffer = Data(), total = 0
        for try await byte in bytes {
            try Task.checkCancellation(); total += 1
            guard total <= 8 * 1024 * 1024 else { throw ModuleError.invalid("响应超过大小限制") }
            buffer.append(byte)
            if streaming && byte == 10 {
                try await emit(id, String(decoding: buffer, as: UTF8.self)); buffer.removeAll(keepingCapacity: true)
            }
        }
        if streaming && !buffer.isEmpty { try await emit(id, String(decoding: buffer, as: UTF8.self)); buffer.removeAll() }
        return ["status": response.statusCode, "headers": headers, "body": String(decoding: buffer, as: UTF8.self)]
    }
    private func emit(_ id: String, _ chunk: String) async throws {
        guard !closed, let webView else { throw CancellationError() }
        _ = try await webView.callAsyncJavaScript("window.__appocketChunk(id, chunk)", arguments: ["id": id, "chunk": chunk], in: nil, contentWorld: .page)
    }
}
