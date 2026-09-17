import XCTest
import WebKit
@testable import Appocket

final class StubNetwork: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in ["data: {\"text\":\"你", "好\"}\n\n", "data: [DONE]\n\n"] { client?.urlProtocol(self, didLoad: Data(chunk.utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class RuntimeTests: XCTestCase {
    @MainActor func testWebKitBridgeStreamsAndRestrictsOrigins() async throws {
        let module = Module(id: "runtime-test", name: "Test", version: "1.0.0", entry: "index.html", minHostVersion: "1.0.0", bridgeVersion: 1, stateSchemaVersion: 1, allowedOrigins: ["https://allowed.example"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let html = "<html><head></head><body><script src='test.js'></script></body></html>"
        try Data(html.utf8).write(to: directory.appendingPathComponent("index.html"))
        try Data("window.__testChunks=[];window.__appocketChunk=(id,chunk)=>{window.__testChunks.push(chunk)};window.webkit.messageHandlers.appocket.postMessage({version:1,method:'runtime.ready',params:{}});".utf8).write(to: directory.appendingPathComponent("test.js"))
        let loaded = expectation(description: "JS host handshake")
        let networkConfig = URLSessionConfiguration.ephemeral; networkConfig.protocolClasses = [StubNetwork.self]
        let runtime = Runtime(module: module, directory: directory, onReady: { loaded.fulfill() }, onFailure: { XCTFail($0) }, networkSession: URLSession(configuration: networkConfig))
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(runtime, forURLScheme: "appocket")
        config.userContentController.addScriptMessageHandler(runtime, contentWorld: .page, name: "appocket")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        runtime.webView = webView; webView.navigationDelegate = runtime
        webView.load(URLRequest(url: URL(string: "appocket://runtime-test/index.html")!))
        await fulfillment(of: [loaded], timeout: 15)
        defer { runtime.close(); config.userContentController.removeScriptMessageHandler(forName: "appocket", contentWorld: .page) }
        let result = try await webView.callAsyncJavaScript("const r=await window.webkit.messageHandlers.appocket.postMessage({version:1,method:'http.request',params:{id:'stream-1',url:'https://allowed.example/test',stream:true}});return {status:r.status,chunks:window.__testChunks.join('')};", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["status"] as? Int, 200)
        XCTAssertEqual(result?["chunks"] as? String, "data: {\"text\":\"你好\"}\n\ndata: [DONE]\n\n")
        let denied = try await webView.callAsyncJavaScript("try{await window.webkit.messageHandlers.appocket.postMessage({version:1,method:'http.request',params:{id:'denied',url:'https://allowed.example.evil.test'}});return false;}catch(e){return true;}", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(denied as? Bool, true)
        let state = try await webView.callAsyncJavaScript("await window.webkit.messageHandlers.appocket.postMessage({version:1,method:'state.set',params:{key:'check',value:'{\"ok\":true}'}});return await window.webkit.messageHandlers.appocket.postMessage({version:1,method:'state.get',params:{key:'check'}});", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(state as? String, "{\"ok\":true}")
    }
}
