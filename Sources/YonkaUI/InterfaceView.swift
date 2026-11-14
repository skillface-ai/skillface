import SwiftUI
import WebKit
import YonkaCore

/// An app's `interface.html`, running. It's given `yonka` and its state, and gets back only
/// what it sends as the user: it keeps nothing, loads nothing (`Interface.policy`) and is never
/// let go anywhere, since it's written from a skill off the internet and it sees the user's memory.
///
/// ponytail: the policy and this delegate are the whole lock, which holds for a page the
/// user's own builder wrote. Sharing apps between people means a hostile page: then it needs
/// Yongkang's `PageLock`, measured against an attack page.
struct InterfaceView: NSViewRepresentable {
    let html: String
    let state: Interface.State
    var send: (String) -> Void = { _ in }
    /// The page's script threw: said to the user, who can tell the builder.
    var failed: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // The state it opens with is there before its first script runs, so it never draws empty first.
        let start = WKUserScript(source: "\(Interface.bridge)\n__yonka(\(state.json));", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(start)
        configuration.userContentController.add(context.coordinator, name: "yonka")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        // The page's own `--bg` is what shows, with no white flash before it in the dark.
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.shown = state
        (context.coordinator.send, context.coordinator.failed) = (send, failed)
        view.loadHTMLString(Interface.page(html), baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        (context.coordinator.send, context.coordinator.failed) = (send, failed)
        guard context.coordinator.shown != state else { return }
        context.coordinator.shown = state
        view.evaluateJavaScript("__yonka(\(state.json))")
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var shown: Interface.State?
        var send: (String) -> Void = { _ in }
        var failed: (String) -> Void = { _ in }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let text = message.body as? String { send(text) }
            if let error = (message.body as? [String: Any])?["error"] as? String { failed(error) }
        }

        /// Only the page itself, which loads as about:blank. A link or a script can't take it elsewhere.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.request.url?.scheme == "about" ? .allow : .cancel
        }
    }
}
