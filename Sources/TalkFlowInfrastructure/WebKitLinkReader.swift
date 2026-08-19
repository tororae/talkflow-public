import Foundation
import TalkFlowDomain
import WebKit

/// Opens links with an offscreen WKWebView and reads the rendered text.
///
/// A real render rather than a raw fetch, because the pages people paste here are
/// usually JS apps that a plain download returns empty. The web view is never
/// shown and never handed to the model: the app renders, pulls the text out, and
/// only that text goes into the prompt. The model still cannot browse.
///
/// Bounded on every axis a page could run away on — a per-page timeout, a settle
/// pause for the page's own JS, a character cap on what is kept, and a two-link
/// cap upstream. Private and loopback hosts are refused before a load starts, and
/// a redirect into one is refused again, so a pasted `http://localhost/…` or an
/// internal address cannot be turned into a request from this Mac. Best effort:
/// a public name that resolves to a private address is not caught here, because
/// the web view does its own resolving.
public struct WebKitLinkReader: MessageLinkSource {
    private let timeout: TimeInterval
    private let settle: TimeInterval
    private let maxChars: Int

    public init(timeout: TimeInterval = 12, settle: TimeInterval = 1.5, maxChars: Int = 6000) {
        self.timeout = timeout
        self.settle = settle
        self.maxChars = maxChars
    }

    public func links(for messages: [ChatMessage], in room: ChatRoom) async -> [MessageLink] {
        let candidates = MessageLinkSelection.candidates(in: messages)
        guard !candidates.isEmpty else { return [] }

        // One at a time. The sweep that calls this is serial already, and two
        // web views rendering at once would only compete for the same main thread.
        var links: [MessageLink] = []
        for candidate in candidates where Self.isSafeToOpen(candidate.url) {
            guard let text = await render(candidate.url) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            links.append(MessageLink(
                messageID: candidate.messageID,
                url: candidate.url,
                text: String(trimmed.prefix(maxChars))
            ))
        }
        return links
    }

    private func render(_ url: URL) async -> String? {
        let timeout = timeout
        let settle = settle
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.main.async {
                let renderer = PageRenderer(url: url, settle: settle) { text in
                    continuation.resume(returning: text)
                }
                renderer.load()
                // The strong capture here is what keeps the renderer alive while it
                // loads: its web view holds the delegate weakly, so nothing else
                // does. When this fires the render is either long done — `finish`
                // is idempotent — or stuck, and this is the ceiling that ends it.
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    renderer.finish(nil)
                }
            }
        }
    }

    /// Refuses a URL before it becomes a request. Host literals only: localhost,
    /// the loopback and private IPv4 ranges, and the IPv6 loopback and local
    /// ranges. Non-http(s) schemes are refused too, so `file:` and `data:` never
    /// load.
    static func isSafeToOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return false
        }
        let octets = host.split(separator: ".")
        if octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) {
            let o = octets.compactMap { Int($0) }
            if o.count == 4 {
                if o[0] == 127 || o[0] == 10 || o[0] == 0 { return false }
                if o[0] == 172, (16...31).contains(o[1]) { return false }
                if o[0] == 192, o[1] == 168 { return false }
                if o[0] == 169, o[1] == 254 { return false }
            }
        }
        if host.contains(":") {
            if host == "::1" || host.hasPrefix("fe80") || host.hasPrefix("fc") || host.hasPrefix("fd") {
                return false
            }
        }
        return true
    }
}

/// Drives one offscreen load to its text and reports once. Lives only on the main
/// thread — every WebKit touch here is reached through `DispatchQueue.main`.
private final class PageRenderer: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let url: URL
    private let settle: TimeInterval
    /// Nil once reported. Doubles as the "already finished" guard, so a timeout
    /// that fires after a successful read reports nothing a second time.
    private var onDone: ((String?) -> Void)?
    private var webView: WKWebView?

    init(url: URL, settle: TimeInterval, onDone: @escaping (String?) -> Void) {
        self.url = url
        self.settle = settle
        self.onDone = onDone
    }

    func load() {
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 900),
            configuration: WKWebViewConfiguration()
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        webView.load(URLRequest(url: url, timeoutInterval: 15))
    }

    func finish(_ text: String?) {
        guard let onDone else { return }
        self.onDone = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        onDone(text)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The page loaded; give its JS a moment to draw before reading the text.
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self, weak webView] in
            guard let self, let webView, self.onDone != nil else { return }
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
                self?.finish(result as? String ?? "")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    /// The one gate every navigation passes through. Only safe http(s) is allowed;
    /// an app-scheme deep link (`transferloom://…`), a `file:`/`data:` URL, or a
    /// private host is cancelled here.
    ///
    /// Cancelling is what stops WebKit from handing the URL to the system — the
    /// handoff that popped the "no app to open this" dialog when an "open in app"
    /// page redirected to its scheme. It does not end the render: the http page
    /// already loaded, so a late redirect is ignored, not treated as a failure.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let target = navigationAction.request.url,
              WebKitLinkReader.isSafeToOpen(target)
        else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// Blocks pop-ups and `window.open`, the other way an "open in app" page
    /// reaches for an external scheme — those bypass the navigation gate above.
    /// Returning nil means no window is opened and nothing is handed to the system.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}
