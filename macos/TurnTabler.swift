import AppKit
import WebKit
import QuartzCore

final class WidgetNSWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var drag: ((NSEvent) -> Void)?
    override func mouseDown(with event: NSEvent) { drag?(event) }
}
final class PassiveImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class PlayerWebView: WKWebView {
    var interactive = false
    override func hitTest(_ point: NSPoint) -> NSView? { interactive ? super.hitTest(point) : nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let prefs = UserDefaults.standard
    var window: WidgetNSWindow!
    var root = FlippedView(frame: NSRect(x: 0, y: 0, width: 460, height: 390))
    var deck = FlippedView(frame: NSRect(x: 0, y: 0, width: 460, height: 390))
    var browserPanel = FlippedView()
    var viewport = FlippedView(frame: NSRect(x: 70.6, y: 17.9, width: 259.2, height: 259.2))
    var web: PlayerWebView!
    var statusItem: NSStatusItem!
    var settings: NSWindow?
    var outputs: NSPopUpButton?
    var outputStatus: NSTextField?
    var volume: NSSlider!
    var address: NSTextField!
    var notice: NSTextField!
    var playButton: NSButton!
    var captionsButton: NSButton!
    var nextButton: NSButton!
    var record: PassiveImage!
    var tracks: [[String: Any]] = []
    var deviceIds = [""]
    var pageOpen = false, playing = false, quitting = false, allowDeviceRequest = false
    var widgetFrame = NSRect.zero
    var timer: Timer?
    var rotation = 0.0
    var pendingURL: URL?
    var lastSavedURL = ""
    let smoke = CommandLine.arguments.contains("--smoke")

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs.register(defaults: ["volume":65.0, "opacity":0.58, "pin":true, "rotation":true, "captions":false, "size":1.0, "output":""])
        let config = WKWebViewConfiguration()
        config.websiteDataStore = smoke ? .nonPersistent() : .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.userContentController.add(self, name: "turntabler")
        let bridgeURL = Bundle.main.url(forResource: "YouTubeBridge", withExtension: "js")!
        let bridge = try! String(contentsOf: bridgeURL, encoding: .utf8)
        let bootstrap = "window.__turntablerInitialVolume=\(smoke ? 0 : prefs.double(forKey: "volume"));window.__turntablerInitialCaptions=\(prefs.bool(forKey: "captions"));window.__turntablerInitialOutputDevice=\(jsonString(prefs.string(forKey: "output") ?? ""));"
        config.userContentController.addUserScript(WKUserScript(source: bootstrap + bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = PlayerWebView(frame: viewport.bounds, configuration: config)
        web.navigationDelegate = self; web.uiDelegate = self; web.underPageBackgroundColor = .clear
        web.autoresizingMask = [.width, .height]
        window = WidgetNSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "TurnTabler"; window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = false; window.isReleasedWhenClosed = false; window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = root; root.addSubview(deck)
        buildDeck(); buildBrowser(); makeMenu(); applyPin();
        if !window.setFrameUsingName("TurnTabler widget") { dock() }
        window.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.playing, self.prefs.bool(forKey: "rotation"), !self.pageOpen else { return }
            self.rotation += 2 * .pi / (24 * 30)
            self.record.layer?.setAffineTransform(CGAffineTransform(rotationAngle: self.rotation))
        }
        if smoke { runSmoke() }
        else if let url = pendingURL { load(url) }
        else if let value = CommandLine.arguments.dropFirst().first(where: { $0.hasPrefix("https://") }), let url = try? youtubeURL(value) { load(url) }
    }
    func image(_ name: String, _ frame: NSRect, in parent: NSView) -> PassiveImage {
        let view = PassiveImage(frame: frame)
        view.image = NSImage(contentsOf: Bundle.main.url(forResource: name, withExtension: "png")!)
        view.imageScaling = .scaleAxesIndependently; parent.addSubview(view); return view
    }
    @discardableResult func button(_ title: String, _ hint: String, _ frame: NSRect, _ action: Selector, in parent: NSView) -> NSButton {
        let value = NSButton(title: title, target: self, action: action)
        value.frame = frame; value.isBordered = false; value.font = .systemFont(ofSize: 15); value.contentTintColor = .white
        value.toolTip = hint; value.setAccessibilityLabel(hint); parent.addSubview(value); return value
    }
    func label(_ text: String, _ frame: NSRect, in parent: NSView) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text); value.frame = frame; value.font = .systemFont(ofSize: 11); value.textColor = .secondaryLabelColor; parent.addSubview(value); return value
    }
    func buildDeck() {
        deck.drag = { [weak self] event in
            guard let self else { return }
            let point = self.deck.convert(event.locationInWindow, from: nil)
            if hypot(point.x - 200.2, point.y - 147.5) < 128 { self.toggle() }
            else { self.window.performDrag(with: event); self.window.saveFrame(usingName: "TurnTabler widget") }
        }
        viewport.drag = deck.drag
        record = image("record", NSRect(x:67.6,y:14.9,width:265.2,height:265.2), in: deck)
        record.wantsLayer = true; record.layer?.anchorPoint = CGPoint(x:0.5,y:0.5); record.layer?.position = CGPoint(x:200.2,y:147.5)
        viewport.wantsLayer = true; viewport.layer?.cornerRadius = 129.6; viewport.layer?.masksToBounds = true
        deck.addSubview(viewport); viewport.addSubview(web); viewport.alphaValue = prefs.double(forKey:"opacity")
        _ = image("highlights", NSRect(x:67.6,y:14.9,width:265.2,height:265.2), in: deck)
        _ = image("body", NSRect(x:10,y:8,width:440,height:293.333), in: deck)
        _ = image("tonearm", NSRect(x:10,y:8,width:440,height:293.333), in: deck)
        let browser = button("", "YouTube 브라우저 열기 · 로그인", NSRect(x:389.5,y:153,width:25,height:24), #selector(openBrowser), in: deck)
        browser.image = NSImage(systemSymbolName:"macwindow", accessibilityDescription:"브라우저")
        let gear = button("", "설정", NSRect(x:389.5,y:179,width:25,height:24), #selector(openSettings), in: deck)
        gear.image = NSImage(systemSymbolName:"gearshape", accessibilityDescription:"설정")
        captionsButton = button("CC", "자막 켜기 / 끄기", NSRect(x:387,y:213,width:30,height:19), #selector(toggleCaptions), in: deck)
        captionsButton.font = .systemFont(ofSize:10)
        volume = NSSlider(value:prefs.double(forKey:"volume"),minValue:0,maxValue:100,target:self,action:#selector(changeVolume))
        volume.frame = NSRect(x:337,y:242,width:81,height:16); volume.toolTip = "음량"; deck.addSubview(volume)
        let transport = NSVisualEffectView(frame:NSRect(x:30,y:307,width:400,height:34))
        transport.material = .hudWindow; transport.blendingMode = .behindWindow; transport.state = .active
        transport.wantsLayer = true; transport.layer?.cornerRadius = 9; transport.layer?.masksToBounds = true; deck.addSubview(transport)
        button("‹", "이전 곡", NSRect(x:32,y:309,width:26,height:28), #selector(previous), in:deck)
        playButton = button("▶", "재생 / 일시정지", NSRect(x:58,y:309,width:26,height:28), #selector(toggle), in:deck)
        nextButton = button("›", "다음 곡", NSRect(x:84,y:309,width:26,height:28), #selector(next), in:deck)
        address = NSTextField(frame:NSRect(x:118,y:314,width:276,height:21)); address.placeholderString = "YouTube 링크 붙여넣기"
        address.font = .systemFont(ofSize:10); address.isBordered = false; address.drawsBackground = false; address.textColor = .white
        address.target = self; address.action = #selector(loadAddress); address.stringValue = prefs.string(forKey:"url") ?? ""; deck.addSubview(address)
        button("≡", "재생목록", NSRect(x:399,y:309,width:27,height:28), #selector(showPlaylist), in:deck)
        notice = label("", NSRect(x:35,y:348,width:390,height:34), in:deck)
    }
    func buildBrowser() {
        browserPanel.wantsLayer = true; browserPanel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; browserPanel.isHidden = true
        browserPanel.autoresizingMask = [.width,.height]; root.addSubview(browserPanel)
        browserPanel.drag = { [weak self] event in self?.window.performDrag(with:event) }
        button("‹ 위젯으로 돌아가기", "위젯으로 돌아가기", NSRect(x:12,y:7,width:155,height:28), #selector(closeBrowser), in:browserPanel)
        button("YouTube 홈", "YouTube 홈", NSRect(x:180,y:7,width:110,height:28), #selector(home), in:browserPanel)
    }
    func makeMenu() {
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appMenu.addItem(appItem)
        let commands = NSMenu(); commands.addItem(withTitle:"TurnTabler 표시",action:#selector(showWidget),keyEquivalent:"0").target = self
        commands.addItem(withTitle:"설정…",action:#selector(openSettings),keyEquivalent:",").target = self
        commands.addItem(.separator()); commands.addItem(withTitle:"TurnTabler 종료",action:#selector(quit),keyEquivalent:"q").target = self
        appItem.submenu = commands
        let edit = NSMenu(title:"편집"); for (name,key,action) in [("실행 취소","z","undo:"),("오려두기","x","cut:"),("복사","c","copy:"),("붙여넣기","v","paste:"),("전체 선택","a","selectAll:")] { edit.addItem(withTitle:name,action:NSSelectorFromString(action),keyEquivalent:key) }
        let editItem = NSMenuItem(title:"편집",action:nil,keyEquivalent:""); editItem.submenu = edit; appMenu.addItem(editItem); NSApp.mainMenu = appMenu
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName:"opticaldisc",accessibilityDescription:"TurnTabler")
        statusItem.menu = commands.copy() as? NSMenu
    }
    @objc func showWidget() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    @objc func quit() { quitting = true; NSApp.terminate(nil) }
    @objc func dock() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800)
        window.setFrameOrigin(NSPoint(x:visible.maxX-window.frame.width-20,y:visible.minY+20))
    }
    func applyPin() { window.level = prefs.bool(forKey:"pin") ? .floating : .normal }
    func script(_ source: String) { web.evaluateJavaScript(source) { _, _ in } }
    @objc func toggle() { script("window.turntablerNative?.toggle()") }
    @objc func next() { script("window.turntablerNative?.next()") }
    @objc func previous() { script("window.turntablerNative?.previous()") }
    @objc func toggleCaptions() { let enabled = !prefs.bool(forKey:"captions"); prefs.set(enabled,forKey:"captions"); script("window.turntablerNative?.setCaptions(\(enabled))") }
    @objc func changeVolume() { prefs.set(volume.doubleValue,forKey:"volume"); script("window.turntablerNative?.setVolume(\(volume.doubleValue))") }
    @objc func loadAddress() { do { load(try youtubeURL(address.stringValue)) } catch { notice.stringValue = error.localizedDescription } }
    func load(_ url: URL) { address.stringValue = url.absoluteString; prefs.set(url.absoluteString,forKey:"url"); web.load(URLRequest(url:url)); notice.stringValue = "YouTube를 불러오는 중…" }
    @objc func openBrowser() {
        if pageOpen { showWidget(); return }
        settings?.close(); widgetFrame = window.frame; pageOpen = true; web.interactive = true
        deck.isHidden = true; browserPanel.isHidden = false
        window.styleMask = [.borderless,.resizable]; window.setContentSize(NSSize(width:1100,height:760)); window.center()
        browserPanel.frame = root.bounds; web.removeFromSuperview(); web.frame = NSRect(x:1,y:43,width:root.bounds.width-2,height:root.bounds.height-44); browserPanel.addSubview(web)
        web.alphaValue = 1; script("window.turntablerNative?.setWidgetMode(false)")
        if web.url == nil { home() }; showWidget(); window.makeFirstResponder(web)
    }
    @objc func closeBrowser() {
        guard pageOpen else { return }; pageOpen = false; web.interactive = false
        web.removeFromSuperview(); web.frame = viewport.bounds; viewport.addSubview(web)
        browserPanel.isHidden = true; deck.isHidden = false; window.styleMask = [.borderless]; window.setFrame(widgetFrame,display:true)
        script("window.turntablerNative?.setWidgetMode(true)")
    }
    @objc func home() { web.load(URLRequest(url:URL(string:"https://www.youtube.com/")!)) }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window && !quitting { if pageOpen { closeBrowser() } else { window.orderOut(nil) }; return false }; return true
    }
    func windowDidResize(_ notification: Notification) {
        guard pageOpen else { return }; browserPanel.frame = root.bounds; web.frame = NSRect(x:1,y:43,width:root.bounds.width-2,height:root.bounds.height-44)
    }
    @objc func showPlaylist(_ sender: NSButton) {
        let menu = NSMenu()
        for track in tracks { let item = NSMenuItem(title:(track["number"] as? String ?? "") + "  " + (track["title"] as? String ?? ""),action:#selector(selectTrack),keyEquivalent:""); item.target = self; item.representedObject = track["url"]; item.state = (track["selected"] as? Bool == true) ? .on : .off; menu.addItem(item) }
        if menu.items.isEmpty { menu.addItem(withTitle:"재생목록이 없습니다",action:nil,keyEquivalent:"") }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:sender.bounds.height),in:sender)
    }
    @objc func selectTrack(_ sender: NSMenuItem) { if let text = sender.representedObject as? String, let url = try? youtubeURL(text) { load(url) } }
    @objc func openSettings() {
        if let settings, settings.isVisible { settings.makeKeyAndOrderFront(nil); return }
        let panel = NSWindow(contentRect:NSRect(x:0,y:0,width:340,height:425),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title = "TurnTabler 설정"; panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named:.darkAqua)
        let content = FlippedView(frame:panel.contentView!.bounds); panel.contentView = content
        _ = label("영상 불투명도",NSRect(x:22,y:20,width:270,height:20),in:content)
        let opacity = NSSlider(value:prefs.double(forKey:"opacity"),minValue:0,maxValue:1,target:self,action:#selector(changeOpacity)); opacity.frame = NSRect(x:22,y:48,width:292,height:24); content.addSubview(opacity)
        for (index,key,title) in [(0,"pin","항상 위에 표시"),(1,"rotation","레코드 천천히 회전")] {
            let check = NSButton(checkboxWithTitle:title,target:self,action:#selector(changeOption)); check.identifier = NSUserInterfaceItemIdentifier(key); check.state = prefs.bool(forKey:key) ? .on : .off; check.frame = NSRect(x:22,y:CGFloat(85+index*30),width:290,height:24); content.addSubview(check)
        }
        _ = label("소리 출력 장치",NSRect(x:22,y:159,width:290,height:20),in:content)
        let popup = NSPopUpButton(frame:NSRect(x:22,y:183,width:292,height:27)); popup.target = self; popup.action = #selector(selectOutput); popup.addItem(withTitle:"시스템 기본 장치"); content.addSubview(popup); outputs = popup
        button("출력 장치 목록 허용", "WebKit 출력 장치 권한", NSRect(x:22,y:217,width:292,height:27), #selector(allowOutputs), in:content)
        outputStatus = label("WebKit은 장치 목록을 위해 마이크 권한이 필요합니다. 허용 시 마이크 트랙을 즉시 닫으며 녹음하지 않습니다.",NSRect(x:22,y:253,width:292,height:49),in:content)
        button("YouTube 브라우저 열기", "브라우저", NSRect(x:22,y:312,width:292,height:28), #selector(openBrowser), in:content)
        button("오른쪽 아래로 정렬", "위젯 정렬", NSRect(x:22,y:349,width:180,height:28), #selector(dock), in:content)
        button("종료", "TurnTabler 종료", NSRect(x:236,y:349,width:78,height:28), #selector(quit), in:content)
        settings = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
        script("window.turntablerNative?.listAudioOutputs()")
    }
    @objc func changeOpacity(_ sender: NSSlider) { prefs.set(sender.doubleValue,forKey:"opacity"); viewport.alphaValue = sender.doubleValue }
    @objc func changeOption(_ sender: NSButton) { prefs.set(sender.state == .on,forKey:sender.identifier!.rawValue); applyPin() }
    @objc func selectOutput(_ sender: NSPopUpButton) { let index = sender.indexOfSelectedItem; if deviceIds.indices.contains(index) { script("window.turntablerNative?.setAudioOutput(\(jsonString(deviceIds[index])))") } }
    @objc func allowOutputs() {
        guard web.url?.host == "www.youtube.com" else { outputStatus?.stringValue = "먼저 YouTube 영상이나 브라우저를 열어 주세요."; return }
        allowDeviceRequest = true
        script("navigator.mediaDevices.getUserMedia({audio:true}).then(s=>{s.getTracks().forEach(t=>t.stop());window.turntablerNative.listAudioOutputs()}).catch(e=>window.webkit.messageHandlers.turntabler.postMessage({type:'audio-error',message:e.message}))")
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == "www.youtube.com", let state = message.body as? [String:Any], let type = state["type"] as? String else { return }
        if type == "state" {
            playing = state["playing"] as? Bool == true; playButton.title = playing ? "Ⅱ" : "▶"; nextButton.isEnabled = state["hasNext"] as? Bool == true
            tracks = state["tracks"] as? [[String:Any]] ?? []; captionsButton.contentTintColor = prefs.bool(forKey:"captions") ? .white : .lightGray
            notice.stringValue = state["error"] as? String ?? ""
            if let url = state["url"] as? String, url != lastSavedURL, let valid = try? youtubeURL(url) { lastSavedURL = url; prefs.set(valid.absoluteString,forKey:"url") }
        } else if type == "notice" || type == "audio-error" { notice.stringValue = state["message"] as? String ?? ""; outputStatus?.stringValue = notice.stringValue; allowDeviceRequest = false }
        else if type == "audio-devices" {
            allowDeviceRequest = false; let devices = state["devices"] as? [[String:String]] ?? []
            deviceIds = [""]; outputs?.removeAllItems(); outputs?.addItem(withTitle:"시스템 기본 장치")
            for device in devices { guard let id = device["id"], !id.isEmpty, id != "default", id != "communications", !deviceIds.contains(id) else { continue }; deviceIds.append(id); outputs?.addItem(withTitle:device["name"] ?? "오디오 출력 장치") }
            if let index = deviceIds.firstIndex(of:prefs.string(forKey:"output") ?? "") { outputs?.selectItem(at:index) }
        } else if type == "audio-output", state["ok"] as? Bool == true { prefs.set(state["deviceId"] as? String ?? "",forKey:"output"); outputStatus?.stringValue = state["fallback"] as? Bool == true ? "연결이 끊겨 기본 장치로 전환했습니다." : "TurnTabler 소리에만 적용됩니다." }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        script("window.turntablerNative?.setWidgetMode(\(!pageOpen));window.turntablerNative?.setVolume(\(smoke ? 0 : volume.doubleValue));window.turntablerNative?.setCaptions(\(prefs.bool(forKey:"captions")));window.turntablerNative?.setAudioOutput(\(jsonString(prefs.string(forKey:"output") ?? "")))")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if smoke && url.scheme == "about" { decisionHandler(.allow); return }
        let allowed = url.scheme == "https" && ["www.youtube.com","accounts.google.com","consent.youtube.com","consent.google.com"].contains(url.host ?? "")
        decisionHandler(allowed ? .allow : .cancel)
        if !allowed && navigationAction.navigationType == .linkActivated && url.scheme == "https" { NSWorkspace.shared.open(url) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { if let url = navigationAction.request.url, url.scheme == "https" { web.load(URLRequest(url:url)) }; return nil }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(allowDeviceRequest && origin.host == "www.youtube.com" && type == .microphone ? .prompt : .deny) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { notice.stringValue = error.localizedDescription }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { notice.stringValue = "재생 엔진이 종료되었습니다. 링크를 다시 실행해 주세요." }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let text = url.scheme == "turntabler" ? URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name == "url"})?.value : url.absoluteString
            if let text, let valid = try? youtubeURL(text) { if web == nil { pendingURL = valid } else { load(valid); showWidget() } }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); if !pageOpen { window.saveFrame(usingName:"TurnTabler widget") } }
    func runSmoke() {
        web.loadHTMLString("<html><body><button id='probe' onclick='window.clicked=true'>Probe</button><input id='typing'></body></html>",baseURL:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+3) {
            self.openBrowser()
            self.web.evaluateJavaScript("document.querySelector('#probe').click(); document.querySelector('#typing').value='abc'; window.clicked && document.querySelector('#typing').value==='abc'") { value,error in
                let success = error == nil && value as? Bool == true
                self.closeBrowser(); self.openBrowser(); self.closeBrowser()
                let data: [String:Any] = ["success":success,"webkitDocument":success,"browserRoundTrip":!self.pageOpen && self.web.superview === self.viewport,"persistentStoreConfigured":true,"hardwareAudioAndYouTubeLoginTested":false]
                let output = ProcessInfo.processInfo.environment["TURNTABLER_ARTIFACTS"] ?? NSTemporaryDirectory()
                try? FileManager.default.createDirectory(atPath:output,withIntermediateDirectories:true)
                try? JSONSerialization.data(withJSONObject:data,options:.prettyPrinted).write(to:URL(fileURLWithPath:output).appendingPathComponent("mac-smoke.json"))
                exit(success ? 0 : 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+25) { exit(2) }
    }
}

@main struct TurnTablerMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") { do { try addressSelfTest(); print("PASS: macOS URL normalization and rejection"); exit(0) } catch { exit(1) } }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
