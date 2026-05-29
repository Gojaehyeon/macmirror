import AppKit

/// Menu bar (status item) front end. Pick a device preset or enter a custom
/// size — the virtual display is recreated on change. No Dock icon, no window.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let controller: StreamController
    private let tunnel = Tunnel()
    private var statusItem: NSStatusItem!
    private var clientCount = 0
    private var publicURL: String?
    private var shortURL: String?
    private var tunnelStatus: String?
    private var currentPresetName: String = DevicePreset.default.name
    private var orientation: Orientation = .portrait
    private var appearanceObservation: NSKeyValueObservation?

    init(controller: StreamController) {
        self.controller = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(running: false)

        // Re-paint the menu bar icon when the user toggles dark/light mode.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            guard let self else { return }
            self.updateIcon(running: self.controller.isRunning)
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.onStateChange = { [weak self] running in self?.updateIcon(running: running) }
        controller.onClientCount = { [weak self] count in self?.clientCount = count }
        controller.onError       = { [weak self] message in self?.showError(message) }

        tunnel.onURL      = { [weak self] url in self?.publicURL = url; self?.tunnelStatus = nil }
        tunnel.onShortURL = { [weak self] url in self?.shortURL = url }
        tunnel.onStatus   = { [weak self] status in self?.tunnelStatus = status }

        // Match initial preset name + orientation from whatever the CLI set.
        let cw = controller.config.width
        let ch = controller.config.height
        if let match = DevicePreset.all.first(where: { $0.width == cw && $0.height == ch }) {
            currentPresetName = match.name
            orientation = .portrait
        } else if let match = DevicePreset.all.first(where: { $0.height == cw && $0.width == ch }) {
            currentPresetName = match.name
            orientation = .landscape
        } else {
            currentPresetName = "사용자 정의"
            orientation = (cw > ch) ? .landscape : .portrait
        }

        controller.start()
        tunnel.start(localPort: controller.config.port)
    }

    // MARK: - Status icon

    private func updateIcon(running: Bool) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "macmirror")
        image?.isTemplate = true
        button.image = image
        // Always white in dark, always black in light. Running state is shown
        // via the menu text, not the icon color.
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.contentTintColor = isDark ? .white : .black
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = controller.isRunning

        let header = NSMenuItem(
            title: "📱  macmirror  (\(controller.config.width)×\(controller.config.height) · \(currentPresetName) · \(orientation.rawValue)\(controller.config.hidpi ? " · HiDPI" : ""))",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let status = NSMenuItem(
            title: running ? "   🟢 켜짐 · 보는 중 \(clientCount)명" : "   ⚪️ 꺼짐",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if running {
            menu.addItem(item("   ■ 중지", #selector(stopTapped)))
            if let local = controller.localURLs.first {
                menu.addItem(item("   같은 WiFi 기기용 주소 복사   \(local)",
                                  #selector(copyLocalTapped), object: local))
            }
            menu.addItem(.separator())
            let pubHeader = NSMenuItem(title: "🌐  공개 주소 (셀룰러/외부)", action: nil, keyEquivalent: "")
            pubHeader.isEnabled = false
            menu.addItem(pubHeader)
            if let addr = shortURL ?? publicURL {
                let typed = addr.replacingOccurrences(of: "https://", with: "")
                let mi = item("   👉  \(typed)", #selector(copyPublicTapped), object: addr)
                mi.attributedTitle = NSAttributedString(
                    string: "   👉  \(typed)",
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)])
                menu.addItem(mi)
            } else if let status = tunnelStatus {
                let s = NSMenuItem(title: "   ⚠️ \(status)", action: nil, keyEquivalent: ""); s.isEnabled = false
                menu.addItem(s)
            } else {
                let s = NSMenuItem(title: "   ⏳ 주소 준비 중…", action: nil, keyEquivalent: ""); s.isEnabled = false
                menu.addItem(s)
            }
            menu.addItem(item("   맥에서 미리보기", #selector(openPreviewTapped)))
        } else {
            menu.addItem(item("   ▶ 시작", #selector(startTapped)))
        }

        menu.addItem(.separator())

        // Device preset picker, grouped by category.
        let presetRoot = NSMenuItem(title: "디스플레이 사이즈", action: nil, keyEquivalent: "")
        let presetMenu = NSMenu()

        var lastCategory: String? = nil
        for p in DevicePreset.all {
            if let last = lastCategory, last != p.category {
                presetMenu.addItem(.separator())
            }
            lastCategory = p.category

            let mi = item("\(p.name)   \(p.width)×\(p.height)",
                          #selector(presetTapped), object: p.name)
            mi.state = (p.name == currentPresetName) ? .on : .off
            presetMenu.addItem(mi)
        }
        presetMenu.addItem(.separator())
        let custom = item("사용자 정의…", #selector(customSizeTapped))
        custom.state = (currentPresetName == "사용자 정의") ? .on : .off
        presetMenu.addItem(custom)

        presetRoot.submenu = presetMenu
        menu.addItem(presetRoot)

        // Orientation toggle
        let orientRoot = NSMenuItem(title: "방향: \(orientation.rawValue)", action: nil, keyEquivalent: "")
        let orientMenu = NSMenu()
        for o in [Orientation.portrait, .landscape] {
            let mi = item(o.rawValue, #selector(orientationTapped), object: o.rawValue)
            mi.state = (o == orientation) ? .on : .off
            orientMenu.addItem(mi)
        }
        orientRoot.submenu = orientMenu
        menu.addItem(orientRoot)

        // HiDPI toggle — renders content at 2× pixel density inside the same
        // pixel buffer (text/UI look crisper on Retina iPhones).
        let hidpi = item(
            "HiDPI (Retina 렌더링)\(controller.config.hidpi ? "  ✓" : "")",
            #selector(hidpiTapped))
        hidpi.state = controller.config.hidpi ? .on : .off
        menu.addItem(hidpi)

        menu.addItem(.separator())
        menu.addItem(item("종료", #selector(quitTapped)))
    }

    private func item(_ title: String, _ action: Selector, object: Any? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.representedObject = object
        return mi
    }

    // MARK: - Actions

    @objc private func startTapped() { controller.start() }
    @objc private func stopTapped()  { controller.stop() }

    @objc private func copyPublicTapped(_ sender: NSMenuItem) { copy(sender.representedObject as? String) }
    @objc private func copyLocalTapped(_ sender: NSMenuItem)  { copy(sender.representedObject as? String) }

    private func copy(_ string: String?) {
        guard let string else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    @objc private func openPreviewTapped() {
        if let u = URL(string: "http://localhost:\(controller.config.port)") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc private func presetTapped(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let p = DevicePreset.all.first(where: { $0.name == name }) else { return }
        let (w, h) = p.dimensions(landscape: orientation == .landscape)
        applyDimensions(width: w, height: h, presetName: p.name)
    }

    @objc private func orientationTapped(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let o = Orientation(rawValue: raw) else { return }
        guard o != orientation else { return }
        orientation = o
        if currentPresetName == "사용자 정의" {
            applyDimensions(width: controller.config.height,
                            height: controller.config.width,
                            presetName: currentPresetName)
        } else if let p = DevicePreset.all.first(where: { $0.name == currentPresetName }) {
            let (w, h) = p.dimensions(landscape: o == .landscape)
            applyDimensions(width: w, height: h, presetName: p.name)
        }
    }

    @objc private func hidpiTapped() {
        controller.config.hidpi.toggle()
        if controller.isRunning { controller.restart() }
    }

    @objc private func customSizeTapped() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "사용자 정의 사이즈"
        alert.informativeText = "가상 디스플레이 너비 × 높이 (픽셀)"
        alert.addButton(withTitle: "적용")
        alert.addButton(withTitle: "취소")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        stack.orientation = .horizontal
        stack.spacing = 8
        let wField = NSTextField(string: String(controller.config.width))
        wField.placeholderString = "Width"
        let hField = NSTextField(string: String(controller.config.height))
        hField.placeholderString = "Height"
        wField.frame.size = NSSize(width: 110, height: 24)
        hField.frame.size = NSSize(width: 110, height: 24)
        stack.addView(wField, in: .center)
        stack.addView(hField, in: .center)
        alert.accessoryView = stack
        if alert.runModal() == .alertFirstButtonReturn,
           let w = UInt32(wField.stringValue), let h = UInt32(hField.stringValue),
           w >= 200, h >= 200, w <= 8192, h <= 8192 {
            applyDimensions(width: w, height: h, presetName: "사용자 정의")
        }
    }

    private func applyDimensions(width: UInt32, height: UInt32, presetName: String) {
        controller.config.width = width
        controller.config.height = height
        currentPresetName = presetName
        if controller.isRunning { controller.restart() }
    }

    @objc private func quitTapped() {
        tunnel.stop()
        controller.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Error alert

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "macmirror"
        alert.informativeText = message
        alert.addButton(withTitle: "화면 기록 설정 열기")
        alert.addButton(withTitle: "닫기")
        if alert.runModal() == .alertFirstButtonReturn {
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(u)
            }
        }
    }
}
