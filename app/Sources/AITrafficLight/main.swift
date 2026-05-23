import AppKit
import WebKit

enum GlassSupport {
    // Concentric radius ~ container width / 3.4 (Adopting Liquid Glass)
    static let panelSize = NSSize(width: 60, height: 154)
    static let cornerRadius: CGFloat = 18

    static var htmlMode: String { "native" }

    @MainActor
    static func makeHostView(frame: NSRect, contentView: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.style = .clear
            glass.contentView = contentView
            contentView.frame = glass.bounds
            contentView.autoresizingMask = [.width, .height]
            return glass
        }

        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.addSubview(contentView)
        contentView.frame = effect.bounds
        contentView.autoresizingMask = [.width, .height]
        return effect
    }

    static func widgetURL(from base: URL) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "glass", value: htmlMode)]
        return components.url ?? base
    }
}

final class DraggingWebView: WKWebView, WKNavigationDelegate {
    var onDragEnd: (() -> Void)?
    var onReady: (() -> Void)?
    private var dragStartScreenPoint: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    override init(frame: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        navigationDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onReady?()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartScreenPoint,
              let startOrigin = dragStartWindowOrigin,
              let window else { return }

        let current = NSEvent.mouseLocation
        window.setFrameOrigin(
            NSPoint(
                x: startOrigin.x + (current.x - startPoint.x),
                y: startOrigin.y + (current.y - startPoint.y)
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        dragStartScreenPoint = nil
        dragStartWindowOrigin = nil
        onDragEnd?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var webView: DraggingWebView!
    private var statusItem: NSStatusItem!
    private var stateWatcher: StateWatcher?
    private var lastState = "idle"
    private var webViewReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HookInstaller.installOnLaunch()

        let contentRect = NSRect(origin: .zero, size: GlassSupport.panelSize)
        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = DraggingWebView(frame: contentRect, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.onDragEnd = { [weak self] in
            self?.savePanelFrame()
        }
        webView.onReady = { [weak self] in
            self?.webViewReady = true
            self?.syncWebView()
        }

        panel.contentView = GlassSupport.makeHostView(frame: contentRect, contentView: webView)

        restorePanelFrame(defaultRect: contentRect)
        panel.orderFrontRegardless()

        loadWidget()
        setupMenuBar()

        stateWatcher = StateWatcher { [weak self] state in
            self?.applyState(state)
        }
    }

    private func syncWebView() {
        applyState(lastState, force: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        savePanelFrame()
    }

    private func loadWidget() {
        if let envPath = ProcessInfo.processInfo.environment["AI_TRAFFIC_LIGHT_UI"],
           FileManager.default.fileExists(atPath: envPath) {
            let url = GlassSupport.widgetURL(from: URL(fileURLWithPath: envPath))
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return
        }

        if let resource = Bundle.module.url(forResource: "widget", withExtension: "html") {
            let url = GlassSupport.widgetURL(from: resource)
            webView.loadFileURL(url, allowingReadAccessTo: resource.deletingLastPathComponent())
            return
        }

        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ui/widget.html")

        if FileManager.default.fileExists(atPath: fallback.path) {
            let url = GlassSupport.widgetURL(from: fallback)
            webView.loadFileURL(url, allowingReadAccessTo: fallback.deletingLastPathComponent())
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusBarIcon(for: lastState)

        let menu = NSMenu()
        menu.addItem(withTitle: "显示悬浮窗", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "重新安装 IDE 集成", action: #selector(reinstallHooks), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showPanel() {
        panel.orderFrontRegardless()
    }

    @objc private func reinstallHooks() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = HookInstaller.install()
            DispatchQueue.main.async {
                let alert = NSAlert()
                if result.succeeded {
                    alert.messageText = "IDE 集成已更新"
                    alert.informativeText = "Cursor、Claude Code、Codex 的 hooks 已重新写入。请重启对应 IDE。"
                } else {
                    alert.messageText = "部分 IDE 集成失败"
                    alert.informativeText = result.errors.joined(separator: "\n")
                }
                alert.addButton(withTitle: "知道了")
                alert.runModal()
            }
        }
    }

    @objc private func quitApp() {
        savePanelFrame()
        NSApp.terminate(nil)
    }

    private func applyState(_ state: String, force: Bool = false) {
        guard force || state != lastState else { return }
        lastState = state
        updateStatusBarIcon(for: state)
        guard webViewReady else { return }

        let script = "window.AITrafficLight && window.AITrafficLight.setState('\(state)')"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func updateStatusBarIcon(for state: String) {
        statusItem?.button?.image = StatusBarIcon.make(state: state)
        statusItem?.button?.image?.accessibilityDescription = "AI Traffic Light"
    }

    private func restorePanelFrame(defaultRect: NSRect) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "panelX") != nil else {
            panel.setFrameOrigin(defaultOrigin(for: defaultRect.size))
            return
        }

        let origin = NSPoint(
            x: defaults.double(forKey: "panelX"),
            y: defaults.double(forKey: "panelY")
        )
        panel.setFrameOrigin(origin)
    }

    private func savePanelFrame() {
        let origin = panel.frame.origin
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: "panelX")
        defaults.set(origin.y, forKey: "panelY")
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24
        )
    }
}

final class StateWatcher {
    private let stateURL: URL
    private let directoryURL: URL
    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private let onChange: (String) -> Void

    init(onChange: @escaping (String) -> Void) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = appSupport.appendingPathComponent("ai-traffic-light", isDirectory: true)
        stateURL = directoryURL.appendingPathComponent("state.json")
        self.onChange = onChange

        ensureInitialState()
        startDirectoryWatch()
        startPolling()
        readState()
    }

    deinit {
        directorySource?.cancel()
        pollTimer?.invalidate()
    }

    private func ensureInitialState() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: stateURL.path) {
            writeState("idle")
        }
    }

    private func writeState(_ state: String) {
        let now = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "state": state,
            "source": "none",
            "updated_at": now,
            "sources": [String: Any]()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: stateURL)
        }
    }

    private func startDirectoryWatch() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.readState()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directorySource = source
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.readState()
        }
    }

    private func readState() {
        guard let data = try? Data(contentsOf: stateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = json["state"] as? String else {
            return
        }
        onChange(state)
    }
}

private let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate
app.run()
