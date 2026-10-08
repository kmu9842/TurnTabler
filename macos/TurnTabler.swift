import AppKit
import WebKit
import QuartzCore
import CoreImage

final class PlayerWebView: WKWebView {
    var interactive = false
    override func hitTest(_ point: NSPoint) -> NSView? { interactive ? super.hitTest(point) : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let prefs: UserDefaults
    let smoke = CommandLine.arguments.contains("--smoke")
    let widgetSize = NSSize(width: 460, height: 390)
    let playbackSize = NSSize(width: 960, height: 540)
    var window: WidgetNSWindow!
    let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 460, height: 390))
    let deck = FlippedView(frame: NSRect(x: 0, y: 0, width: 460, height: 390))
    let browserPanel = FlippedView()
    let viewport = FlippedView(frame: NSRect(x: 70.6, y: 17.9, width: 259.2, height: 259.2))
    let videoContainer = FlippedView(frame: NSRect(x: 0, y: 0, width: 259.2, height: 259.2))
    let film = FilmView(frame: NSRect(x: 0, y: 0, width: 259.2, height: 259.2))
    let ambient = FlippedView(frame: NSRect(x: 10, y: 8, width: 440, height: 293.333))
    let ambientLayers = [CALayer(), CALayer()]
    let imageContext = CIContext()
    let transport = GlassPanel(frame: NSRect(x: 30, y: 299, width: 400, height: 34))
    var web: PlayerWebView!
    var bridge = ""
    var statusItem: NSStatusItem!
    var settings: NSWindow?
    var playlistPanel: NSPanel?
    var browserPopups: [ObjectIdentifier: BrowserPopupController] = [:]
    var browserHomeButton: NSButton!
    var browserReloadButton: NSButton!
    var browserCloseButton: NSButton!
    var browserStatus: NSTextField!
    var outputs: NSPopUpButton?
    var outputStatus: NSTextField?
    var opacityValue: NSTextField?
    var lightValue: NSTextField?
    var volume: NSSlider!
    var address: NSTextField!
    var notice: NSTextField!
    var playButton: NSButton!
    var previousButton: NSButton!
    var nextButton: NSButton!
    var playlistButton: NSButton!
    var captionsButton: NSButton!
    var captionsMark = FlippedView()
    var record: RotatingArtworkView!
    var grooves: RotatingArtworkView!
    var tracks: [[String: Any]] = []
    var audioDevices: [(id: String, name: String)] = [("", "시스템 기본 장치")]
    var audioMessage = "출력 장치 목록을 허용하면 스피커·헤드폰을 선택할 수 있습니다."
    var pageOpen = false, playing = false, videoAvailable = false, quitting = false
    var allowDeviceRequest = false, sampling = false, navigatingBack = false
    var widgetFrame = NSRect.zero
    var timer: Timer?
    var visualTimer: Timer?
    var rotation = 0.0, previousFrame = 0.0
    var ambientIndex = 0
    var pendingURL: URL?
    var currentVideoID = "", currentVideoURL: URL?
    var previousVideos: [URL] = []
    var lastSavedURL = ""

    override init() {
        // Smoke runs must not overwrite the user's settings or saved window position.
        prefs = CommandLine.arguments.contains("--smoke") ? UserDefaults(suiteName: "com.turntabler.smoke.\(UUID().uuidString)")! : .standard
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs.register(defaults: ["volume":65.0, "opacity":0.58, "pin":true, "rotation":true,
                                  "captions":false, "size":1, "output":"", "effect":true, "ambient":true, "light":75.0])
        for (key, range, fallback) in [("volume", 0.0...100.0, 65.0), ("opacity", 0.0...1.0, 0.58), ("light", 0.0...100.0, 75.0)] {
            let value = prefs.double(forKey: key)
            prefs.set(value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback, forKey: key)
        }
        prefs.set(min(2, max(0, prefs.integer(forKey: "size"))), forKey: "size")
        guard let bridgeURL = Bundle.main.url(forResource: "YouTubeBridge", withExtension: "js"),
              let source = try? String(contentsOf: bridgeURL, encoding: .utf8) else {
            let alert = NSAlert(); alert.messageText = "재생 스크립트를 찾을 수 없습니다."; alert.runModal(); NSApp.terminate(nil); return
        }
        bridge = source
        let config = WKWebViewConfiguration()
        config.websiteDataStore = smoke ? .nonPersistent() : .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.userContentController.add(self, name: "turntabler")
        web = PlayerWebView(frame: NSRect(origin: .zero, size: playbackSize), configuration: config)
        web.navigationDelegate = self; web.uiDelegate = self; web.underPageBackgroundColor = .black
        refreshBootstrap()
        window = WidgetNSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "TurnTabler"; window.isOpaque = false; window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.hasShadow = false; window.isReleasedWhenClosed = false; window.delegate = self
        window.dismissPanels = { [weak self] in self?.settings?.close(); self?.playlistPanel?.close() }
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        root.autoresizingMask = [.width, .height]; window.contentView = root; root.addSubview(deck)
        buildDeck(); buildBrowser(); makeMenu(); applyOptions()
        var restored = false
        if let saved = prefs.string(forKey: "widgetFrame") { window.setFrame(NSRectFromString(saved), display: false); restored = true }
        else if !smoke { restored = window.setFrameUsingName("TurnTabler widget") }
        applySize()
        if !restored { dock() }
        clampWindow(); window.makeKeyAndOrderFront(nil)
        previousFrame = ProcessInfo.processInfo.systemUptime
        timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.animate() }
        RunLoop.main.add(timer!, forMode: .common)
        visualTimer = Timer(timeInterval: 0.32, repeats: true) { [weak self] _ in self?.reflectVideo() }
        RunLoop.main.add(visualTimer!, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if smoke { runSmoke() }
        else if let url = pendingURL { load(url); pendingURL = nil }
        else if let value = CommandLine.arguments.dropFirst().first(where: { $0.hasPrefix("https://") }), let url = try? youtubeURL(value) { load(url) }
    }

    func refreshBootstrap() {
        let bootstrap = "window.__turntablerInitialVolume=\(smoke ? 0 : prefs.double(forKey: "volume"));window.__turntablerInitialCaptions=\(prefs.bool(forKey: "captions"));window.__turntablerInitialOutputDevice=\(jsonString(prefs.string(forKey: "output") ?? ""));window.__turntablerInitialWidgetMode=\(!pageOpen);window.__turntablerAllowNativeSkipInput=false;"
        let controller = web.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: bootstrap + bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    func image(_ name: String, _ frame: NSRect, in parent: NSView) -> PassiveImage {
        let view = PassiveImage(frame: frame)
        if let url = Bundle.main.url(forResource: name, withExtension: "png") { view.image = NSImage(contentsOf: url) }
        view.imageScaling = .scaleAxesIndependently; parent.addSubview(view); return view
    }
    func rotatingImage(_ name: String, _ frame: NSRect, in parent: NSView) -> RotatingArtworkView {
        let view = RotatingArtworkView(frame: frame)
        if let url = Bundle.main.url(forResource: name, withExtension: "png") { view.image = NSImage(contentsOf: url) }
        view.wantsLayer = true
        parent.addSubview(view)
        return view
    }
    @discardableResult func button(_ title: String, _ hint: String, _ frame: NSRect, _ action: Selector, in parent: NSView) -> NSButton {
        let value = NSButton(title: title, target: self, action: action)
        value.frame = frame; value.isBordered = false; value.font = .systemFont(ofSize: 13); value.contentTintColor = .white
        value.toolTip = hint; value.setAccessibilityLabel(hint); parent.addSubview(value); return value
    }
    @discardableResult func label(_ text: String, _ frame: NSRect, in parent: NSView) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text); value.frame = frame
        value.font = .systemFont(ofSize: 11); value.textColor = .white.withAlphaComponent(0.85); parent.addSubview(value); return value
    }
    func slider(_ value: Double, max maximum: Double, frame: NSRect, action: Selector, in parent: NSView) -> NSSlider {
        let slider = NSSlider(frame: frame); slider.cell = GlassSliderCell()
        slider.minValue = 0; slider.maxValue = maximum; slider.doubleValue = value
        slider.target = self; slider.action = action; slider.isContinuous = true; parent.addSubview(slider); return slider
    }

    func buildDeck() {
        deck.drag = { [weak self] event in
            guard let self else { return }
            let point = self.deck.convert(event.locationInWindow, from: nil)
            if hypot(point.x - 200.2, point.y - 147.5) < 129.6 { self.toggle() }
            else { self.window.performDrag(with: event); self.saveWidgetFrame() }
        }
        viewport.drag = deck.drag; videoContainer.drag = deck.drag; ambient.drag = deck.drag
        buildAmbient(); deck.addSubview(ambient)
        let discFrame = NSRect(x:67.6,y:14.9,width:265.2,height:265.2)
        record = rotatingImage("record", discFrame, in: deck)
        record.drawsDisc = true
        viewport.wantsLayer = true; viewport.layer?.cornerRadius = 129.6; viewport.layer?.masksToBounds = true
        viewport.layer?.mask = radialMask(size: viewport.bounds.size, locations: [0, 0.75, 0.93, 1], opacities: [1, 1, 0.94, 0])
        deck.addSubview(viewport); viewport.addSubview(videoContainer)
        // Match Windows' 960×540 player, scaled to 460.8×259.2 and cropped at the disc center.
        videoContainer.bounds = NSRect(x: 0, y: 0, width: 540, height: 540)
        attachWidgetPlayer(); viewport.addSubview(film)
        grooves = RotatingArtworkView(frame: discFrame); grooves.wantsLayer = true
        grooves.drawsGroove = true; deck.addSubview(grooves)
        let highlights = image("highlights", discFrame, in: deck); highlights.alphaValue = 0.55
        _ = image("body", NSRect(x:10,y:8,width:440,height:293.333), in: deck)
        let arm = rotatingImage("tonearm", NSRect(x:10,y:8,width:440,height:293.333), in: deck)
        arm.pivot = NSPoint(x:368.671875,y:100.546875)
        arm.rotationRadians = 3 * .pi / 180
        let browser = button("", "YouTube 브라우저 열기 · 로그인", NSRect(x:389.5,y:153,width:25,height:24), #selector(openBrowser), in: deck)
        browser.image = NSImage(systemSymbolName:"macwindow", accessibilityDescription:"브라우저")
        let gear = button("", "설정", NSRect(x:389.5,y:179,width:25,height:24), #selector(openSettings), in: deck)
        gear.image = NSImage(systemSymbolName:"gearshape", accessibilityDescription:"설정")
        let cc = GlassPanel(frame: NSRect(x:387,y:213,width:30,height:19)); cc.radius = 5; deck.addSubview(cc)
        captionsButton = button("CC", "자막 켜기 / 끄기", cc.bounds, #selector(toggleCaptions), in: cc)
        captionsButton.font = .systemFont(ofSize:9, weight:.semibold)
        captionsMark.frame = NSRect(x:9.5,y:16,width:11,height:1); captionsMark.wantsLayer = true; captionsMark.layer?.backgroundColor = NSColor.white.cgColor; cc.addSubview(captionsMark)
        let housing = GlassPanel(frame:NSRect(x:317,y:239,width:108,height:25)); housing.radius = 7; deck.addSubview(housing)
        let speaker = NSImageView(frame:NSRect(x:7,y:6,width:12,height:12)); speaker.image = NSImage(systemSymbolName:"speaker.wave.1",accessibilityDescription:"음량"); speaker.contentTintColor = .white; housing.addSubview(speaker)
        volume = slider(smoke ? 0 : prefs.double(forKey:"volume"), max:100, frame:NSRect(x:21,y:2,width:81,height:22), action:#selector(changeVolume), in:housing)
        volume.toolTip = "음량"; volume.setAccessibilityLabel("음량")
        deck.addSubview(transport)
        previousButton = button("‹", "이전 곡", NSRect(x:5,y:3,width:26,height:28), #selector(previous), in:transport)
        playButton = button("▶", "재생 / 일시정지", NSRect(x:31,y:3,width:28,height:28), #selector(toggle), in:transport)
        nextButton = button("›", "다음 곡", NSRect(x:59,y:3,width:26,height:28), #selector(next), in:transport)
        previousButton.isEnabled = false; nextButton.isEnabled = false
        address = NSTextField(frame:NSRect(x:94,y:7,width:245,height:21)); address.placeholderString = "YouTube 링크 붙여넣기"
        address.font = .systemFont(ofSize:10.5); address.isBordered = false; address.drawsBackground = false; address.textColor = .white
        address.target = self; address.action = #selector(loadAddress); address.stringValue = prefs.string(forKey:"url") ?? ""
        address.setAccessibilityLabel("YouTube 링크"); transport.addSubview(address)
        button("↵", "링크 재생", NSRect(x:340,y:3,width:26,height:28), #selector(loadAddress), in:transport)
        playlistButton = button("≡", "재생목록", NSRect(x:367,y:3,width:27,height:28), #selector(showPlaylist), in:transport)
        playlistButton.isEnabled = false
        notice = label("", NSRect(x:40,y:337,width:380,height:45), in:deck); notice.alignment = .center
        updatePlaybackAppearance()
    }

    func attachWidgetPlayer() {
        web.removeFromSuperview(); web.autoresizingMask = []
        web.frame = NSRect(x: -210, y: 0, width: playbackSize.width, height: playbackSize.height)
        videoContainer.addSubview(web)
    }
    func buildBrowser() {
        browserPanel.wantsLayer = true; browserPanel.layer?.backgroundColor = NSColor(calibratedWhite:0.09,alpha:1).cgColor
        browserPanel.isHidden = true; browserPanel.autoresizingMask = [.width,.height]; root.addSubview(browserPanel)
        browserPanel.drag = { [weak self] event in self?.window.performDrag(with:event) }
        button("‹ 위젯으로 돌아가기", "위젯으로 돌아가기", NSRect(x:12,y:7,width:155,height:28), #selector(closeBrowser), in:browserPanel)
        browserStatus = label("YouTube · TurnTabler", NSRect(x:180,y:13,width:140,height:20), in:browserPanel)
        browserStatus.lineBreakMode = .byTruncatingMiddle
        browserHomeButton = button("홈", "YouTube 홈", NSRect(x:180,y:7,width:40,height:28), #selector(home), in:browserPanel)
        browserReloadButton = button("↻", "페이지 새로고침", NSRect(x:225,y:7,width:32,height:28), #selector(reloadBrowser), in:browserPanel)
        browserCloseButton = button("×", "브라우저 닫기", NSRect(x:265,y:7,width:32,height:28), #selector(closeBrowser), in:browserPanel)
    }
    func makeMenu() {
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appMenu.addItem(appItem)
        let commands = NSMenu()
        for (title, action, key) in [("TurnTabler 표시", #selector(showWidget), "0"), ("설정…", #selector(openSettings), ","), ("숨기기", #selector(hideWidget), "h")] {
            commands.addItem(withTitle:title,action:action,keyEquivalent:key).target = self
        }
        commands.addItem(.separator()); commands.addItem(withTitle:"TurnTabler 종료",action:#selector(quit),keyEquivalent:"q").target = self
        appItem.submenu = commands
        let edit = NSMenu(title:"편집")
        for (name,key,action) in [("실행 취소","z","undo:"),("오려두기","x","cut:"),("복사","c","copy:"),("붙여넣기","v","paste:"),("전체 선택","a","selectAll:")] { edit.addItem(withTitle:name,action:NSSelectorFromString(action),keyEquivalent:key) }
        let editItem = NSMenuItem(title:"편집",action:nil,keyEquivalent:""); editItem.submenu = edit; appMenu.addItem(editItem); NSApp.mainMenu = appMenu
        let browserMenu = NSMenu(title:"브라우저")
        browserMenu.addItem(withTitle:"페이지 새로고침",action:#selector(reloadBrowser),keyEquivalent:"r").target = self
        let browserItem = NSMenuItem(title:"브라우저",action:nil,keyEquivalent:""); browserItem.submenu = browserMenu; appMenu.addItem(browserItem)
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName:"opticaldisc",accessibilityDescription:"TurnTabler")
        statusItem.menu = commands.copy() as? NSMenu
    }
    @objc func showWidget() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let popup = browserPopups.values.first { popup.show() }
        else { showWidget() }
        return false
    }
    @objc func hideWidget() { settings?.close(); playlistPanel?.close(); window.orderOut(nil) }
    @objc func quit() { quitting = true; NSApp.terminate(nil) }
    var workArea: NSRect { window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800) }
    @objc func dock() {
        let visible = workArea
        if pageOpen { widgetFrame.origin = NSPoint(x:visible.maxX-widgetFrame.width-16,y:visible.minY+16) }
        else { window.setFrameOrigin(NSPoint(x:visible.maxX-window.frame.width-16,y:visible.minY+16)); clampWindow() }
        saveWidgetFrame()
    }
    func clampWindow() {
        let area = workArea, frame = window.frame
        window.setFrameOrigin(NSPoint(x:min(max(frame.minX,area.minX),max(area.minX,area.maxX-frame.width)), y:min(max(frame.minY,area.minY),max(area.minY,area.maxY-frame.height))))
    }
    @objc func screenChanged() { clampWindow(); saveWidgetFrame() }
    func saveWidgetFrame() { if !smoke { prefs.set(NSStringFromRect(pageOpen ? widgetFrame : window.frame), forKey:"widgetFrame") } }
    func applySize() {
        let scale = [0.8, 1.0, 1.2][prefs.integer(forKey:"size")]
        let size = NSSize(width:widgetSize.width*scale,height:widgetSize.height*scale)
        deck.frame = NSRect(origin:.zero,size:size); deck.bounds = NSRect(origin:.zero,size:widgetSize)
        if pageOpen { widgetFrame.size = size }
        else { window.setContentSize(size); clampWindow() }
    }
    func applyOptions() {
        window.level = prefs.bool(forKey:"pin") ? .floating : .normal; settings?.level = window.level
        film.isHidden = !prefs.bool(forKey:"effect")
        ambient.isHidden = !prefs.bool(forKey:"ambient"); ambient.alphaValue = prefs.double(forKey:"light") / 100
        updatePlaybackAppearance()
    }
    func updatePlaybackAppearance() {
        videoContainer.alphaValue = videoAvailable ? prefs.double(forKey:"opacity") : 0
        film.isHidden = !videoAvailable || !prefs.bool(forKey:"effect")
        playButton?.title = playing ? "Ⅱ" : "▶"; transport.alphaValue = playing ? 0.1 : 1
        captionsButton?.contentTintColor = prefs.bool(forKey:"captions") ? .white : .lightGray
        captionsMark.isHidden = !prefs.bool(forKey:"captions")
    }
    func script(_ source: String) { web.evaluateJavaScript(source) { _, _ in } }
    @objc func toggle() {
        if web.url == nil || (!videoAvailable && !web.isLoading && currentVideoID.isEmpty) { if !address.stringValue.isEmpty { loadAddress() }; return }
        script("window.turntablerNative?.toggle()")
    }
    @objc func next() { script("window.turntablerNative?.next()") }
    @objc func previous() {
        if let url = previousVideos.popLast() { navigatingBack = true; load(url, fromHistory:true) }
        else { script("window.turntablerNative?.previous()") }
    }
    @objc func toggleCaptions() {
        let enabled = !prefs.bool(forKey:"captions"); prefs.set(enabled,forKey:"captions"); refreshBootstrap(); updatePlaybackAppearance()
        script("window.turntablerNative?.setCaptions(\(enabled))")
    }
    @objc func changeVolume() { prefs.set(volume.doubleValue,forKey:"volume"); refreshBootstrap(); script("window.turntablerNative?.setVolume(\(volume.doubleValue))") }
    @objc func loadAddress() { do { load(try youtubeURL(address.stringValue)) } catch { notice.stringValue = error.localizedDescription } }
    func resetPlayback() {
        playing = false; videoAvailable = false; updatePlaybackAppearance()
        previousButton.isEnabled = !previousVideos.isEmpty; nextButton.isEnabled = false; playlistButton.isEnabled = false
        tracks = []; ambientLayers.forEach { $0.contents = nil }
    }
    func load(_ url: URL, fromHistory: Bool = false) {
        if !fromHistory { navigatingBack = false }
        resetPlayback(); settings?.close(); playlistPanel?.close()
        address.stringValue = url.absoluteString; prefs.set(url.absoluteString,forKey:"url")
        refreshBootstrap(); web.load(URLRequest(url:url)); notice.stringValue = "YouTube를 불러오는 중…"
    }
    @objc func openBrowser() { showBrowser(loadHomeIfEmpty: true) }
    func showBrowser(loadHomeIfEmpty: Bool) {
        if pageOpen { showWidget(); return }
        settings?.close(); playlistPanel?.close(); saveWidgetFrame(); widgetFrame = window.frame
        pageOpen = true; web.interactive = true; refreshBootstrap()
        deck.isHidden = true; browserPanel.isHidden = false
        let area = workArea
        window.styleMask = [.borderless,.resizable]; window.minSize = NSSize(width:min(640,area.width),height:min(420,area.height))
        window.setFrame(NSRect(x:area.midX-min(1100,area.width-24)/2,y:area.midY-min(760,area.height-24)/2,width:min(1100,area.width-24),height:min(760,area.height-24)),display:true)
        browserPanel.frame = root.bounds; web.removeFromSuperview(); browserPanel.addSubview(web); layoutBrowser()
        script("window.turntablerNative?.setWidgetMode(false)")
        if loadHomeIfEmpty && web.url == nil { home() }; showWidget(); window.makeFirstResponder(web)
    }
    @objc func closeBrowser() {
        guard pageOpen else { return }
        pageOpen = false; web.interactive = false; refreshBootstrap(); window.makeFirstResponder(nil)
        browserPanel.isHidden = true; deck.isHidden = false; window.minSize = .zero; window.styleMask = [.borderless]
        window.setFrame(widgetFrame,display:true); applySize(); attachWidgetPlayer(); clampWindow(); saveWidgetFrame()
        script("window.turntablerNative?.setWidgetMode(true)")
    }
    func layoutBrowser() {
        browserPanel.frame = root.bounds
        web.frame = NSRect(x:1,y:43,width:max(1,root.bounds.width-2),height:max(1,root.bounds.height-44))
        browserHomeButton.setFrameOrigin(NSPoint(x:root.bounds.width-132,y:7))
        browserReloadButton.setFrameOrigin(NSPoint(x:root.bounds.width-84,y:7))
        browserCloseButton.setFrameOrigin(NSPoint(x:root.bounds.width-44,y:7))
        browserStatus.frame = NSRect(x:180,y:13,width:max(0,root.bounds.width-328),height:20)
    }
    @objc func home() { refreshBootstrap(); web.load(URLRequest(url:URL(string:"https://www.youtube.com/")!)) }
    @objc func reloadBrowser() {
        if let popup = browserPopups.values.first(where: { $0.window?.isKeyWindow == true }) { popup.webView.reload(); return }
        refreshBootstrap()
        if web.url == nil { home() } else { web.reload() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window && !quitting { if pageOpen { closeBrowser() } else { hideWidget() }; return false }; return true
    }
    func windowDidResize(_ notification: Notification) { if pageOpen { layoutBrowser() } }
    func windowDidMove(_ notification: Notification) { if (notification.object as? NSWindow) === window { saveWidgetFrame() } }

    @objc func showPlaylist() {
        if let panel = playlistPanel, panel.isVisible { panel.close(); return }
        guard !tracks.isEmpty else { return }
        settings?.close()
        let rect = window.convertToScreen(deck.convert(NSRect(x:42,y:71,width:376,height:204),to:nil))
        let panel = NSPanel(contentRect:rect,styleMask:[.borderless],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.appearance = window.appearance; panel.hasShadow = true
        let content = FlippedView(frame:NSRect(x:0,y:0,width:rect.width,height:rect.height)); content.bounds = NSRect(x:0,y:0,width:376,height:204)
        content.wantsLayer = true; content.layer?.backgroundColor = NSColor(calibratedWhite:0.1,alpha:0.97).cgColor
        content.layer?.cornerRadius = 12; content.layer?.borderWidth = 0.8; content.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        panel.contentView = content
        label("재생목록 · \(tracks.count)",NSRect(x:12,y:14,width:300,height:20),in:content)
        button("×","재생목록 닫기",NSRect(x:338,y:8,width:26,height:28),#selector(closePlaylist),in:content)
        let scroll = NSScrollView(frame:NSRect(x:12,y:44,width:352,height:148)); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let rows = FlippedView(frame:NSRect(x:0,y:0,width:340,height:max(148,CGFloat(tracks.count)*32)))
        var selectedRect: NSRect?
        for (index,track) in tracks.enumerated() {
            let title = (track["number"] as? String ?? "\(index+1)") + "    " + (track["title"] as? String ?? "")
            let row = button(title,title,NSRect(x:0,y:CGFloat(index)*32,width:338,height:31),#selector(selectTrack),in:rows)
            row.identifier = NSUserInterfaceItemIdentifier(track["url"] as? String ?? ""); row.alignment = .left; row.font = .systemFont(ofSize:11)
            row.lineBreakMode = .byTruncatingTail
            if track["selected"] as? Bool == true {
                row.wantsLayer = true; row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor; row.layer?.cornerRadius = 5
                selectedRect = row.frame
            }
        }
        scroll.documentView = rows; content.addSubview(scroll)
        playlistPanel = panel; window.addChildWindow(panel,ordered:.above); panel.orderFront(nil)
        if let selectedRect { rows.scrollToVisible(selectedRect) }
    }
    @objc func closePlaylist() { playlistPanel?.close() }
    @objc func selectTrack(_ sender: NSButton) {
        guard let text = sender.identifier?.rawValue, let url = try? youtubeURL(text) else { return }
        load(url)
    }

    @objc func openSettings() {
        if let settings, settings.isVisible { settings.makeKeyAndOrderFront(nil); return }
        playlistPanel?.close()
        let panel = NSWindow(contentRect:NSRect(x:0,y:0,width:340,height:min(640,workArea.height-64)),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title = "TurnTabler 설정"; panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named:.darkAqua)
        panel.backgroundColor = NSColor(calibratedWhite:0.11,alpha:1); panel.level = window.level
        let scroll = NSScrollView(frame:panel.contentView!.bounds); scroll.autoresizingMask = [.width,.height]
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let content = FlippedView(frame:NSRect(x:0,y:0,width:320,height:650)); scroll.documentView = content; panel.contentView?.addSubview(scroll)
        label("영상 불투명도",NSRect(x:22,y:18,width:210,height:20),in:content)
        opacityValue = label("\(Int((prefs.double(forKey:"opacity")*100).rounded()))%",NSRect(x:258,y:18,width:45,height:20),in:content)
        let opacity = slider(prefs.double(forKey:"opacity")*100,max:100,frame:NSRect(x:22,y:44,width:276,height:24),action:#selector(changeOpacity),in:content)
        opacity.setAccessibilityLabel("영상 불투명도")
        for (index,key,title) in [(0,"pin","항상 위에 표시"),(1,"rotation","레코드 천천히 회전"),(2,"effect","프로젝터 효과"),(3,"ambient","영상 색 반사")] {
            let check = NSButton(checkboxWithTitle:title,target:self,action:#selector(changeOption)); check.identifier = NSUserInterfaceItemIdentifier(key)
            check.state = prefs.bool(forKey:key) ? .on : .off; check.frame = NSRect(x:22,y:CGFloat(86+index*30),width:276,height:24)
            check.contentTintColor = .white; content.addSubview(check)
        }
        label("빛 퍼짐",NSRect(x:22,y:220,width:200,height:20),in:content)
        lightValue = label("\(Int(prefs.double(forKey:"light")))%",NSRect(x:258,y:220,width:45,height:20),in:content)
        let light = slider(prefs.double(forKey:"light"),max:100,frame:NSRect(x:22,y:245,width:276,height:24),action:#selector(changeLight),in:content)
        light.setAccessibilityLabel("빛 퍼짐")
        label("크기",NSRect(x:22,y:289,width:60,height:20),in:content)
        let sizes = NSSegmentedControl(labels:["작게","보통","크게"],trackingMode:.selectOne,target:self,action:#selector(changeSize))
        sizes.frame = NSRect(x:100,y:283,width:198,height:29); sizes.selectedSegment = prefs.integer(forKey:"size"); content.addSubview(sizes)
        label("소리 출력 장치",NSRect(x:22,y:334,width:220,height:20),in:content)
        button("↻","출력 장치 새로고침",NSRect(x:266,y:327,width:32,height:28),#selector(refreshOutputs),in:content)
        let popup = NSPopUpButton(frame:NSRect(x:22,y:358,width:276,height:28)); popup.target = self; popup.action = #selector(selectOutput)
        popup.setAccessibilityLabel("소리 출력 장치"); content.addSubview(popup); outputs = popup
        outputStatus = label(audioMessage,NSRect(x:22,y:394,width:276,height:42),in:content)
        button("출력 장치 목록 허용","출력 장치 목록 허용",NSRect(x:22,y:440,width:276,height:27),#selector(allowOutputs),in:content)
        label("목록 조회에 필요한 마이크 권한만 요청하며, 마이크 트랙은 즉시 해제합니다.",NSRect(x:22,y:472,width:276,height:36),in:content)
        button("YouTube 브라우저 열기","브라우저",NSRect(x:22,y:523,width:276,height:30),#selector(openBrowser),in:content)
        button("오른쪽 아래로 정렬","위젯 정렬",NSRect(x:22,y:558,width:276,height:30),#selector(dock),in:content)
        button("숨기기","위젯 숨기기",NSRect(x:22,y:602,width:130,height:30),#selector(hideWidget),in:content)
        button("종료","TurnTabler 종료",NSRect(x:168,y:602,width:130,height:30),#selector(quit),in:content)
        settings = panel; updateAudioControls(); panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        refreshOutputs()
    }
    @objc func changeOpacity(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded(); prefs.set(value/100,forKey:"opacity"); opacityValue?.stringValue = "\(Int(value))%"; updatePlaybackAppearance()
    }
    @objc func changeLight(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded(); prefs.set(value,forKey:"light"); lightValue?.stringValue = "\(Int(value))%"; applyOptions()
    }
    @objc func changeSize(_ sender: NSSegmentedControl) { prefs.set(sender.selectedSegment,forKey:"size"); playlistPanel?.close(); applySize(); dock() }
    @objc func changeOption(_ sender: NSButton) { prefs.set(sender.state == .on,forKey:sender.identifier!.rawValue); applyOptions() }
    @objc func selectOutput(_ sender: NSPopUpButton) {
        guard audioDevices.indices.contains(sender.indexOfSelectedItem) else { return }
        audioMessage = "출력 장치를 적용하는 중…"; outputStatus?.stringValue = audioMessage
        script("window.turntablerNative?.setAudioOutput(\(jsonString(audioDevices[sender.indexOfSelectedItem].id)))")
    }
    func updateAudioControls() {
        outputs?.removeAllItems(); outputs?.addItems(withTitles:audioDevices.map { $0.name })
        outputs?.selectItem(at:audioDevices.firstIndex(where: { $0.id == prefs.string(forKey:"output") ?? "" }) ?? 0)
        outputStatus?.stringValue = audioMessage
    }
    @objc func refreshOutputs() {
        if web.url == nil { home() }
        else { script("window.turntablerNative?.listAudioOutputs()") }
    }
    @objc func allowOutputs() {
        guard web.url?.host == "www.youtube.com", !web.isLoading else { audioMessage = "YouTube를 불러온 뒤 다시 눌러 주세요."; refreshOutputs(); updateAudioControls(); return }
        allowDeviceRequest = true
        script("navigator.mediaDevices.getUserMedia({audio:true}).then(s=>{s.getTracks().forEach(t=>t.stop());window.turntablerNative.listAudioOutputs()}).catch(e=>window.webkit.messageHandlers.turntabler.postMessage({type:'audio-error',message:e.message}))")
    }

    func buildAmbient() {
        ambient.wantsLayer = true; ambient.layer?.masksToBounds = true
        let path = CGMutablePath()
        path.move(to:CGPoint(x:157,y:80)); path.addLine(to:CGPoint(x:1362,y:80)); path.addQuadCurve(to:CGPoint(x:1455,y:175),control:CGPoint(x:1455,y:80))
        path.addLine(to:CGPoint(x:1455,y:850)); path.addQuadCurve(to:CGPoint(x:1364,y:944),control:CGPoint(x:1455,y:944))
        path.addLine(to:CGPoint(x:158,y:944)); path.addQuadCurve(to:CGPoint(x:75,y:852),control:CGPoint(x:75,y:944))
        path.addLine(to:CGPoint(x:75,y:172)); path.addQuadCurve(to:CGPoint(x:157,y:80),control:CGPoint(x:75,y:80)); path.closeSubpath()
        var transform = CGAffineTransform(scaleX:440/1536,y:440/1536)
        let clip = CAShapeLayer(); clip.path = path.copy(using:&transform); ambient.layer?.mask = clip
        let content = CALayer(); content.frame = ambient.bounds
        let mask = radialMask(size:ambient.bounds.size,locations:[0,0.5,0.83,1],opacities:[1,1,0.81,0])
        mask.endPoint = CGPoint(x:1.19,y:1.2); content.mask = mask
        for layer in ambientLayers { layer.frame = ambient.bounds; layer.contentsGravity = .resize; layer.opacity = 0; content.addSublayer(layer) }
        ambient.layer?.addSublayer(content)
    }
    func animate() {
        let now = ProcessInfo.processInfo.systemUptime, elapsed = min(0.1,max(0,now-previousFrame)); previousFrame = now
        guard playing, prefs.bool(forKey:"rotation"), !pageOpen, window.isVisible else { return }
        rotation = (rotation + elapsed * 2 * .pi / 24).truncatingRemainder(dividingBy:2 * .pi)
        record.rotationRadians = CGFloat(rotation)
        grooves.rotationRadians = CGFloat(rotation)
    }
    func reflectVideo() {
        guard playing, videoAvailable, prefs.bool(forKey:"ambient"), !sampling, !pageOpen, window.isVisible, !quitting else { return }
        sampling = true
        let config = WKSnapshotConfiguration(); config.rect = web.bounds; config.snapshotWidth = 80; config.afterScreenUpdates = false
        web.takeSnapshot(with:config) { [weak self] image, _ in
            guard let self else { return }; defer { self.sampling = false }
            guard !self.pageOpen, self.videoAvailable, let cg = image?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return }
            let input = CIImage(cgImage:cg)
            let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:6]).cropped(to:input.extent)
            guard let result = self.imageContext.createCGImage(blurred,from:input.extent) else { return }
            let front = self.ambientLayers[self.ambientIndex], back = self.ambientLayers[1-self.ambientIndex]
            CATransaction.begin(); CATransaction.setDisableActions(true); front.contents = result; CATransaction.commit()
            CATransaction.begin(); CATransaction.setAnimationDuration(0.3); front.opacity = 1; back.opacity = 0; CATransaction.commit()
            self.ambientIndex = 1-self.ambientIndex
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === web, message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == "www.youtube.com",
              let state = message.body as? [String:Any], let type = state["type"] as? String else { return }
        // Never synthesize a mouse click for ads: by the time WebKit delivers it,
        // the ad may have ended and the same point toggles the content video.
        if type == "skip-input" { return }
        if type == "state" {
            playing = state["playing"] as? Bool == true; videoAvailable = state["hasVideo"] as? Bool == true
            updatePlaybackAppearance(); nextButton.isEnabled = state["hasNext"] as? Bool == true
            tracks = (state["tracks"] as? [[String:Any]] ?? []).filter { track in
                guard let text = track["url"] as? String else { return false }; return (try? youtubeURL(text)) != nil
            }
            playlistButton.isEnabled = !tracks.isEmpty
            let captionsAvailable = state["captionsAvailable"] as? Bool == true
            captionsButton.toolTip = captionsAvailable ? (prefs.bool(forKey:"captions") ? "자막 끄기" : "자막 켜기") : "이 영상은 자막을 제공하지 않습니다"
            let error = state["error"] as? String ?? ""
            if !error.isEmpty { notice.stringValue = String(error.prefix(180)) }
            else if videoAvailable { notice.stringValue = "" }
            else if state["needsPage"] as? Bool == true { notice.stringValue = "브라우저를 열어 로그인 또는 안내를 확인해 주세요." }
            if let text = state["url"] as? String, let valid = try? youtubeURL(text) {
                let id = state["videoId"] as? String ?? ""
                if videoAvailable, id.count == 11, id != currentVideoID {
                    if let currentVideoURL, !navigatingBack { previousVideos.append(currentVideoURL) }
                    if previousVideos.count > 200 { previousVideos.removeFirst() }
                    navigatingBack = false; currentVideoID = id; currentVideoURL = valid
                }
                if text != lastSavedURL { lastSavedURL = text; prefs.set(valid.absoluteString,forKey:"url") }
            }
            previousButton.isEnabled = !previousVideos.isEmpty || state["hasPrevious"] as? Bool == true
        } else if type == "notice" { notice.stringValue = state["message"] as? String ?? "" }
        else if type == "audio-error" {
            allowDeviceRequest = false; audioMessage = state["message"] as? String ?? "출력 장치를 변경하지 못했습니다."; updateAudioControls()
        } else if type == "audio-devices" {
            allowDeviceRequest = false; audioDevices = [("", "시스템 기본 장치")]
            for device in state["devices"] as? [[String:String]] ?? [] {
                guard let id = device["id"], !id.isEmpty, id != "default", id != "communications", !audioDevices.contains(where: { $0.id == id }) else { continue }
                audioDevices.append((id,device["name"] ?? "오디오 출력 장치"))
            }
            updateAudioControls()
        } else if type == "audio-output", state["ok"] as? Bool == true {
            prefs.set(state["deviceId"] as? String ?? "",forKey:"output"); refreshBootstrap()
            audioMessage = state["fallback"] as? Bool == true ? "연결이 끊겨 기본 장치로 전환했습니다." : "TurnTabler 소리에만 적용됩니다."
            updateAudioControls()
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === web else { browserPopups[ObjectIdentifier(webView)]?.updateLocation(); return }
        browserStatus.stringValue = "불러오는 중…"
        resetPlayback(); allowDeviceRequest = false; notice.stringValue = "YouTube를 불러오는 중…"
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === web else { browserPopups[ObjectIdentifier(webView)]?.updateLocation(); return }
        browserStatus.stringValue = webView.url?.host ?? "YouTube · TurnTabler"
        script("window.turntablerNative?.setWidgetMode(\(!pageOpen));window.turntablerNative?.setVolume(\(smoke ? 0 : volume.doubleValue));window.turntablerNative?.setCaptions(\(prefs.bool(forKey:"captions")));window.turntablerNative?.setAudioOutput(\(jsonString(prefs.string(forKey:"output") ?? "")));window.turntablerNative?.listAudioOutputs()")
        if webView.url?.host != "www.youtube.com" { notice.stringValue = "브라우저를 열어 로그인 또는 동의를 진행해 주세요." }
    }
    func isInternal(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        // Authentication finishes on accounts.youtube.com before returning to
        // www.youtube.com. Canceling that redirect leaves Google's UI waiting.
        return host == "youtube.com" || host.hasSuffix(".youtube.com") ||
            ["accounts.google.com", "consent.google.com", "myaccount.google.com", "www.google.com", "google.com",
             "accounts.google.co.kr", "consent.google.co.kr", "www.google.co.kr", "google.co.kr"].contains(host)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if smoke && url.scheme == "about" { decisionHandler(.allow); return }
        // YouTube and Google use cross-origin subframes for login and media. Only top-level navigation is restricted.
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if webView === web { refreshBootstrap() }
        let trustedBlank = url.absoluteString == "about:blank" &&
            (browserPopups[ObjectIdentifier(webView)] != nil || navigationAction.sourceFrame.request.url.map(isInternal) == true)
        if isInternal(url) || trustedBlank {
            if webView === web, isInternal(url), url.host != "www.youtube.com", !pageOpen {
                // Login/consent must be an interactive full page, never hidden in
                // the non-interactive circular player.
                showBrowser(loadHomeIfEmpty: false)
            }
            decisionHandler(.allow)
        }
        else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated && url.scheme == "https" { NSWorkspace.shared.open(url) }
            else if webView === web {
                notice.stringValue = "페이지 이동이 차단되었습니다. 브라우저의 새로고침으로 다시 시도해 주세요."
                browserStatus.stringValue = "이동 차단: \(url.host ?? url.scheme ?? "")"
            } else { browserPopups[ObjectIdentifier(webView)]?.window?.subtitle = "이동 차단: \(url.host ?? url.scheme ?? "")" }
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let trustedBlank = url.absoluteString == "about:blank" && navigationAction.sourceFrame.request.url.map(isInternal) == true
        guard isInternal(url) || trustedBlank else {
            if url.scheme == "https" { NSWorkspace.shared.open(url) }
            return nil
        }
        let popup = BrowserPopupController(configuration: configuration, screen: window.screen)
        popup.webView.navigationDelegate = self; popup.webView.uiDelegate = self
        popup.window?.level = window.level
        let key = ObjectIdentifier(popup.webView)
        browserPopups[key] = popup
        popup.onClose = { [weak self] view in self?.browserPopups.removeValue(forKey: ObjectIdentifier(view)) }
        popup.show()
        // WebKit loads the original request into the returned view and maintains
        // window.opener/postMessage. Loading just its URL into the player loses both.
        return popup.webView
    }
    func webViewDidClose(_ webView: WKWebView) { browserPopups[ObjectIdentifier(webView)]?.close() }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let allowed = webView === web && allowDeviceRequest && frame.isMainFrame && origin.protocol == "https" && origin.host == "www.youtube.com" && type == .microphone
        allowDeviceRequest = false; decisionHandler(allowed ? .prompt : .deny)
    }
    func navigationFailed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        resetPlayback(); navigatingBack = false; notice.stringValue = "YouTube 페이지를 열지 못했습니다: \(error.localizedDescription)"
        browserStatus.stringValue = "페이지를 열지 못했습니다 · ↻로 다시 시도"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { reportNavigationFailure(webView, error: error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { reportNavigationFailure(webView, error: error) }
    func reportNavigationFailure(_ webView: WKWebView, error: Error) {
        if webView === web { navigationFailed(error) }
        else if (error as NSError).code != NSURLErrorCancelled {
            browserPopups[ObjectIdentifier(webView)]?.window?.subtitle = "페이지를 불러오지 못했습니다. 창을 닫고 다시 로그인해 주세요."
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === web else { browserPopups[ObjectIdentifier(webView)]?.close(); return }
        resetPlayback(); notice.stringValue = "재생 엔진이 종료되었습니다. 링크를 다시 실행해 주세요."
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "turntabler" && url.host != "play" { continue }
            let text = url.scheme == "turntabler" ? URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name == "url"})?.value : url.absoluteString
            if let text, let valid = try? youtubeURL(text) { if web == nil { pendingURL = valid } else { load(valid); showWidget() } }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); visualTimer?.invalidate()
        if window != nil { saveWidgetFrame() }
        web?.configuration.userContentController.removeScriptMessageHandler(forName:"turntabler")
    }
    func runSmoke() {
        web.loadHTMLString("<html><body><button id='probe' onclick='window.clicked=true'>Probe</button><input id='typing'></body></html>",baseURL:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+3) {
            self.openBrowser()
            self.web.evaluateJavaScript("document.querySelector('#probe').click(); document.querySelector('#typing').value='abc'; window.clicked && document.querySelector('#typing').value==='abc'") { value,error in
                let documentWorked = error == nil && value as? Bool == true
                self.closeBrowser(); self.openBrowser(); self.closeBrowser()
                let roundTrip = !self.pageOpen && self.web.superview === self.videoContainer
                let success = documentWorked && roundTrip
                let data: [String:Any] = ["success":success,"webkitDocument":documentWorked,"browserRoundTrip":roundTrip,"usesIsolatedTestProfile":true,"hardwareAudioAndYouTubeLoginTested":false]
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
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate(); application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
