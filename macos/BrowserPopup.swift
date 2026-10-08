import AppKit
import WebKit

final class BrowserPopupController: NSWindowController, NSWindowDelegate {
    let webView: WKWebView
    var onClose: ((WKWebView) -> Void)?

    init(configuration: WKWebViewConfiguration, screen: NSScreen?) {
        // Keep WebKit's supplied process/session configuration and opener, but
        // never inject the player's scripts into an authentication popup.
        configuration.userContentController = WKUserContentController()
        webView = WKWebView(frame: .zero, configuration: configuration)
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: min(720, area.width - 40), height: min(680, area.height - 80))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "로그인 · TurnTabler"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: min(420, size.width), height: min(360, size.height))
        super.init(window: window)
        window.delegate = self
        webView.frame = window.contentView!.bounds
        webView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webView)
        window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
                                      y: area.midY - window.frame.height / 2))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(webView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateLocation() { window?.subtitle = webView.url?.host ?? "" }

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onClose?(webView)
    }
}
