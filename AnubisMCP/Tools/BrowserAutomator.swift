import Foundation
import UIKit
import WebKit

/// In-app browser the avatar can drive end-to-end: navigate, inspect a
/// token-lean snapshot of the page, click/fill by element index or CSS
/// selector, run JS, and take screenshots. Hosted visibly in StatusView so a
/// human can watch what the avatar is doing.
@MainActor
final class BrowserAutomator: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: - Navigation

    func navigate(to urlString: String) async throws -> String {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            throw ToolError("Invalid http(s) URL: \(urlString)")
        }
        if navigationContinuation != nil {
            throw ToolError("A navigation is already in progress")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.navigationContinuation = continuation
            self.webView.load(URLRequest(url: url, timeoutInterval: 25))
        }
        // Let late scripts/layout settle before the caller snapshots.
        try? await Task.sleep(nanoseconds: 500_000_000)
        return currentPageDescription()
    }

    func goBack() async throws -> String {
        guard webView.canGoBack else { throw ToolError("No page to go back to") }
        webView.goBack()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return currentPageDescription()
    }

    private func currentPageDescription() -> String {
        JSON.encodeString([
            "url": webView.url?.absoluteString ?? "about:blank",
            "title": webView.title ?? "",
        ])
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishNavigation(with: error)
    }

    nonisolated func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        finishNavigation(with: error)
    }

    private nonisolated func finishNavigation(with error: Error) {
        Task { @MainActor in
            self.navigationContinuation?.resume(throwing: ToolError("Navigation failed: \(error.localizedDescription)"))
            self.navigationContinuation = nil
        }
    }

    // MARK: - JavaScript

    @discardableResult
    func evaluate(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: ToolError("JavaScript error: \(error.localizedDescription)"))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Token-lean page outline: URL, title, trimmed visible text, and an
    /// indexed list of interactive elements. Indexes are stable until the next
    /// snapshot and are the primary target handles for click/fill.
    func snapshot(maxTextLength: Int) async throws -> String {
        let script = """
        (function() {
          const interactiveSelector = 'a[href], button, input, textarea, select, [role=button], [role=link], [onclick]';
          const elements = Array.from(document.querySelectorAll(interactiveSelector));
          window.__anubisElements = [];
          const items = [];
          for (const el of elements) {
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            if (rect.width === 0 || rect.height === 0 || style.visibility === 'hidden' || style.display === 'none') continue;
            const index = window.__anubisElements.length;
            window.__anubisElements.push(el);
            const entry = {
              i: index,
              tag: el.tagName.toLowerCase(),
              text: (el.innerText || el.value || el.placeholder || el.getAttribute('aria-label') || '').trim().slice(0, 80),
            };
            if (el.tagName === 'A' && el.href) entry.href = el.href.slice(0, 120);
            if (el.tagName === 'INPUT') entry.type = el.type;
            if (el.name) entry.name = el.name;
            items.push(entry);
            if (items.length >= 120) break;
          }
          const text = (document.body ? document.body.innerText : '').replace(/\\n{3,}/g, '\\n\\n').slice(0, \(maxTextLength));
          return JSON.stringify({
            url: location.href,
            title: document.title,
            text: text,
            elements: items,
          });
        })();
        """
        guard let result = try await evaluate(script) as? String else {
            throw ToolError("Snapshot returned no data")
        }
        return result
    }

    func click(index: Int?, selector: String?) async throws -> String {
        let target: String
        if let index {
            target = "window.__anubisElements && window.__anubisElements[\(index)]"
        } else if let selector {
            let escaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            target = "document.querySelector('\(escaped)')"
        } else {
            throw ToolError("Provide 'index' (from browser_snapshot) or 'selector'")
        }
        let script = """
        (function() {
          const el = \(target);
          if (!el) return JSON.stringify({ok: false, error: 'element not found'});
          el.scrollIntoView({block: 'center'});
          el.click();
          return JSON.stringify({ok: true, clicked: (el.innerText || el.value || el.tagName).trim().slice(0, 80)});
        })();
        """
        let result = try await evaluate(script) as? String ?? "{\"ok\": false}"
        // Clicks often trigger navigation; give the page a beat to move.
        try? await Task.sleep(nanoseconds: 800_000_000)
        return result
    }

    func fill(index: Int?, selector: String?, text: String) async throws -> String {
        let target: String
        if let index {
            target = "window.__anubisElements && window.__anubisElements[\(index)]"
        } else if let selector {
            let escaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            target = "document.querySelector('\(escaped)')"
        } else {
            throw ToolError("Provide 'index' (from browser_snapshot) or 'selector'")
        }
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = """
        (function() {
          const el = \(target);
          if (!el) return JSON.stringify({ok: false, error: 'element not found'});
          el.focus();
          el.value = '\(escapedText)';
          el.dispatchEvent(new Event('input', {bubbles: true}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
          return JSON.stringify({ok: true});
        })();
        """
        return try await evaluate(script) as? String ?? "{\"ok\": false}"
    }

    func screenshot() async throws -> String {
        let configuration = WKSnapshotConfiguration()
        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: ToolError("Screenshot failed: \(error?.localizedDescription ?? "unknown")"))
                }
            }
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.6) else {
            throw ToolError("Could not encode screenshot")
        }
        return jpeg.base64EncodedString()
    }
}
